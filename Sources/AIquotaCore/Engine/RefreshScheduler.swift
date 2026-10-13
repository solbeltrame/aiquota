import Foundation

/// Pure scheduling math for one provider: event debouncing, adaptive polling and backoff.
public struct RefreshScheduler: Equatable, Sendable {
    public var policy: RefreshPolicy
    /// User-chosen fallback interval while active (clamped to safe bounds for the provider).
    public var userActiveInterval: TimeInterval?

    public private(set) var lastFetch: Date?
    public private(set) var lastEvent: Date?
    public private(set) var consecutiveFailures = 0
    public private(set) var notBefore: Date?

    public init(policy: RefreshPolicy, userActiveInterval: TimeInterval? = nil) {
        self.policy = policy
        self.userActiveInterval = userActiveInterval
    }

    public static let userIntervalRange: ClosedRange<TimeInterval> = 30...900

    public var activeInterval: TimeInterval {
        let requested = userActiveInterval ?? policy.activeInterval
        return max(policy.minimumInterval, min(Self.userIntervalRange.upperBound, max(Self.userIntervalRange.lowerBound, requested)))
    }

    public var idleInterval: TimeInterval { max(activeInterval, policy.idleInterval) }

    public func isActive(at now: Date) -> Bool {
        guard let lastEvent else { return false }
        return now.timeIntervalSince(lastEvent) < policy.activityWindow
    }

    /// Exponential backoff after failures: interval × 2^(n-1), capped.
    public func backoff() -> TimeInterval {
        guard consecutiveFailures > 0 else { return 0 }
        let exponent = Double(min(consecutiveFailures - 1, 10))
        return min(policy.maximumBackoff, max(policy.minimumInterval, activeInterval) * pow(2, exponent))
    }

    /// When the fallback poll should run next.
    public func nextPoll(at now: Date) -> Date {
        guard let lastFetch else { return max(now, notBefore ?? now) }
        var interval = isActive(at: now) ? activeInterval : idleInterval
        if consecutiveFailures > 0 { interval = max(interval, backoff()) }
        return max(lastFetch.addingTimeInterval(interval), notBefore ?? .distantPast)
    }

    /// When an event-triggered fetch may run (immediately, or after the minimum interval).
    public func earliestFetch(at now: Date) -> Date {
        var earliest = now
        if let lastFetch { earliest = max(earliest, lastFetch.addingTimeInterval(policy.minimumInterval)) }
        if consecutiveFailures > 0, let lastFetch { earliest = max(earliest, lastFetch.addingTimeInterval(backoff())) }
        if let notBefore { earliest = max(earliest, notBefore) }
        return earliest
    }

    public mutating func recordEvent(at now: Date) { lastEvent = now }

    public mutating func recordFetchStarted(at now: Date) { lastFetch = now }

    public mutating func recordSuccess() {
        consecutiveFailures = 0
        notBefore = nil
    }

    public mutating func recordFailure(_ error: ProviderError, at now: Date) {
        guard error.countsAsFailure else { return }
        consecutiveFailures += 1
        if case .rateLimited(let retryAfter) = error {
            // Respect Retry-After, or cool down for at least the current backoff.
            notBefore = now.addingTimeInterval(max(retryAfter ?? 0, backoff(), 5 * 60))
        }
    }
}
