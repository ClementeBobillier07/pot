#!/bin/bash
# Explicit operator action: contacts Apple's notarization service. Never publishes.
set -euo pipefail
fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $# -eq 2 ]] || fail "Usage: scripts/notarize.sh /absolute/path/Pot.app-or-installer.dmg EXISTING_KEYCHAIN_PROFILE"
[[ $(uname -s) == Darwin ]] || fail "Notarization requires a Mac with Xcode."
ARTIFACT="$1"
PROFILE="$2"
[[ -n "$PROFILE" ]] || fail "A previously configured notarytool Keychain profile is required."
if [[ "$ARTIFACT" == *.app && -d "$ARTIFACT/Contents/MacOS" ]]; then
    KIND=app
elif [[ "$ARTIFACT" == *.dmg && -f "$ARTIFACT" ]]; then
    KIND=dmg
else
    fail "Expected a signed application bundle or DMG."
fi
codesign --verify --strict --verbose=2 "$ARTIFACT"
SIGNATURE=$(codesign --display --verbose=4 "$ARTIFACT" 2>&1)
[[ "$SIGNATURE" == *"Authority=Developer ID Application:"* ]] || fail "Refusing to notarize a local/ad-hoc installer."
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/pot-notary.XXXXXX")
trap 'rm -rf -- "$STAGING"' EXIT
RESPONSE="$STAGING/response.plist"
SUBMISSION="$ARTIFACT"
if [[ "$KIND" == app ]]; then
    SUBMISSION="$STAGING/Pot.zip"
    ditto -c -k --keepParent "$ARTIFACT" "$SUBMISSION"
fi
xcrun notarytool submit "$SUBMISSION" --keychain-profile "$PROFILE" --wait --output-format plist > "$RESPONSE"
STATUS=$(/usr/libexec/PlistBuddy -c 'Print :status' "$RESPONSE")
[[ "$STATUS" == Accepted ]] || fail "Apple did not accept this notarization. Inspect notarytool log locally; no release has been published."
xcrun stapler staple "$ARTIFACT"
xcrun stapler validate "$ARTIFACT"
if [[ "$KIND" == app ]]; then
    spctl --assess --type execute --verbose=2 "$ARTIFACT"
else
    spctl --assess --type open --context context:primary-signature --verbose=2 "$ARTIFACT"
fi
printf 'Accepted and stapled: %s\n' "$ARTIFACT"
