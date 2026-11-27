# Release checklist (v0.1.0)

Nothing here runs automatically. Each step that contacts Apple or GitHub is an explicit operator action.

## 0. Decisions to close first (owner)

- [x] Bundle ID `com.agentpots.pot`; landing domain agentpots.com (owner to purchase).
- [x] D06 source license: MIT (`LICENSE`, decision 30); notices list zstd BSD and SQLite public domain.
- [ ] D05 minimum macOS (code targets macOS 14) and Intel support (universal builds; needs a run on an Intel Mac).

## Status (2026-11-26)

- [x] Developer ID Application certificate (team X7NK42H74M) in the owner's login keychain.
- [x] Notary profile `pot-notary` (App Store Connect API key; the .p8 stays in `~/.pot-signing`, never in the repo).
- [x] v0.1.0 universal DMG built, signed, notarized, stapled and verified (see BASELINE.md).
- [x] Owner authorized; `v0.1.0` tagged and the GitHub Release published with the DMG and its `.sha256`.
- [x] agentpots.com (GoDaddy DNS → Vercel Hobby) serves the landing over HTTPS; www redirects 308 to the apex.
- [x] 2026-11-27: v0.1.1 (build 2) published with Sparkle; `agentpots.com/appcast.xml` offers it. Sparkle key backed up by the owner outside the repo.

## 1. Apple credentials (once, owner)

Checked on the owner's Mac (2026-11-26): the Keychain has an **Apple Development** certificate only. That one signs builds for your own devices; distribution outside the App Store needs a **Developer ID Application** certificate.

1. Apple Developer Program membership (done).
2. Create a **Developer ID Application** certificate: Xcode → Settings → Accounts → select the team → Manage Certificates… → **+** → *Developer ID Application*. Only the team's Account Holder can create it. Keep the private key in your login Keychain and export an encrypted .p12 backup somewhere safe. Check with `security find-identity -v -p codesigning` (it should list "Developer ID Application: …").
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

## 3b. Every later version: automatic update (decision 31)

Since v0.1.1, installed copies update themselves from `https://agentpots.com/appcast.xml`.

1. Raise both numbers: `--version 0.1.2 --build 3`. Sparkle compares the build number (`CFBundleVersion`); it must always grow.
2. Build, sign, notarize and staple as in section 2, then publish the GitHub Release `vX.Y.Z` with the DMG (section 3).
3. Write the release notes as a short HTML fragment (`<ul><li>…</li></ul>`), then sign the update and write the appcast:
   ```bash
   scripts/appcast.sh 0.1.2 3 /tmp/pot-0.1.2/Pot-0.1.2-macOS-universal.dmg notes.html
   ```
   It signs with the Sparkle key in the login keychain (account `com.agentpots.pot`) and writes `landing/public/appcast.xml`. Back up that key once: `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.agentpots.pot -x pot-sparkle-key.txt`, then store the file somewhere safe outside the repo. Without it, no further update can reach installed copies.
4. Only after the GitHub asset URL works: commit `landing/public/appcast.xml` and merge to `main`. Vercel deploys it, and every Pot with automatic updates installs the version within about a day.

## 4. After release

- Watch issues for format changes in Codex / Claude Code (adapters mark coverage partial rather than miscount).
- Refresh `Sources/PotCore/Resources/prices-v1.json` from the official pricing pages for each release; bump `version`.
