# AIquota help

## Reading the indicators

`83%⁵ʰ 42%⁷ᵈ` means 83% of the 5-hour limit and 42% of the weekly limit are still **available**
(you can switch to **used** in Settings → General). The thin bar or ring shows the same number.

- Neutral bar: more than 20% available.
- Muted amber: 20% available or less. Muted red: below 10%. (Thresholds and colors are configurable.)
- Dimmed number: the data is more than 3 hours old.
- `–`: no reliable data yet, or the window has renewed and new data has not arrived. AIquota never guesses.

## Moving the indicators

**Hold ⌘ Command and drag an AIquota indicator to place it next to your AI app.**

Release the mouse where you want it. macOS remembers the position for each indicator when possible.
AIquota cannot place indicators automatically — menu bar order is controlled by macOS — and it never moves
or modifies other apps' icons. If an indicator disappears, the menu bar may be full: remove other items or,
on Macs with a notch, use fewer items. On recent macOS versions you can also check System Settings →
Menu Bar to make sure AIquota is allowed.

## "Waiting for data" / "–" for Claude

AIquota reads Claude data locally:

1. Keep the Claude app open — it records your plan usage about every 5 minutes. Or:
2. Enable the **status line integration** (Settings → Providers → Claude Code → Enable…). After your next
   Claude Code response in the terminal, AIquota gets the exact numbers and reset times.

Rate limits are only reported for Claude.ai Pro and Max plans.

## Codex shows "Not installed" or "Not signed in"

AIquota looks for the `codex` command on your PATH, in common install folders and inside ChatGPT for Mac.
Set a custom path in Settings → Providers if needed. Subscription limits require signing in to Codex with
ChatGPT (`codex login`); API-key sign-ins have no 5-hour/weekly limits.

## Removing the Claude status line integration

Settings → Providers → Claude Code → **Remove**. Your previous status line is restored exactly. A full
backup of `settings.json` from installation time is kept in
`~/Library/Application Support/AIquota/claude/`.

## Uninstalling AIquota

1. Remove the status line integration (above), if enabled.
2. Quit AIquota (popover → power button) and delete `/Applications/AIquota.app`.
3. Optionally delete `~/Library/Application Support/AIquota` and run `defaults delete app.aiquota.AIquota`.
