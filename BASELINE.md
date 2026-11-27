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

## macOS verification (2026-11-25)

Host: macOS 27.0.1, Apple Silicon, Xcode with Swift 6.4.2. Real local logs from Codex desktop and Claude Code; only aggregate counts were printed, nothing left the Mac.

| Check | Result |
|---|---|
| `swift build` (debug/release) | Pass; Sendable warnings removed |
| `swift test` | **44 passed**, 0 failures (real-format regressions, growth engine 2, periods, export, coverage) |
| Real Codex reconciliation | 6,357 calls / 1,392,511,987 tokens = independent oracle (final cumulative counters per session), categories match; 0 incomplete files |
| Real Claude reconciliation | 15,964 messages / 6,581,321,556 tokens = independent oracle (dedup by message id); 0 incomplete files |
| Replay / restart | 0 events added on re-scan |
| Real import performance (`pot-dev reconcile`, release) | 2.4 GB of logs in ~7 s, **77 MB peak RSS** (was ~3 GB before autorelease pools) |
| Native app launch | Onboarding window, status item, transparent floating plant, garden with real stats |
| Idle (debug build, window open, after import) | ~0.5 % CPU, 110–127 MB RSS |
| Universal `.app` + DMG (`scripts/build-macos.sh --arch universal --dmg`) | Built, ad-hoc signed, `codesign` valid, `hdiutil verify` valid, price catalog bundled, app launches |
| Landing | 7 tests, TypeScript and production build pass; desktop/390 px/dark render reviewed |

Defects found only with real data or a real Mac, now fixed: Codex `.zst` archives were skipped (97 % of history); real 10–17 MiB non-usage records marked files partial and froze plant health; Codex `cache_write_input_tokens` was ignored; Codex per-session account evidence ignored; every Claude event was marked partial because `inference_geo:"global"` was treated as non-standard; Claude 5.5 models were missing from the price catalog (Haiku 5.5 prompt tiers added); zero-token `<synthetic>` messages made estimates partial; a login identity created a permanently empty plant; calibration never adapted to heavy usage; an empty "Pot Settings" window opened at launch; first import advanced 64 MiB per minute; 3 GB peak memory while importing; "Chart unit" label wrapped.

Not yet verified: hover/drag/click-through interaction, Spaces/full screen, multiple displays, sleep/wake, launch at login from /Applications, VoiceOver, Developer ID signing and notarization, clean-Mac install.

### Added after verification (same day)

- Plant illustration redrawn in the landing's two families (Codex eucalyptus/sage pot, Claude slender leaves/terracotta), with visible health (droop, yellowing), seven flower stages and balanced branch placement. `Pot --render-plants DIR` writes synthetic renders (days 0–365, rest, floating light/dark) without touching user data.
- (Pause the garden was added and later removed, decision 25.) Periods Today / 7 days / 30 days / All, coverage ("Data since … · N calls · read …"), local JSON export without identifiers, onboarding/Settings corner choice, menu bar Presentation submenu.
- CI workflow (Swift on macOS, landing on Linux), beta kit (docs/BETA.md, issue template), release checklist (docs/RELEASE.md).

## First signed and notarized build (2026-11-26)

`artifacts/Pot-0.1.0-macOS-universal.dmg` (not committed; build output). Universal (arm64 + x86_64), bundle ID `com.agentpots.pot`, signed with Developer ID Application (team X7NK42H74M), hardened runtime, app and DMG notarized by Apple (status Accepted) and stapled. Verified as a quarantined download: `spctl` reports "accepted · source=Notarized Developer ID" for both the DMG and the app inside it. SHA-256 `1cf6f3963474a87ed124146fc43ca70819cb38b54271a29fc07460f797bf4ec3`. Published 2026-11-26 as GitHub Release v0.1.0.

**v0.1.1 (build 2, 2026-11-27):** same build and notarization path plus embedded Sparkle 2.10.1 (signed inside-out). `spctl` accepts the DMG and the app as "Notarized Developer ID"; both slices (arm64, x86_64) present in Pot and Sparkle; no local paths in the binary. SHA-256 `5e688726837ebc7b36041d9513241c04525863424e8484d16146e169bc597a4d`, identical when downloaded from the public release. The appcast's EdDSA signature verifies against the downloaded DMG. An end-to-end update (0.1.1 → 0.1.2 test build from a local signed feed) installed and relaunched without UI in about 6 s. Intel execution still untested on real Intel hardware.

**v0.1.2 (build 3, 2026-11-27):** same path; first release delivered through the appcast. `spctl` accepts the DMG and the app as "Notarized Developer ID"; arm64 and x86_64 present; no local paths in the binary; 48 tests pass. SHA-256 `1862fcfc8eb224af7c2c8663e1c2f21f2ccb60df34172dcd31ed8ceaba3eeaa6`, identical when downloaded from the public release, and the appcast's EdDSA signature verifies against that download.
