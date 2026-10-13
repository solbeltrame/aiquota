import Foundation
import Testing
import libzstd
@testable import AIquotaCore

/// Builds Chromium "simple cache" entries like the ones the Claude app writes. No real data.
enum CacheEntryBuilder {
    static let sampleJSON = #"""
    {"five_hour":{"utilization":87.0,"resets_at":"2026-10-13T06:59:59.562807+00:00","limit_dollars":null},
     "seven_day":{"utilization":51.0,"resets_at":"2026-10-13T13:59:59.562830+00:00"},
     "seven_day_opus":null,"extra_usage":{"is_enabled":false},
     "limits":[{"kind":"session","percent":87,"resets_at":"2026-10-13T06:59:59.562807+00:00"}]}
    """#

    static func zstd(_ data: Data) -> Data {
        var output = [UInt8](repeating: 0, count: ZSTD_compressBound(data.count))
        let size = data.withUnsafeBytes { input in
            ZSTD_compress(&output, output.count, input.baseAddress, data.count, 3)
        }
        return Data(output[0..<size])
    }

    static func entry(key: String = "1/0/https://claude.ai/api/organizations/00000000-0000-0000-0000-000000000000/usage?skip_spend=1",
                      body: Data, headers: [String] = ["content-type:application/json", "content-encoding:zstd",
                                                       "date:Tue, 13 Oct 2026 04:09:37 GMT"]) -> Data {
        func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        var data = Data()
        data += le(UInt64(0xFCFB_6D1B_A772_5C30)) + le(UInt32(5)) + le(UInt32(key.utf8.count)) + le(UInt32(0)) + le(UInt32(0))
        data += Data(key.utf8)
        data += body
        data += le(UInt64(0xF4FA_6F45_970D_41D8)) + le(UInt32(1)) + le(UInt32(0)) + le(UInt32(0)) + le(UInt32(0))
        let headerBlock = Data((["HTTP/1.1 200"] + headers).joined(separator: "\0").utf8) + Data([0, 0])
        var stream0 = le(UInt32(headerBlock.count)) + headerBlock   // pickle-like prefix, as in real entries
        stream0 += Data(repeating: 0xAB, count: 32)                  // key SHA-256 placeholder
        data += stream0
        data += le(UInt64(0xF4FA_6F45_970D_41D8)) + le(UInt32(3)) + le(UInt32(0)) + le(UInt32(stream0.count)) + le(UInt32(0))
        return data
    }
}

@Suite struct ClaudeDesktopCacheTests {
    @Test func zstdRoundTrip() throws {
        let original = Data(CacheEntryBuilder.sampleJSON.utf8)
        #expect(HTTPBodyDecoder.decode(CacheEntryBuilder.zstd(original), contentEncoding: "zstd") == original)
        #expect(HTTPBodyDecoder.decode(original, contentEncoding: nil) == original)
        #expect(HTTPBodyDecoder.decode(Data("garbage".utf8), contentEncoding: "zstd") == nil)
        let truncated = CacheEntryBuilder.zstd(original).dropLast(10)
        #expect(HTTPBodyDecoder.decode(Data(truncated), contentEncoding: "zstd") == nil)
    }

    @Test func parsesUsageEntryWithResetTimes() throws {
        let entry = CacheEntryBuilder.entry(body: CacheEntryBuilder.zstd(Data(CacheEntryBuilder.sampleJSON.utf8)))
        let snapshot = try #require(ClaudeDesktopCacheReader.parseEntry(entry))
        #expect(snapshot.source == .claudeDesktopCache)
        #expect(!snapshot.source.isDocumented)
        #expect(snapshot.observedAt == ClaudeDesktopCacheReader.parseHTTPDate("Tue, 13 Oct 2026 04:09:37 GMT"))
        let five = try #require(snapshot.window(.fiveHour))
        #expect(five.usedPercent == 87)
        #expect(five.resetsAt == ClaudeDesktopCacheReader.parseISODate("2026-10-13T06:59:59.562Z"))
        #expect(snapshot.window(.weekly)?.usedPercent == 51)
        #expect(PercentFormatter.displayValue(usedPercent: five.usedPercent, mode: .available) == 13)
    }

    @Test func uncompressedEntryAlsoWorks() throws {
        let entry = CacheEntryBuilder.entry(body: Data(CacheEntryBuilder.sampleJSON.utf8),
                                            headers: ["content-type:application/json", "date:Tue, 13 Oct 2026 04:09:37 GMT"])
        #expect(ClaudeDesktopCacheReader.parseEntry(entry)?.windows.count == 2)
    }

    @Test func otherURLsAreIgnored() {
        #expect(ClaudeDesktopCacheReader.isUsageURL("1/0/https://claude.ai/api/organizations/abc/usage"))
        #expect(ClaudeDesktopCacheReader.isUsageURL("1/0/_dk_https://claude.ai https://claude.ai https://claude.ai/api/organizations/abc/usage?x=1"))
        #expect(!ClaudeDesktopCacheReader.isUsageURL("1/0/https://claude.ai/api/organizations/abc/usage/details"))
        #expect(!ClaudeDesktopCacheReader.isUsageURL("1/0/https://claude.ai/api/organizations/abc/chat_conversations"))
        #expect(!ClaudeDesktopCacheReader.isUsageURL("1/0/https://evil.example/api/organizations/abc/usage"))
        let other = CacheEntryBuilder.entry(key: "1/0/https://claude.ai/api/bootstrap",
                                            body: CacheEntryBuilder.zstd(Data(CacheEntryBuilder.sampleJSON.utf8)))
        #expect(ClaudeDesktopCacheReader.parseEntry(other) == nil)
    }

    @Test func malformedEntriesAreRejected() {
        #expect(ClaudeDesktopCacheReader.parseEntry(Data()) == nil)
        #expect(ClaudeDesktopCacheReader.parseEntry(Data(repeating: 7, count: 200)) == nil)
        let bodyNotJSON = CacheEntryBuilder.entry(body: CacheEntryBuilder.zstd(Data("<html>".utf8)))
        #expect(ClaudeDesktopCacheReader.parseEntry(bodyNotJSON) == nil)
        let noWindows = CacheEntryBuilder.entry(body: CacheEntryBuilder.zstd(Data(#"{"five_hour":null}"#.utf8)))
        #expect(ClaudeDesktopCacheReader.parseEntry(noWindows) == nil)
    }

    @Test func directoryScanPicksTheNewestUsageEntry() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aiquota-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let older = #"{"five_hour":{"utilization":10.0,"resets_at":"2026-10-13T01:00:00Z"}}"#
        try CacheEntryBuilder.entry(body: CacheEntryBuilder.zstd(Data(older.utf8)),
                                    headers: ["content-encoding:zstd", "date:Tue, 13 Oct 2026 01:00:00 GMT"])
            .write(to: dir.appendingPathComponent("aaaaaaaaaaaaaaaa_0"))
        try CacheEntryBuilder.entry(body: CacheEntryBuilder.zstd(Data(CacheEntryBuilder.sampleJSON.utf8)))
            .write(to: dir.appendingPathComponent("bbbbbbbbbbbbbbbb_0"))
        try Data(repeating: 1, count: 500).write(to: dir.appendingPathComponent("cccccccccccccccc_0"))
        try Data("index".utf8).write(to: dir.appendingPathComponent("index"))
        let snapshot = try #require(ClaudeDesktopCacheReader.read(directory: dir))
        #expect(snapshot.window(.fiveHour)?.usedPercent == 87)
    }

    @Test func isoDatesWithMicroseconds() {
        #expect(ClaudeDesktopCacheReader.parseISODate("2026-10-13T06:59:59.562807+00:00") != nil)
        #expect(ClaudeDesktopCacheReader.parseISODate("2026-10-13T06:59:59Z") != nil)
        #expect(ClaudeDesktopCacheReader.parseISODate("2026-10-13T06:59:59.5+00:00") != nil)
        #expect(ClaudeDesktopCacheReader.parseISODate("not a date") == nil)
    }

    @Test func combinePrefersTheReadingWithResetTimesWhenSimultaneous() {
        let history = snapshot(used5h: 87, usedWeekly: 51, provider: .claude, observedAt: now.addingTimeInterval(0.9),
                               reset5h: nil, resetWeekly: nil, source: .claudeDesktopHistory)
        let cache = snapshot(used5h: 87, usedWeekly: 51, provider: .claude, observedAt: now,
                             reset5h: now.addingTimeInterval(3600), resetWeekly: now.addingTimeInterval(86_400),
                             source: .claudeDesktopCache)
        let combined = ClaudeProvider.combine([history, cache])
        #expect(combined?.source == .claudeDesktopCache)
        #expect(combined?.window(.fiveHour)?.resetsAt == now.addingTimeInterval(3600))

        // A much newer history sample still wins, borrowing still-valid reset times from the cache.
        let laterHistory = snapshot(used5h: 90, usedWeekly: 52, provider: .claude, observedAt: now.addingTimeInterval(600),
                                    reset5h: nil, resetWeekly: nil, source: .claudeDesktopHistory)
        let later = ClaudeProvider.combine([laterHistory, cache])
        #expect(later?.source == .claudeDesktopHistory)
        #expect(later?.window(.fiveHour)?.usedPercent == 90)
        #expect(later?.window(.fiveHour)?.resetsAt == now.addingTimeInterval(3600))
    }
}
