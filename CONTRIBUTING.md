# Contributing to AIquota

Thank you for helping! AIquota is meant to be friendly to first-time open source contributors — if
something here is unclear, that is a bug in this document; please open an issue.

## Ways to help

- **New providers** (Gemini CLI, GitHub Copilot, Cursor, …) — see [docs/ADDING_A_PROVIDER.md](docs/ADDING_A_PROVIDER.md).
- **Visual polish** of the menu bar indicators, popover and settings.
- **Performance and energy** improvements.
- **Tests**, especially on other macOS versions, Intel Macs and Macs with a notch.
- **Bug fixes**, **translations** and **documentation**.

Look for [`good first issue`](../../labels/good%20first%20issue) and [`help wanted`](../../labels/help%20wanted).
For anything bigger than a small fix, open an issue first so we can agree on the approach.

## Getting started

Requirements: macOS 14+, Xcode 16+ (Swift 6 toolchain).

```bash
git clone https://github.com/solbeltrame/aiquota.git
cd aiquota
swift build
swift test
scripts/build-app.sh && open dist/AIquota.app
```

You can also open `Package.swift` in Xcode.

### Useful development switches

| Variable / flag | Effect |
|---|---|
| `--fixtures` or `AIQUOTA_FIXTURES=1` | Show sample data (labelled "Sample data", never cached or notified). |
| `AIQUOTA_FIXTURE_CODEX_5H=9` (and `_CODEX_7D`, `_CLAUDE_5H`, `_CLAUDE_7D`) | Choose the sample percentages. |
| `AIQUOTA_DEBUG_DUMP_DIR=/tmp/aiquota` | After 8 s, write PNGs of the live indicators (no screen recording permission needed). |
| `AIQUOTA_DEBUG_DUMP_VIEWS=1` | With the above, also render popovers, settings and onboarding. |
| `AIQUOTA_GALLERY_DIR=/tmp/g swift test --filter RenderGallery` | Render every style at 100/99/50/20/10/9/5/0% in light and dark. |
| `AIQUOTA_LIVE_TESTS=1 swift test --filter Live` | Read your real limits (no model calls, no tokens). |

## Project layout

```
Sources/AIquotaCore   Foundation only: model, providers, refresh scheduler, alerts, settings, l10n
Sources/AIquotaUI     AppKit drawing of the indicators (layout, palette, renderer, view)
Sources/AIquota       The app: status items, popover, settings, onboarding, notifications
Tests/                Swift Testing suites; fixtures contain no real account data
scripts/build-app.sh  Builds and signs (ad-hoc by default) the app, ZIP and DMG downloads
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how data flows.

## Ground rules

These keep AIquota trustworthy. PRs that break them will not be merged:

1. **Never show a made-up number.** Missing data is `–`, never 100%. Do not estimate reset times.
2. **Never spend tokens** or call a model to learn about limits.
3. **Never read, store or log credentials.** Prefer documented interfaces; isolate and label undocumented ones.
4. **Never change another tool's configuration silently.** Ask first, back up, make it reversible.
5. **Stay discreet.** No saturated colors, gradients or decorative animation. Measure widths in points.
6. **Stay light.** No dependencies without discussion; no aggressive polling.

## Code style

- Match the surrounding code. Swift API Design Guidelines; 4-space indentation; lines under ~130 characters.
- Keep `AIquotaCore` free of AppKit so it stays testable.
- User-facing strings go through `L("…")`. Add the Portuguese translation in `Sources/AIquotaCore/Support/L10n.swift`
  (or mention in the PR that you need help with it).
- Add or update tests for behaviour changes. Visual changes: attach before/after PNGs from the gallery test.

## Pull requests

1. Fork, create a branch (`feature/gemini-provider`, `fix/ring-alignment`).
2. `swift test` must pass.
3. Fill in the PR template, including screenshots for visual changes.
4. Update `CHANGELOG.md` under **Unreleased**.
5. Be patient and kind in review — we will be too.

## Translations

Translations live in `Sources/AIquotaCore/Support/L10n.swift`: English strings are keys, each language is a
dictionary. To add a language, add a case to `AppLanguage`, a dictionary and a picker entry in General settings.

## Releases (maintainers)

1. Bump `AIquotaVersion.current` and `CHANGELOG.md`.
2. Tag `vX.Y.Z` and push. The release workflow builds the universal app, creates ZIP and DMG downloads, signs the Sparkle appcast, and publishes a GitHub release. It needs the `SPARKLE_PRIVATE_KEY` repository secret.
3. Sign and notarize if a Developer ID is configured (see [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)).
