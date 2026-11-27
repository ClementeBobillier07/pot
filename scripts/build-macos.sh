#!/bin/bash
# Build only. This script never publishes or uploads a release.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ARCH="host"
VERSION="0.1.0"
BUILD_NUMBER="1"
OUTPUT="$ROOT/artifacts"
MAKE_DMG=false

usage() {
    cat <<'USAGE'
Usage: scripts/build-macos.sh [--arch host|arm64|x86_64|universal]
       [--version 0.1.0] [--build 1] [--output DIRECTORY] [--dmg]

Runs tests, builds a release .app and verifies its Mach-O architectures.
Default: host architecture, ad-hoc local signature, no upload.

Optional environment:
  POT_SIGN_IDENTITY  Exact Developer ID Application identity in your Keychain.
                     Enables hardened runtime and timestamped distribution signing.
  POT_NOTARY_PROFILE  Existing notarytool Keychain profile; requires signing and
                      --dmg. Uploads the signed DMG to Apple's notarization service,
                      only when explicitly configured by the operator.

Do not supply passwords, certificate data, or API keys as arguments.
USAGE
}

fail() { printf '%s\n' "$*" >&2; exit 1; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch|--version|--build|--output)
            [[ $# -ge 2 ]] || fail "Missing value for $1."
            case "$1" in
                --arch) ARCH="$2" ;;
                --version) VERSION="$2" ;;
                --build) BUILD_NUMBER="$2" ;;
                --output) OUTPUT="$2" ;;
            esac
            shift 2 ;;
        --dmg) MAKE_DMG=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

[[ $(uname -s) == Darwin ]] || fail "A Mac with Xcode 16+ is required. Linux cannot build AppKit or create a macOS application."
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must be three numeric components."
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail "Build number must be a positive integer."
case "$ARCH" in
    host) ARCH=$(uname -m) ;;
    arm64|x86_64|universal) ;;
    *) fail "Unsupported architecture: $ARCH" ;;
esac
if [[ -n "${POT_NOTARY_PROFILE:-}" ]]; then
    [[ -n "${POT_SIGN_IDENTITY:-}" ]] || fail "Notarization requires POT_SIGN_IDENTITY."
    [[ "$MAKE_DMG" == true ]] || fail "Notarization requires --dmg."
