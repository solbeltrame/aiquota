import Foundation

/// Optional, opt-in integration with Claude Code's documented status line
/// (https://code.claude.com/docs/en/statusline).
///
/// Claude Code pipes session JSON — including `rate_limits.five_hour` / `seven_day` — to the status
/// line command after every response. The bridge script saves ONLY the `rate_limits` object and then
/// runs the user's previous status line command unchanged, so their status line keeps working.
///
/// Install never happens silently: the app asks first, backs up `settings.json`, records the previous
/// `statusLine` value and can restore it exactly.
public struct ClaudeStatusLineBridge: Sendable {
    public enum Status: Equatable, Sendable {
        case notInstalled
        case installed
        /// Our entry was replaced by something else after installation.
        case replacedByUser
        /// `settings.json` exists but is not valid JSON; we will not touch it.
        case settingsUnreadable
    }

    public enum BridgeError: Error, Equatable, LocalizedError {
        case settingsUnreadable
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .settingsUnreadable: return "Claude Code settings.json is not valid JSON. AIquota did not change it."
            case .writeFailed(let reason): return "Could not update Claude Code settings: \(reason)"
            }
        }
    }

    public let claudeConfigDir: URL
    public let supportDir: URL

    public init(claudeConfigDir: URL = ClaudeStatusLineBridge.defaultClaudeConfigDir(),
                supportDir: URL = ClaudeStatusLineBridge.defaultSupportDir()) {
        self.claudeConfigDir = claudeConfigDir
        self.supportDir = supportDir
    }

    public static func defaultClaudeConfigDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    public static func defaultSupportDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AIquota/claude")
    }

    public var settingsURL: URL { claudeConfigDir.appendingPathComponent("settings.json") }
    public var scriptURL: URL { supportDir.appendingPathComponent("statusline-bridge.sh") }
    public var rateLimitsURL: URL { supportDir.appendingPathComponent("rate-limits.json") }
    var previousCommandURL: URL { supportDir.appendingPathComponent("previous-command") }
    var previousStatusLineURL: URL { supportDir.appendingPathComponent("previous-statusline.json") }

    /// The exact command string written to settings.json (quoted: the path contains a space).
    public var bridgeCommand: String { "\"\(scriptURL.path)\"" }

    // MARK: Status

    public func status() -> Status {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return .notInstalled }
        guard let settings = try? readSettings() else { return .settingsUnreadable }
        let command = (settings["statusLine"] as? [String: Any])?["command"] as? String
        if command == bridgeCommand { return .installed }
        if FileManager.default.fileExists(atPath: previousStatusLineURL.path) { return .replacedByUser }
        return .notInstalled
    }

    /// Plain-language description of what install will change, shown before asking for consent.
    public func installPlan() -> [String] {
        var lines = ["Back up \(settingsURL.path)",
                     "Set Claude Code's \"statusLine\" to run \(scriptURL.lastPathComponent)",
                     "Save only the rate_limits numbers to \(rateLimitsURL.path)"]
        if let previous = try? currentStatusLineCommand(), previous != nil {
            lines.append("Keep running your current status line command after AIquota reads the numbers")
        } else {
            lines.append("You have no status line today; Claude Code will show an empty one and hide some footer hints")
        }
        lines.append("Remove at any time from AIquota → Settings → Providers")
        return lines
    }

    // MARK: Install / remove

    public func install(now: Date = Date()) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: claudeConfigDir, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: settingsURL.path) {
            guard let parsed = try? readSettings() else { throw BridgeError.settingsUnreadable }
            settings = parsed
            let backup = supportDir.appendingPathComponent("settings.backup-\(Int(now.timeIntervalSince1970)).json")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settingsURL, to: backup)
        }

        let previous = settings["statusLine"] as? [String: Any]
        let previousCommand = previous?["command"] as? String
        if previousCommand != bridgeCommand {
            // Remember the user's status line exactly as it was.
            let record: [String: Any] = previous.map { ["statusLine": $0] } ?? ["statusLine": NSNull()]
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                .write(to: previousStatusLineURL, options: .atomic)
            try Data((previousCommand ?? "").utf8).write(to: previousCommandURL, options: .atomic)
        }

        try writeScript()

        var entry: [String: Any] = ["type": "command", "command": bridgeCommand]
        // Preserve layout options the user had chosen.
        for key in ["padding", "refreshInterval"] {
            if let value = previous?[key] { entry[key] = value }
        }
        settings["statusLine"] = entry
        try writeSettings(settings)
    }

    /// Restores the previous status line if our entry is still in place. Returns false when the
    /// user had already replaced it (we then leave their settings alone).
    @discardableResult
    public func uninstall() throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsURL.path) else { cleanUp(); return true }
        guard var settings = try? readSettings() else { throw BridgeError.settingsUnreadable }
        let command = (settings["statusLine"] as? [String: Any])?["command"] as? String
        guard command == bridgeCommand else { cleanUp(); return false }

        if let data = try? Data(contentsOf: previousStatusLineURL),
           let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let previous = record["statusLine"] as? [String: Any] {
            settings["statusLine"] = previous
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try writeSettings(settings)
        cleanUp()
        return true
    }

    private func cleanUp() {
        let fm = FileManager.default
        for url in [scriptURL, previousCommandURL, previousStatusLineURL] {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: Reading captured data

    struct Capture: Decodable {
        struct Window: Decodable {
            var used_percentage: Double?
            var resets_at: Double?
        }
        struct Limits: Decodable {
            var five_hour: Window?
            var seven_day: Window?
        }
        var captured_at: Double
        var rate_limits: Limits
    }

    public func readCapturedSnapshot() -> QuotaSnapshot? {
        guard let data = try? Data(contentsOf: rateLimitsURL) else { return nil }
        return Self.parseCapture(data)
    }

    public static func parseCapture(_ data: Data) -> QuotaSnapshot? {
        guard let capture = try? JSONDecoder().decode(Capture.self, from: data) else { return nil }
        var windows: [QuotaWindow] = []
        if let five = capture.rate_limits.five_hour, let used = five.used_percentage {
            windows.append(QuotaWindow(kind: .fiveHour, durationMinutes: 300, usedPercent: used,
                                       resetsAt: five.resets_at.map { Date(timeIntervalSince1970: $0) }))
        }
        if let week = capture.rate_limits.seven_day, let used = week.used_percentage {
            windows.append(QuotaWindow(kind: .weekly, durationMinutes: 10_080, usedPercent: used,
                                       resetsAt: week.resets_at.map { Date(timeIntervalSince1970: $0) }))
        }
        guard !windows.isEmpty else { return nil }
        return QuotaSnapshot(provider: .claude, windows: windows,
                             observedAt: Date(timeIntervalSince1970: capture.captured_at), source: .claudeStatusLine)
    }

    // MARK: Helpers

    private func currentStatusLineCommand() throws -> String? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let settings = try readSettings()
        return (settings["statusLine"] as? [String: Any])?["command"] as? String
    }

    private func readSettings() throws -> [String: Any] {
        let data = try Data(contentsOf: settingsURL)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BridgeError.settingsUnreadable
        }
        return object
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        do {
            let data = try JSONSerialization.data(withJSONObject: settings,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            throw BridgeError.writeFailed(error.localizedDescription)
        }
    }

    private func writeScript() throws {
        let script = Self.scriptTemplate.replacingOccurrences(of: "__AIQUOTA_DIR__", with: supportDir.path)
        try Data(script.utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    static let scriptTemplate = """
    #!/bin/sh
    # AIquota — Claude Code status line bridge (installed with your permission).
    # Saves ONLY the rate_limits numbers for AIquota, then runs your previous status line command.
    # Remove it from AIquota → Settings → Providers → Claude Code.
    AIQ_DIR="__AIQUOTA_DIR__"
    input=$(cat)
    rl=$(printf '%s' "$input" | /usr/bin/plutil -extract rate_limits json -o - - 2>/dev/null)
    if [ -n "$rl" ]; then
      tmp="$AIQ_DIR/.rate-limits.$$"
      if printf '{"captured_at":%s,"rate_limits":%s}\\n' "$(date +%s)" "$rl" > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$AIQ_DIR/rate-limits.json" 2>/dev/null
      fi
    fi
    if [ -s "$AIQ_DIR/previous-command" ]; then
      printf '%s' "$input" | "${SHELL:-/bin/sh}" -c "$(cat "$AIQ_DIR/previous-command")"
    fi

    """
}
