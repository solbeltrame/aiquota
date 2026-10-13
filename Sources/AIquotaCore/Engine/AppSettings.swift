import Foundation

public enum IndicatorStyle: String, Codable, Sendable, CaseIterable {
    case minimal
    case microbar
    case ring
}

public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case system
    case english = "en"
    case portugueseBR = "pt-BR"
}

public struct ProviderSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// `nil` follows the global setting.
    public var windows: WindowSelection?

    public init(enabled: Bool = true, windows: WindowSelection? = nil) {
        self.enabled = enabled
        self.windows = windows
    }
}

/// Visual parameters of the menu bar indicators.
public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var style: IndicatorStyle = .microbar
    public var numberSize: Double = 12
    public var labelSize: Double = 7
    public var barThickness: Double = 1.5
    public var ringThickness: Double = 1.5
    /// Space between the 5h and 7d groups inside one indicator.
    public var cellSpacing: Double = 5
    public var showPercentSign: Bool = true
    public var colorizeNumbers: Bool = false
    /// Show each AI app's icon before its numbers (useful when the app's own menu bar icon is hidden).
    public var showProviderIcon: Bool = false
    /// Hex overrides; `nil` uses the built-in muted palette (adapts to light/dark).
    public var cautionColorHex: String?
    public var criticalColorHex: String?

    public static let numberSizeRange: ClosedRange<Double> = 9...14
    public static let labelSizeRange: ClosedRange<Double> = 5.5...9
    public static let barThicknessRange: ClosedRange<Double> = 1...3
    public static let ringThicknessRange: ClosedRange<Double> = 1...2.5
    public static let cellSpacingRange: ClosedRange<Double> = 2...12

    public init() {}

    enum CodingKeys: String, CodingKey {
        case style, numberSize, labelSize, barThickness, ringThickness, cellSpacing, showPercentSign,
             colorizeNumbers, showProviderIcon, cautionColorHex, criticalColorHex
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppearanceSettings()
        style = (try? c.decode(IndicatorStyle.self, forKey: .style)) ?? d.style
        numberSize = ((try? c.decode(Double.self, forKey: .numberSize)) ?? d.numberSize).clamped(to: Self.numberSizeRange)
        labelSize = ((try? c.decode(Double.self, forKey: .labelSize)) ?? d.labelSize).clamped(to: Self.labelSizeRange)
        barThickness = ((try? c.decode(Double.self, forKey: .barThickness)) ?? d.barThickness).clamped(to: Self.barThicknessRange)
        ringThickness = ((try? c.decode(Double.self, forKey: .ringThickness)) ?? d.ringThickness).clamped(to: Self.ringThicknessRange)
        cellSpacing = ((try? c.decode(Double.self, forKey: .cellSpacing)) ?? d.cellSpacing).clamped(to: Self.cellSpacingRange)
        showPercentSign = (try? c.decode(Bool.self, forKey: .showPercentSign)) ?? d.showPercentSign
        colorizeNumbers = (try? c.decode(Bool.self, forKey: .colorizeNumbers)) ?? d.colorizeNumbers
        showProviderIcon = (try? c.decode(Bool.self, forKey: .showProviderIcon)) ?? d.showProviderIcon
        cautionColorHex = try? c.decodeIfPresent(String.self, forKey: .cautionColorHex)
        criticalColorHex = try? c.decodeIfPresent(String.self, forKey: .criticalColorHex)
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var appearance = AppearanceSettings()
    public var valueMode: ValueMode = .available
    public var windows: WindowSelection = .both
    public var thresholds = ToneThresholds.default
    public var providers: [String: ProviderSettings] = [:]
    /// Fallback polling while active, in seconds. Each provider clamps it to its own safe minimum.
    public var refreshInterval: Double = 60
    public var language: AppLanguage = .system
    public var alerts = AlertSettings()
    public var useClaudeDesktopHistory = true
    public var codexExecutablePath: String?
    public var onboardingCompleted = false

    public init() {}

    public func providerSettings(_ id: ProviderID) -> ProviderSettings {
        providers[id.rawValue] ?? ProviderSettings()
    }

    public mutating func updateProvider(_ id: ProviderID, _ change: (inout ProviderSettings) -> Void) {
        var value = providerSettings(id)
        change(&value)
        providers[id.rawValue] = value
    }

    public func windows(for id: ProviderID) -> WindowSelection {
        providerSettings(id).windows ?? windows
    }

    enum CodingKeys: String, CodingKey {
        case appearance, valueMode, windows, thresholds, providers, refreshInterval, language, alerts,
             useClaudeDesktopHistory, codexExecutablePath, onboardingCompleted
    }

    /// Every field falls back to its default, so new versions never wipe older preferences.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        appearance = (try? c.decode(AppearanceSettings.self, forKey: .appearance)) ?? d.appearance
        valueMode = (try? c.decode(ValueMode.self, forKey: .valueMode)) ?? d.valueMode
        windows = (try? c.decode(WindowSelection.self, forKey: .windows)) ?? d.windows
        thresholds = (try? c.decode(ToneThresholds.self, forKey: .thresholds)) ?? d.thresholds
        providers = (try? c.decode([String: ProviderSettings].self, forKey: .providers)) ?? d.providers
        refreshInterval = ((try? c.decode(Double.self, forKey: .refreshInterval)) ?? d.refreshInterval)
            .clamped(to: RefreshScheduler.userIntervalRange)
        language = (try? c.decode(AppLanguage.self, forKey: .language)) ?? d.language
        alerts = (try? c.decode(AlertSettings.self, forKey: .alerts)) ?? d.alerts
        useClaudeDesktopHistory = (try? c.decode(Bool.self, forKey: .useClaudeDesktopHistory)) ?? d.useClaudeDesktopHistory
        codexExecutablePath = try? c.decodeIfPresent(String.self, forKey: .codexExecutablePath)
        onboardingCompleted = (try? c.decode(Bool.self, forKey: .onboardingCompleted)) ?? d.onboardingCompleted
    }
}

/// Stores `AppSettings` as one JSON blob in UserDefaults.
public struct SettingsStore: Sendable {
    public let key: String
    private let suiteName: String?

    public init(suiteName: String? = nil, key: String = "settings.v1") {
        self.suiteName = suiteName
        self.key = key
    }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(range.upperBound, max(range.lowerBound, self)) }
}
