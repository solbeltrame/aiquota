#!/bin/sh
# Builds dist/AIquota.app (universal, ad-hoc signed) and dist/AIquota-<version>.zip.
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
cp "$BIN_DIR/AIquota" "$APP/Contents/MacOS/AIquota"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi

IDENTITY=${SIGN_IDENTITY:--}
if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

ZIP="dist/AIquota-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $APP and $ZIP"