fi
if [[ -n "${POT_SIGN_IDENTITY:-}" && "$POT_SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
    fail "POT_SIGN_IDENTITY must be a Developer ID Application identity."
fi

xcode-select -p >/dev/null
xcrun --find swift >/dev/null
xcrun --find codesign >/dev/null
cd "$ROOT"
export MACOSX_DEPLOYMENT_TARGET=14.0
xcrun swift --version
# Test on the host architecture. Cross-compiled slices need an actual target Mac
# for execution; the universal build alone does not prove both runtime paths.
xcrun swift test --configuration release

if [[ "$ARCH" == universal ]]; then
    ARCHITECTURES=(arm64 x86_64)
else
    ARCHITECTURES=("$ARCH")
fi
BIN_PATHS=()
for TARGET_ARCH in "${ARCHITECTURES[@]}"; do
    SCRATCH="$ROOT/.build/distribution/$TARGET_ARCH"
    xcrun swift build --configuration release --product Pot --arch "$TARGET_ARCH" --scratch-path "$SCRATCH"
    BIN_PATH=$(xcrun swift build --configuration release --product Pot --arch "$TARGET_ARCH" --scratch-path "$SCRATCH" --show-bin-path)
    [[ -x "$BIN_PATH/Pot" ]] || fail "Missing executable for $TARGET_ARCH."
    BIN_PATHS+=("$BIN_PATH")
done

mkdir -p "$OUTPUT"
OUTPUT=$(cd -- "$OUTPUT" && pwd)
STAGING=$(mktemp -d "$OUTPUT/.pot-build.XXXXXX")
trap 'rm -rf -- "$STAGING"' EXIT
APP="$STAGING/Pot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "$ARCH" == universal ]]; then
    xcrun lipo -create "${BIN_PATHS[0]}/Pot" "${BIN_PATHS[1]}/Pot" -output "$APP/Contents/MacOS/Pot"
else
    cp "${BIN_PATHS[0]}/Pot" "$APP/Contents/MacOS/Pot"
fi
chmod 755 "$APP/Contents/MacOS/Pot"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
# Keep bundles in the conventional macOS resource directory. PriceCatalog checks
# this location explicitly before SwiftPM's build-path-oriented Bundle.module.
FOUND_CORE_RESOURCES=false
for RESOURCE_BUNDLE in "${BIN_PATHS[0]}"/*.bundle; do
    [[ -d "$RESOURCE_BUNDLE" ]] || continue
    ditto "$RESOURCE_BUNDLE" "$APP/Contents/Resources/$(basename -- "$RESOURCE_BUNDLE")"
    if [[ "$(basename -- "$RESOURCE_BUNDLE")" == Pot_PotCore.bundle ]]; then
        FOUND_CORE_RESOURCES=true
    fi
done
[[ "$FOUND_CORE_RESOURCES" == true ]] || fail "The PotCore resource bundle is missing from the Swift build."
find "$APP/Contents/Resources/Pot_PotCore.bundle" -name prices-v1.json -type f -print -quit | /usr/bin/grep -q . || fail "The bundled price catalog is missing."

# Sparkle (decision 31) ships as a universal framework; one copy serves every slice.
SPARKLE_SOURCE="${BIN_PATHS[0]}/Sparkle.framework"
[[ -d "$SPARKLE_SOURCE" ]] || fail "Sparkle.framework is missing from the Swift build."
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_SOURCE" "$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_LICENSE="$ROOT/.build/distribution/${ARCHITECTURES[0]}/artifacts/sparkle/Sparkle/LICENSE"
[[ -f "$SPARKLE_LICENSE" ]] || fail "Sparkle's license file is missing."
cp "$SPARKLE_LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
otool -l "$APP/Contents/MacOS/Pot" | /usr/bin/grep -q "@executable_path/../Frameworks" || fail "Pot is missing the Frameworks rpath."

xcrun swift "$ROOT/scripts/generate-icon.swift" "$STAGING/Pot.iconset"
xcrun iconutil --convert icns "$STAGING/Pot.iconset" --output "$APP/Contents/Resources/Pot.icns"
for TARGET_ARCH in "${ARCHITECTURES[@]}"; do
    xcrun lipo -verify_arch "$TARGET_ARCH" "$APP/Contents/MacOS/Pot"
done

if [[ -n "${POT_SIGN_IDENTITY:-}" ]]; then
    SIGN=(codesign --force --options runtime --timestamp --sign "$POT_SIGN_IDENTITY")
    VARIANT="signed"
else
    # A local ad-hoc signature is not a Developer ID release and cannot be notarized.
    SIGN=(codesign --force --sign -)
    VARIANT="local"
fi
# Inside-out, as Sparkle documents for Developer ID: helpers, then the framework, then Pot.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
DESTINATION="$OUTPUT/Pot-$VERSION-$ARCH-$VARIANT.app"
[[ ! -e "$DESTINATION" ]] || fail "Output already exists: $DESTINATION. Choose a new output directory."
ditto "$APP" "$DESTINATION"
printf 'Built application: %s\n' "$DESTINATION"

if [[ -n "${POT_NOTARY_PROFILE:-}" ]]; then
    # Staple the app before copying it into the installer, so the installed
    # bundle also carries its ticket for offline validation.
    "$ROOT/scripts/notarize.sh" "$DESTINATION" "$POT_NOTARY_PROFILE"
fi

if [[ "$MAKE_DMG" == true ]]; then
    if [[ "$VARIANT" == signed ]]; then
        DMG="$OUTPUT/Pot-$VERSION-macOS-$ARCH.dmg"
    else
        DMG="$OUTPUT/Pot-$VERSION-macOS-$ARCH-local.dmg"
    fi
    "$ROOT/scripts/make-dmg.sh" "$DESTINATION" "$DMG"
    if [[ -n "${POT_NOTARY_PROFILE:-}" ]]; then
        "$ROOT/scripts/notarize.sh" "$DMG" "$POT_NOTARY_PROFILE"
    fi
    shasum -a 256 "$DMG" > "$DMG.sha256"
    printf 'Installer: %s\n' "$DMG"
fi
