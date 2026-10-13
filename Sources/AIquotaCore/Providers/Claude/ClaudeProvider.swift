import Foundation

/// Anthropic Claude Code. Purely local: no credentials, no network, no tokens spent.
///
/// Sources (the newest reading wins; reset times are kept while they still describe the same window):
/// 1. Status line bridge (documented, opt-in) — percentages and reset times after every response.
/// 2. Claude desktop app usage cache (undocumented, read-only) — percentages and reset times, ~every 5 minutes.
/// 3. Claude desktop app usage history (undocumented, read-only) — percentages only, ~every 5 minutes.
public final class ClaudeProvider: QuotaProvider, @unchecked Sendable {
    public let id = ProviderID.claude
    public let displayName = "Claude Code"
    /// Reads are local file reads, so they are cheap; events drive most updates.
    public let refreshPolicy = RefreshPolicy(minimumInterval: 2, activeInterval: 60, idleInterval: 5 * 60)

    public let bridge: ClaudeStatusLineBridge
    private let desktopHistoryURL: URL
    private let desktopCacheDirectory: URL
    private let useDesktopHistory: @Sendable () -> Bool
    private var watcher: FileWatcher?
    private let lock = NSLock()

    public init(bridge: ClaudeStatusLineBridge = ClaudeStatusLineBridge(),
                desktopHistoryURL: URL = ClaudeDesktopHistoryReader.defaultURL(),
                desktopCacheDirectory: URL = ClaudeDesktopCacheReader.defaultDirectory(),
                useDesktopHistory: @escaping @Sendable () -> Bool = { true }) {
        self.bridge = bridge
        self.desktopHistoryURL = desktopHistoryURL
        self.desktopCacheDirectory = desktopCacheDirectory
        self.useDesktopHistory = useDesktopHistory
    }

    public func detect() async -> ProviderDetection {
        let fm = FileManager.default
        var notes: [String] = []
        let desktopInstalled = fm.fileExists(atPath: "/Applications/Claude.app")
            || fm.fileExists(atPath: desktopHistoryURL.deletingLastPathComponent().path)
        let cliInstalled = fm.fileExists(atPath: bridge.claudeConfigDir.path)
        notes.append(cliInstalled ? "Claude Code config: \(bridge.claudeConfigDir.path)" : "Claude Code config folder not found")
        switch bridge.status() {
        case .installed: notes.append("Status line bridge: installed")
        case .notInstalled: notes.append("Status line bridge: not installed (optional)")
        case .replacedByUser: notes.append("Status line bridge: replaced by another status line")
        case .settingsUnreadable: notes.append("Status line bridge: settings.json is not valid JSON")
        }
        if desktopInstalled {
            let hasHistory = fm.fileExists(atPath: desktopHistoryURL.path)
            notes.append(hasHistory ? "Claude desktop usage history: found" : "Claude desktop usage history: not written yet")
            let cached = ClaudeDesktopCacheReader.read(directory: desktopCacheDirectory)
            notes.append(cached != nil ? "Claude desktop usage cache: found (includes reset times)"
                                       : "Claude desktop usage cache: no usage response cached yet")
        }
        return ProviderDetection(isInstalled: desktopInstalled || cliInstalled, notes: notes)
    }

    public func fetch() async throws -> QuotaSnapshot {
        var readings = [bridge.readCapturedSnapshot()]
        if useDesktopHistory() {
            readings.append(ClaudeDesktopCacheReader.read(directory: desktopCacheDirectory))
            readings.append(ClaudeDesktopHistoryReader.read(desktopHistoryURL))
        }
        if let snapshot = Self.combine(readings.compactMap { $0 }) {
            return snapshot
        }
        if bridge.status() == .installed {
            throw ProviderError.noData("Waiting for the next Claude Code response")
        }
        throw ProviderError.noData("Open Claude, or enable the Claude Code status line integration")
    }

    /// Picks the newest reading (preferring one with reset times when readings are within a minute of
    /// each other, as the Claude app writes its cache and history together). Missing reset times are
    /// filled from other readings only while those still describe the same window (they lie after the
    /// chosen reading). Nothing is estimated.
    public static func combine(_ readings: [QuotaSnapshot]) -> QuotaSnapshot? {
        guard let newestDate = readings.map(\.observedAt).max() else { return nil }
        func resetCount(_ snapshot: QuotaSnapshot) -> Int { snapshot.windows.filter { $0.resetsAt != nil }.count }
        let candidates = readings.filter { newestDate.timeIntervalSince($0.observedAt) <= 60 }
        guard var chosen = candidates.max(by: { (resetCount($0), $0.observedAt) < (resetCount($1), $1.observedAt) })
        else { return nil }
        chosen.windows = chosen.windows.map { window in
            guard window.resetsAt == nil else { return window }
            var window = window
            window.resetsAt = readings.compactMap { $0.window(window.kind)?.resetsAt }
                .filter { $0 > chosen.observedAt }.min()
            return window
        }
        return chosen
    }

    /// Two-source variant kept for readability in tests.
    public static func combine(statusLine: QuotaSnapshot?, desktop: QuotaSnapshot?) -> QuotaSnapshot? {
        combine([statusLine, desktop].compactMap { $0 })
    }

    public func startWatching(emit: @escaping @Sendable (ChangeSignal) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard watcher == nil else { return }
        try? FileManager.default.createDirectory(at: bridge.supportDir, withIntermediateDirectories: true)
        let targets: Set<String> = [desktopHistoryURL.lastPathComponent, bridge.rateLimitsURL.lastPathComponent]
        let watcher = FileWatcher(paths: [desktopHistoryURL.deletingLastPathComponent().path, bridge.supportDir.path],
                                  latency: 0.5,
                                  filter: { targets.contains(($0 as NSString).lastPathComponent) }) { _ in
            emit(ChangeSignal(snapshot: nil, wantsFetch: true))
        }
        if watcher.start() { self.watcher = watcher }
    }

    public func stopWatching() {
        lock.lock(); defer { lock.unlock() }
        watcher?.stop()
        watcher = nil
    }
}
