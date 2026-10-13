import AIquotaCore
import AIquotaUI
import SwiftUI

struct PopoverView: View {
    let providerID: ProviderID
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: QuotaStore

    var body: some View {
        // Countdowns and "updated x ago" tick locally; no network involved.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let status = store.statuses[providerID] {
                content(status, now: context.date)
            }
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private func content(_ status: ProviderStatus, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(status)
            if let snapshot = status.snapshot {
                ForEach(WindowKind.allCases.filter { $0 != .other }, id: \.self) { kind in
                    if let window = snapshot.window(kind) {
                        WindowRow(window: window, outdated: snapshot.isOutdated(window, at: now), now: now,
                                  mode: model.settings.valueMode,
                                  thresholds: model.settings.thresholds, appearance: model.settings.appearance,
                                  stale: status.freshness(at: now) == .stale)
                    }
                }
                if let credits = snapshot.resetCredits, credits.availableCount > 0 {
                    Divider()
                    CreditsSection(credits: credits, providerName: status.displayName)
                }
            } else {
                EmptyStateView(state: status.state)
            }
            Divider()
            footer(status, now: now)
        }
        .padding(14)
    }

    private func header(_ status: ProviderStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(status.displayName).font(.headline)
            if let plan = status.snapshot?.planName {
                Text(plan).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if status.snapshot?.isFixture == true {
                Badge(text: L("Sample data"))
            }
        }
    }

    private func footer(_ status: ProviderStatus, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(stateColor(status, now: now)).frame(width: 6, height: 6)
                Text(stateText(status, now: now)).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if let source = status.snapshot?.source {
                Text(sourceText(source)).font(.caption2).foregroundStyle(.tertiary)
            }
            HStack {
                Button { store.refresh(providerID, reason: .manual) } label: {
                    Label(L("Refresh"), systemImage: "arrow.clockwise")
                }
                Spacer()
                Button { model.openSettings(.general) } label: {
                    Label(L("Settings…"), systemImage: "gearshape")
                }
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                }.help(L("Quit AIquota"))
            }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
            .font(.caption)
        }
    }

    private func stateText(_ status: ProviderStatus, now: Date) -> String {
        var age = ""
        if let snapshot = status.snapshot {
            age = String(format: L("Updated %@ ago"), RelativeTime.age(of: snapshot.observedAt, at: now))
        }
        switch status.state {
        case .connected:
            switch status.freshness(at: now) {
            case .current: return age
            case .cached: return age + " · " + L("cached")
            case .stale: return age + " · " + L("may be outdated")
            case .unavailable: return L("No data yet")
            }
        case .waitingForData(let reason):
            return [age, reason.isEmpty ? L("Waiting for data") : L(reason)].filter { !$0.isEmpty }.joined(separator: " · ")
        case .notInstalled: return L("Not installed")
        case .notAuthenticated: return L("Not signed in")
        case .unsupported(let reason): return L(reason)
        case .error(let message): return [age, message].filter { !$0.isEmpty }.joined(separator: " · ")
        case .disabled: return L("Disabled")
        }
    }

    private func stateColor(_ status: ProviderStatus, now: Date) -> Color {
        if status.state.isProblem { return Color(nsColor: IndicatorPalette.defaultCritical) }
        switch status.freshness(at: now) {
        case .current: return .secondary
        case .cached, .stale: return Color(nsColor: IndicatorPalette.defaultCaution)
        case .unavailable: return .secondary.opacity(0.5)
        }
    }

    private func sourceText(_ source: DataSource) -> String {
        let name: String
        switch source {
        case .codexAppServer: name = L("Codex App Server")
        case .codexSessionLog: name = L("Codex session activity")
        case .claudeStatusLine: name = L("Claude Code status line")
        case .claudeDesktopHistory: name = L("Claude app usage history")
        case .claudeDesktopCache: name = L("Claude app usage data")
        case .fixture: name = L("Sample data")
        }
        return String(format: L("Source: %@"), name) + (source.isDocumented || source == .fixture ? "" : " · " + L("unofficial"))
    }
}

private struct WindowRow: View {
    let window: QuotaWindow
    let outdated: Bool
    let now: Date
    let mode: ValueMode
    let thresholds: ToneThresholds
    let appearance: AppearanceSettings
    let stale: Bool

    var body: some View {
        let rolledOver = outdated
        let value = PercentFormatter.displayValue(usedPercent: window.usedPercent, mode: mode)
        let tone = rolledOver || stale ? Tone.muted : thresholds.tone(forAvailable: window.availablePercent)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(AlertText.windowName(window.kind)).font(.subheadline.weight(.medium))
                Spacer()
                if rolledOver {
                    Text("—").font(.title3.monospacedDigit()).foregroundStyle(.tertiary)
                } else {
                    Text("\(value)%").font(.title3.monospacedDigit().weight(.medium))
                    Text(mode == .available ? L("available") : L("used")).font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressBar(fraction: rolledOver ? 0 : PercentFormatter.fraction(usedPercent: window.usedPercent, mode: mode),
                        color: Color(nsColor: IndicatorPalette.accent(for: tone, settings: appearance)))
            Text(resetText(rolledOver: rolledOver)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func resetText(rolledOver: Bool) -> String {
        guard let resetsAt = window.resetsAt else {
            return rolledOver ? L("Window renewed since the last reading · waiting for new data")
                              : L("Renewal time not reported by this source")
        }
        if rolledOver {
            return String(format: L("Renewed at %@ · waiting for new data"), Formatters.time(resetsAt))
        }
        return String(format: L("Renews %@ · in %@"), Formatters.time(resetsAt), RelativeTime.countdown(to: resetsAt, from: now))
    }
}

private struct CreditsSection: View {
    let credits: ResetCreditsSummary
    let providerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L("Saved resets")).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(credits.availableCount)").font(.subheadline.monospacedDigit())
            }
            Text(String(format: L("Manual resets you can use in %@. Separate from the automatic renewal."), providerName))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(credits.credits ?? []) { credit in
                HStack {
                    Text(credit.title ?? L("Reset")).font(.caption)
                    Spacer()
                    if let expires = credit.expiresAt {
                        Text(String(format: L("expires %@"), Formatters.date(expires))).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct EmptyStateView: View {
    let state: IntegrationState
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("No usage data yet")).font(.subheadline.weight(.medium))
            Text(L("AIquota never shows an estimated number. Indicators show “–” until a source reports real values."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(L("Open Providers settings")) { model.openSettings(.providers) }
                .buttonStyle(.link).font(.caption)
        }
    }
}

struct ProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(color).frame(width: max(fraction > 0 ? 4 : 0, geometry.size.width * fraction))
            }
        }
        .frame(height: 4)
    }
}

struct Badge: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .foregroundStyle(.secondary)
    }
}
