import Foundation

public enum AIquotaVersion {
    public static let current = "0.3.0"
}

/// Development fixtures for previews, screenshots and visual tests.
///
/// Every snapshot here has `isFixture == true`; the UI labels it "Sample data" and it is never
/// cached, notified about, or shown as a real reading.
public enum Fixtures {
    public static let visualPercentages: [Double] = [100, 99, 50, 20, 10, 9, 5, 0]

    public static func snapshot(_ provider: ProviderID, fiveHourAvailable: Double, weeklyAvailable: Double,
                                now: Date = Date()) -> QuotaSnapshot {
        QuotaSnapshot(provider: provider,
                      windows: [
                          QuotaWindow(kind: .fiveHour, durationMinutes: 300, usedPercent: 100 - fiveHourAvailable,
                                      resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60)),
                          QuotaWindow(kind: .weekly, durationMinutes: 10_080, usedPercent: 100 - weeklyAvailable,
                                      resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3600)),
                      ],
                      observedAt: now, source: .fixture,
                      resetCredits: provider == .codex
                          ? ResetCreditsSummary(availableCount: 1, credits: [
                              ResetCredit(id: "fixture", title: "Full reset (Weekly + 5 hr)",
                                          expiresAt: now.addingTimeInterval(9 * 86_400)),
                          ])
                          : nil,
                      planName: "Sample", isFixture: true)
    }

    public static func status(_ provider: ProviderID, name: String, fiveHourAvailable: Double, weeklyAvailable: Double,
                              now: Date = Date()) -> ProviderStatus {
        ProviderStatus(provider: provider, displayName: name,
                       snapshot: snapshot(provider, fiveHourAvailable: fiveHourAvailable,
                                          weeklyAvailable: weeklyAvailable, now: now),
                       state: .connected, lastAttempt: now)
    }
}
