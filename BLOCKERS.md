# Blockers

## macOS execution and native distribution — partially resolved 2026-11-25

Built, tested and launched on macOS 27.0.1 (Apple Silicon, Xcode / Swift 6.4.2): 39/39 tests, native app launch, real-data import, floating panel, universal ad-hoc `.app` and local DMG. Still open: interactive QA of hover controls, drag, click-through, focus, Spaces/full screen/Stage Manager, multiple displays, sleep/wake, launch at login from /Applications, VoiceOver and reduced motion (docs/MAC_QA.md).

## Real Claude Code compatibility — reconciled 2026-11-25

Claude Code local logs (164 files, 1.6 GB) reconcile exactly with an independent oracle (15,964 messages, 6,581,321,556 tokens). Claude Code deletes old session files under its own retention policy; Pot keeps already-imported aggregates.

## Signing/notarization

Production release requires Apple Developer ID Application certificate in the owner's Keychain and a notarytool credential profile. No release is authorized by this task.

## Real Codex usage — reconciled 2026-11-25

Codex desktop logs (107 rollouts, 734 MB, 97 % zstd) reconcile exactly with per-session final cumulative counters: 6,357 calls, 1,392,511,987 tokens, matching cached and output categories. `codex-auto-review` (guardian subagent) usage has no public rate and stays unpriced.

## Landing browser QA — static review done 2026-11-25

Production build served locally and rendered in headless Chrome at 1440 px, a true 390 px viewport and dark mode; layout is correct. Interactive hover/tab behavior and real-device Safari remain to check.

## Format coverage and attribution

Zstandard archives are supported (decision 15). New or ambiguous schemas are partial. Roots with more than10,000 files can leave files beyond the traversal cap unvisited; choose smaller subdirectories and keep coverage partial until a persistent traversal scheduler is implemented. Current sign-in does not identify history in shared log folders. A public account can have a separate plant while historical usage remains in a provider-local unattributed plant. Do not market exact multi-account historical reconciliation or universal desktop/extension compatibility before testing.

## Performance and release quality

Core benchmarks can run on Linux, but native idle CPU, resident memory, energy, window-open latency, monitor/Spaces behavior and clean-Mac install remain unmeasured. These are release gates, not verified claims.
