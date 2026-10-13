import Foundation

/// UNDOCUMENTED SOURCE — isolated on purpose.
///
/// Codex appends a `token_count` event with a `rate_limits` object to the session rollout file
/// (`$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl`) after every model response. Watching those
/// files lets AIquota react within a second of Codex activity without any network call.
///
/// The format is internal to Codex and may change. Values read here are shown immediately but are
/// always followed by a confirming `account/rateLimits/read` from the documented App Server.
public enum CodexSessionLogReader {
    /// Rollout files can grow to tens of megabytes; only the tail is read.
    static let tailBytes = 256 * 1024

    public static func isRolloutFile(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.hasPrefix("rollout-") && name.hasSuffix(".jsonl")
    }

    public static func latestSnapshot(inFile url: URL) -> QuotaSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        return latestSnapshot(inTail: data)
    }

    /// Scans JSONL lines from the end and returns the newest rate-limit snapshot.
    public static func latestSnapshot(inTail data: Data) -> QuotaSnapshot? {
        let marker = Data("\"rate_limits\"".utf8)
        var end = data.endIndex
        while end > data.startIndex {
            let lineStart = data[data.startIndex..<end].lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
            let line = data[lineStart..<end]
            if line.range(of: marker) != nil, let snapshot = parse(line: Data(line)) {
                return snapshot
            }
            end = lineStart > data.startIndex ? lineStart - 1 : data.startIndex
        }
        return nil
    }

    struct Line: Decodable {
        struct Payload: Decodable {
            var type: String?
            var rate_limits: Limits?
        }
        struct Limits: Decodable {
            var limit_id: String?
            var primary: Window?
            var secondary: Window?
            var plan_type: String?
        }
        struct Window: Decodable {
            var used_percent: Double
            var window_minutes: Int?
            var resets_at: Int64?
        }
        var timestamp: String?
        var payload: Payload?
    }

    static func parse(line: Data) -> QuotaSnapshot? {
        guard let decoded = try? JSONDecoder().decode(Line.self, from: line),
              let limits = decoded.payload?.rate_limits,
              limits.limit_id == nil || limits.limit_id == "codex" else { return nil }
        let windows = [limits.primary, limits.secondary].compactMap { $0 }.map {
            QuotaWindow(kind: WindowKind.classify(durationMinutes: $0.window_minutes),
                        durationMinutes: $0.window_minutes, usedPercent: $0.used_percent,
                        resetsAt: $0.resets_at.map { Date(timeIntervalSince1970: TimeInterval($0)) })
        }
        guard !windows.isEmpty else { return nil }
        let observed = decoded.timestamp.flatMap(parseTimestamp) ?? Date()
        return QuotaSnapshot(provider: .codex, windows: windows, observedAt: observed, source: .codexSessionLog,
                             planName: limits.plan_type.flatMap(CodexRateLimitParser.planDisplayName))
    }

    static func parseTimestamp(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
