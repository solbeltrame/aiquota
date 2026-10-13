#!/bin/bash
# Create the signed Sparkle appcast for a built release ZIP.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION=${1:?Usage: scripts/create-appcast.sh VERSION dist/AIquota-VERSION.zip}
ZIP=${2:?Usage: scripts/create-appcast.sh VERSION dist/AIquota-VERSION.zip}
SIGN_UPDATE=${SPARKLE_SIGN_UPDATE:-$(find .build/artifacts -path '*/bin/sign_update' -type f -print -quit)}

if [ -z "$SIGN_UPDATE" ] || [ ! -x "$SIGN_UPDATE" ]; then
  echo "Sparkle sign_update was not found. Resolve/build the Swift package first." >&2
  exit 1
fi
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  SIGNATURE_ATTRIBUTES=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$ZIP")
else
  # Local maintainers can sign from the aiquota entry in their macOS login Keychain.
  SIGNATURE_ATTRIBUTES=$("$SIGN_UPDATE" --account aiquota "$ZIP")
fi
SIGNATURE=$(printf '%s\n' "$SIGNATURE_ATTRIBUTES" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(printf '%s\n' "$SIGNATURE_ATTRIBUTES" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
if [ -z "$SIGNATURE" ] || [ -z "$LENGTH" ]; then
  echo "Sparkle did not return a valid EdDSA signature." >&2
  exit 1
fi

BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' dist/AIquota.app/Contents/Info.plist)
ZIP_NAME=$(basename "$ZIP")
PUB_DATE=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')
DOWNLOAD_URL="https://github.com/solbeltrame/aiquota/releases/download/v${VERSION}/${ZIP_NAME}"
RELEASE_NOTES_URL="https://github.com/solbeltrame/aiquota/releases/tag/v${VERSION}"

cat > dist/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>AIquota Updates</title>
    <item>
      <title>AIquota ${VERSION}</title>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>${RELEASE_NOTES_URL}</sparkle:releaseNotesLink>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure url="${DOWNLOAD_URL}" sparkle:edSignature="${SIGNATURE}" length="${LENGTH}" type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

echo "Created signed Sparkle appcast for AIquota ${VERSION} (${BUILD})."
