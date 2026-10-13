# Distribution

## What the build produces

`scripts/build-app.sh` creates:

- `dist/AIquota.app` — universal (arm64 + x86_64), `LSUIElement` (menu bar only), minimum macOS 14.0.
- `dist/AIquota-<version>.dmg` — a disk image with the app and an `/Applications` shortcut for drag-and-drop installation.
- `dist/AIquota-<version>.zip` — made with `ditto`, ready for a GitHub release or manual extraction.

## Signing today: ad-hoc

Without an Apple Developer ID certificate the app is **ad-hoc signed** (`codesign --sign -`). This means:

- It runs on the Mac that built it.
- On other Macs, Gatekeeper blocks the first launch of a downloaded copy. Users must **right-click → Open**
  (or System Settings → Privacy & Security → *Open Anyway*). Advanced users can run
  `xattr -dr com.apple.quarantine /Applications/AIquota.app`.
- Launch at login (`SMAppService`) and notifications work with ad-hoc signing, but macOS may ask the user to
  approve them again after each update because the signature changes.

## Signing and notarizing with a Developer ID

Requires a paid Apple Developer Program membership (not assumed by this project).

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build-app.sh
xcrun notarytool submit dist/AIquota-0.1.0.zip --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple dist/AIquota.app
ditto -c -k --keepParent dist/AIquota.app dist/AIquota-0.1.0.zip   # re-zip the stapled app
```

The build script enables the hardened runtime when an identity is provided. AIquota needs no special
entitlements: it is not sandboxed (it launches the Codex CLI and reads other tools' local files), which also
means it cannot be distributed through the Mac App Store.

## Release workflow

Pushing a `v*` tag runs `.github/workflows/release.yml`, which builds, ad-hoc signs, creates a ZIP and DMG,
and drafts a GitHub release with both downloads and their SHA-256 checksums. Signing/notarization secrets can be added later
(`MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PASSWORD`, `NOTARY_*`); the workflow notes where.
