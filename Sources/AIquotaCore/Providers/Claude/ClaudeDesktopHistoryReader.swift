import Foundation

/// UNDOCUMENTED SOURCE — isolated on purpose.
///
/// While it runs, the Claude desktop app records plan usage samples about every five minutes in
/// `~/Library/Application Support/Claude/plan-usage-history.json`:
///
///     {"version":2,"samples":[{"t":<ms>,"org":"<uuid>","u":{"fh":<5h used %>,"sd":<7d used %>}}]}
///
/// AIquota only reads the newest sample. It never reads credentials, cookies or caches, and makes no
/// network request. The file carries no reset times, so those come from the status line bridge when
/// available and are otherwise left blank (never estimated). If the format changes, this reader
/// returns `nil` and the provider reports "waiting for data".
public enum ClaudeDesktopHistoryReader {
    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    }

    struct File: Decodable {
        struct Sample: Decodable {
            struct Usage: Decodable {
                var fh: Double?
                var sd: Double?
            }
            var t: Double
            var org: String?
            var u: Usage
        }
        var version: Int?
        var samples: [Sample]
    }

    public static func read(_ url: URL = defaultURL()) -> QuotaSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    public static func parse(_ data: Data) -> QuotaSnapshot? {
        guard let file = try? JSONDecoder().decode(File.self, from: data),
              file.version == nil || file.version == 2,
              let latest = file.samples.max(by: { $0.t < $1.t }) else { return nil }
        var windows: [QuotaWindow] = []
        if let fh = latest.u.fh { windows.append(QuotaWindow(kind: .fiveHour, durationMinutes: 300, usedPercent: fh)) }
        if let sd = latest.u.sd { windows.append(QuotaWindow(kind: .weekly, durationMinutes: 10_080, usedPercent: sd)) }
        guard !windows.isEmpty else { return nil }
        return QuotaSnapshot(provider: .claude, windows: windows,
                             observedAt: Date(timeIntervalSince1970: latest.t / 1000), source: .claudeDesktopHistory)
    }
}
