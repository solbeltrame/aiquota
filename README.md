<p align="center">
  <img src="docs/images/icon.png" alt="AIquota app icon" width="96">
</p>

<h1 align="center">AIquota</h1>

<p align="center"><strong>Your AI limits. Always visible. Zero clicks.</strong></p>

<p align="center">
  <a href="https://github.com/solbeltrame/aiquota/releases/latest"><strong>⬇️ Download for macOS</strong></a>
  &nbsp;·&nbsp;
  <a href="docs/README.pt-BR.md">Português (Brasil)</a>
  &nbsp;·&nbsp;
  <a href="CONTRIBUTING.md">Contribute</a>
</p>

<p align="center">
  <a href="https://github.com/solbeltrame/aiquota/blob/main/LICENSE"><img src="https://img.shields.io/github/license/solbeltrame/aiquota" alt="MIT License"></a>
  <a href="https://github.com/solbeltrame/aiquota/releases/latest"><img src="https://img.shields.io/github/v/release/solbeltrame/aiquota" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-555" alt="macOS 14 or later">
</p>

AIquota is a small, free, open-source macOS app that keeps your Codex and Claude Code usage limits in the menu bar. No dashboards, accounts, or extra clicks — just a quick glance while you work.

<p align="center">
  <img src="docs/images/menubar-light.png" alt="AIquota in a light menu bar" width="420"><br>
  <img src="docs/images/menubar-dark.png" alt="AIquota in a dark menu bar" width="420"><br>
  <sub>Sample values shown. Supports light and dark menu bars.</sub>
</p>

## Download and use

Choose either download from the [latest release](https://github.com/solbeltrame/aiquota/releases/latest):

- **DMG (easy install):** open it and drag `AIquota.app` onto the **Applications** shortcut.
- **ZIP:** unzip it and move `AIquota.app` to your Applications folder.

On first launch, right-click the app and choose **Open**. AIquota is not notarized yet, so macOS asks you to confirm.

Open **AIquota → Settings → Updates** to check your version or choose automatic updates. To move from the original 0.1.0 release to in-app updates, install this version once from the download above; 0.1.0 did not include an updater.

Requires macOS 14 Sonoma or later, on Apple silicon or Intel. You can use the app as-is — no coding or setup account needed. If it helps you, starring the repo or sharing it is a lovely way to support the project 💛

## What it does

- Shows your remaining 5-hour and weekly limits for Codex and Claude Code right in the menu bar.
- Offers three compact styles: Minimal, Microbar, and Ring.
- Supports available or used percentages, light and dark appearance, and optional alerts.
- Privacy-first: no AIquota servers, analytics, or telemetry. AIquota reads local app data and asks Codex's App Server for usage limits. Update checks contact GitHub Releases; no usage data is sent.
- Uses no tokens to check your limits.
- Keeps each indicator visible while its AI app is running, even after you close its window; quitting the AI app hides its indicator.
- Includes signed in-app updates, with automatic checks enabled by default and automatic downloads/installation as an option.

Hold ⌘ Command and drag an indicator to place it near its AI app. macOS controls menu bar placement, so automatic positioning is not available.

## Everyone is welcome here

AIquota is open source under the [MIT License](LICENSE). **Everyone is welcome to use it, share it, study it, and make it better.** You don't need to write code to help:

- Use the app and tell us what worked (or what got weird) by [opening an issue](https://github.com/solbeltrame/aiquota/issues/new/choose).
- Share AIquota with someone who might find it useful.
- Improve the code, documentation, translations, or add support for another AI tool.

First contribution? You're in the right place. Check [good first issues](https://github.com/solbeltrame/aiquota/labels/good%20first%20issue), read [CONTRIBUTING.md](CONTRIBUTING.md), or just say hi in an issue. We also have a [Code of Conduct](CODE_OF_CONDUCT.md).

## Build it yourself

Want to change the app or help with development? You'll need macOS 14+ and Xcode 16+.

```bash
git clone https://github.com/solbeltrame/aiquota.git
cd aiquota
swift build
swift test
```

For a standalone app bundle, run `scripts/build-app.sh`. More details about the integrations, privacy, settings, and development are in the [`docs/`](docs/) folder.

## Credits

AIquota was created by **Sol Beltrame** and is open to contributions from everyone. Claude's local usage cache is decoded with [Zstandard](https://github.com/facebook/zstd) (BSD), and in-app updates are powered by [Sparkle](https://sparkle-project.org/) (MIT).

AIquota is not affiliated with, endorsed by, or sponsored by OpenAI or Anthropic. Codex, ChatGPT, Claude, and Claude Code are trademarks of their respective owners.

## License

[MIT](LICENSE) © 2026 Sol Beltrame and AIquota contributors.
