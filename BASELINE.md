# Verified baseline

Verified on 2026-11-25. The repository began empty. The supplied master DOCX was read completely before implementation; the latest user prompt overrides its Tauri/Rust proposal. The attachment and real vendor data are not committed.

## Evidence

| Check | Result |
|---|---|
| Native SDK build / launch | **Not verified**: no macOS or Xcode on this Linux host |
| Swift portable debug tests | 34 passed, 0 failures; 24 integration/statistics/pricing, 8 engine, 2 visibility |
| Swift portable release tests | 34 passed, 0 failures in 0.938s; release build 18.05s |
| Development release executable | Built and executed; real sanitized discovery and synthetic simulation/import benchmark |
| Native source syntax | All five files parse for arm64 and x86_64 macOS14 targets; **not SDK type checking** |
| Installed tools | Codex CLI0.172.0-alpha.2 authenticated using ChatGPT; Claude absent |
| Real usage integration | **Not verified**: no session JSONL exists in this runtime's Codex roots; Claude absent |
| Landing tests | 7 passed, 0 failures |
| Landing TypeScript | Pass |
| Landing production build | Pass; Next homepage prerendered and release API dynamic |
| Dependency audit | 0 reported production vulnerabilities at check time; no claim beyond that snapshot |
| Public release metadata | Actual GitHub retrieval yielded no eligible public installer; no count is displayed |
| Landing browser QA | **Blocked**: managed preview relay timeout |
| Distribution scripts | Shell syntax, plist invariants, icon source syntax and Linux refusal guards passed; not executed on Mac |
| Publication | No release, website, analytics, scheduled task or external deployment created |

## Implemented source

Codex legacy cumulative/current response records and Claude assistant usage adapters; bounded incremental file reads; SQLite atomic cursor/metrics commits; cross-restart/copied-log deduplication; partial-line/oversized-line/rotation/fork safeguards; explicit identity or provider-local unattributed profiles; public status detection and optional bounded account lookup; custom source picker; seven-day timezone statistics; exact-model versioned Decimal price references and honest partial/unavailable estimates.

Persistent seeded organ graphs, individual leaf sizes, branches, seven flower stages, 72h calibration, rolling personal reference, diminishing daily energy/reserve caps, recoverable health, data-gap protection, clock/import guards and bounded renewal are tested. Separate development simulations never ship in the native app.

Native UI source includes English onboarding, profile/plant navigation, tokens/USD chart selection, reference-price date, settings/aliases, launch at login, appearance, confirmed data erasure and status item. Floating source includes clear nonactivating NSPanel, one selected plant, hover controls, silhouette pass-through, click/drag threshold, position/size persistence, monitor clamping, three display modes and reduced motion. Native behavior remains pending Mac execution.

Independent Next.js landing contains the ten requested sections and original SVG provider families. Its previews are illustrative; release availability and download counts are never fabricated.

## Artifacts available here

- `/workspace/pot/.build/release/pot-dev`: optimized **Linux development executable**, not a Mac app.
- `/workspace/pot/.build/debug/pot-dev`: debug development executable.
- `/workspace/pot/landing/.next/`: optimized Next build.
- No `.app`, DMG, signed installer or notarized artifact exists. The Linux `Pot` executable is a platform guard only.

Measured synthetic workload results are in [docs/PERFORMANCE.md](docs/PERFORMANCE.md). Remaining acceptance gates are tracked in [BLOCKERS.md](BLOCKERS.md), [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) and [docs/MAC_QA.md](docs/MAC_QA.md).
