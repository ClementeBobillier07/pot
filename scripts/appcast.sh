#!/bin/bash
# Writes landing/public/appcast.xml for a notarized DMG that is (or will be) attached to the
# GitHub Release vVERSION. Signs locally with the Sparkle EdDSA key in the login keychain
# (account com.agentpots.pot). Never uploads: committing and deploying the appcast is the
# explicit operator step that delivers the update to every installed Pot.
set -euo pipefail
fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $# -eq 4 ]] || fail "Usage: scripts/appcast.sh VERSION BUILD /absolute/path/Pot-VERSION-macOS-universal.dmg NOTES.html"
VERSION="$1"; BUILD="$2"; DMG="$3"; NOTES="$4"
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
REPOSITORY="${POT_GITHUB_REPOSITORY:-ClementeBobillier07/pot}"
SIGN_UPDATE="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must be three numeric components."
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || fail "Build number must be a positive integer."
[[ -f "$DMG" && "$DMG" == *.dmg ]] || fail "DMG not found."
[[ -f "$NOTES" ]] || fail "Release notes (HTML fragment) not found."
[[ -x "$SIGN_UPDATE" ]] || fail "Run 'swift package resolve' first to fetch Sparkle's tools."
xcrun stapler validate "$DMG" >/dev/null || fail "The DMG must be notarized and stapled before it is offered as an update."

ATTRIBUTES=$("$SIGN_UPDATE" --account com.agentpots.pot "$DMG")
[[ "$ATTRIBUTES" == *'sparkle:edSignature="'*'length="'* ]] || fail "sign_update did not return a signature."
URL="https://github.com/$REPOSITORY/releases/download/v$VERSION/$(basename -- "$DMG")"
DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
OUT="$ROOT/landing/public/appcast.xml"
mkdir -p "$(dirname -- "$OUT")"
# Sparkle only needs the newest item; older versions update straight to it.
cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Pot</title>
    <link>https://agentpots.com/appcast.xml</link>
    <language>en</language>
    <item>
      <title>Pot $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
$(cat "$NOTES")
      ]]></description>
      <enclosure url="$URL" type="application/octet-stream" $ATTRIBUTES />
    </item>
  </channel>
</rss>
XML
xmllint --noout "$OUT"
printf 'Wrote %s for Pot %s (build %s)\n%s\n' "$OUT" "$VERSION" "$BUILD" "$URL"
