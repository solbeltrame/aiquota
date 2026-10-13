import Foundation
import Testing
@testable import AIquotaCore

@Suite struct RefreshSchedulerTests {
    let policy = RefreshPolicy(minimumInterval: 20, activeInterval: 60, idleInterval: 300, activityWindow: 600, maximumBackoff: 1800)

    @Test func firstFetchIsImmediate() {
        let scheduler = RefreshScheduler(policy: policy)
        #expect(scheduler.nextPoll(at: now) == now)
        #expect(scheduler.earliestFetch(at: now) == now)
    }

    @Test func adaptivePolling() {
        var scheduler = RefreshScheduler(policy: policy)
        scheduler.recordFetchStarted(at: now)
        scheduler.recordSuccess()
        #expect(scheduler.nextPoll(at: now) == now.addingTimeInterval(300))      // idle
        scheduler.recordEvent(at: now)
        #expect(scheduler.nextPoll(at: now) == now.addingTimeInterval(60))       // active
        #expect(scheduler.nextPoll(at: now.addingTimeInterval(700)) == now.addingTimeInterval(300))  // idle again
    }

    @Test func eventsAreDebouncedByMinimumInterval() {
        var scheduler = RefreshScheduler(policy: policy)
        scheduler.recordFetchStarted(at: now)
        scheduler.recordSuccess()
        #expect(scheduler.earliestFetch(at: now.addingTimeInterval(5)) == now.addingTimeInterval(20))
        #expect(scheduler.earliestFetch(at: now.addingTimeInterval(30)) == now.addingTimeInterval(30))
    }

    @Test func userIntervalIsClampedToSafeBounds() {
        #expect(RefreshScheduler(policy: policy, userActiveInterval: 1).activeInterval == 30)
        #expect(RefreshScheduler(policy: policy, userActiveInterval: 99_999).activeInterval == 900)
        #expect(RefreshScheduler(policy: policy, userActiveInterval: 120).activeInterval == 120)
        #expect(RefreshScheduler(policy: policy, userActiveInterval: 600).idleInterval == 600)
    }

    @Test func exponentialBackoffAfterFailures() {
        var scheduler = RefreshScheduler(policy: policy)
        scheduler.recordFetchStarted(at: now)
        scheduler.recordFailure(.failed("x"), at: now)
        #expect(scheduler.backoff() == 60)
        scheduler.recordFailure(.failed("x"), at: now)
        #expect(scheduler.backoff() == 120)
        for _ in 0..<10 { scheduler.recordFailure(.failed("x"), at: now) }
        #expect(scheduler.backoff() == 1800)
        scheduler.recordSuccess()
        #expect(scheduler.backoff() == 0)
    }

    @Test func noDataIsNotAFailure() {
        var scheduler = RefreshScheduler(policy: policy)
        scheduler.recordFailure(.noData("waiting"), at: now)
        #expect(scheduler.consecutiveFailures == 0)
    }

    @Test func retryAfterIsRespected() {
        var scheduler = RefreshScheduler(policy: policy)
        scheduler.recordFetchStarted(at: now)
        scheduler.recordFailure(.rateLimited(retryAfter: 900), at: now)
        #expect(scheduler.earliestFetch(at: now) == now.addingTimeInterval(900))
        #expect(scheduler.nextPoll(at: now) >= now.addingTimeInterval(900))
    }
}

@Suite struct AlertEngineTests {
    let settings = AlertSettings()

    func evaluate(_ previous: QuotaSnapshot?, _ current: QuotaSnapshot, _ fired: inout Set<String>,
                  settings: AlertSettings? = nil, at time: Date = now) -> [AlertEvent] {
        AlertEngine.evaluate(previous: previous, current: current, providerName: "Codex",
                             settings: settings ?? self.settings, firedKeys: &fired, now: time)
    }

    @Test func crossingThresholdNotifiesOnce() {
        var fired = Set<String>()
        let events = evaluate(snapshot(used5h: 50, usedWeekly: 10), snapshot(used5h: 82, usedWeekly: 10), &fired)
        #expect(events.map(\.kind) == [.lowAvailable(threshold: 20, available: 18)])
        // Same state again: nothing new.
        #expect(evaluate(snapshot(used5h: 82, usedWeekly: 10), snapshot(used5h: 83, usedWeekly: 10), &fired).isEmpty)
    }

    @Test func jumpingPastSeveralThresholdsSendsOnlyTheLowest() {
        var fired = Set<String>()
        let events = evaluate(nil, snapshot(used5h: 97, usedWeekly: 0), &fired)
        #expect(events.map(\.kind) == [.lowAvailable(threshold: 5, available: 3)])
        // Later dipping "below 10" must not fire, it was already passed.
        #expect(evaluate(nil, snapshot(used5h: 98, usedWeekly: 0), &fired).isEmpty)
    }

