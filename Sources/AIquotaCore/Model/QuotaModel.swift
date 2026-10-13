import Foundation

/// Stable identifier for a provider. New providers add a static constant.
public struct ProviderID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    public static let codex = ProviderID("codex")
    public static let claude = ProviderID("claude")
}

/// The kind of rolling window, derived from the duration the source reports.
public enum WindowKind: String, Codable, Sendable, CaseIterable {
    case fiveHour
    case weekly
    case other

    /// Classifies a window by its real duration instead of assuming every account has the same windows.
    public static func classify(durationMinutes: Int?) -> WindowKind {
        guard let minutes = durationMinutes else { return .other }
        switch minutes {
        case 240...360: return .fiveHour
        case 9_000...11_000: return .weekly
        default: return .other
        }
    }

    /// Tiny label rendered as a superscript in the menu bar.
    public var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "7d"
        case .other: return "•"
        }
    }
}

/// One usage window (for example "5 hours" or "weekly"), normalized across providers.
public struct QuotaWindow: Codable, Equatable, Sendable {
    public var kind: WindowKind
    public var durationMinutes: Int?
    /// Percentage consumed, 0...100 (sources may report values slightly outside; we clamp on read).
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(kind: WindowKind, durationMinutes: Int? = nil, usedPercent: Double, resetsAt: Date? = nil) {
        self.kind = kind
        self.durationMinutes = durationMinutes
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    public var clampedUsed: Double { min(100, max(0, usedPercent)) }
    public var availablePercent: Double { 100 - clampedUsed }

    /// True when the source's reset time has passed: the usage value belongs to a finished window
    /// and must not be shown as current.
    public func hasRolledOver(at now: Date) -> Bool {
        guard let resetsAt else { return false }
        return now >= resetsAt
    }
}

/// Manual reset credits the user can spend (currently reported by Codex only).
public struct ResetCredit: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String?
    public var detail: String?
    public var grantedAt: Date?
    public var expiresAt: Date?

    public init(id: String, title: String? = nil, detail: String? = nil, grantedAt: Date? = nil, expiresAt: Date? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
    }
}

public struct ResetCreditsSummary: Codable, Equatable, Sendable {
    public var availableCount: Int
    /// `nil` when only the count is known.
    public var credits: [ResetCredit]?

    public init(availableCount: Int, credits: [ResetCredit]? = nil) {
        self.availableCount = availableCount
        self.credits = credits
    }

    /// The soonest expiration among known credits.
    public var nextExpiry: Date? {
        credits?.compactMap(\.expiresAt).min()
    }
}

/// Where a snapshot came from. Shown in the popover and diagnostics.
public enum DataSource: String, Codable, Sendable {
    case codexAppServer
    case codexSessionLog
    case claudeStatusLine
    case claudeDesktopHistory
    case claudeDesktopCache
    case fixture

    /// Whether the source is an officially documented interface.
    public var isDocumented: Bool {
        switch self {
        case .codexAppServer, .claudeStatusLine: return true
        case .codexSessionLog, .claudeDesktopHistory, .claudeDesktopCache, .fixture: return false
        }
    }
}

/// A normalized reading of one provider's limits at a moment in time.
public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public var provider: ProviderID
    public var windows: [QuotaWindow]
    /// When the source produced/observed the values (not when we read the file).
    public var observedAt: Date
    public var source: DataSource
    public var resetCredits: ResetCreditsSummary?
    public var planName: String?
    /// True for development fixtures. Never presented as real data.
    public var isFixture: Bool

    public init(provider: ProviderID, windows: [QuotaWindow], observedAt: Date, source: DataSource,
                resetCredits: ResetCreditsSummary? = nil, planName: String? = nil, isFixture: Bool = false) {
        self.provider = provider
        self.windows = windows
        self.observedAt = observedAt
        self.source = source
        self.resetCredits = resetCredits
        self.planName = planName
        self.isFixture = isFixture || source == .fixture
    }

    public func window(_ kind: WindowKind) -> QuotaWindow? {
        windows.first { $0.kind == kind }
    }

    /// True when `window` can no longer describe the current period: its reset time has passed, or —
    /// when the source gives no reset time — more than one full window length has elapsed since the
    /// reading (the window must have renewed at least once). Nothing is estimated beyond that.
    public func isOutdated(_ window: QuotaWindow, at now: Date) -> Bool {
        if window.hasRolledOver(at: now) { return true }
        guard window.resetsAt == nil, let minutes = window.durationMinutes else { return false }
        return now.timeIntervalSince(observedAt) > TimeInterval(minutes * 60)
    }
}

/// Health of an integration, independent of whether we still hold cached data.
public enum IntegrationState: Equatable, Sendable, Codable {
    case connected
    case waitingForData(String)
    case notInstalled
    case notAuthenticated
    case unsupported(String)
    case error(String)
    case disabled

    public var isProblem: Bool {
        switch self {
        case .connected, .waitingForData, .disabled: return false
        case .notInstalled, .notAuthenticated, .unsupported, .error: return true
        }
    }
}

/// How much the displayed numbers can be trusted right now.
public enum Freshness: String, Sendable, Equatable {
    /// Recently confirmed by a source.
    case current
    /// From a previous read; still plausible.
    case cached
    /// Old enough that the real value may have changed noticeably.
    case stale
    /// Nothing usable.
    case unavailable
}

/// Everything the UI needs for one provider.
public struct ProviderStatus: Equatable, Sendable {
    public var provider: ProviderID
    public var displayName: String
    public var snapshot: QuotaSnapshot?
    public var state: IntegrationState
    public var lastAttempt: Date?
    /// True when `snapshot` was restored from disk at launch and not yet re-confirmed.
    public var loadedFromCache: Bool

    public init(provider: ProviderID, displayName: String, snapshot: QuotaSnapshot? = nil,
                state: IntegrationState = .waitingForData(""), lastAttempt: Date? = nil, loadedFromCache: Bool = false) {
        self.provider = provider
        self.displayName = displayName
        self.snapshot = snapshot
        self.state = state
        self.lastAttempt = lastAttempt
        self.loadedFromCache = loadedFromCache
    }

    public func freshness(at now: Date, policy: FreshnessPolicy = .default) -> Freshness {
        guard let snapshot else { return .unavailable }
        let age = now.timeIntervalSince(snapshot.observedAt)
        if age > policy.staleAfter { return .stale }
        if loadedFromCache || age > policy.currentFor { return .cached }
        return .current
    }
}

public struct FreshnessPolicy: Sendable, Equatable {
    public var currentFor: TimeInterval
    public var staleAfter: TimeInterval
    public init(currentFor: TimeInterval, staleAfter: TimeInterval) {
        self.currentFor = currentFor
        self.staleAfter = staleAfter
    }
    public static let `default` = FreshnessPolicy(currentFor: 15 * 60, staleAfter: 3 * 60 * 60)
}
