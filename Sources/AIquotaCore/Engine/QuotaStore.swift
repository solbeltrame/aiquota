import Combine
import Foundation

/// Coordinates providers: local events first, adaptive polling as fallback, cache at launch.
@MainActor
public final class QuotaStore: ObservableObject {
    public enum RefreshReason: String, Sendable {
        case launch, event, poll, manual, wake, settings
    }

    @Published public private(set) var statuses: [ProviderID: ProviderStatus] = [:]
    @Published public private(set) var detections: [ProviderID: ProviderDetection] = [:]
    @Published public private(set) var isShowingFixtures = false

    public let providers: [any QuotaProvider]
    public var onAlert: ((AlertEvent) -> Void)?

    public private(set) var settings: AppSettings
    private var schedulers: [ProviderID: RefreshScheduler] = [:]
    private var pollTasks: [ProviderID: Task<Void, Never>] = [:]
    private var eventFetchTasks: [ProviderID: Task<Void, Never>] = [:]
    private var inFlight: Set<ProviderID> = []
    private var started = false
    private let cache: SnapshotCache?
    private let alertDefaults: UserDefaults
    private static let firedKeysKey = "alerts.firedKeys.v1"
    private var firedKeys: Set<String>

    public init(providers: [any QuotaProvider], settings: AppSettings, cache: SnapshotCache? = SnapshotCache(),
                alertDefaults: UserDefaults = .standard) {
        self.providers = providers
        self.settings = settings
        self.cache = cache
        self.alertDefaults = alertDefaults
        self.firedKeys = Set(alertDefaults.stringArray(forKey: Self.firedKeysKey) ?? [])
        for provider in providers {
            statuses[provider.id] = ProviderStatus(provider: provider.id, displayName: provider.displayName,
                                                   state: .waitingForData(""))
            schedulers[provider.id] = RefreshScheduler(policy: provider.refreshPolicy,
                                                       userActiveInterval: settings.refreshInterval)
        }
    }

    public func provider(_ id: ProviderID) -> (any QuotaProvider)? {
        providers.first { $0.id == id }
    }

    public var orderedStatuses: [ProviderStatus] {
        providers.compactMap { statuses[$0.id] }
    }

    // MARK: Lifecycle

    public func start() {
        guard !started else { return }
        started = true
        if let cache {
            for (id, snapshot) in cache.load() where statuses[id] != nil {
                statuses[id]?.snapshot = snapshot
                statuses[id]?.loadedFromCache = true
            }
        }
        for provider in providers { activate(provider) }
        Task { await refreshDetections() }
    }

    public func stop() {
        for provider in providers { deactivate(provider.id) }
        started = false
    }

    /// Replaces live data with sample data for screenshots and visual checks.
    public func showFixtures(_ statuses: [ProviderStatus]) {
        stop()
        isShowingFixtures = true
        for status in statuses { self.statuses[status.provider] = status }
    }

    public func update(settings newValue: AppSettings) {
        let old = settings
        settings = newValue
        for provider in providers {
            schedulers[provider.id]?.userActiveInterval = newValue.refreshInterval
            let wasEnabled = old.providerSettings(provider.id).enabled
            let isEnabled = newValue.providerSettings(provider.id).enabled
            guard started, !isShowingFixtures else { continue }
            if wasEnabled != isEnabled {
                isEnabled ? activate(provider) : deactivate(provider.id)
                continue
            }
            if old.refreshInterval != newValue.refreshInterval { schedulePoll(provider.id) }
            // Source settings changed: re-read (still subject to the provider's minimum interval).
            if old.useClaudeDesktopHistory != newValue.useClaudeDesktopHistory
                || old.codexExecutablePath != newValue.codexExecutablePath {
                refresh(provider.id, reason: .settings)
            }
        }
    }

    public func refreshDetections() async {
        for provider in providers {
            detections[provider.id] = await provider.detect()
        }
    }

    // MARK: Refreshing

    public func refreshAll(reason: RefreshReason) {
        for provider in providers { refresh(provider.id, reason: reason) }
    }

    public func refresh(_ id: ProviderID, reason: RefreshReason) {
        guard started, !isShowingFixtures, settings.providerSettings(id).enabled else { return }
        Task { await performFetch(id, reason: reason) }
    }

    private func activate(_ provider: any QuotaProvider) {
        let id = provider.id
        guard settings.providerSettings(id).enabled else {
            statuses[id]?.state = .disabled
            return
        }
        provider.startWatching { [weak self] signal in
            Task { @MainActor in self?.handle(signal, from: id) }
        }
        Task { await performFetch(id, reason: .launch) }
    }

