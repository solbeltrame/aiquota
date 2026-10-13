import Foundation

/// Decodes the Codex App Server `account/rateLimits/read` response and the
/// `account/rateLimits/updated` notification into `QuotaSnapshot`s.
///
/// Field names follow the schema produced by `codex app-server generate-json-schema`.
public enum CodexRateLimitParser {
    struct Window: Decodable {
        var usedPercent: Double
        var windowDurationMins: Int?
        var resetsAt: Int64?
    }

    struct Snapshot: Decodable {
        var limitId: String?
        var primary: Window?
        var secondary: Window?
        var planType: String?
    }

    struct Credit: Decodable {
        var id: String
        var status: String?
        var title: String?
        var description: String?
        var grantedAt: Int64?
        var expiresAt: Int64?
    }

    struct CreditsSummary: Decodable {
        var availableCount: Int
        var credits: [Credit]?
    }

    struct ReadResponse: Decodable {
        var rateLimits: Snapshot
        var rateLimitsByLimitId: [String: Snapshot]?
        var rateLimitResetCredits: CreditsSummary?
    }

    struct UpdatedNotification: Decodable {
        var rateLimits: Snapshot
    }

    /// The bucket that drives Codex usage. Other buckets (per-model aliases) are ignored for the menu bar.
    static let primaryLimitID = "codex"

    public static func parseReadResponse(_ data: Data, observedAt: Date) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(ReadResponse.self, from: data)
        let bucket = response.rateLimitsByLimitId?[primaryLimitID] ?? response.rateLimits
        var snapshot = makeSnapshot(bucket, observedAt: observedAt, source: .codexAppServer)
        if let summary = response.rateLimitResetCredits {
            snapshot.resetCredits = makeCredits(summary)
        }
        return snapshot
    }

    /// Notifications are sparse: merge into the previous snapshot instead of replacing it.
    public static func mergeUpdatedNotification(_ data: Data, into base: QuotaSnapshot?, observedAt: Date) throws -> QuotaSnapshot? {
        let note = try JSONDecoder().decode(UpdatedNotification.self, from: data)
        if let limitId = note.rateLimits.limitId, limitId != primaryLimitID { return base }
        let update = makeSnapshot(note.rateLimits, observedAt: observedAt, source: .codexAppServer)
        guard var merged = base else { return update.windows.isEmpty ? nil : update }
        for window in update.windows {
            if let index = merged.windows.firstIndex(where: { $0.kind == window.kind }) {
                merged.windows[index] = window
            } else {
                merged.windows.append(window)
            }
        }
        merged.observedAt = observedAt
        merged.source = .codexAppServer
        if let plan = update.planName { merged.planName = plan }
        return merged
    }

    static func makeSnapshot(_ bucket: Snapshot, observedAt: Date, source: DataSource) -> QuotaSnapshot {
        let windows = [bucket.primary, bucket.secondary].compactMap { $0 }.map { window in
            QuotaWindow(kind: WindowKind.classify(durationMinutes: window.windowDurationMins),
                        durationMinutes: window.windowDurationMins,
                        usedPercent: window.usedPercent,
                        resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) })
        }
        return QuotaSnapshot(provider: .codex, windows: windows, observedAt: observedAt, source: source,
                             planName: bucket.planType.flatMap(planDisplayName))
    }

    static func makeCredits(_ summary: CreditsSummary) -> ResetCreditsSummary {
        let credits = summary.credits?
            .filter { ($0.status ?? "available") == "available" }
            .map { credit in
                ResetCredit(id: credit.id, title: credit.title, detail: credit.description,
                            grantedAt: credit.grantedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                            expiresAt: credit.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) })
            }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        return ResetCreditsSummary(availableCount: summary.availableCount, credits: credits)
    }

    static func planDisplayName(_ raw: String) -> String? {
        switch raw {
        case "unknown", "": return nil
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        default:
            return raw.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
    }
}
