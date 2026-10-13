import Foundation
import Testing
@testable import AIquotaCore

/// Opt-in checks against the real tools on this Mac: `AIQUOTA_LIVE_TESTS=1 swift test --filter Live`.
/// They read limits only (no model calls, no tokens) and print nothing account-specific.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AIQUOTA_LIVE_TESTS"] == "1"))
struct LiveIntegrationTests {
    @Test func codexAppServerReturnsRealWindows() async throws {
        let provider = CodexProvider()
        guard await provider.detect().isInstalled else {
            Issue.record("Codex CLI not installed")
            return
        }
        let snapshot = try await provider.fetch()
        #expect(snapshot.source == .codexAppServer)
        #expect(!snapshot.isFixture)
        #expect(!snapshot.windows.isEmpty)
        for window in snapshot.windows {
            #expect((0...100).contains(window.usedPercent))
            #expect(window.durationMinutes != nil)
        }
        print("Codex live: windows=\(snapshot.windows.map { "\($0.kind.rawValue):\($0.durationMinutes ?? 0)min" }) credits=\(snapshot.resetCredits?.availableCount ?? -1)")
    }

    @Test func claudeLocalSourcesParse() async throws {
        let provider = ClaudeProvider()
        do {
            let snapshot = try await provider.fetch()
            #expect(!snapshot.windows.isEmpty)
            print("Claude live: source=\(snapshot.source.rawValue) windows=\(snapshot.windows.map(\.kind.rawValue))")
        } catch ProviderError.noData(let reason) {
            print("Claude live: no data yet (\(reason))")
        }
    }

    @Test func codexSessionLogsParseWhenPresent() throws {
        let sessions = CodexLocator.codexHome().appendingPathComponent("sessions")
        guard let enumerator = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        var newest: (URL, Date)?
        for case let url as URL in enumerator where CodexSessionLogReader.isRolloutFile(url.path) {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if newest == nil || date > newest!.1 { newest = (url, date) }
        }
        guard let newest else { return }
        let snapshot = CodexSessionLogReader.latestSnapshot(inFile: newest.0)
        print("Codex session log: \(snapshot == nil ? "no rate_limits in tail" : "parsed \(snapshot!.windows.count) windows")")
    }
}
