# Security Policy

## Supported versions

Security fixes are made for the latest release.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Use GitHub's
[private vulnerability reporting](../../security/advisories/new) for this repository.
Include steps to reproduce, the affected version and your macOS version. We aim to reply within 7 days.

## What AIquota touches

AIquota is designed to need as little trust as possible. Reviewers should check that changes keep these properties:

| Area | Behaviour |
|---|---|
| Network | AIquota makes no network requests of its own. It launches `codex app-server`, which talks to OpenAI as Codex itself does. |
| Credentials | Never read, copied, stored or logged. AIquota does not open `~/.codex/auth.json`, the Keychain, cookies, or any cached response other than the Claude usage one. |
| Files read | `~/.codex/sessions/**/rollout-*.jsonl` (tail only, for `rate_limits`), `~/Library/Application Support/Claude/plan-usage-history.json`, the Claude app's HTTP cache folder (`Cache/Cache_Data`: only the key of each small entry is read; only `…/api/organizations/<org>/usage` entries are decoded, and only their usage windows are kept), AIquota's own support folder. |
| Files written | `~/Library/Application Support/AIquota/` (cache, status line bridge). `~/.claude/settings.json` **only** after the user confirms the status line integration; a full backup is made first and removal restores the previous `statusLine`. |
| Processes | `codex app-server` (on demand, stdio). The status line bridge script runs `/usr/bin/plutil` and the user's previous status line command. |
| Logs | Unified logging (`app.aiquota`). No tokens, account identifiers or raw payloads. |

The app is not sandboxed because it must launch the Codex CLI and read other tools' local files;
this is why it is distributed outside the Mac App Store.
