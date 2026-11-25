# Release checklist (v0.1.0)

Nothing here runs automatically. Each step that contacts Apple or GitHub is an explicit operator action.

## 0. Decisions to close first (owner)

- [ ] D06 brand/domain: final bundle ID (today `com.pot.mac`, a development default) and landing domain.
- [ ] D06 license for the source (today "owner-reserved"; notices already list zstd BSD, SQLite PD).
- [ ] D05 minimum macOS (code targets macOS 14) and Intel support (universal builds; needs a run on an Intel Mac).

## 1. Apple credentials (once, owner)

1. Enroll in the Apple Developer Program (USD 99/year).
2. Create a **Developer ID Application** certificate in Xcode → Settings → Accounts → Manage Certificates. Keep the private key in your login Keychain; export an encrypted backup somewhere safe.
3. Create a notarytool profile (prompts for an app-specific password; nothing is stored in the repo):
   ```bash
   xcrun notarytool store-credentials pot-notary --apple-id YOU@EXAMPLE.COM --team-id TEAMID
   ```

## 2. Build, sign, notarize (Mac)

```bash
git switch main && git pull && swift test
export POT_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export POT_NOTARY_PROFILE=pot-notary
scripts/build-macos.sh --arch universal --version 0.1.0 --build 1 --output /tmp/pot-0.1.0 --dmg
scripts/verify-distribution.sh /tmp/pot-0.1.0/Pot-0.1.0-universal.app
```

Then on a **different, clean Mac** (or a fresh user account): download the DMG through a browser (so it is quarantined), open it, drag to Applications, launch, finish onboarding, enable launch at login, restart the Mac, confirm Pot comes back. Run docs/MAC_QA.md "Install and startup".

## 3. Publish (owner authorizes each)

1. Tag: `git tag -s v0.1.0 -m "Pot 0.1.0" && git push origin v0.1.0`.
2. GitHub Release from the tag: attach `Pot-0.1.0-macOS-universal.dmg` and its `.sha256`; paste notes (what is supported, what is not: Codex desktop/CLI and Claude Code local logs on this Mac; estimates are not bills; no telemetry).
   ```bash
   gh release create v0.1.0 /tmp/pot-0.1.0/Pot-0.1.0-macOS-universal.dmg /tmp/pot-0.1.0/Pot-0.1.0-macOS-universal.dmg.sha256 --title "Pot 0.1.0" --notes-file RELEASE_NOTES.md
   ```
3. Landing: set `POT_GITHUB_REPOSITORY=ClementeBobillier07/pot` (see `landing/.env.example`), deploy (Vercel or any Node host), verify the download button resolves to the release asset and the counter shows only eligible DMG downloads.
4. Smoke test the public download link from a clean Mac once more.

## 4. After release

- Watch issues for format changes in Codex / Claude Code (adapters mark coverage partial rather than miscount).
- Refresh `Sources/PotCore/Resources/prices-v1.json` from the official pricing pages for each release; bump `version`.
