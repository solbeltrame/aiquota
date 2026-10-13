import AIquotaCore
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: QuotaStore
    @EnvironmentObject var notifications: NotificationService
    let finish: () -> Void
    @State private var step = 0
    private let stepCount = 5

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: providers
                case 2: alerts
                case 3: indicators
                default: reposition
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)

            HStack {
                HStack(spacing: 5) {
                    ForEach(0..<stepCount, id: \.self) { index in
                        Circle().fill(index == step ? Color.primary.opacity(0.7) : Color.primary.opacity(0.15))
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer()
                if step > 0 { Button(L("Back")) { step -= 1 } }
                Button(step == stepCount - 1 ? L("Done") : L("Continue")) {
                    if step == stepCount - 1 { finish() } else { step += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28).padding(.vertical, 16)
        }
        .frame(width: 520, height: 400)
        .task { await store.refreshDetections() }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Welcome to AIquota")).font(.largeTitle.weight(.semibold))
            Text("Your AI limits. Always visible. Zero clicks.").font(.title3).foregroundStyle(.secondary)
            Text(L("AIquota keeps the remaining 5-hour and weekly limits of your AI coding tools in the menu bar, so you never have to open a dashboard."))
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Everything runs on your Mac. AIquota never sends your data anywhere and never spends tokens to check limits."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var providers: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Your AI tools")).font(.title2.weight(.semibold))
            ForEach(store.orderedStatuses, id: \.provider) { status in
                let detection = store.detections[status.provider]
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: detection?.isInstalled == true ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.displayName).font(.headline)
                        Text(detection?.isInstalled == true ? L("Found on this Mac") : L("Not found — the indicator will show “–”"))
                            .font(.caption).foregroundStyle(.secondary)
                        if status.provider == .claude {
                            Text(L("Keep the Claude app open for automatic updates. Optional: the Claude Code status line integration in Settings → Providers updates after every response."))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Text(L("No sign-in is needed: AIquota uses the tools you already have."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Gentle alerts")).font(.title2.weight(.semibold))
            Text(L("Get a notification when a limit drops below 20%, 10% or 5%, and when a window renews. Each alert is sent once and respects Focus."))
                .fixedSize(horizontal: false, vertical: true)
            switch notifications.authorization {
            case .authorized, .provisional, .ephemeral:
                Label(L("Notifications allowed"), systemImage: "checkmark").foregroundStyle(.secondary)
            case .denied:
                Text(L("Notifications are turned off for AIquota in System Settings.")).foregroundStyle(.secondary)
            default:
                Button(L("Allow notifications…")) { Task { await notifications.requestAuthorization() } }
                Text(L("Optional. You can change this later.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var indicators: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Your indicators")).font(.title2.weight(.semibold))
            Text(L("Each tool has its own indicator in the menu bar. The big number is what is left; the tiny 5h and 7d mark the window."))
                .fixedSize(horizontal: false, vertical: true)
            PreviewStrip(appearance: model.settings.appearance, thresholds: model.settings.thresholds)
            Text(L("Bars turn amber at 20% and red below 10%. Change the style in Settings → Appearance."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var reposition: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Put them next to your AI apps")).font(.title2.weight(.semibold))
            HStack(spacing: 14) {
                Text("⌘").font(.system(size: 34, weight: .semibold)).frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
                Text(L("Hold ⌘ Command and drag to reposition.")).font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.15)))
            Text(L("Drag the Codex indicator next to the ChatGPT icon and the Claude indicator next to the Claude icon. macOS remembers the position when possible, but placement is controlled by macOS and cannot be guaranteed automatically."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