    private func deactivate(_ id: ProviderID) {
        provider(id)?.stopWatching()
        pollTasks[id]?.cancel(); pollTasks[id] = nil
        eventFetchTasks[id]?.cancel(); eventFetchTasks[id] = nil
        if !settings.providerSettings(id).enabled { statuses[id]?.state = .disabled }
    }

    func handle(_ signal: ChangeSignal, from id: ProviderID) {
        guard settings.providerSettings(id).enabled, !isShowingFixtures else { return }
        let now = Date()
        schedulers[id]?.recordEvent(at: now)
        if let snapshot = signal.snapshot { apply(snapshot, for: id) }
        guard signal.wantsFetch, eventFetchTasks[id] == nil, let scheduler = schedulers[id] else { return }
        let delay = max(0, scheduler.earliestFetch(at: now).timeIntervalSince(now))
        eventFetchTasks[id] = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            self?.eventFetchTasks[id] = nil
            await self?.performFetch(id, reason: .event)
        }
    }

    private func performFetch(_ id: ProviderID, reason: RefreshReason) async {
        guard let provider = provider(id), !inFlight.contains(id) else { return }
        if let last = schedulers[id]?.lastFetch {
            let minimumGap: TimeInterval
            switch reason {
            case .launch, .wake: minimumGap = 0
            case .manual: minimumGap = min(5, provider.refreshPolicy.minimumInterval)
            case .event, .poll, .settings: minimumGap = provider.refreshPolicy.minimumInterval
            }
            if Date().timeIntervalSince(last) < minimumGap {
                if reason == .settings { schedulePoll(id) }
                return
            }
        }
        inFlight.insert(id)
        schedulers[id]?.recordFetchStarted(at: Date())
        do {
            let snapshot = try await provider.fetch()
            schedulers[id]?.recordSuccess()
            apply(snapshot, for: id)
            statuses[id]?.state = .connected
        } catch {
            let providerError = (error as? ProviderError) ?? .failed(error.localizedDescription)
            schedulers[id]?.recordFailure(providerError, at: Date())
            statuses[id]?.state = providerError.integrationState
            Log.store.info("\(id.rawValue, privacy: .public) fetch failed: \(String(describing: providerError), privacy: .public)")
        }
        statuses[id]?.lastAttempt = Date()
        inFlight.remove(id)
        schedulePoll(id)
    }

    private func schedulePoll(_ id: ProviderID) {
        pollTasks[id]?.cancel()
        guard started, settings.providerSettings(id).enabled, let scheduler = schedulers[id] else { return }
        let delay = max(1, scheduler.nextPoll(at: Date()).timeIntervalSinceNow)
        pollTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.performFetch(id, reason: .poll)
        }
    }

    // MARK: Applying data

    /// Accepts a snapshot if it is not older than what we show, merges sparse fields and evaluates alerts.
    public func apply(_ incoming: QuotaSnapshot, for id: ProviderID, now: Date = Date()) {
        guard var status = statuses[id] else { return }
        let previous = status.snapshot
        if let previous, !status.loadedFromCache, !previous.isFixture, incoming.observedAt < previous.observedAt {
            return
        }
        var merged = incoming
        if let previous, previous.provider == incoming.provider {
            if merged.resetCredits == nil { merged.resetCredits = previous.resetCredits }
            if merged.planName == nil { merged.planName = previous.planName }
        }
        status.snapshot = merged
        status.loadedFromCache = false
        if case .connected = status.state {} else { status.state = .connected }
        statuses[id] = status

        if !merged.isFixture {
            let events = AlertEngine.evaluate(previous: previous?.isFixture == true ? nil : previous, current: merged,
                                              providerName: status.displayName, settings: settings.alerts,
                                              firedKeys: &firedKeys, now: now)
            persistFiredKeys()
            events.forEach { onAlert?($0) }
            saveCache()
        }
    }

    private func persistFiredKeys() {
        alertDefaults.set(Array(firedKeys.sorted().suffix(300)), forKey: Self.firedKeysKey)
    }

    private func saveCache() {
        guard let cache else { return }
        var snapshots: [ProviderID: QuotaSnapshot] = [:]
        for (id, status) in statuses { if let snapshot = status.snapshot { snapshots[id] = snapshot } }
        cache.save(snapshots)
    }

    // MARK: Test hooks

    public func _scheduler(for id: ProviderID) -> RefreshScheduler? { schedulers[id] }
    public func _markStarted() { started = true }
}
