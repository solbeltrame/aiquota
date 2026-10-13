import Foundation

public enum CodexLocator {
    /// `$CODEX_HOME` or `~/.codex`.
    public static func codexHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["CODEX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    /// Apps launched from Finder get a minimal PATH, so common install locations are probed explicitly.
    public static func candidateExecutables(override: String?,
                                            environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths: [String] = []
        if let override, !override.isEmpty { paths.append((override as NSString).expandingTildeInPath) }
        for dir in (environment["PATH"] ?? "").split(separator: ":") {
            paths.append("\(dir)/codex")
        }
        paths += [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.bun/bin/codex",
            "\(home)/.volta/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
        ]
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }.map { URL(fileURLWithPath: $0) }
    }

    public static func findExecutable(override: String?) -> URL? {
        candidateExecutables(override: override).first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }
}

/// OpenAI Codex: documented App Server for data, session files as the real-time trigger.
public final class CodexProvider: QuotaProvider, @unchecked Sendable {
    public let id = ProviderID.codex
    public let displayName = "Codex"
    /// The App Server is local, but each read spawns a process and hits OpenAI's usage endpoint:
    /// never more than once every 20 s.
    public let refreshPolicy = RefreshPolicy(minimumInterval: 20, activeInterval: 60, idleInterval: 5 * 60)

    private let executableOverride: @Sendable () -> String?
    private let home: URL
    private var watcher: FileWatcher?
    private let lock = NSLock()

    public init(home: URL = CodexLocator.codexHome(), executableOverride: @escaping @Sendable () -> String? = { nil }) {
        self.home = home
        self.executableOverride = executableOverride
    }

    public func detect() async -> ProviderDetection {
        var notes: [String] = []
        let executable = CodexLocator.findExecutable(override: executableOverride())
        if let executable {
            notes.append("Codex CLI: \(executable.path)")
        } else {
            notes.append("Codex CLI not found. Install Codex or ChatGPT for Mac, or set the path in Providers.")
        }
        let sessions = home.appendingPathComponent("sessions")
        let hasSessions = FileManager.default.fileExists(atPath: sessions.path)
        notes.append(hasSessions ? "Watching \(sessions.path) for activity" : "No Codex sessions folder yet")
        let hasAuth = FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path)
        notes.append(hasAuth ? "Codex sign-in found (credentials are never read by AIquota)" : "No Codex sign-in file found")
        return ProviderDetection(isInstalled: executable != nil, notes: notes)
    }

    public func fetch() async throws -> QuotaSnapshot {
        guard let executable = CodexLocator.findExecutable(override: executableOverride()) else {
            throw ProviderError.notInstalled
        }
        do {
            return try await CodexAppServerClient(executable: executable).readRateLimits()
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.failed(error.localizedDescription)
        }
    }

    public func startWatching(emit: @escaping @Sendable (ChangeSignal) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard watcher == nil else { return }
        let sessions = home.appendingPathComponent("sessions").path
        let watcher = FileWatcher(paths: [sessions], latency: 0.5,
                                  filter: CodexSessionLogReader.isRolloutFile) { paths in
            // Newest event wins; the snapshot is shown at once and confirmed by a fetch.
            let snapshot = paths.compactMap { CodexSessionLogReader.latestSnapshot(inFile: URL(fileURLWithPath: $0)) }
                .max { $0.observedAt < $1.observedAt }
            emit(ChangeSignal(snapshot: snapshot, wantsFetch: true))
        }
        if watcher.start() {
            self.watcher = watcher
        } else {
            Log.providers.info("Codex sessions folder missing; relying on polling")
        }
    }

    public func stopWatching() {
        lock.lock(); defer { lock.unlock() }
        watcher?.stop()
        watcher = nil
    }
}
