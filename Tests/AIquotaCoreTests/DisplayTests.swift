import Foundation
import Testing
@testable import AIquotaCore

@Suite struct PercentFormattingTests {
    @Test(arguments: [
        (0.0, 100, 0), (1.0, 99, 1), (50.0, 50, 50), (80.0, 20, 80), (90.0, 10, 90),
        (91.0, 9, 91), (95.0, 5, 95), (100.0, 0, 100),
    ])
    func availableAndConsumed(used: Double, available: Int, consumed: Int) {
        #expect(PercentFormatter.displayValue(usedPercent: used, mode: .available) == available)
        #expect(PercentFormatter.displayValue(usedPercent: used, mode: .consumed) == consumed)
    }

    @Test(arguments: [0.3, 23.5, 41.2, 62.8, 99.4, 99.99])
    func roundingNeverOverstatesAndModesSumTo100(used: Double) {
        let available = PercentFormatter.displayValue(usedPercent: used, mode: .available)
        let consumed = PercentFormatter.displayValue(usedPercent: used, mode: .consumed)
        #expect(available + consumed == 100)
        #expect(Double(available) <= 100 - used)
    }

    @Test func clampsOutOfRangeValues() {
        #expect(PercentFormatter.displayValue(usedPercent: 120, mode: .available) == 0)
        #expect(PercentFormatter.displayValue(usedPercent: -5, mode: .available) == 100)
    }

    @Test func fractionMatchesDisplayedNumber() {
        #expect(PercentFormatter.fraction(usedPercent: 62, mode: .available) == 0.38)
        #expect(PercentFormatter.fraction(usedPercent: 62, mode: .consumed) == 0.62)
    }
}

@Suite struct ToneTests {
    @Test(arguments: [
        (100.0, Tone.neutral), (50.0, .neutral), (20.1, .neutral), (20.0, .caution), (15.0, .caution),
        (10.0, .caution), (9.9, .critical), (5.0, .critical), (0.0, .critical),
    ])
    func defaultBands(available: Double, tone: Tone) {
        #expect(ToneThresholds.default.tone(forAvailable: available) == tone)
    }

    @Test func customThresholds() {
        let thresholds = ToneThresholds(caution: 30, critical: 15)
        #expect(thresholds.tone(forAvailable: 25) == .caution)
        #expect(thresholds.tone(forAvailable: 14) == .critical)
    }

    @Test func toneFollowsAvailableEvenInConsumedMode() {
        let status = statusWith(used5h: 95, usedWeekly: 10)
        let cells = IndicatorModelBuilder.cells(for: status, windows: .both, mode: .consumed, thresholds: .default, now: now)
        #expect(cells[0].value == 95)
        #expect(cells[0].tone == .critical)  // 5% available
        #expect(cells[1].tone == .neutral)   // 90% available
    }
}

@Suite struct IndicatorModelTests {
    @Test func superscriptLabels() {
        #expect(WindowKind.fiveHour.shortLabel == "5h")
        #expect(WindowKind.weekly.shortLabel == "7d")
        let cells = IndicatorModelBuilder.cells(for: statusWith(used5h: 17, usedWeekly: 58), windows: .both,
                                                mode: .available, thresholds: .default, now: now)
        #expect(cells.map(\.label) == ["5h", "7d"])
        #expect(cells.map(\.value) == [83, 42])
    }

    @Test func windowSelection() {
        let status = statusWith(used5h: 17, usedWeekly: 58)
        #expect(IndicatorModelBuilder.cells(for: status, windows: .fiveHourOnly, mode: .available, thresholds: .default, now: now).map(\.kind) == [.fiveHour])
        #expect(IndicatorModelBuilder.cells(for: status, windows: .weeklyOnly, mode: .available, thresholds: .default, now: now).map(\.kind) == [.weekly])
    }

    @Test func missingDataIsNeverShownAsAFullLimit() {
        let status = ProviderStatus(provider: .claude, displayName: "Claude Code")
        let cells = IndicatorModelBuilder.cells(for: status, windows: .both, mode: .available, thresholds: .default, now: now)
        #expect(cells.allSatisfy { $0.value == nil && $0.tone == .muted && $0.fraction == 0 })
    }

    @Test func windowsTheAccountDoesNotHaveAreHidden() {
        // e.g. a plan with only a weekly limit
        var status = statusWith(used5h: 17, usedWeekly: 58)
        status.snapshot?.windows.removeAll { $0.kind == .fiveHour }
        let cells = IndicatorModelBuilder.cells(for: status, windows: .both, mode: .available, thresholds: .default, now: now)
        #expect(cells.map(\.kind) == [.weekly])
        #expect(cells.first?.value == 42)
    }

    @Test func statusLineGapKeepsPlaceholder() {
        var status = statusWith(used5h: 17, usedWeekly: 58, provider: .claude)
        status.snapshot?.source = .claudeStatusLine
        status.snapshot?.windows.removeAll { $0.kind == .fiveHour }
        let cells = IndicatorModelBuilder.cells(for: status, windows: .both, mode: .available, thresholds: .default, now: now)
        #expect(cells.map(\.kind) == [.fiveHour, .weekly])
        #expect(cells[0].value == nil)
    }

    @Test func onlySelectedButUnavailableWindowFallsBackToPlaceholder() {
        var status = statusWith(used5h: 17, usedWeekly: 58)
        status.snapshot?.windows.removeAll { $0.kind == .fiveHour }
        let cells = IndicatorModelBuilder.cells(for: status, windows: .fiveHourOnly, mode: .available, thresholds: .default, now: now)
        #expect(cells.map(\.kind) == [.fiveHour])
        #expect(cells[0].value == nil)
    }

