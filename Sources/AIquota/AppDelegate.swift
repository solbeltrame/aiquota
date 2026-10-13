import AppKit
import AIquotaCore
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var controllers: [StatusItemController] = []
    private var cancellables: Set<AnyCancellable> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var tickTimer: Timer?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let settingsTab = SettingsTabState()
    private let updateManager = UpdateManager()
    private var updaterController: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        updaterController = SPUStandardUpdaterController(startingUpdater: false,
                                                        updaterDelegate: updateManager,
                                                        userDriverDelegate: nil)
        updateManager.attach(updaterController.updater)
        updaterController.startUpdater()
        model.openSettings = { [weak self] tab in self?.showSettings(tab) }
        model.openOnboarding = { [weak self] in self?.showOnboarding() }

        controllers = model.store.providers.map { StatusItemController(providerID: $0.id, model: model) }

        // Re-render when data or settings change.
        model.store.$statuses
            .combineLatest(model.$settings)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.renderAll() }
            .store(in: &cancellables)

        // Process launch/termination, rather than window visibility, controls the paired indicators.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let observer = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.model.refreshRunningProviderApps()
                    self?.renderAll()
                }
            }
            workspaceObservers.append(observer)
        }

        // Freshness and window roll-over are evaluated locally; this costs no I/O.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.refreshRunningProviderApps()
                self?.renderAll()
            }
        }
        tickTimer?.tolerance = 10

        let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.store.refreshAll(reason: .wake) }
        }
        workspaceObservers.append(wakeObserver)

        if Self.fixturesRequested {
            model.store.showFixtures(Self.fixtureStatuses())
        } else {
            model.store.start()
        }
        model.refreshRunningProviderApps()
        renderAll()

        if !model.settings.onboardingCompleted && !Self.fixturesRequested {
            showOnboarding()
        }

        if let dump = ProcessInfo.processInfo.environment["AIQUOTA_DEBUG_DUMP_DIR"] {
            let directory = URL(fileURLWithPath: dump)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.controllers.forEach { $0.dumpIndicator(to: directory) }
                    if ProcessInfo.processInfo.environment["AIQUOTA_DEBUG_DUMP_VIEWS"] == "1" {
                        DebugSnapshots.dumpViews(model: self.model, updates: self.updateManager, to: directory)
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.store.stop()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(.general)
        return false
    }

    private func renderAll() {
        let now = Date()
        controllers.forEach { $0.update(now: now) }
    }

    // MARK: Windows

    func showSettings(_ tab: SettingsTab) {
        controllers.forEach { $0.closePopover() }
        settingsTab.tab = tab
        if settingsWindow == nil {
            let root = SettingsRoot(tabState: settingsTab)
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.notifications)
                .environmentObject(updateManager)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = L("AIquota Settings")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let root = OnboardingView(finish: { [weak self] in
                self?.model.updateSettings { $0.onboardingCompleted = true }
                self?.onboardingWindow?.close()
            })
            .environmentObject(model)
            .environmentObject(model.store)
            .environmentObject(model.notifications)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "AIquota"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Fixtures (screenshots / visual checks only)

    static var fixturesRequested: Bool {
        CommandLine.arguments.contains("--fixtures") || ProcessInfo.processInfo.environment["AIQUOTA_FIXTURES"] == "1"
    }

    static func fixtureStatuses() -> [ProviderStatus] {
        let env = ProcessInfo.processInfo.environment
        func value(_ key: String, _ fallback: Double) -> Double { env[key].flatMap(Double.init) ?? fallback }
        return [
            Fixtures.status(.codex, name: "Codex", fiveHourAvailable: value("AIQUOTA_FIXTURE_CODEX_5H", 83),
                            weeklyAvailable: value("AIQUOTA_FIXTURE_CODEX_7D", 42)),
            Fixtures.status(.claude, name: "Claude Code", fiveHourAvailable: value("AIQUOTA_FIXTURE_CLAUDE_5H", 15),
                            weeklyAvailable: value("AIQUOTA_FIXTURE_CLAUDE_7D", 7)),
        ]
    }
}

final class SettingsTabState: ObservableObject {
    @Published var tab: SettingsTab = .general
}

private struct SettingsRoot: View {
    @ObservedObject var tabState: SettingsTabState
    var body: some View { SettingsView(tab: $tabState.tab) }
}
