# Blockers

## macOS execution and native distribution

This workspace is Linux. Xcode, macOS SDK, AppKit runtime, signing and hdiutil cannot run here. A Mac with Xcode is necessary to compile/run/test the actual native UI and generate the .app/DMG. Until that evidence exists, the requested MVP acceptance gate remains open.

## Real Claude Code compatibility

Claude Code is not installed in this environment. Its adapter can be tested with synthetic fixtures and documented formats, but real client validation requires a Mac with Claude Code and local logs. Never request credentials or full transcripts.

## Signing/notarization

Production release requires Apple Developer ID Application certificate in the owner's Keychain and a notarytool credential profile. No release is authorized by this task.

## Real Codex usage

Codex CLI is installed/authenticated here, but CODEX_HOME has no session JSONL. Neither provider has been reconciled with real usage. An optional official account/read probe timed out on this alpha runtime; no account email or stable account ID was established. Synthetic fixtures are explicit test evidence only.

## Landing browser QA

Managed Sites preview failed with `relay could not open browser port 4173: timed out waiting for relay readiness`; status is stopped. The prescribed troubleshooting provides no application repair for this infrastructure failure. The landing passes production compilation, TypeScript and tests, but responsive/dark/interactive visual behavior remains unverified in a browser.

## Format coverage and attribution

Zstandard archives are detected but unsupported. New or ambiguous schemas are partial. Roots with more than10,000 files can leave files beyond the traversal cap unvisited; choose smaller subdirectories and keep coverage partial until a persistent traversal scheduler is implemented. Current sign-in does not identify history in shared log folders. A public account can have a separate plant while historical usage remains in a provider-local unattributed plant. Do not market exact multi-account historical reconciliation or universal desktop/extension compatibility before testing.

## Performance and release quality

Core benchmarks can run on Linux, but native idle CPU, resident memory, energy, window-open latency, monitor/Spaces behavior and clean-Mac install remain unmeasured. These are release gates, not verified claims.
