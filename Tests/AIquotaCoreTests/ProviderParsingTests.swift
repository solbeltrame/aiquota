import Foundation
import Testing
@testable import AIquotaCore

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct CodexParsingTests {
    @Test func readResponse() throws {
        let snapshot = try CodexRateLimitParser.parseReadResponse(try fixture("codex-rate-limits-read.json"), observedAt: now)
        #expect(snapshot.provider == .codex)
        #expect(snapshot.source == .codexAppServer)
        #expect(snapshot.planName == "Plus")
        #expect(!snapshot.isFixture)
        let five = try #require(snapshot.window(.fiveHour))
        #expect(five.usedPercent == 62)
        #expect(five.durationMinutes == 300)
        #expect(five.resetsAt == Date(timeIntervalSince1970: 1_791_872_691))
        #expect(PercentFormatter.displayValue(usedPercent: five.usedPercent, mode: .available) == 38)
        #expect(snapshot.window(.weekly)?.usedPercent == 90)
    }

    @Test func resetCreditsKeepOnlyAvailableSortedByExpiry() throws {
        let snapshot = try CodexRateLimitParser.parseReadResponse(try fixture("codex-rate-limits-read.json"), observedAt: now)
        let credits = try #require(snapshot.resetCredits)
        #expect(credits.availableCount == 2)
        #expect(credits.credits?.map(\.id) == ["credit-a", "credit-b"])
        #expect(credits.nextExpiry == Date(timeIntervalSince1970: 1_793_299_650))
    }

    @Test func sparseUpdateMergesIntoPreviousSnapshot() throws {
        let base = try CodexRateLimitParser.parseReadResponse(try fixture("codex-rate-limits-read.json"), observedAt: now)
        let update = Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":70,"windowDurationMins":300,"resetsAt":1791872691}}}"#.utf8)
        let merged = try #require(try CodexRateLimitParser.mergeUpdatedNotification(update, into: base, observedAt: now.addingTimeInterval(5)))
        #expect(merged.window(.fiveHour)?.usedPercent == 70)
        #expect(merged.window(.weekly)?.usedPercent == 90)           // untouched
        #expect(merged.resetCredits?.availableCount == 2)            // untouched
        #expect(merged.planName == "Plus")                           // absent in update: kept
    }

    @Test func updatesForOtherBucketsAreIgnored() throws {
        let base = try CodexRateLimitParser.parseReadResponse(try fixture("codex-rate-limits-read.json"), observedAt: now)
        let update = Data(#"{"rateLimits":{"limitId":"codex_other","primary":{"usedPercent":1,"windowDurationMins":300}}}"#.utf8)
        let merged = try CodexRateLimitParser.mergeUpdatedNotification(update, into: base, observedAt: now)
        #expect(merged == base)
    }

    @Test func missingWindowsAreNotInvented() throws {
        let data = Data(#"{"rateLimits":{"limitId":"codex","primary":null,"secondary":null}}"#.utf8)
        let snapshot = try CodexRateLimitParser.parseReadResponse(data, observedAt: now)
        #expect(snapshot.windows.isEmpty)
    }

    @Test func sessionLogTailYieldsNewestSnapshot() throws {
        let snapshot = try #require(CodexSessionLogReader.latestSnapshot(inTail: try fixture("codex-rollout-tail.jsonl")))
        #expect(snapshot.source == .codexSessionLog)
        #expect(snapshot.window(.fiveHour)?.usedPercent == 61)
        #expect(snapshot.window(.weekly)?.usedPercent == 90)
        #expect(snapshot.observedAt == CodexSessionLogReader.parseTimestamp("2026-10-13T03:13:46.381Z"))
        #expect(!snapshot.source.isDocumented)
    }

    @Test func sessionLogWithoutLimitsYieldsNothing() {
        #expect(CodexSessionLogReader.latestSnapshot(inTail: Data("{\"a\":1}\n{\"b\":2}\n".utf8)) == nil)
        #expect(CodexSessionLogReader.isRolloutFile("/x/sessions/2026/10/12/rollout-2026-10-12T11-27-08-abc.jsonl"))
        #expect(!CodexSessionLogReader.isRolloutFile("/x/sessions/index.json"))
    }
}

@Suite struct ClaudeParsingTests {
    @Test func desktopHistoryUsesNewestSample() throws {
        let snapshot = try #require(ClaudeDesktopHistoryReader.parse(try fixture("claude-plan-usage-history.json")))
        #expect(snapshot.window(.fiveHour)?.usedPercent == 47)
        #expect(snapshot.window(.weekly)?.usedPercent == 46)
        #expect(snapshot.window(.fiveHour)?.resetsAt == nil)  // never estimated
        #expect(snapshot.observedAt == Date(timeIntervalSince1970: 1_791_861_456.875))
        #expect(snapshot.source == .claudeDesktopHistory)
    }

    @Test func unknownDesktopFormatIsRejected() {
        #expect(ClaudeDesktopHistoryReader.parse(Data(#"{"version":3,"samples":[{"t":1,"u":{"fh":1}}]}"#.utf8)) == nil)
        #expect(ClaudeDesktopHistoryReader.parse(Data(#"{"samples":[]}"#.utf8)) == nil)
        #expect(ClaudeDesktopHistoryReader.parse(Data("garbage".utf8)) == nil)
    }

    @Test func statusLineCapture() throws {
        let data = Data(#"{"captured_at":1791860000,"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1791870000},"seven_day":{"used_percentage":41.2,"resets_at":1792400000}}}"#.utf8)
        let snapshot = try #require(ClaudeStatusLineBridge.parseCapture(data))
        #expect(snapshot.window(.fiveHour)?.usedPercent == 23.5)
        #expect(snapshot.window(.fiveHour)?.resetsAt == Date(timeIntervalSince1970: 1_791_870_000))
        #expect(snapshot.window(.weekly)?.usedPercent == 41.2)
        #expect(PercentFormatter.displayValue(usedPercent: 23.5, mode: .available) == 76)
    }

    @Test func statusLineCaptureWithAbsentWindows() {
        let partial = Data(#"{"captured_at":1791860000,"rate_limits":{"seven_day":{"used_percentage":41.2,"resets_at":1792400000}}}"#.utf8)
        #expect(ClaudeStatusLineBridge.parseCapture(partial)?.windows.map(\.kind) == [.weekly])
        let empty = Data(#"{"captured_at":1791860000,"rate_limits":{}}"#.utf8)
        #expect(ClaudeStatusLineBridge.parseCapture(empty) == nil)
    }

    @Test func combineKeepsResetTimesOnlyForTheSameWindow() {
        let statusLine = snapshot(used5h: 20, usedWeekly: 40, provider: .claude, observedAt: now,
                                  reset5h: now.addingTimeInterval(3600), resetWeekly: now.addingTimeInterval(-10),
                                  source: .claudeStatusLine)
        let desktop = snapshot(used5h: 30, usedWeekly: 41, provider: .claude, observedAt: now.addingTimeInterval(300),
                               reset5h: nil, resetWeekly: nil, source: .claudeDesktopHistory)
        let combined = ClaudeProvider.combine(statusLine: statusLine, desktop: desktop)
        #expect(combined?.source == .claudeDesktopHistory)
        #expect(combined?.window(.fiveHour)?.usedPercent == 30)
        #expect(combined?.window(.fiveHour)?.resetsAt == now.addingTimeInterval(3600))
        #expect(combined?.window(.weekly)?.resetsAt == nil)  // already passed: not carried over

        let older = ClaudeProvider.combine(statusLine: statusLine, desktop: snapshot(used5h: 1, usedWeekly: 1, provider: .claude,
                                                                                     observedAt: now.addingTimeInterval(-60), source: .claudeDesktopHistory))
        #expect(older?.source == .claudeStatusLine)
        #expect(ClaudeProvider.combine(statusLine: nil, desktop: nil) == nil)
    }
}