    @Test func disabledThresholdsAreSkipped() {
        var fired = Set<String>()
        var custom = AlertSettings()
        custom.lowAvailableThresholds = [20: false, 10: true, 5: false]
        #expect(evaluate(nil, snapshot(used5h: 85, usedWeekly: 0), &fired, settings: custom).isEmpty)
        #expect(evaluate(nil, snapshot(used5h: 92, usedWeekly: 0), &fired, settings: custom).map(\.kind)
                == [.lowAvailable(threshold: 10, available: 8)])
    }

    @Test func thresholdsReArmAfterRecovery() {
        var fired = Set<String>()
        _ = evaluate(nil, snapshot(used5h: 85, usedWeekly: 0), &fired)
        _ = evaluate(nil, snapshot(used5h: 70, usedWeekly: 0), &fired)  // 30% available: re-armed
        #expect(evaluate(nil, snapshot(used5h: 85, usedWeekly: 0), &fired).count == 1)
    }

    @Test func renewalNeedsConfirmationFromData() {
        var fired = Set<String>()
        let before = snapshot(used5h: 95, usedWeekly: 30, reset5h: now)
        // Clock passed the reset but data still says 95%: no renewal.
        #expect(!evaluate(before, before, &fired, at: now.addingTimeInterval(60)).contains { $0.kind == .windowRenewed })
        // New data: usage dropped and reset moved forward.
        let after = snapshot(used5h: 2, usedWeekly: 30, observedAt: now.addingTimeInterval(120), reset5h: now.addingTimeInterval(5 * 3600))
        let events = evaluate(before, after, &fired, at: now.addingTimeInterval(120))
        #expect(events.map(\.kind) == [.windowRenewed])
        #expect(events.first?.window == .fiveHour)
        // Not repeated.
        #expect(evaluate(before, after, &fired, at: now.addingTimeInterval(120)).isEmpty)
    }

    @Test func renewalNotAnnouncedLongAfterTheFact() {
        var fired = Set<String>()
        let before = snapshot(used5h: 95, usedWeekly: 30, observedAt: now.addingTimeInterval(-3 * 86_400), reset5h: now.addingTimeInterval(-2 * 86_400))
        let after = snapshot(used5h: 2, usedWeekly: 30, reset5h: now.addingTimeInterval(3600))
        #expect(evaluate(before, after, &fired).isEmpty)
    }

    @Test func resetCreditExpiringOncePerCredit() {
        var fired = Set<String>()
        var current = snapshot(used5h: 10, usedWeekly: 10)
        current.resetCredits = ResetCreditsSummary(availableCount: 2, credits: [
            ResetCredit(id: "soon", expiresAt: now.addingTimeInterval(24 * 3600)),
            ResetCredit(id: "later", expiresAt: now.addingTimeInterval(20 * 86_400)),
        ])
        let events = evaluate(nil, current, &fired)
        #expect(events.count == 1)
        if case .resetCreditExpiring(let id, _) = events.first?.kind { #expect(id == "soon") } else { Issue.record("wrong kind") }
        #expect(evaluate(nil, current, &fired).isEmpty)
    }

    @Test func fixturesNeverNotify() {
        var fired = Set<String>()
        let sample = Fixtures.snapshot(.codex, fiveHourAvailable: 1, weeklyAvailable: 1, now: now)
        #expect(evaluate(nil, sample, &fired).isEmpty)
        #expect(fired.isEmpty)
    }
}

@Suite struct SettingsPersistenceTests {
    @Test func roundTrip() throws {
        let suite = "aiquota.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = SettingsStore(suiteName: suite)
        var settings = AppSettings()
        settings.appearance.style = .ring
        settings.appearance.numberSize = 11
        settings.appearance.cautionColorHex = "#AA8800"
        settings.appearance.showProviderIcon = true
        settings.valueMode = .consumed
        settings.windows = .weeklyOnly
        settings.thresholds = ToneThresholds(caution: 25, critical: 8)
        settings.updateProvider(.claude) { $0.enabled = false; $0.windows = .fiveHourOnly }
        settings.alerts.lowAvailableThresholds[5] = false
        settings.language = .portugueseBR
        settings.onboardingCompleted = true
        store.save(settings)
        #expect(store.load() == settings)
        #expect(store.load().windows(for: .claude) == .fiveHourOnly)
        #expect(store.load().windows(for: .codex) == .weeklyOnly)
    }

    @Test func missingAndInvalidFieldsFallBackToDefaults() throws {
        let partial = Data(#"{"valueMode":"consumed","appearance":{"style":"bogus","numberSize":99},"refreshInterval":1}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: partial)
        #expect(settings.valueMode == .consumed)
        #expect(settings.appearance.style == .microbar)
        #expect(settings.appearance.numberSize == AppearanceSettings.numberSizeRange.upperBound)
        #expect(settings.refreshInterval == 30)
        #expect(settings.alerts == AlertSettings())
        #expect(settings.providerSettings(.codex).enabled)
    }

    @Test func defaultsMatchSpec() {
        let settings = AppSettings()
        #expect(settings.appearance.style == .microbar)
        #expect(settings.valueMode == .available)
        #expect(settings.windows == .both)
        #expect(settings.thresholds == ToneThresholds(caution: 20, critical: 10))
        #expect(settings.alerts.enabledThresholds == [20, 10, 5])
        #expect(settings.appearance.showProviderIcon == false)
    }
}

@Suite struct CacheTests {
    @Test func roundTripSkipsFixtures() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aiquota-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = SnapshotCache(url: url)
        let real = snapshot(used5h: 10, usedWeekly: 20)
        cache.save([.codex: real, .claude: Fixtures.snapshot(.claude, fiveHourAvailable: 50, weeklyAvailable: 50)])
        let loaded = cache.load()
        #expect(loaded[.codex] == real)
        #expect(loaded[.claude] == nil)
    }
}
