# Architecture

```
            ┌────────────────────────── AIquotaCore (Foundation only) ──────────────────────────┐
 local      │  QuotaProvider ──fetch()──▶ QuotaSnapshot ──▶ QuotaStore ──▶ ProviderStatus        │
 files ─FSEvents─▶ ChangeSignal ─────────────┘    │  RefreshScheduler (events, polling, backoff)  │
            │                                     │  AlertEngine (thresholds, renewals, credits)  │
            │                                     │  SnapshotCache, SettingsStore, L10n           │
            └─────────────────────────────────────┼────────────────────────────────────────────────┘
                                                  ▼
            AIquotaUI: IndicatorLayout / IndicatorRenderer / IndicatorPalette / IndicatorView
                                                  ▼
            AIquota app: StatusItemController (one NSStatusItem per provider) · PopoverView
                         SettingsView · OnboardingView · NotificationService · LaunchAtLogin
```

## Data model

- `QuotaWindow` — kind (`fiveHour`, `weekly`, `other`, classified from the real duration), used %, reset time.
- `QuotaSnapshot` — provider, windows, `observedAt` (when the *source* produced it), `source`, optional reset
  credits and plan, `isFixture`.
- `ProviderStatus` — the latest snapshot plus integration state (`connected`, `waitingForData`,
  `notInstalled`, `notAuthenticated`, `unsupported`, `error`, `disabled`) and whether it came from cache.
- `Freshness` — `current` (< 15 min), `cached` (restored at launch or < 3 h), `stale` (> 3 h, drawn dimmed),
  `unavailable`.

A window whose `resetsAt` is in the past — or, when the source has no reset time, whose reading is older than one full window length — is shown as `–` until new data arrives.

## Refresh flow

1. At launch the store restores the cache (marked cached), starts each provider's watcher and fetches once.
2. A provider's `FileWatcher` (FSEvents, 0.5 s latency, path-filtered) emits a `ChangeSignal`. If it carries a
   locally-read snapshot, the UI updates immediately. If `wantsFetch`, one confirming fetch is scheduled no
   earlier than `minimumInterval` after the previous one; bursts coalesce into a single fetch.
3. After every fetch the next fallback poll is scheduled: `activeInterval` if an event happened in the last
   10 minutes, otherwise `idleInterval`. Failures back off exponentially (capped at 30 min); `rateLimited`
   errors honour `Retry-After` with a minimum 5-minute cooldown. `noData` is not a failure.
4. Wake from sleep triggers a refresh; a 30-second local timer re-evaluates freshness and roll-over (no I/O).

| Provider | Min interval | Active | Idle | Events |
|---|---|---|---|---|
| Codex | 20 s | 60 s | 5 min | `~/.codex/sessions` rollout writes |
| Claude Code | 2 s (local reads) | 60 s | 5 min | status line capture, Claude app history (written together with the usage cache) |

## Rendering

The indicator is an `NSView` inside the status bar button (clicks pass through). It resolves colors against
the opaque `aqua` / `darkAqua` appearance matching the menu bar's vibrant appearance, so text stays crisp and
solid. Layout is computed from settings only:

- Number slot: width of `00` + `%` (or `100`, whichever is wider) using tabular figures, numbers
  left-aligned and centered on their cap height (checked by `VerticalCenteringTests`); `100` is drawn without `%`. With `%` hidden the slot is two digits and `100` adds one digit.
- Labels: a fixed width for `5h`/`7d`, cap-top aligned with the number (a typographic superscript).
- Microbar: a rounded bar under the slot, default 1.5 pt, 2 pt below the baseline.
- Ring: diameter `min(18, height − 5)`, stroke 1.5 pt, clockwise from 12 o'clock; inner number scaled to fit.

No leading padding (1 pt trailing), so an indicator can sit right next to the AI app's icon; macOS keeps its
own standard gap between status items. The optional provider icon (16 pt + 3 pt gap) is the installed app's icon
from `NSWorkspace`, or a neutral monogram when the app is not installed.

### Width budget (defaults, 22 pt button)

| Style | Both windows | One window | Both, no `%` |
|---|---|---|---|
| Minimal | 77 pt | 37 pt | 59 pt |
| Microbar | 77 pt | 37 pt | 59 pt |
| Ring | 61 pt | 29 pt | 61 pt |

Enforced by `LayoutBudgetTests`.

## Alerts

`AlertEngine.evaluate` is pure and receives a persisted set of fired keys:

- Low availability: crossing below 20/10/5% fires once (only the lowest newly crossed threshold); re-armed
  after recovering 5 points above it, or after a confirmed renewal.
- Renewal: only when new data shows usage dropped ≥ 10 points to ≤ 10% and the reset time moved forward (when
  known), and the previous reading is recent. Never from the clock alone.
- Saved reset expiring within 72 h: once per credit.
- Fixtures never notify. Notification identifiers equal the alert key, so the system de-duplicates too.

## Claude status line bridge

`ClaudeStatusLineBridge.install()` (only after user confirmation): backs up `settings.json`, records the previous
`statusLine` object and command, writes `statusline-bridge.sh` to AIquota's support folder and points
`statusLine.command` at it (keeping `padding` / `refreshInterval`). The script extracts `rate_limits` with
`/usr/bin/plutil`, writes it atomically to `rate-limits.json`, then pipes the original JSON to the previous
command. `uninstall()` restores the previous `statusLine` only if AIquota's entry is still in place.

## Measured cost (MacBook Air M1, macOS 26, release build)

| | |
|---|---|
| App memory (RSS) | 26–45 MB |
| App CPU while idle | 0.11 s over 3 minutes (≈0.06%); `top` power 0.0 |
| One Codex App Server read | 1.45 s wall, ≈0.28 s CPU in the child process |
| Codex reads | ≤ 1 per 20 s while active (usually 1/min), 1 per 5 min idle |
| Claude reads | Local file reads only |
