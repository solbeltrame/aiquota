import Foundation

/// UNDOCUMENTED SOURCE — isolated on purpose.
///
/// The Claude desktop app (Electron/Chromium) refreshes your plan usage about every five minutes from
/// `claude.ai/api/organizations/<org>/usage`, and Chromium keeps the last response in its HTTP disk cache
/// (`~/Library/Application Support/Claude/Cache/Cache_Data`). That response includes reset times:
///
///     {"five_hour":{"utilization":87.0,"resets_at":"2026-10-13T06:59:59.562807+00:00"},
///      "seven_day":{"utilization":51.0,"resets_at":"…"}, …}
///
/// AIquota only reads that cached file: no request to Anthropic, no cookies, no tokens, no credentials.
/// Only cache entries whose key is the usage URL are decoded, and only the two usage windows are kept.
/// If Chromium's cache layout or the response format changes, this reader returns `nil` and the
/// provider falls back to the other sources.
public enum ClaudeDesktopCacheReader {
    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/Cache/Cache_Data")
    }

    /// Usage responses are a few KB; anything bigger is skipped without being opened.
    static let maximumEntrySize = 256 * 1024

    /// Newest usage response in the cache directory.
    public static func read(directory: URL = defaultDirectory()) -> QuotaSnapshot? {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys,
                                                                      options: [.skipsHiddenFiles]) else { return nil }
        var newest: QuotaSnapshot?
        for file in files where file.lastPathComponent.hasSuffix("_0") {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let size = values.fileSize, size > 64, size <= maximumEntrySize,
                  isUsageEntry(file), let data = try? Data(contentsOf: file),
                  let snapshot = parseEntry(data) else { continue }
            if newest == nil || snapshot.observedAt > newest!.observedAt { newest = snapshot }
        }
        return newest
    }

    // MARK: Chromium simple cache entry

    /// Layout of `<hash>_0` (Chromium "simple" backend, version 5):
    /// header (24 bytes: magic, version, key length, key hash) · key · stream 1 (body) · EOF record ·
    /// stream 0 (HTTP headers) · [key SHA-256] · EOF record.
    struct Entry {
        var key: String
        var body: Data
        var headers: [String: String]
    }

    static let initialMagic: UInt64 = 0xFCFB_6D1B_A772_5C30
    static let finalMagic: UInt64 = 0xF4FA_6F45_970D_41D8
    static let headerSize = 24
    static let eofSize = 24

    /// Reads just the key to decide whether an entry is worth decoding.
    static func isUsageEntry(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 1024), let key = parseKey(prefix) else { return false }
        return isUsageURL(key)
    }

    static func isUsageURL(_ key: String) -> Bool {
        // Keys look like "1/0/https://claude.ai/api/organizations/<uuid>/usage?skip_spend=1".
        guard let range = key.range(of: "https://claude.ai/api/organizations/") else { return false }
        let path = key[range.upperBound...].split(separator: "?", maxSplits: 1).first ?? ""
        let parts = path.split(separator: "/")
        return parts.count == 2 && parts[1] == "usage"
    }

    static func parseKey(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(headerSize + 2048))
        guard bytes.count >= headerSize, readUInt64(bytes, 0) == initialMagic else { return nil }
        let keyLength = Int(readUInt32(bytes, 12))
        guard keyLength > 0, headerSize + keyLength <= bytes.count else { return nil }
        return String(bytes: bytes[headerSize..<(headerSize + keyLength)], encoding: .utf8)
    }

    static func parseEntryStructure(_ data: Data) -> Entry? {
        let bytes = [UInt8](data)
        guard let key = parseKey(data) else { return nil }
        let bodyStart = headerSize + key.utf8.count
        // Stream 1 ends at the first EOF record after the key.
        guard let firstEOF = findMagic(finalMagic, in: bytes, from: bodyStart),
              let lastEOF = findMagic(finalMagic, in: bytes, from: firstEOF + eofSize) else { return nil }
        let body = Data(bytes[bodyStart..<firstEOF])
        // Stream 0 holds the raw header block: "HTTP/1.1 200\0name:value\0…\0\0".
        let headerBytes = bytes[(firstEOF + eofSize)..<lastEOF]
        var headers: [String: String] = [:]
        for line in headerBytes.split(separator: 0) {
            guard let text = String(bytes: line, encoding: .utf8), let colon = text.firstIndex(of: ":"),
                  !text.hasPrefix("HTTP/") else { continue }
            let name = text[..<colon].lowercased()
            // The pickled block may contain binary data after the headers; keep plausible header names only.
            guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { continue }
            if headers[name] == nil { headers[name] = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces) }
        }
        return Entry(key: key, body: body, headers: headers)
    }

    // MARK: Usage response

    struct UsageResponse: Decodable {
        struct Window: Decodable {
            var utilization: Double?
            var resets_at: String?
        }
        var five_hour: Window?
        var seven_day: Window?
    }

    public static func parseEntry(_ data: Data, fallbackDate: Date? = nil) -> QuotaSnapshot? {
        guard let entry = parseEntryStructure(data), isUsageURL(entry.key),
              let json = HTTPBodyDecoder.decode(entry.body, contentEncoding: entry.headers["content-encoding"]) else { return nil }
        let observed = entry.headers["date"].flatMap(parseHTTPDate) ?? fallbackDate
        guard let observed else { return nil }
        return parseUsage(json, observedAt: observed)
    }

    public static func parseUsage(_ json: Data, observedAt: Date) -> QuotaSnapshot? {
        guard let response = try? JSONDecoder().decode(UsageResponse.self, from: json) else { return nil }
        var windows: [QuotaWindow] = []
        for (kind, minutes, window) in [(WindowKind.fiveHour, 300, response.five_hour), (.weekly, 10_080, response.seven_day)] {
            guard let window, let used = window.utilization else { continue }
            windows.append(QuotaWindow(kind: kind, durationMinutes: minutes, usedPercent: used,
                                       resetsAt: window.resets_at.flatMap(parseISODate)))
        }
        guard !windows.isEmpty else { return nil }
        return QuotaSnapshot(provider: .claude, windows: windows, observedAt: observedAt, source: .claudeDesktopCache)
    }

    // MARK: Helpers

    static func parseHTTPDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: string)
    }

    /// ISO 8601 with any number of fractional digits ("…59.562807+00:00").
    static func parseISODate(_ string: String) -> Date? {
        var trimmed = string
        if let dot = string.firstIndex(of: ".") {
            let fractionEnd = string[dot...].dropFirst().firstIndex { !$0.isNumber } ?? string.endIndex
            let digits = string[string.index(after: dot)..<fractionEnd].prefix(3)
            trimmed = String(string[..<dot]) + "." + digits.padding(toLength: 3, withPad: "0", startingAt: 0)
                + String(string[fractionEnd...])
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    static func findMagic(_ magic: UInt64, in bytes: [UInt8], from start: Int) -> Int? {
        guard start >= 0, bytes.count >= 8 else { return nil }
        var index = start
        while index + 8 <= bytes.count {
            if readUInt64(bytes, index) == magic { return index }
            index += 1
        }
        return nil
    }

    static func readUInt64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << (8 * UInt64($1)) }
    }

    static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }
}
