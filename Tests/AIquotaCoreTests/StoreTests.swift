import Foundation
import Testing
@testable import AIquotaCore

final class MockProvider: QuotaProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName = "Mock"
    let refreshPolicy = RefreshPolicy(minimumInterval: 0.05, activeInterval: 30, idleInterval: 300)
    var results: [Result<QuotaSnapshot, ProviderError>]
    private(set) var fetchCount = 0
    var emit: (@Sendable (ChangeSignal) -> Void)?

    init(id: ProviderID = .codex, results: [Result<QuotaSnapshot, ProviderError>]) {
        self.id = id
        self.results = results
    }

    func detect() async -> ProviderDetection { ProviderDetection(isInstalled: true) }

    func fetch() async throws -> QuotaSnapshot {
        fetchCount += 1
        let result = results.count > 1 ? results.removeFirst() : results[0]
        return try result.get()
    }

    func startWatching(emit: @escaping @Sendable (ChangeSignal) -> Void) { self.emit = emit }
    func stopWatching() { emit = nil }
}

@MainActor
@Suite struct QuotaStoreTests {
    func makeStore(_ provider: MockProvider, settings: AppSettings = AppSettings()) -> (QuotaStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "aiquota.tests.\(UUID().uuidString)")!
        let store = QuotaStore(providers: [provider], settings: settings, cache: nil, alertDefaults: defaults)
        return (store, defaults)
    }

    func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    @Test func launchFetchesAndPublishes() async {
        let provider = MockProvider(results: [.success(snapshot(used5h: 17, usedWeekly: 58, observedAt: Date()))])
        let (store, _) = makeStore(provider)
        store.start()
        await waitUntil { store.statuses[.codex]?.snapshot != nil }
        #expect(store.statuses[.codex]?.state == .connected)
        #expect(store.statuses[.codex]?.snapshot?.window(.fiveHour)?.usedPercent == 17)
        store.stop()
    }

    @Test func authenticationFailureIsReportedWithoutFakeData() async {
        let provider = MockProvider(results: [.failure(.notAuthenticated)])
        let (store, _) = makeStore(provider)
        store.start()
        await waitUntil { store.statuses[.codex]?.state == .notAuthenticated }
        #expect(store.statuses[.codex]?.state == .notAuthenticated)
        #expect(store.statuses[.codex]?.snapshot == nil)
        #expect(store._scheduler(for: .codex)?.consecutiveFailures == 1)
        store.stop()
    }

    @Test func failureKeepsLastGoodDataAndMarksError() async {
        let provider = MockProvider(results: [.success(snapshot(used5h: 30, usedWeekly: 30, observedAt: Date())),
                                              .failure(.failed("boom"))])
        let (store, _) = makeStore(provider)
        store.start()
        await waitUntil { store.statuses[.codex]?.snapshot != nil }
        store.refresh(.codex, reason: .settings)
        await waitUntil { store.statuses[.codex]?.state == .error("boom") }
        #expect(store.statuses[.codex]?.snapshot?.window(.fiveHour)?.usedPercent == 30)
        store.stop()
    }

    @Test func eventSnapshotAppliesImmediatelyThenFetchConfirms() async {
        let confirmed = snapshot(used5h: 62, usedWeekly: 90, observedAt: Date().addingTimeInterval(10))
        let provider = MockProvider(results: [.success(snapshot(used5h: 50, usedWeekly: 90, observedAt: Date())), .success(confirmed)])
        let (store, _) = makeStore(provider)
        store.start()
        await waitUntil { provider.fetchCount == 1 && store.statuses[.codex]?.snapshot != nil }

        var fromLog = snapshot(used5h: 61, usedWeekly: 90, observedAt: Date().addingTimeInterval(5), source: .codexSessionLog)
        fromLog.resetCredits = nil
        store.handle(ChangeSignal(snapshot: fromLog, wantsFetch: true), from: .codex)
        #expect(store.statuses[.codex]?.snapshot?.source == .codexSessionLog)
        #expect(store._scheduler(for: .codex)?.isActive(at: Date()) == true)

        await waitUntil { provider.fetchCount == 2 && store.statuses[.codex]?.snapshot?.source == .codexAppServer }
        #expect(store.statuses[.codex]?.snapshot?.window(.fiveHour)?.usedPercent == 62)
        store.stop()
    }

    @Test func burstOfEventsCoalescesIntoOneFetch() async {
        let provider = MockProvider(results: [.success(snapshot(used5h: 10, usedWeekly: 10, observedAt: Date()))])
        let (store, _) = makeStore(provider)
        store.start()
        await waitUntil { provider.fetchCount == 1 }
        for _ in 0..<10 { store.handle(ChangeSignal(), from: .codex) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(provider.fetchCount == 2)
        store.stop()
    }

    @Test func olderSnapshotsDoNotOverwriteNewerOnes() {
        let provider = MockProvider(results: [.failure(.noData(""))])
        let (store, _) = makeStore(provider)
        store.apply(snapshot(used5h: 40, usedWeekly: 40, observedAt: now), for: .codex, now: now)
        store.apply(snapshot(used5h: 10, usedWeekly: 10, observedAt: now.addingTimeInterval(-60)), for: .codex, now: now)
        #expect(store.statuses[.codex]?.snapshot?.window(.fiveHour)?.usedPercent == 40)
    }

    @Test func resetCreditsSurviveSparseUpdates() {
        let provider = MockProvider(results: [.failure(.noData(""))])
        let (store, _) = makeStore(provider)
        var first = snapshot(used5h: 40, usedWeekly: 40, observedAt: now)
        first.resetCredits = ResetCreditsSummary(availableCount: 2)
        first.planName = "Plus"
        store.apply(first, for: .codex, now: now)
        store.apply(snapshot(used5h: 45, usedWeekly: 40, observedAt: now.addingTimeInterval(5), source: .codexSessionLog), for: .codex, now: now)
        #expect(store.statuses[.codex]?.snapshot?.resetCredits?.availableCount == 2)
        #expect(store.statuses[.codex]?.snapshot?.planName == "Plus")
    }

    @Test func duplicateAlertsAreSuppressedAcrossStoreInstances() {
        let provider = MockProvider(results: [.failure(.noData(""))])
        let defaults = UserDefaults(suiteName: "aiquota.tests.\(UUID().uuidString)")!
        var delivered: [AlertEvent] = []
        let store = QuotaStore(providers: [provider], settings: AppSettings(), cache: nil, alertDefaults: defaults)
        store.onAlert = { delivered.append($0) }
        store.apply(snapshot(used5h: 85, usedWeekly: 10, observedAt: now), for: .codex, now: now)
        store.apply(snapshot(used5h: 86, usedWeekly: 10, observedAt: now.addingTimeInterval(5)), for: .codex, now: now)
        #expect(delivered.count == 1)

        // A relaunch (new store, same defaults) must not repeat it.
        let relaunched = QuotaStore(providers: [provider], settings: AppSettings(), cache: nil, alertDefaults: defaults)
        relaunched.onAlert = { delivered.append($0) }
        relaunched.apply(snapshot(used5h: 86, usedWeekly: 10, observedAt: now.addingTimeInterval(10)), for: .codex, now: now)
        #expect(delivered.count == 1)
    }

    @Test func disabledProviderIsNotFetched() async {
        let provider = MockProvider(results: [.success(snapshot(used5h: 10, usedWeekly: 10))])
        var settings = AppSettings()
        settings.updateProvider(.codex) { $0.enabled = false }
        let (store, _) = makeStore(provider, settings: settings)
        store.start()
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(provider.fetchCount == 0)
        #expect(store.statuses[.codex]?.state == .disabled)
        store.stop()
    }
}

