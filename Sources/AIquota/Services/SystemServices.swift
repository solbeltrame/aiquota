import AppKit
import AIquotaCore
import ServiceManagement
import UserNotifications

/// Native notifications. Permission is requested only when the user asks (onboarding or settings).
@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private var center: UNUserNotificationCenter? {
        // UNUserNotificationCenter requires a bundled app; `swift run` binaries have no bundle identifier.
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    var isAvailable: Bool { center != nil }

    override init() {
        super.init()
        center?.delegate = self
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        guard let center else { return }
        authorization = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        guard let center else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshAuthorization()
    }

    func deliver(_ event: AlertEvent) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        let text = AlertText.make(event)
        content.title = text.title
        content.body = text.body
        content.threadIdentifier = event.provider.rawValue
        content.interruptionLevel = .active  // Focus modes decide whether it breaks through.
        // The key de-duplicates: re-sending the same alert replaces it instead of stacking.
        center.add(UNNotificationRequest(identifier: event.key, content: content, trigger: nil))
    }

    func sendTest() {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "AIquota"
        content.body = L("Notifications are working.")
        center.add(UNNotificationRequest(identifier: "aiquota.test", content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

enum AlertText {
    static func make(_ event: AlertEvent) -> (title: String, body: String) {
        let window = event.window.map(windowName) ?? ""
        switch event.kind {
        case .lowAvailable(let threshold, let available):
            return (String(format: L("%@: %@ below %d%%"), event.providerName, window, threshold),
                    String(format: L("%d%% of the %@ limit is still available."), available, window.lowercased()))
        case .windowRenewed:
            return (String(format: L("%@: %@ renewed"), event.providerName, window),
                    L("Fresh usage confirmed by the latest data."))
        case .resetCreditExpiring(_, let expiresAt):
            return (String(format: L("%@: reset expiring soon"), event.providerName),
                    String(format: L("A saved reset expires %@. Use it in %@ if you need it."),
                           Formatters.dateTime(expiresAt), event.providerName))
        }
    }

    static func windowName(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: return L("5-hour limit")
        case .weekly: return L("Weekly limit")
        case .other: return L("Limit")
        }
    }
}

/// Launch at login through the modern Service Management API (macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

enum Formatters {
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(date) ? "jmm" : "EEEjmm")
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMdjmm")
        return formatter.string(from: date)
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }
}

enum AppLinks {
    // Update when the public repository is created.
    static let repository = URL(string: "https://github.com/solbeltrame/aiquota")!
    static var releases: URL { repository.appendingPathComponent("releases") }
    static var contributing: URL { repository.appendingPathComponent("blob/main/CONTRIBUTING.md") }
    static var contributors: URL { repository.appendingPathComponent("graphs/contributors") }
    static var license: URL { repository.appendingPathComponent("blob/main/LICENSE") }
    static var addingProviders: URL { repository.appendingPathComponent("blob/main/docs/ADDING_A_PROVIDER.md") }
}

func L(_ key: String) -> String { L10n.t(key) }
