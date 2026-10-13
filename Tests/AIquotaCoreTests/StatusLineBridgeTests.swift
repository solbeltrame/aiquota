import Foundation
import Testing
@testable import AIquotaCore

@Suite struct StatusLineBridgeTests {
    struct Sandbox {
        let root: URL
        let bridge: ClaudeStatusLineBridge
        init() throws {
            // No spaces here on purpose? No: the real support path has one, so test with one too.
            root = FileManager.default.temporaryDirectory.appendingPathComponent("aiquota bridge \(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            bridge = ClaudeStatusLineBridge(claudeConfigDir: root.appendingPathComponent("claude"),
                                            supportDir: root.appendingPathComponent("Application Support/AIquota/claude"))
        }
        func writeSettings(_ json: String) throws {
            try FileManager.default.createDirectory(at: bridge.claudeConfigDir, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: bridge.settingsURL)
        }
        func settings() throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(contentsOf: bridge.settingsURL)) as! [String: Any]
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    static let sampleInput = #"{"session_id":"s","cwd":"/secret/project","model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1791870000},"seven_day":{"used_percentage":41.2,"resets_at":1792400000}}}"#

    /// Runs the installed command the way Claude Code does: through a shell, JSON on stdin.
    func runStatusLine(_ sandbox: Sandbox, input: String = sampleInput) throws -> String {
        let command = try #require((try sandbox.settings()["statusLine"] as? [String: Any])?["command"] as? String)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ["SHELL": "/bin/sh", "PATH": "/usr/bin:/bin"]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        return String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    @Test func installPreservesExistingStatusLineAndSettings() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        try sandbox.writeSettings(#"{"model":"opus","permissions":{"allow":["Bash(ls)"]},"statusLine":{"type":"command","command":"printf 'PREV:%s' \"$(cat | wc -c | tr -d ' ')\"","padding":1}}"#)
        let original = try sandbox.settings()

        #expect(sandbox.bridge.status() == .notInstalled)
        try sandbox.bridge.install(now: now)
        #expect(sandbox.bridge.status() == .installed)

        let settings = try sandbox.settings()
        let statusLine = try #require(settings["statusLine"] as? [String: Any])
        #expect(statusLine["command"] as? String == sandbox.bridge.bridgeCommand)
        #expect(statusLine["padding"] as? Int == 1)
        #expect(settings["model"] as? String == "opus")
        #expect((settings["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls)"])

        // Full backup was taken.
        let backups = try FileManager.default.contentsOfDirectory(atPath: sandbox.bridge.supportDir.path).filter { $0.hasPrefix("settings.backup-") }
        #expect(backups.count == 1)

        // The user's previous status line still prints, with the full JSON on stdin.
        let output = try runStatusLine(sandbox)
        #expect(output == "PREV:\(Self.sampleInput.utf8.count)")

        // Only rate limits were captured — not cwd, model or session.
        let captured = try String(contentsOf: sandbox.bridge.rateLimitsURL, encoding: .utf8)
        #expect(!captured.contains("secret"))
        #expect(!captured.contains("session_id"))
        let snapshot = try #require(sandbox.bridge.readCapturedSnapshot())
        #expect(snapshot.window(.fiveHour)?.usedPercent == 23.5)
        #expect(snapshot.window(.weekly)?.resetsAt == Date(timeIntervalSince1970: 1_792_400_000))

        // Reverting restores the original status line exactly.
        #expect(try sandbox.bridge.uninstall())
        let restored = try sandbox.settings()
        #expect(NSDictionary(dictionary: restored).isEqual(to: original))
        #expect(!FileManager.default.fileExists(atPath: sandbox.bridge.scriptURL.path))
    }

    @Test func installWithoutPreviousStatusLineAndRevert() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        try sandbox.bridge.install(now: now)
        #expect(try runStatusLine(sandbox) == "")
        #expect(sandbox.bridge.readCapturedSnapshot() != nil)
        try sandbox.bridge.uninstall()
        #expect(try sandbox.settings()["statusLine"] == nil)
    }

    @Test func inputWithoutRateLimitsWritesNothing() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        try sandbox.bridge.install(now: now)
        _ = try runStatusLine(sandbox, input: #"{"model":{"display_name":"Opus"}}"#)
        #expect(!FileManager.default.fileExists(atPath: sandbox.bridge.rateLimitsURL.path))
    }

    @Test func invalidSettingsAreNeverTouched() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        try sandbox.writeSettings("{ not json")
        #expect(sandbox.bridge.status() == .settingsUnreadable)
        #expect(throws: ClaudeStatusLineBridge.BridgeError.settingsUnreadable) { try sandbox.bridge.install(now: now) }
        #expect(try String(contentsOf: sandbox.bridge.settingsURL, encoding: .utf8) == "{ not json")
    }

    @Test func userReplacementIsRespectedOnRevert() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        try sandbox.writeSettings(#"{"statusLine":{"type":"command","command":"echo old"}}"#)
        try sandbox.bridge.install(now: now)
        try sandbox.writeSettings(#"{"statusLine":{"type":"command","command":"echo mine"}}"#)
        #expect(sandbox.bridge.status() == .replacedByUser)
        #expect(try sandbox.bridge.uninstall() == false)
        #expect((try sandbox.settings()["statusLine"] as? [String: Any])?["command"] as? String == "echo mine")
    }

    @Test func reinstallKeepsOriginalPreviousCommand() throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanup() }
        try sandbox.writeSettings(#"{"statusLine":{"type":"command","command":"echo original"}}"#)
        try sandbox.bridge.install(now: now)
        try sandbox.bridge.install(now: now.addingTimeInterval(1))  // second install must not record itself as "previous"
        #expect(try runStatusLine(sandbox) == "original\n")
        try sandbox.bridge.uninstall()
        #expect((try sandbox.settings()["statusLine"] as? [String: Any])?["command"] as? String == "echo original")
    }
}
