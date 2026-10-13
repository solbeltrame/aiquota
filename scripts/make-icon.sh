#!/bin/sh
# Rebuilds Resources/AppIcon.icns from scripts/make-icon.swift.
set -eu
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swift scripts/make-icon.swift "$TMP/icon-1024.png"
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$TMP/icon-1024.png" docs/images/icon.png
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns"
