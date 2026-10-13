#!/bin/sh
# Builds dist/AIquota.app (universal, ad-hoc signed), plus versioned ZIP and DMG downloads.
#
#   scripts/build-app.sh            # release build
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh   # sign with your certificate
#
# Without a Developer ID certificate the app is ad-hoc signed: it runs on the machine that built
# it, and other people must right-click → Open (or remove the quarantine flag) on first launch.
set -eu

cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/AIquotaCore/Engine/Fixtures.swift)
BUILD=${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
ARCHS=${ARCHS:-"arm64 x86_64"}
APP=dist/AIquota.app

ARCH_FLAGS=""
for arch in $ARCHS; do ARCH_FLAGS="$ARCH_FLAGS --arch $arch"; done

echo "Building AIquota $VERSION ($BUILD) for: $ARCHS"
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS
BIN_DIR=$(swift build -c release $ARCH_FLAGS --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"
cp "$BIN_DIR/AIquota" "$APP/Contents/MacOS/AIquota"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
SPARKLE_FRAMEWORK=$(find .build/artifacts -path '*/Sparkle.framework' -type d -print -quit)
if [ -z "$SPARKLE_FRAMEWORK" ]; then
  echo "Sparkle.framework was not found in the SwiftPM artifacts." >&2
  exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi

IDENTITY=${SIGN_IDENTITY:--}
if [ "$IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"

ZIP="dist/AIquota-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

DMG="dist/AIquota-$VERSION.dmg"
DMG_STAGE=$(mktemp -d)
trap 'rm -rf "$DMG_STAGE"' EXIT
cp -R "$APP" "$DMG_STAGE/AIquota.app"
ln -s /Applications "$DMG_STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "AIquota" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG"
rm -rf "$DMG_STAGE"
trap - EXIT

echo "Built $APP, $ZIP and $DMG"
