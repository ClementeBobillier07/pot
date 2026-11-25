# Local build and future distribution

The implementation workspace is Linux. The scripts below have **not** produced a native macOS application here. No installer, code signature, notarization, release, or clean installation is claimed as verified. macOS acceptance remains open until the app is built and its flows are tested on a Mac.

## Requirements

- macOS 14 or later and Xcode 16 or later (Swift 6 toolchain), with the command-line tools selected and the Xcode license accepted.
- A checkout of this repository. The app uses system SQLite and Apple frameworks; end users need no package manager or extra runtime.
- For production distribution only: Apple Developer Program membership, an installed **Developer ID Application** signing identity with its private key in the developer's Keychain, and a `notarytool` Keychain credential profile. Never commit certificates, passwords, API keys or Keychain exports.
- Choose a permanent reverse-DNS bundle ID before the first public release. `com.pot.mac` is a development default, not a claim of domain or trademark ownership.

## Build a local application

From the repository root on a Mac:

```bash
scripts/build-macos.sh --dmg
open artifacts/Pot-0.1.0-arm64-local.app
```

The default uses the host architecture, runs the Swift tests in release configuration, builds the `Pot` product, packages required Swift resource bundles, generates original vector-based icon artwork and applies an ad-hoc signature. On an Intel Mac the output includes `x86_64` instead of `arm64`. Copy the `.app` into `/Applications` before testing launch at login.

The ad-hoc signature supports local development; it is not a Developer ID signature, is not notarized, and must not be presented as a public-ready installer. Do not disable Gatekeeper to distribute a local build.

Public distribution DMG filenames are `Pot-<version>-macOS-<arm64|x86_64|universal>.dmg`, matching the landing counter's allowlist. Local installers have an additional `-local` suffix and are never eligible for the public counter.

Build folders under `artifacts/` and `.build/` are ignored by Git. The build script refuses to overwrite an existing named output. Use a different `--output` directory or deliberately remove your own previous build first.

```bash
scripts/build-macos.sh --arch arm64 --version 0.1.0 --build 1 --output /tmp/Pot-local-arm64 --dmg
scripts/build-macos.sh --arch x86_64 --output /tmp/Pot-local-intel --dmg
scripts/build-macos.sh --arch universal --output /tmp/Pot-local-universal --dmg
scripts/verify-distribution.sh /tmp/Pot-local-universal/Pot-0.1.0-universal-local.app
```

Universal packaging cross-compiles both slices and verifies them with `lipo`; it does **not** demonstrate successful execution on Intel. Run the app on actual target hardware before advertising that architecture. `MACOSX_DEPLOYMENT_TARGET=14.0` is applied explicitly.

The scripts use the active Xcode toolchain through `xcrun`. If the machine has several Xcode installations, select the desired one with Apple's standard Xcode settings before running the scripts. This is a developer task, not an end-user installation step.

## Prepare a signed build

Use the exact identity name already present in your Keychain. This variable is a public certificate identity, never private key material:

```bash
export POT_SIGN_IDENTITY='Developer ID Application: YOUR ORGANIZATION (TEAMID)'
scripts/build-macos.sh --arch arm64 --version 0.1.0 --build 1 --output /tmp/Pot-signed
```

The script signs the `.app` with hardened runtime and a secure timestamp. Adding `--dmg` also signs an installer, verifies both signatures, and creates a SHA-256 checksum. For the manual notarization sequence below, build the app alone first. No network entitlement, unsigned-code exception, login credential, or application telemetry is added. The direct-download build is intentionally outside the Mac App Store sandbox because it reads explicitly approved agent log folders.

## Notarize only when authorized

Notarization uploads the binary to Apple. The current task does not authorize publishing a release; merely preparing these commands does not execute them. The owner should first authorize this Apple submission and configure a `notarytool` profile locally using Apple's secure credential workflow.

```bash
scripts/notarize.sh /tmp/Pot-signed/Pot-0.1.0-arm64-signed.app YOUR_EXISTING_KEYCHAIN_PROFILE
scripts/make-dmg.sh /tmp/Pot-signed/Pot-0.1.0-arm64-signed.app /tmp/Pot-signed/Pot-0.1.0-macOS-arm64.dmg
scripts/notarize.sh /tmp/Pot-signed/Pot-0.1.0-macOS-arm64.dmg YOUR_EXISTING_KEYCHAIN_PROFILE
shasum -a 256 /tmp/Pot-signed/Pot-0.1.0-macOS-arm64.dmg > /tmp/Pot-signed/Pot-0.1.0-macOS-arm64.dmg.sha256
```

Alternatively, the build script can submit and staple only when both `POT_SIGN_IDENTITY` and `POT_NOTARY_PROFILE` are explicitly configured and `--dmg` is supplied. It rejects ad-hoc signatures for notarization and fails if Apple's returned status is not `Accepted`.

The `.app` receives a stapled ticket first, and is then copied into the signed DMG, which is submitted and stapled separately. This preserves offline verification of both the installed bundle and installer. If manually notarizing a previously built DMG, do not leave a stale installer after stapling the app; recreate and re-notarize it under a fresh output filename.

```bash
scripts/verify-distribution.sh /tmp/Pot-signed/Pot-0.1.0-arm64-signed.app --release
```

Do not modify any signed bundle after signing or any installer after checksumming. A checksum must be regenerated after stapling changes the DMG.

## Manual CI preparation

`.github/workflows/macos-validation.yml` is `workflow_dispatch` only. It has read-only repository permissions and no release step. It runs tests/builds on a GitHub macOS runner and retains an ad-hoc DMG artifact for seven days. It does not prove interactive UI behavior, clean installation, actual agent compatibility or both CPU architectures. Running the workflow requires pushing the reviewed code and explicitly starting it; neither has been done here.

## Before a public GitHub Release

1. Close every native QA item in `docs/MAC_QA.md` and record the macOS/Xcode/client versions and hardware.
2. Decide the source license, bundle ID, app ownership details and public compatibility claims.
3. Build from a reviewed commit/tag. Keep signing credentials outside source control. Sign, notarize, staple and validate the final installer.
4. Install from an actual downloaded quarantined DMG on a clean Mac. Test with networking unavailable as well as available. Verify that upgrading preserves the database and plants.
5. Record artifact names, architecture, minimum macOS, checksums and release notes. Upload/publish only after explicit authorization.
6. Configure the landing's real GitHub Releases download integration. Count eligible installer downloads, never users; verify the actual download path.

Future updates should preserve plant engine/database versions and add migration tests. The MVP does not silently self-update. A future updater would need its own integrity/signature design and user consent; Developer ID signing alone does not implement an updater.
