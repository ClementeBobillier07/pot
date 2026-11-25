#!/bin/bash
set -euo pipefail
fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $# -eq 1 || $# -eq 2 ]] || fail "Usage: scripts/verify-distribution.sh /absolute/path/Pot.app [--release]"
[[ $(uname -s) == Darwin ]] || fail "Native verification requires macOS."
APP="$1"
[[ -d "$APP/Contents/MacOS" ]] || fail "Application bundle not found."
if [[ $# -eq 2 && "$2" != --release ]]; then fail "Unknown verification option."; fi
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun lipo -info "$APP/Contents/MacOS/Pot"
otool -L "$APP/Contents/MacOS/Pot"
if [[ "${2:-}" == --release ]]; then
    SIGNATURE=$(codesign --display --verbose=4 "$APP" 2>&1)
    [[ "$SIGNATURE" == *"Authority=Developer ID Application:"* ]] || fail "Release requires a Developer ID signature."
    [[ "$SIGNATURE" == *"runtime"* ]] || fail "Release requires hardened runtime."
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
fi
printf 'Static bundle checks passed; launch and manual QA still required.\n'
