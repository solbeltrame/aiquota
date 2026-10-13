# Adding a provider

A provider is a small adapter that turns some tool's usage data into a `QuotaSnapshot`. The menu bar,
popover, colors, notifications, cache and refresh scheduling all work automatically once it exists.

## 1. Find a trustworthy source

In order of preference:

1. **An official, documented local interface** (CLI command, local server, status hook) — like the Codex App
   Server or Claude Code's status line.
2. **Files the tool already writes locally**, read-only — isolate the parser and label the source "unofficial".
3. **An official HTTP API** the user is already authenticated for — with strict rate limits and `Retry-After`.

Not acceptable: calling a model, scraping with stored passwords, sending data to third parties, or polling
private endpoints aggressively. Open an issue describing the source before writing code.

## 2. Implement `QuotaProvider`

```swift
import AIquotaCore

public final class GeminiProvider: QuotaProvider, @unchecked Sendable {
    public let id = ProviderID("gemini")          // also add `static let gemini` in QuotaModel.swift
    public let displayName = "Gemini CLI"
    public let refreshPolicy = RefreshPolicy(minimumInterval: 30, activeInterval: 60, idleInterval: 300)

    public func detect() async -> ProviderDetection {
        // Local checks only: is the tool installed? Where does it keep data? No network.
        ProviderDetection(isInstalled: FileManager.default.fileExists(atPath: "…"), notes: ["…"])
    }

    public func fetch() async throws -> QuotaSnapshot {
        // Read the source. Throw ProviderError.notInstalled / .notAuthenticated / .noData / .rateLimited / .failed.
        QuotaSnapshot(provider: id,
                      windows: [QuotaWindow(kind: WindowKind.classify(durationMinutes: 300), durationMinutes: 300,
                                            usedPercent: 12, resetsAt: Date(timeIntervalSince1970: 1_800_000_000))],
                      observedAt: Date(),          // when the SOURCE produced the value
                      source: .fixture)            // add a DataSource case for your source
    }

    public func startWatching(emit: @escaping @Sendable (ChangeSignal) -> Void) {
        // Optional but encouraged: watch local files with FileWatcher and call emit(...) on change.
    }

    public func stopWatching() {}
}
```

Rules of thumb:

- Report the **real window duration**; `WindowKind.classify` decides whether it is the 5h or weekly slot.
  Windows of other lengths are kept as `.other` and not shown in the menu bar yet.
- `usedPercent` is 0–100 **used**. AIquota derives "available" and rounds conservatively.
- If you do not know a reset time, leave `resetsAt` nil. Never estimate it.
- Use `ChangeSignal(snapshot:)` to show a locally-read value instantly and `wantsFetch: true` to confirm it.
- Never log secrets. Use `Log.providers` with `privacy: .public` only for non-sensitive values.

## 3. Register it

Add it to the provider list in `Sources/AIquota/AppModel.swift`:

```swift
store = QuotaStore(providers: [codex, claude, GeminiProvider()], settings: settings)
```

That creates a new independent status item (with its own autosave name) and a section in Settings → Providers.

## 4. Test it

- Parser tests with **fixtures that contain no real account data** (`Tests/AIquotaCoreTests/Fixtures`).
- Error mapping: not installed, signed out, no data.
- Optionally a live test gated by `AIQUOTA_LIVE_TESTS=1`.

## 5. Document it

Add the provider to the integration tables in `README.md` and `docs/README.pt-BR.md`, including which
sources are official and which are not, and any limitations.