    @Test func weeklyOnlyCodexResponseIsClassifiedByDuration() throws {
        let data = Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":1792297736},"secondary":null}}"#.utf8)
        let snapshot = try CodexRateLimitParser.parseReadResponse(data, observedAt: now)
        let status = ProviderStatus(provider: .codex, displayName: "Codex", snapshot: snapshot, state: .connected)
        let cells = IndicatorModelBuilder.cells(for: status, windows: .both, mode: .available, thresholds: .default, now: now)
        #expect(cells.map(\.kind) == [.weekly])
        #expect(cells.first?.value == 70)
    }

    @Test func rolledOverWindowIsNotShownAsCurrent() {
        var status = statusWith(used5h: 90, usedWeekly: 58)
        status.snapshot?.windows[0].resetsAt = now.addingTimeInterval(-60)
        let cells = IndicatorModelBuilder.cells(for: status, windows: .both, mode: .available, thresholds: .default, now: now)
        #expect(cells[0].value == nil)
        #expect(cells[1].value == 42)
    }

    @Test func staleDataIsMuted() {
        var status = statusWith(used5h: 95, usedWeekly: 58)
        status.snapshot?.observedAt = now.addingTimeInterval(-4 * 3600)
        let windows = status.snapshot!.windows.map { var w = $0; w.resetsAt = nil; return w }
        status.snapshot?.windows = windows
        let cells = IndicatorModelBuilder.cells(for: status, windows: .both, mode: .available, thresholds: .default, now: now)
        #expect(cells[0].value == 5)
        #expect(cells[0].tone == .muted)
    }

    @Test func freshnessStates() {
        var status = statusWith(used5h: 10, usedWeekly: 10)
        #expect(status.freshness(at: now) == .current)
        status.loadedFromCache = true
        #expect(status.freshness(at: now) == .cached)
        status.loadedFromCache = false
        status.snapshot?.observedAt = now.addingTimeInterval(-20 * 60)
        #expect(status.freshness(at: now) == .cached)
        status.snapshot?.observedAt = now.addingTimeInterval(-4 * 3600)
        #expect(status.freshness(at: now) == .stale)
        status.snapshot = nil
        #expect(status.freshness(at: now) == .unavailable)
    }

    @Test func windowClassificationUsesRealDurations() {
        #expect(WindowKind.classify(durationMinutes: 300) == .fiveHour)
        #expect(WindowKind.classify(durationMinutes: 10_080) == .weekly)
        #expect(WindowKind.classify(durationMinutes: 1_440) == .other)
        #expect(WindowKind.classify(durationMinutes: nil) == .other)
    }

    @Test func relativeTime() {
        #expect(RelativeTime.countdown(to: now.addingTimeInterval(2 * 3600 + 14 * 60), from: now) == "2h 14m")
        #expect(RelativeTime.countdown(to: now.addingTimeInterval(3 * 86_400 + 4 * 3600 + 59), from: now) == "3d 4h")
        #expect(RelativeTime.countdown(to: now.addingTimeInterval(45 * 60), from: now) == "45m")
        #expect(RelativeTime.countdown(to: now.addingTimeInterval(20), from: now) == "<1m")
        #expect(RelativeTime.countdown(to: now.addingTimeInterval(-100), from: now) == "<1m")
    }
}

let now = Date(timeIntervalSince1970: 1_791_860_000)

func statusWith(used5h: Double, usedWeekly: Double, provider: ProviderID = .codex, observedAt: Date = now) -> ProviderStatus {
    ProviderStatus(provider: provider, displayName: provider == .codex ? "Codex" : "Claude Code",
                   snapshot: snapshot(used5h: used5h, usedWeekly: usedWeekly, provider: provider, observedAt: observedAt),
                   state: .connected)
}

func snapshot(used5h: Double, usedWeekly: Double, provider: ProviderID = .codex, observedAt: Date = now,
              reset5h: Date? = now.addingTimeInterval(3600), resetWeekly: Date? = now.addingTimeInterval(86_400),
              source: DataSource = .codexAppServer) -> QuotaSnapshot {
    QuotaSnapshot(provider: provider, windows: [
        QuotaWindow(kind: .fiveHour, durationMinutes: 300, usedPercent: used5h, resetsAt: reset5h),
        QuotaWindow(kind: .weekly, durationMinutes: 10_080, usedPercent: usedWeekly, resetsAt: resetWeekly),
    ], observedAt: observedAt, source: source)
}

@Suite struct OutdatedWindowTests {
    @Test func readingOlderThanTheWindowWithoutResetTimeIsOutdated() {
        var status = statusWith(used5h: 100, usedWeekly: 40, provider: .claude, observedAt: now.addingTimeInterval(-6 * 3600))
        let windows = status.snapshot!.windows.map { var w = $0; w.resetsAt = nil; return w }
        status.snapshot?.windows = windows
        let cells = IndicatorModelBuilder.cells(for: status, windows: .both, mode: .available, thresholds: .default, now: now)
        #expect(cells[0].value == nil)          // a 5h window seen 6h ago has certainly renewed
        #expect(cells[1].value == 60)           // weekly window is still the same period (dimmed as stale)
        #expect(cells[1].tone == .muted)
    }

    @Test func recentReadingWithoutResetTimeIsKept() {
        var status = statusWith(used5h: 40, usedWeekly: 40, provider: .claude, observedAt: now.addingTimeInterval(-600))
        let windows = status.snapshot!.windows.map { var w = $0; w.resetsAt = nil; return w }
        status.snapshot?.windows = windows
        let cells = IndicatorModelBuilder.cells(for: status, windows: .both, mode: .available, thresholds: .default, now: now)
        #expect(cells.map(\.value) == [60, 60])
    }
}