@MainActor
@Suite struct StoreThrottlingTests {
    @Test func settingsChangesDoNotBypassTheMinimumInterval() async {
        final class SlowPolicyProvider: QuotaProvider, @unchecked Sendable {
            let id = ProviderID.codex
            let displayName = "Mock"
            let refreshPolicy = RefreshPolicy(minimumInterval: 60, activeInterval: 60, idleInterval: 300)
            var fetchCount = 0
            func detect() async -> ProviderDetection { ProviderDetection(isInstalled: true) }
            func fetch() async throws -> QuotaSnapshot { fetchCount += 1; return snapshot(used5h: 1, usedWeekly: 1, observedAt: Date()) }
            func startWatching(emit: @escaping @Sendable (ChangeSignal) -> Void) {}
            func stopWatching() {}
        }
        let provider = SlowPolicyProvider()
        let store = QuotaStore(providers: [provider], settings: AppSettings(), cache: nil,
                               alertDefaults: UserDefaults(suiteName: "aiquota.tests.\(UUID().uuidString)")!)
        store.start()
        for _ in 0..<100 where provider.fetchCount == 0 { try? await Task.sleep(nanoseconds: 10_000_000) }
        var settings = AppSettings()
        for path in ["/a", "/ab", "/abc"] {
            settings.codexExecutablePath = path
            store.update(settings: settings)
        }
        settings.refreshInterval = 120
        store.update(settings: settings)
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(provider.fetchCount == 1)
        store.stop()
    }
}
