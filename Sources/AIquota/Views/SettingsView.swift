import AIquotaCore
import AIquotaUI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Binding var tab: SettingsTab

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings().tabItem { Label(L("General"), systemImage: "gearshape") }.tag(SettingsTab.general)
            AppearanceSettingsView().tabItem { Label(L("Appearance"), systemImage: "paintbrush") }.tag(SettingsTab.appearance)
            ProvidersSettings().tabItem { Label(L("Providers"), systemImage: "point.3.connected.trianglepath.dotted") }.tag(SettingsTab.providers)
            NotificationSettings().tabItem { Label(L("Notifications"), systemImage: "bell") }.tag(SettingsTab.notifications)
            UpdatesSettings().tabItem { Label(L("Updates"), systemImage: "arrow.triangle.2.circlepath") }.tag(SettingsTab.updates)
            AboutView().tabItem { Label(L("About"), systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .frame(width: 560, height: 520)
        .id(model.settings.language)  // re-render strings after a language change
    }
}

// MARK: - Updates

private struct UpdatesSettings: View {
    @EnvironmentObject var updates: UpdateManager

    var body: some View {
        Form {
            Section(L("Current version")) {
                LabeledContent(L("Installed version"), value: AIquotaVersion.current)
                Label(updates.stateDescription, systemImage: updates.stateSymbol)
                    .foregroundStyle(updates.state == .upToDate ? Color.green : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: updates.checkForUpdates) {
                    Label(L("Check for updates"), systemImage: "arrow.clockwise")
                }
                .disabled(!updates.canCheckForUpdates)
                Link(L("View releases on GitHub"), destination: AppLinks.releases)
            }
            Section(L("Automatic updates")) {
                Toggle(L("Check for updates automatically"), isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: updates.setAutomaticChecks))
                Toggle(L("Download and install updates automatically"), isOn: Binding(
                    get: { updates.automaticallyDownloadsUpdates },
                    set: updates.setAutomaticDownloads))
                    .disabled(!updates.automaticallyChecksForUpdates)
                Text(L("Automatic checks run about once a day. Downloads and installs can wait until AIquota is closed."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Text(L("Updates are downloaded from the official GitHub releases and verified before installation."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

/// "Tip: Hold ⌘ Command and drag…" — shown in onboarding, settings and About.
struct RepositionTip: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("⌘").font(.system(size: 20, weight: .semibold)).frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Tip: Hold ⌘ Command and drag an AIquota indicator to place it next to your AI app."))
                    .font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Text(L("macOS decides menu bar placement, so AIquota cannot move items automatically. Positions are remembered when possible."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Toggle(L("Launch at login"), isOn: Binding(get: { launchAtLogin }, set: { newValue in
                    do {
                        try LaunchAtLogin.set(newValue)
                        launchError = nil
                    } catch {
                        launchError = error.localizedDescription
                    }
                    launchAtLogin = LaunchAtLogin.isEnabled
                }))
                if LaunchAtLogin.requiresApproval {
                    Text(L("Approve AIquota in System Settings → General → Login Items.")).font(.caption).foregroundStyle(.secondary)
                }
                if let launchError { Text(launchError).font(.caption).foregroundStyle(.red) }
                Picker(L("Language"), selection: binding(\.language)) {
                    Text(L("System")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("Português (Brasil)").tag(AppLanguage.portugueseBR)
                }
            }
            Section(L("Indicators")) {
                Toggle(L("Always show indicators"), isOn: binding(\.alwaysShowIndicators))
                Text(L("When this is off, each indicator appears only while its AI app is open."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Picker(L("Show"), selection: binding(\.valueMode)) {
                    Text(L("Available %")).tag(ValueMode.available)
                    Text(L("Used %")).tag(ValueMode.consumed)
                }
                Picker(L("Windows"), selection: binding(\.windows)) {
                    Text(L("5h and 7d")).tag(WindowSelection.both)
                    Text(L("5h only")).tag(WindowSelection.fiveHourOnly)
                    Text(L("7d only")).tag(WindowSelection.weeklyOnly)
                }
                Text(L("Alert colors always follow the available percentage, even when showing used."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Updates")) {
                LabeledContent(L("Fallback refresh")) {
                    HStack {
                        Slider(value: binding(\.refreshInterval), in: RefreshScheduler.userIntervalRange, step: 30)
                        Text(RelativeTime.countdown(to: Date(timeIntervalSinceNow: model.settings.refreshInterval), from: Date()))
                            .monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                Text(L("AIquota updates as soon as local activity is detected. This interval is only the fallback while you are active; when idle it slows down to save energy. Each provider enforces its own safe minimum."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section { RepositionTip() }
        }
        .formStyle(.grouped)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }
}

// MARK: - Appearance

private struct AppearanceSettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: QuotaStore
    @State private var draft = AppearanceSettings()
    @State private var draftThresholds = ToneThresholds.default
    @State private var loaded = false

    private var hasChanges: Bool {
        draft != model.settings.appearance || draftThresholds != model.settings.thresholds
    }

    var body: some View {
        VStack(spacing: 0) {
            PreviewStrip(appearance: draft, thresholds: draftThresholds)
                .padding(.horizontal, 20).padding(.top, 16)
            Form {
                Section(L("Style")) {
                    Picker(L("Style"), selection: $draft.style) {
                        Text(L("Minimal")).tag(IndicatorStyle.minimal)
                        Text(L("Microbar")).tag(IndicatorStyle.microbar)
                        Text(L("Ring")).tag(IndicatorStyle.ring)
                    }.pickerStyle(.segmented).labelsHidden()
                    Toggle(L("Show % sign"), isOn: $draft.showPercentSign).disabled(draft.style == .ring)
                    Toggle(L("Show each AI app's icon"), isOn: $draft.showProviderIcon)
                    Text(L("Useful when the AI app's own menu bar icon is hidden. Uses the icon of the app installed on your Mac."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Section(L("Typography & shapes")) {
                    slider(L("Number size"), $draft.numberSize, AppearanceSettings.numberSizeRange, step: 0.5)
                    slider(L("Label size (5h / 7d)"), $draft.labelSize, AppearanceSettings.labelSizeRange, step: 0.5)
                    if draft.style == .microbar {
                        slider(L("Bar thickness"), $draft.barThickness, AppearanceSettings.barThicknessRange, step: 0.25)
                    }
                    if draft.style == .ring {
                        slider(L("Ring thickness"), $draft.ringThickness, AppearanceSettings.ringThicknessRange, step: 0.25)
                    }
                    slider(L("Spacing"), $draft.cellSpacing, AppearanceSettings.cellSpacingRange, step: 1)
                }
                Section(L("Colors")) {
                    colorRow(L("Caution"), hex: $draft.cautionColorHex, fallback: IndicatorPalette.defaultCaution)
                    colorRow(L("Critical"), hex: $draft.criticalColorHex, fallback: IndicatorPalette.defaultCritical)
                    Toggle(L("Also color the numbers"), isOn: $draft.colorizeNumbers)
                    Stepper(value: $draftThresholds.caution, in: max(draftThresholds.critical + 1, 2)...50, step: 1) {
                        Text(String(format: L("Caution at %d%% available or less"), Int(draftThresholds.caution)))
                    }
                    Stepper(value: $draftThresholds.critical, in: 1...max(1, draftThresholds.caution - 1), step: 1) {
                        Text(String(format: L("Critical below %d%% available"), Int(draftThresholds.critical)))
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button(L("Restore defaults")) {
                    draft = AppearanceSettings()
                    draftThresholds = .default
                }
                Spacer()
                Button(L("Revert")) { load() }.disabled(!hasChanges)
                Button(L("Apply")) {
                    model.updateSettings {
                        $0.appearance = draft
                        $0.thresholds = draftThresholds
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasChanges)
            }
            .padding(.horizontal, 20).padding(.bottom, 14)
        }
        .onAppear { if !loaded { load(); loaded = true } }
    }

    private func load() {
        draft = model.settings.appearance
        draftThresholds = model.settings.thresholds
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: step)
                Text(String(format: "%.2g", value.wrappedValue)).monospacedDigit().frame(width: 34, alignment: .trailing)
            }
        }
    }

    private func colorRow(_ title: String, hex: Binding<String?>, fallback: NSColor) -> some View {
        HStack {
            ColorPicker(title, selection: Binding(
                get: { Color(nsColor: hex.wrappedValue.flatMap(NSColor.init(hex:)) ?? fallback) },
                set: { hex.wrappedValue = NSColor($0).hexString }), supportsOpacity: false)
            if hex.wrappedValue != nil {
                Button(L("Default")) { hex.wrappedValue = nil }.buttonStyle(.link)
            }
        }
    }
}

/// Real preview: the same renderer as the menu bar, on light and dark strips, using current data
/// (or clearly labelled sample values when there is none yet).
struct PreviewStrip: View {
    let appearance: AppearanceSettings
    let thresholds: ToneThresholds
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: QuotaStore

    var body: some View {
        let (statuses, isSample) = previewStatuses()
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                strip(statuses, appearance: NSAppearance(named: .aqua)!, background: Color(white: 0.94))
                strip(statuses, appearance: NSAppearance(named: .darkAqua)!, background: Color(white: 0.17))
            }
            Text(isSample ? L("Preview with sample values") : L("Preview with your current data"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func previewStatuses() -> ([ProviderStatus], Bool) {
        let real = store.orderedStatuses.filter { $0.snapshot != nil && model.settings.providerSettings($0.provider).enabled }
        if !real.isEmpty { return (real, real.allSatisfy { $0.snapshot?.isFixture == true }) }
        return ([Fixtures.status(.codex, name: "Codex", fiveHourAvailable: 83, weeklyAvailable: 42),
                 Fixtures.status(.claude, name: "Claude Code", fiveHourAvailable: 15, weeklyAvailable: 7)], true)
    }

    private func strip(_ statuses: [ProviderStatus], appearance: NSAppearance, background: Color) -> some View {
        HStack(spacing: 10) {
            ForEach(statuses, id: \.provider) { status in
                let cells = IndicatorModelBuilder.cells(for: status, windows: model.settings.windows(for: status.provider),
                                                        mode: model.settings.valueMode, thresholds: thresholds, now: Date())
                Image(nsImage: IndicatorRenderer.image(cells: cells, settings: self.appearance,
                                                       mark: self.appearance.showProviderIcon ? ProviderIcons.icon(for: status.provider) : nil,
                                                       height: 22, appearance: appearance))
                    .help(status.displayName)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
        .background(RoundedRectangle(cornerRadius: 5).fill(background))
    }
}

// MARK: - Providers

private struct ProvidersSettings: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: QuotaStore
    @State private var bridgeStatus: ClaudeStatusLineBridge.Status = .notInstalled
    @State private var confirmInstall = false
    @State private var bridgeMessage: String?

    var body: some View {
        Form {
            ForEach(store.orderedStatuses, id: \.provider) { status in
                Section(status.displayName) {
                    Toggle(L("Show in menu bar"), isOn: Binding(
                        get: { model.settings.providerSettings(status.provider).enabled },
                        set: { value in model.updateSettings { $0.updateProvider(status.provider) { $0.enabled = value } } }))
                    Picker(L("Windows"), selection: Binding(
                        get: { model.settings.providerSettings(status.provider).windows },
                        set: { value in model.updateSettings { $0.updateProvider(status.provider) { $0.windows = value } } })) {
                        Text(L("Same as General")).tag(WindowSelection?.none)
                        Text(L("5h and 7d")).tag(WindowSelection?.some(.both))
                        Text(L("5h only")).tag(WindowSelection?.some(.fiveHourOnly))
                        Text(L("7d only")).tag(WindowSelection?.some(.weeklyOnly))
                    }
                    LabeledContent(L("Status"), value: stateDescription(status))
                    if status.provider == .codex { codexOptions }
                    if status.provider == .claude { claudeOptions }
                    DisclosureGroup(L("Diagnostics")) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(store.detections[status.provider]?.notes ?? [], id: \.self) { note in
                                Text(note).font(.caption).textSelection(.enabled)
                            }
                            if let snapshot = status.snapshot {
                                Text(String(format: L("Last data: %@ (%@)"), Formatters.dateTime(snapshot.observedAt), snapshot.source.rawValue))
                                    .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Section {
                Text(L("Want Gemini, Copilot or Cursor? Providers are small adapters — contributions are welcome."))
                    .font(.caption).foregroundStyle(.secondary)
                Link(L("How to add a provider"), destination: AppLinks.addingProviders).font(.caption)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            bridgeStatus = model.claudeBridge.status()
            Task { await store.refreshDetections() }
        }
        .alert(L("Enable the Claude Code status line integration?"), isPresented: $confirmInstall) {
            Button(L("Enable")) { installBridge() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(model.claudeBridge.installPlan().map { "• " + L($0) }.joined(separator: "\n"))
        }
    }

    private var codexOptions: some View {
        Group {
            LabeledContent(L("Data source"), value: L("Codex App Server (official) + local session activity"))
            TextField(L("Codex CLI path (optional)"), text: Binding(
                get: { model.settings.codexExecutablePath ?? "" },
                set: { value in model.updateSettings { $0.codexExecutablePath = value.isEmpty ? nil : value } }),
                      prompt: Text(L("Detected automatically")))
        }
    }

    private var claudeOptions: some View {
        Group {
            LabeledContent(L("Status line integration")) {
                HStack {
                    Text(bridgeStatusText).foregroundStyle(.secondary)
                    switch bridgeStatus {
                    case .installed:
                        Button(L("Remove")) { removeBridge() }
                    case .notInstalled, .replacedByUser:
                        Button(L("Enable…")) { confirmInstall = true }
                    case .settingsUnreadable:
                        EmptyView()
                    }
                }
            }
            Text(L("Official source with reset times. Updates after each Claude Code response in the terminal. Your existing status line keeps working and can be restored at any time."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let bridgeMessage { Text(bridgeMessage).font(.caption).foregroundStyle(.secondary) }
            Toggle(L("Read Claude app usage data (unofficial)"), isOn: Binding(
                get: { model.settings.useClaudeDesktopHistory },
                set: { value in model.updateSettings { $0.useClaudeDesktopHistory = value } }))
            Text(L("The Claude app refreshes your plan usage about every 5 minutes and keeps it on disk. AIquota reads only the percentages and renewal times from those local files: no credentials, no network. These formats are undocumented and may change."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bridgeStatusText: String {
        switch bridgeStatus {
        case .installed: return L("Enabled")
        case .notInstalled: return L("Off")
        case .replacedByUser: return L("Replaced by another status line")
        case .settingsUnreadable: return L("settings.json is not valid JSON")
        }
    }

    private func installBridge() {
        do {
            try model.claudeBridge.install()
            bridgeMessage = L("Enabled. A backup of settings.json was saved in AIquota's support folder.")
        } catch {
            bridgeMessage = error.localizedDescription
        }
        bridgeStatus = model.claudeBridge.status()
        store.refresh(.claude, reason: .settings)
    }

    private func removeBridge() {
        do {
            let restored = try model.claudeBridge.uninstall()
            bridgeMessage = restored ? L("Removed. Your previous status line was restored.")
                                     : L("Your status line had already been changed; AIquota left it untouched.")
        } catch {
            bridgeMessage = error.localizedDescription
        }
        bridgeStatus = model.claudeBridge.status()
    }

    private func stateDescription(_ status: ProviderStatus) -> String {
        switch status.state {
        case .connected: return L("Connected")
        case .waitingForData(let reason): return reason.isEmpty ? L("Waiting for data") : L(reason)
        case .notInstalled: return L("Not installed")
        case .notAuthenticated: return L("Not signed in")
        case .unsupported(let reason): return L(reason)
        case .error(let message): return message
        case .disabled: return L("Disabled")
        }
    }
}

// MARK: - Notifications

private struct NotificationSettings: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var service: NotificationService

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Permission")) {
                    HStack {
                        Text(permissionText).foregroundStyle(.secondary)
                        if service.authorization == .notDetermined {
                            Button(L("Allow…")) { Task { await service.requestAuthorization() } }
                        } else if service.authorization == .denied {
                            Button(L("Open System Settings")) {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                            }
                        } else {
                            Button(L("Send test")) { service.sendTest() }
                        }
                    }
                }
                if !service.isAvailable {
                    Text(L("Notifications need the bundled app (run scripts/build-app.sh)."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("Low limits")) {
                ForEach(AlertSettings.thresholdChoices, id: \.self) { threshold in
                    Toggle(String(format: L("Available below %d%%"), threshold), isOn: Binding(
                        get: { model.settings.alerts.lowAvailableThresholds[threshold] ?? false },
                        set: { value in model.updateSettings { $0.alerts.lowAvailableThresholds[threshold] = value } }))
                }
            }
            Section(L("Renewals")) {
                Toggle(L("5-hour window renewed"), isOn: alertBinding(\.fiveHourRenewal))
                Toggle(L("Weekly window renewed"), isOn: alertBinding(\.weeklyRenewal))
                Text(L("Renewals are announced only when new data confirms them, never from the clock alone."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Saved resets")) {
                Toggle(L("Saved reset expiring within 3 days"), isOn: alertBinding(\.resetCreditExpiring))
            }
            Section {
                Text(L("Each alert is sent once per window. macOS Focus modes are respected."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await service.refreshAuthorization() }
    }

    private var permissionText: String {
        switch service.authorization {
        case .authorized, .provisional, .ephemeral: return L("Allowed")
        case .denied: return L("Denied")
        default: return L("Not requested")
        }
    }

    private func alertBinding(_ keyPath: WritableKeyPath<AlertSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings.alerts[keyPath: keyPath] },
                set: { value in model.updateSettings { $0.alerts[keyPath: keyPath] = value } })
    }
}

// MARK: - About

private struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AIquota").font(.title2.weight(.semibold))
                    Text("Your AI limits. Always visible. Zero clicks.").foregroundStyle(.secondary)
                    Text(String(format: L("Version %@"), AIquotaVersion.current)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Link(L("GitHub repository"), destination: AppLinks.repository)
                Link(L("MIT License"), destination: AppLinks.license)
                Link(L("Contributors"), destination: AppLinks.contributors)
                Link(L("How to contribute"), destination: AppLinks.contributing)
            }
            Section(L("Positioning indicators")) { RepositionTip() }
            Section {
                Text(L("AIquota is independent and not affiliated with OpenAI or Anthropic. Codex, ChatGPT, Claude and Claude Code are trademarks of their respective owners."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
