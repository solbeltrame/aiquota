# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-10-13

### Added
- Menu bar indicators follow whether the matching Codex/ChatGPT or Claude app is running. Closing a window keeps the indicator; quitting the app hides it.
- Updates settings with installed-version status, a manual check, automatic update checks and optional automatic download/installation, powered by signed Sparkle updates.
- Optional icon of each AI app before its numbers (Appearance), taken from the app installed on the Mac.

### Changed
- Windows an account doesn't have (e.g. plans with only a weekly limit) are hidden instead of showing "–".
- Numbers are vertically centered on their cap height (like the menu bar clock); the microbar sits below them.
- Numbers are always left-aligned, with the 5h/7d label right after them.
- No left padding: indicators sit right next to the AI app's own icon (77 pt instead of 82 pt by default).

### Added (Claude)
- Claude reset times without the status line: AIquota reads the usage response the Claude app keeps in its
  local HTTP cache (zstd, decoded with the official libzstd). Read-only, no network, no credentials.

## [0.1.0] - 2026-10-13

### Added
- DMG download with an Applications shortcut, alongside the ZIP release asset.
- Independent, always-visible menu bar indicators for OpenAI Codex and Anthropic Claude Code, with stable
  autosave names so ⌘-drag positions are remembered.
- Three ultra-compact styles — Minimal, Microbar (default) and Ring — drawn with AppKit/Core Graphics,
  with fixed-width tabular layout and light/dark support.
- Available or used percentage, 5h / 7d / both windows, sizes, thicknesses, spacing, `%` sign, colors and
  alert thresholds, with a live light/dark preview before applying.
- Codex integration through the official App Server (`account/rateLimits/read`), including saved reset
  credits, triggered in near real time by Codex session activity.
- Claude Code integration through an opt-in, reversible status line bridge (official `rate_limits`) and the
  Claude app's local usage history (read-only, unofficial).
- Adaptive refresh: events first, fallback polling (active/idle), minimum intervals, exponential backoff,
  Retry-After, cache at launch, refresh on wake.
- Details popover with larger bars, renewal times and countdowns, data age, source and state.
- Native notifications for low limits (20/10/5%), confirmed renewals and expiring saved resets, de-duplicated.
- Onboarding, settings (General, Appearance, Providers, Notifications, About), English and Brazilian Portuguese.
- Provider protocol and guide for community integrations.
- Unit, rendering and opt-in live tests; CI and release workflows.
