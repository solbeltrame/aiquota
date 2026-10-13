import Foundation

public enum ValueMode: String, Codable, Sendable, CaseIterable {
    case available
    case consumed
}

public enum WindowSelection: String, Codable, Sendable, CaseIterable {
    case both
    case fiveHourOnly
    case weeklyOnly

    public var kinds: [WindowKind] {
        switch self {
        case .both: return [.fiveHour, .weekly]
        case .fiveHourOnly: return [.fiveHour]
        case .weeklyOnly: return [.weekly]
        }
    }
}

/// Alert tone. Always derived from the AVAILABLE percentage, whatever the display mode.
public enum Tone: String, Sendable, Equatable, Codable {
    case neutral
    case caution
    case critical
    /// Data is old or the window already rolled over: render dimmed.
    case muted
}

public struct ToneThresholds: Codable, Equatable, Sendable {
    /// Available at or below this → caution.
    public var caution: Double
    /// Available below this → critical.
    public var critical: Double

    public init(caution: Double = 20, critical: Double = 10) {
        self.caution = caution
        self.critical = critical
    }

    public static let `default` = ToneThresholds()

    /// > caution: neutral. critical...caution: caution. < critical: critical.
    public func tone(forAvailable available: Double) -> Tone {
        if available < critical { return .critical }
        if available <= caution { return .caution }
        return .neutral
    }
}

/// Percentage rounding shared by every surface.
///
/// Available is rounded down and consumed is rounded up, so the app never overstates what is left
/// and the two modes always add up to exactly 100.
public enum PercentFormatter {
    public static func displayValue(usedPercent: Double, mode: ValueMode) -> Int {
        let used = min(100, max(0, usedPercent))
        switch mode {
        case .available: return Int((100 - used + 1e-9).rounded(.down))
        case .consumed: return Int((used - 1e-9).rounded(.up))
        }
    }

    /// Fraction used for bars and rings: matches the number being shown.
    public static func fraction(usedPercent: Double, mode: ValueMode) -> Double {
        Double(displayValue(usedPercent: usedPercent, mode: mode)) / 100
    }
}

/// One number in the menu bar, ready to be drawn.
public struct IndicatorCell: Equatable, Sendable {
    public var kind: WindowKind
    /// `nil` renders a placeholder dash: no data, never a fake number.
    public var value: Int?
    public var fraction: Double
    public var tone: Tone

    public init(kind: WindowKind, value: Int?, fraction: Double, tone: Tone) {
        self.kind = kind
        self.value = value
        self.fraction = fraction
        self.tone = tone
    }

    public var label: String { kind.shortLabel }
}

public enum IndicatorModelBuilder {
    /// Builds the cells for one provider's status item.
    public static func cells(for status: ProviderStatus, windows: WindowSelection, mode: ValueMode,
                             thresholds: ToneThresholds, now: Date,
                             freshness policy: FreshnessPolicy = .default) -> [IndicatorCell] {
        let freshness = status.freshness(at: now, policy: policy)
        return applicableKinds(windows.kinds, snapshot: status.snapshot).map { kind in
            guard let snapshot = status.snapshot, let window = snapshot.window(kind),
                  !snapshot.isOutdated(window, at: now), freshness != .unavailable else {
                return IndicatorCell(kind: kind, value: nil, fraction: 0, tone: .muted)
            }
            let value = PercentFormatter.displayValue(usedPercent: window.usedPercent, mode: mode)
            let tone: Tone = freshness == .stale ? .muted : thresholds.tone(forAvailable: window.availablePercent)
            return IndicatorCell(kind: kind, value: value,
                                 fraction: PercentFormatter.fraction(usedPercent: window.usedPercent, mode: mode),
                                 tone: tone)
        }
    }
}

extension IndicatorModelBuilder {
    /// Plans differ: some only have a weekly limit. When a source answered without a window, that window
    /// does not apply and is hidden. Exception: Claude Code's status line drops a window temporarily once it
    /// renews, so there a missing window means "no data yet" and keeps its "–" placeholder.
    public static func applicableKinds(_ kinds: [WindowKind], snapshot: QuotaSnapshot?) -> [WindowKind] {
        guard let snapshot, snapshot.source != .claudeStatusLine else { return kinds }
        let reported = kinds.filter { snapshot.window($0) != nil }
        return reported.isEmpty ? kinds : reported
    }
}

/// "in 2h 14m", "in 3d 4h" — computed locally, never by polling.
public enum RelativeTime {
    public static func countdown(to date: Date, from now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let minutes = seconds / 60
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let mins = minutes % 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h" }
        if minutes > 0 { return "\(mins)m" }
        return "<1m"
    }

    public static func age(of date: Date, at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "<1m" }
        return countdown(to: now, from: date)
    }
}
