#!/bin/bash
set -euo pipefail
fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $# -eq 2 ]] || fail "Usage: scripts/make-dmg.sh /absolute/path/Pot.app /absolute/path/Pot-version-arch-local.dmg"
[[ $(uname -s) == Darwin ]] || fail "hdiutil requires macOS."
APP="$1"
DMG="$2"
[[ -d "$APP/Contents/MacOS" ]] || fail "Application bundle not found."
[[ "$DMG" == *.dmg ]] || fail "Output must have a .dmg extension."
[[ ! -e "$DMG" ]] || fail "Output already exists."
mkdir -p "$(dirname -- "$DMG")"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/pot-dmg.XXXXXX")
trap 'rm -rf -- "$STAGING"' EXIT
ditto "$APP" "$STAGING/Pot.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Pot -srcfolder "$STAGING" -format UDZO -fs HFS+ "$DMG"
hdiutil verify "$DMG"
if [[ -n "${POT_SIGN_IDENTITY:-}" ]]; then
    [[ "$POT_SIGN_IDENTITY" == "Developer ID Application:"* ]] || fail "Expected a Developer ID Application identity."
    codesign --force --timestamp --sign "$POT_SIGN_IDENTITY" "$DMG"
    codesign --verify --strict --verbose=2 "$DMG"
fi
