import Combine
import Foundation
import Sparkle

enum UpdateCheckState: Equatable {
    case notChecked
    case checking
    case upToDate
    case updateAvailable
    case failed(String)
}

@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var state: UpdateCheckState = .notChecked
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false

    private var updater: SPUUpdater?
    private var cancellables: Set<AnyCancellable> = []

    func attach(_ updater: SPUUpdater) {
        self.updater = updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates

        updater.publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
        updater.publisher(for: \.automaticallyChecksForUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &cancellables)
        updater.publisher(for: \.automaticallyDownloadsUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyDownloadsUpdates = $0 }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        state = .checking
        updater?.checkForUpdates()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        updater?.automaticallyDownloadsUpdates = enabled
        automaticallyDownloadsUpdates = enabled
    }

    var stateDescription: String {
        switch state {
        case .notChecked: return L("Check for updates to see if you have the latest version.")
        case .checking: return L("Checking for updates…")
        case .upToDate: return L("AIquota is up to date.")
        case .updateAvailable: return L("A new version is available.")
        case .failed(let message): return String(format: L("Could not check for updates: %@"), message)
        }
    }

    var stateSymbol: String {
        switch state {
        case .notChecked: return "info.circle"
        case .checking: return "arrow.clockwise"
        case .upToDate: return "checkmark.circle.fill"
        case .updateAvailable: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        state = .updateAvailable
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        state = .upToDate
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        state = .failed(error.localizedDescription)
    }
}
