# Implementation plan

Status (2026-11-25, macOS): native build, tests, real-data reconciliation, app launch and local universal DMG **verified on a Mac**; interactive UI QA, beta and signed release remain. See BASELINE.md "macOS verification".

Original status: available implementation/QA handed off, native acceptance **blocked**. Discovery ran on Debian Linux x86_64, 2026-11-25. The repository was empty. Native acceptance remains blocked by the absence of macOS/Xcode; implementation is not proof of native behavior.

| Phase | State | Exit evidence |
|---|---|---|
| 0 Discovery | Complete with platform limits | Master read completely; Codex 0.172.0-alpha.2 installed/authenticated; no session logs, Xcode or Claude |
| 1 Integrations | Fixture QA passes; real reconciliation open | Independent Codex/Claude adapters; bounded status detection; custom source directories; no real usage available |
| 2 Persistence/statistics | Portable QA passes | SQLite transaction/cursor dedup, seven-day timezone aggregates, exact reference prices and partial estimates |
| 3 Plant engine | Portable QA passes | Persistent genetic organs, 72h calibration, renewable caps, year-long tests |
| 4 Visual system | Source implemented; Mac review pending | Two Canvas vector families, growth/flower interpolation, reduced motion, activity pulses |
| 5 Main app | Source implemented; Mac build/run pending | English onboarding, account/local profiles, alias, stats, settings, NSStatusItem |
| 6 Floating plant | Source implemented; Mac runtime pending | Transparent nonactivating NSPanel, hover-only controls, silhouette hit testing, drag threshold, display policy tests |
| 7 Landing | Build/test verified; visual QA blocked | Next.js local-only, own SVGs, real releases API, no eligible public installer; preview relay failed |
| 8 QA | Available checks complete; native gate blocked | 34 Swift debug/release tests + 7 landing tests, TypeScript/build; native source syntax only, not SDK type checking |
| 9 Distribution | Scripts prepared/tested; artifacts blocked | Local/universal .app + DMG/sign/notarize scripts; require macOS; no release created |
| 10 Handoff | Source/evidence handoff complete; product acceptance open | README, baseline, decisions, blockers, acceptance matrix and Mac checklist; no deployment/publication |

## Remaining acceptance gates

- Compile and launch Pot on a Mac with Xcode, fix any SDK errors and run docs/MAC_QA.md.
- Reconcile both adapters against actual local usage from installed Codex and Claude Code; no raw logs need to leave the Mac.
- Browser review of landing once the managed preview relay works, or in the owner's local environment.
- Measure native idle CPU/RSS/energy and app-open latency on named hardware.
- Generate/verify local app and DMG; production signing/notarization requires owner's Apple credentials.

## Execution plan after macOS verification (2026-11-25)

| Step | State |
|---|---|
| 1 Push branch / PR | Done: branch `ClementeBobillier07/pot-macos-app-plan`, PR against `main` |
| 2 Interactive Mac QA (hover, drag, click-through, focus, Spaces, displays, sleep, login items, VoiceOver) | **Owner** — follow docs/MAC_QA.md (no screen-control tool was available to the agent) |
| 3a Plant illustration matching landing families | Implemented; offscreen render harness `Pot --render-plants DIR` |
| 3b Onboarding corner choice (master doc §3/§10) | Implemented (onboarding + Settings) |
| 3c Pause the garden (§9) | Implemented (engine, Settings, menu bar) with tests |
| 3d Periods today/7d/30d/all + coverage since/last read (§5, §10) | Implemented |
| 3e Local export of daily totals and plant state (§12) | Implemented with privacy test |
| 3f Menu bar: presentation + pause (§10) | Implemented |
| 3g Energy reference at median vs higher percentile; `codex-auto-review` price | Deferred to beta evidence (docs/BETA.md) |
| 4 Beta kit | docs/BETA.md, issue template, `pot-dev reconcile` |
| 5 CI | `.github/workflows/ci.yml` (Swift on macOS, landing on Linux); manual DMG workflow unchanged |
| 6 Launch | docs/RELEASE.md — needs owner's Developer ID, notarytool profile, license/domain/bundle ID decisions, and explicit publish authorization |
