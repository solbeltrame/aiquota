import Foundation

public struct AlertSettings: Codable, Equatable, Sendable {
    public var lowAvailableThresholds: [Int: Bool]
    public var fiveHourRenewal: Bool
    public var weeklyRenewal: Bool
    public var resetCreditExpiring: Bool
    /// How long before expiry a reset credit warning fires.
    public var creditExpiryLeadHours: Double

    public static let thresholdChoices = [20, 10, 5]

    public init(lowAvailableThresholds: [Int: Bool] = [20: true, 10: true, 5: true],
                fiveHourRenewal: Bool = true, weeklyRenewal: Bool = true,
                resetCreditExpiring: Bool = true, creditExpiryLeadHours: Double = 72) {
        self.lowAvailableThresholds = lowAvailableThresholds
        self.fiveHourRenewal = fiveHourRenewal
        self.weeklyRenewal = weeklyRenewal
        self.resetCreditExpiring = resetCreditExpiring
        self.creditExpiryLeadHours = creditExpiryLeadHours
    }

    public var enabledThresholds: [Int] {
        Self.thresholdChoices.filter { lowAvailableThresholds[$0] ?? false }.sorted(by: >)
    }

    enum CodingKeys: String, CodingKey {
        case lowAvailableThresholds, fiveHourRenewal, weeklyRenewal, resetCreditExpiring, creditExpiryLeadHours
    }

    public init(from decoder: Decoder) throws {
        let defaults = AlertSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lowAvailableThresholds = (try? c.decode([Int: Bool].self, forKey: .lowAvailableThresholds)) ?? defaults.lowAvailableThresholds
        fiveHourRenewal = (try? c.decode(Bool.self, forKey: .fiveHourRenewal)) ?? defaults.fiveHourRenewal
        weeklyRenewal = (try? c.decode(Bool.self, forKey: .weeklyRenewal)) ?? defaults.weeklyRenewal
        resetCreditExpiring = (try? c.decode(Bool.self, forKey: .resetCreditExpiring)) ?? defaults.resetCreditExpiring
        creditExpiryLeadHours = (try? c.decode(Double.self, forKey: .creditExpiryLeadHours)) ?? defaults.creditExpiryLeadHours
    }
}

public struct AlertEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case lowAvailable(threshold: Int, available: Int)
        case windowRenewed
        case resetCreditExpiring(creditID: String, expiresAt: Date)
    }

    /// Stable de-duplication key.
    public var key: String
    public var provider: ProviderID
    public var providerName: String
    public var window: WindowKind?
    public var kind: Kind
}

/// Decides which notifications to send. Pure: the caller persists `firedKeys`.
public enum AlertEngine {
    /// Usage must recover this far above a threshold before that alert can fire again.
    static let hysteresis = 5.0

    public static func evaluate(previous: QuotaSnapshot?, current: QuotaSnapshot, providerName: String,
                                settings: AlertSettings, firedKeys: inout Set<String>, now: Date) -> [AlertEvent] {
        guard !current.isFixture else { return [] }
        var events: [AlertEvent] = []
        let provider = current.provider.rawValue

        for window in current.windows where window.kind != .other && !window.hasRolledOver(at: now) {
            let base = "\(provider).\(window.kind.rawValue)"
            let available = window.availablePercent

            // Confirmed renewal: usage fell sharply in data we actually received.
            if let old = previous.flatMap({ $0.window(window.kind) }), let previous, !previous.isFixture,
               isConfirmedRenewal(old: old, new: window, previousObservedAt: previous.observedAt, now: now) {
                for threshold in AlertSettings.thresholdChoices { firedKeys.remove("\(base).low\(threshold)") }
                let wanted = window.kind == .fiveHour ? settings.fiveHourRenewal : settings.weeklyRenewal
                let key = "\(base).renewed.\(Int(window.resetsAt?.timeIntervalSince1970 ?? current.observedAt.timeIntervalSince1970) / 60)"
                if wanted, firedKeys.insert(key).inserted {
                    events.append(AlertEvent(key: key, provider: current.provider, providerName: providerName,
                                             window: window.kind, kind: .windowRenewed))
                }
            }

            // Re-arm thresholds once usage has clearly recovered.
            for threshold in AlertSettings.thresholdChoices where available >= Double(threshold) + hysteresis {
                firedKeys.remove("\(base).low\(threshold)")
            }

            // Only the lowest newly-crossed threshold notifies; the others are marked as handled.
            var lowest: Int?
            for threshold in settings.enabledThresholds where available < Double(threshold) {
                if firedKeys.insert("\(base).low\(threshold)").inserted { lowest = threshold }
            }
            if let lowest {
                events.append(AlertEvent(key: "\(base).low\(lowest)", provider: current.provider,
                                         providerName: providerName, window: window.kind,
                                         kind: .lowAvailable(threshold: lowest,
                                                             available: PercentFormatter.displayValue(usedPercent: window.usedPercent, mode: .available))))
            }
        }

        if settings.resetCreditExpiring, let credits = current.resetCredits?.credits {
            let horizon = now.addingTimeInterval(settings.creditExpiryLeadHours * 3600)
            for credit in credits {
                guard let expires = credit.expiresAt, expires > now, expires <= horizon else { continue }
                let key = "\(provider).credit.\(credit.id).expiring"
                if firedKeys.insert(key).inserted {
                    events.append(AlertEvent(key: key, provider: current.provider, providerName: providerName,
                                             window: nil, kind: .resetCreditExpiring(creditID: credit.id, expiresAt: expires)))
                }
            }
        }
        return events
    }

    /// A renewal is only reported from real data: usage dropped by at least 10 points to a low value,
    /// and the reset time (when both readings have one) moved forward. Never inferred from the clock.
    static func isConfirmedRenewal(old: QuotaWindow, new: QuotaWindow, previousObservedAt: Date, now: Date) -> Bool {
        let dropped = old.clampedUsed - new.clampedUsed >= 10 && new.clampedUsed <= 10
        guard dropped else { return false }
        if let oldReset = old.resetsAt, let newReset = new.resetsAt, newReset <= oldReset.addingTimeInterval(60) {
            return false
        }
        // Don't announce renewals discovered long after the fact (e.g. after days offline).
        let windowLength = TimeInterval((new.durationMinutes ?? 300) * 60)
        return now.timeIntervalSince(previousObservedAt) <= windowLength * 1.2
    }
}
