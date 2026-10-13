# Distribution

## What the build produces

`scripts/build-app.sh` creates:

- `dist/AIquota.app` — universal (arm64 + x86_64), `LSUIElement` (menu bar only), minimum macOS 14.0.
- `dist/AIquota-<version>.dmg` — a disk image with the app and an `/Applications` shortcut for drag-and-drop installation.
- `dist/AIquota-<version>.zip` — made with `ditto`, ready for a GitHub release or manual extraction.

The app embeds Sparkle and checks the appcast hosted as an asset on the latest GitHub release. The feed points to the signed ZIP; the DMG remains the easiest first install. Versions before 0.2.0 need one manual install from the DMG or ZIP because they do not contain Sparkle.

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

Pushing a `v*` tag runs `.github/workflows/release.yml`, which builds and signs the appcast update archive with Sparkle EdDSA, then publishes the ZIP, DMG, checksum file and `appcast.xml` to GitHub Releases. To sign in GitHub Actions, maintainers must add the matching EdDSA private key as the repository's `SPARKLE_PRIVATE_KEY` Actions secret; never commit it. Local maintainers can instead sign with the `aiquota` entry in their macOS login Keychain by running `scripts/create-appcast.sh` after the app bundle is built. The public key is embedded in `Resources/Info.plist`.

The app currently uses ad-hoc code signing because no Developer ID certificate is configured. Sparkle still verifies each update archive with the EdDSA key. A Developer ID certificate and notarization are recommended for a smoother first launch and stronger macOS signing continuity; these require the maintainer's Apple Developer credentials.
