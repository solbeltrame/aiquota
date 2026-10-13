import Foundation

/// What a provider knows about the local machine before fetching anything.
public struct ProviderDetection: Equatable, Sendable {
    public var isInstalled: Bool
    /// Human-readable lines for the Providers → Diagnostics panel. Never include secrets.
    public var notes: [String]

    public init(isInstalled: Bool, notes: [String] = []) {
        self.isInstalled = isInstalled
        self.notes = notes
    }
}

/// How often the store may ask a provider for data.
public struct RefreshPolicy: Equatable, Sendable {
    /// Lower bound between two fetches, even when events arrive in bursts.
    public var minimumInterval: TimeInterval
    /// Fallback polling while the provider shows recent activity.
    public var activeInterval: TimeInterval
    /// Fallback polling when nothing has happened for a while.
    public var idleInterval: TimeInterval
    /// How long after the last event the provider counts as "active".
    public var activityWindow: TimeInterval
    /// Upper bound for exponential backoff after failures.
    public var maximumBackoff: TimeInterval

    public init(minimumInterval: TimeInterval, activeInterval: TimeInterval, idleInterval: TimeInterval,
                activityWindow: TimeInterval = 10 * 60, maximumBackoff: TimeInterval = 30 * 60) {
        self.minimumInterval = minimumInterval
        self.activeInterval = activeInterval
        self.idleInterval = idleInterval
        self.activityWindow = activityWindow
        self.maximumBackoff = maximumBackoff
    }
}

/// A local hint that new data may be available. Providers may attach a snapshot they could read
/// instantly (for example from a local file) so the UI updates before the confirming fetch.
public struct ChangeSignal: Sendable {
    public var snapshot: QuotaSnapshot?
    /// When true the store should follow up with a `fetch()` (debounced by `minimumInterval`).
    public var wantsFetch: Bool

    public init(snapshot: QuotaSnapshot? = nil, wantsFetch: Bool = true) {
        self.snapshot = snapshot
        self.wantsFetch = wantsFetch
    }
}

public enum ProviderError: Error, Equatable, Sendable {
    case notInstalled
    case notAuthenticated
    case unsupported(String)
    /// The source asked us to slow down.
    case rateLimited(retryAfter: TimeInterval?)
    /// The integration works but has nothing to report yet (for example no Claude session ran).
    case noData(String)
    case failed(String)

    public var integrationState: IntegrationState {
        switch self {
        case .notInstalled: return .notInstalled
        case .notAuthenticated: return .notAuthenticated
        case .unsupported(let reason): return .unsupported(reason)
        case .rateLimited: return .error("Rate limited by source")
        case .noData(let reason): return .waitingForData(reason)
        case .failed(let reason): return .error(reason)
        }
    }

    /// `noData` is a normal state, not a failure worth backing off from.
    public var countsAsFailure: Bool {
        if case .noData = self { return false }
        return true
    }
}

/// The extension point for new integrations (Gemini, Copilot, Cursor, …).
///
/// Implementations must:
/// - only use local or officially documented interfaces where possible;
/// - never persist or log credentials;
/// - never call a model just to learn about limits;
/// - report real durations in `QuotaWindow.durationMinutes` and let `WindowKind.classify` label them.
public protocol QuotaProvider: AnyObject, Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    var refreshPolicy: RefreshPolicy { get }

    /// Cheap, local check (files, binaries). Must not hit the network.
    func detect() async -> ProviderDetection

    /// Read the best data currently available. Throw `ProviderError` on failure.
    func fetch() async throws -> QuotaSnapshot

    /// Start watching local events. Call `emit` whenever new data may exist.
    func startWatching(emit: @escaping @Sendable (ChangeSignal) -> Void)
    func stopWatching()
}
