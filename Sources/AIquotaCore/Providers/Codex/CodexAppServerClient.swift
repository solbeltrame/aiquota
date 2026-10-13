import Foundation

/// Talks to `codex app-server` over stdio (newline-delimited JSON-RPC).
///
/// A persistent app-server costs ~110 MB of memory and only emits `account/rateLimits/updated`
/// for turns it runs itself, so AIquota launches it on demand: initialize → read → exit (~1.5 s).
/// Real-time triggers come from `CodexSessionWatcher` instead.
public final class CodexAppServerClient: @unchecked Sendable {
    public let executable: URL
    private let environment: [String: String]

    public init(executable: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.executable = executable
        self.environment = environment
    }

    public func readRateLimits(timeout: TimeInterval = 20) async throws -> QuotaSnapshot {
        let session = Session(executable: executable, environment: environment, timeout: timeout)
        return try await session.run()
    }
}

private final class Session: @unchecked Sendable {
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let queue = DispatchQueue(label: "aiquota.codex.appserver")
    private let timeout: TimeInterval
    private var buffer = Data()
    private var continuation: CheckedContinuation<QuotaSnapshot, Error>?
    private var finished = false
    private var authMode: String??  // .none = not reported yet, .some(nil) = logged out
    private var result: QuotaSnapshot?

    init(executable: URL, environment: [String: String], timeout: TimeInterval) {
        self.timeout = timeout
        process.executableURL = executable
        process.arguments = ["app-server"]
        var env = environment
        let extraPath = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        env["PATH"] = ((env["PATH"].map { [$0] } ?? []) + extraPath).joined(separator: ":")
        process.environment = env
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
    }

    func run() async throws -> QuotaSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.start()
            }
        }
    }

    private func start() {
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            self.queue.async {
                if chunk.isEmpty {
                    self.finish(.failure(ProviderError.failed("Codex app-server exited unexpectedly")))
                } else {
                    self.consume(chunk)
                }
            }
        }
        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.queue.async {
                self.finish(.failure(ProviderError.failed("Codex app-server exited (status \(proc.terminationStatus))")))
            }
        }
        do {
            try process.run()
        } catch {
            finish(.failure(ProviderError.notInstalled))
            return
        }
        send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "aiquota", "title": "AIquota", "version": AIquotaVersion.current],
            "capabilities": ["optOutNotificationMethods": ["remoteControl/status/changed"]],
        ]])
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(.failure(ProviderError.failed("Codex app-server timed out")))
        }
    }

    private func send(_ message: [String: Any]) {
        guard !finished, var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        try? stdin.fileHandleForWriting.write(contentsOf: data)
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty,
                  let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            handle(object)
            if finished { return }
        }
    }

    private func handle(_ message: [String: Any]) {
        if let method = message["method"] as? String {
            let params = message["params"] as? [String: Any] ?? [:]
            switch method {
            case "account/updated":
                authMode = .some(params["authMode"] as? String)
            case "account/rateLimits/updated":
                if let data = try? JSONSerialization.data(withJSONObject: params) {
                    result = (try? CodexRateLimitParser.mergeUpdatedNotification(data, into: result, observedAt: Date())) ?? result
                }
            default:
                break
            }
            return
        }
        let id = message["id"] as? Int
        if let error = message["error"] as? [String: Any] {
            finish(.failure(mapError(error["message"] as? String ?? "Unknown error")))
            return
        }
        switch id {
        case 1:
            send(["method": "initialized"])
            // Background reads skip the per-credit detail lookup only when we already know the details;
            // reset credits are cheap enough to request every time for an accurate popover.
            send(["id": 2, "method": "account/rateLimits/read", "params": NSNull()])
        case 2:
            guard let result = message["result"],
                  let data = try? JSONSerialization.data(withJSONObject: result) else {
                finish(.failure(ProviderError.failed("Empty rate limit response")))
                return
            }
            do {
                let snapshot = try CodexRateLimitParser.parseReadResponse(data, observedAt: Date())
                if snapshot.windows.isEmpty {
                    finish(.failure(ProviderError.noData("Codex returned no usage windows for this account")))
                } else {
                    finish(.success(snapshot))
                }
            } catch {
                finish(.failure(ProviderError.failed("Unexpected rate limit format")))
            }
        default:
            break
        }
    }

    private func mapError(_ message: String) -> ProviderError {
        if case .some(.none) = authMode { return .notAuthenticated }
        if case .some(.some("apikey")) = authMode {
            return .unsupported("Signed in with an API key. Subscription limits need a ChatGPT sign-in.")
        }
        let lower = message.lowercased()
        if lower.contains("auth") || lower.contains("log in") || lower.contains("login") || lower.contains("sign in") {
            return .notAuthenticated
        }
        if lower.contains("rate limit") || lower.contains("too many") {
            return .rateLimited(retryAfter: nil)
        }
        return .failed(String(message.prefix(160)))
    }

    private func finish(_ outcome: Result<QuotaSnapshot, Error>) {
        guard !finished else { return }
        finished = true
        stdout.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        try? stdin.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        continuation?.resume(with: outcome)
        continuation = nil
    }
}
