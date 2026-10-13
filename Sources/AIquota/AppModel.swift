import AppKit
import AIquotaCore
import Combine

/// Shared app state for AppKit controllers and SwiftUI views.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settingsStore.save(settings)
            L10n.language = settings.language
            store.update(settings: settings)
        }
    }

    let store: QuotaStore
    let notifications = NotificationService()
    let claudeBridge: ClaudeStatusLineBridge
    var openSettings: (SettingsTab) -> Void = { _ in }
    var openOnboarding: () -> Void = {}

    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore = SettingsStore()) {
        self.settingsStore = settingsStore
        let settings = settingsStore.load()
        self.settings = settings
        L10n.language = settings.language

        let bridge = ClaudeStatusLineBridge()
        claudeBridge = bridge
        // Providers read live settings through these closures (no restart needed).
        let settingsBox = SettingsBox(settings)
        let codex = CodexProvider(executableOverride: { settingsBox.value.codexExecutablePath })
        let claude = ClaudeProvider(bridge: bridge, useDesktopHistory: { settingsBox.value.useClaudeDesktopHistory })
        store = QuotaStore(providers: [codex, claude], settings: settings)
        self.settingsBox = settingsBox

        store.onAlert = { [weak self] event in self?.notifications.deliver(event) }
    }

    private let settingsBox: SettingsBox

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        settingsBox.value = copy
        settings = copy
    }

    func cells(for status: ProviderStatus, now: Date = Date()) -> [IndicatorCell] {
        IndicatorModelBuilder.cells(for: status, windows: settings.windows(for: status.provider),
                                    mode: settings.valueMode, thresholds: settings.thresholds, now: now)
    }
}

/// Thread-safe settings holder read by providers off the main actor.
final class SettingsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: AppSettings
    init(_ value: AppSettings) { _value = value }
    var value: AppSettings {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, providers, notifications, about
    var id: String { rawValue }
}
