# Pot

A little plant on your Mac. You code. It grows.

Native local-first macOS utility in development. **Built, tested and run on macOS 27 (Apple Silicon) with real Codex and Claude Code logs**, whose counts reconcile exactly with independent oracles. Interactive UI QA, beta and signed release are pending. See [BASELINE.md](BASELINE.md), [BLOCKERS.md](BLOCKERS.md), the [acceptance matrix](docs/ACCEPTANCE.md) and the [handoff prompt](docs/HANDOFF.md). No release or public deployment has been created.

Architecture: `Sources/PotCore` contains local integration, SQLite, statistics and procedural growth. `Sources/PotApp` provides SwiftUI/AppKit surfaces. `Sources/PotDev` contains explicit development-only simulations. `landing` is an independent local Next.js site. `scripts` prepares macOS distribution without publishing.

## Run on a Mac

Requirements: macOS 14+, Xcode 16+ with its command-line tools selected. End users will not need Node, Swift packages, ccusage or an additional runtime once a verified app is distributed.

From the repository folder:

```sh
swift test
swift run Pot
```

Or open `Package.swift` in Xcode and run the **Pot** scheme on **My Mac**. Pot is a menu-bar application: closing its window leaves it running. Click its leaf menu icon to reopen; right-click for show/hide, Settings and Quit. Onboarding detects local agents, lets you choose custom log folders, confirms safe account/local profiles and selects a display mode. Use the native agents to sign in, never Pot.

The preferred installed local app build is:

```sh
scripts/build-macos.sh --arch host --dmg
```

This runs release tests, produces a locally signed `.app` and development DMG under `artifacts/`, and verifies resources/architectures. It requires a Mac and has not been run here. Production/universal/signing/notarization commands are in [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md). Nothing publishes automatically.

## Local landing

```sh
cd landing
npm ci
npm run dev
```

Then visit the URL printed by Next. Production checks are `npm test`, `npm run typecheck` and `npm run build`; output is `landing/.next/`. Run `npm start` after building for a local production server. In the managed Codex environment, use `sites-preview start /workspace/pot/landing`; its relay is currently blocked. The landing is prepared for Vercel with `landing` as project root, but is not deployed. See [docs/LANDING.md](docs/LANDING.md).

## Architecture

- `PotCore`: Codex/Claude format adapters, bounded incremental ingestion, transactional SQLite, safe account attribution, seven calendar days, versioned exact-model Decimal reference prices and deterministic procedural organs.
- `PotApp`: SwiftUI/Charts main view and onboarding; AppKit status item, nonactivating transparent NSPanel, click/drag/hit testing; FSEvents plus a 60-second incremental fallback; ServiceManagement login item; local UserDefaults.
- `PotDev`: independent synthetic simulations/benchmark executable; not bundled in the app and does not open the production database.
- `landing`: Next.js/TypeScript site, original SVG illustrations and server-only cached public GitHub Releases counter; no analytics enabled.

Native code depends only on system Apple frameworks, Foundation and SQLite. Sources are not modified, credentials are not read directly, and transcripts/code are not retained. Data lives in `~/Library/Application Support/Pot/` and the `com.pot.mac` preferences domain. See [privacy](docs/PRIVACY.md).

## Development tools

```sh
swift run pot-dev --detect
swift run pot-dev simulate 365 42 codex
swift run pot-dev simulate 365 17 claude
swift run pot-dev benchmark-import 100
```

Simulation and benchmark output is clearly labeled synthetic. `--detect` is real local discovery but prints no emails, account IDs or paths. The engine's injectable dates test growth without waiting three days. Model identity is not inferred from price or provider labels; missing rates remain unavailable/partial.

On this Linux host, official Swift 6.0.3 was extracted under `/tmp/pot-swift/` and Debian SQLite development headers under `/tmp/pot-sqlite/` only for development. The reproducible test invocation here is:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/pot-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/pot-swift-cache \
/tmp/pot-swift/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swift test \
  --cache-path /tmp/pot-spm-cache \
  -Xcc -I/tmp/pot-sqlite/usr/include \
  -Xlinker -L/tmp/pot-sqlite/usr/lib/x86_64-linux-gnu
```

The Linux `Pot` executable is a platform guard and must never be distributed as the macOS app. `.build/debug/pot-dev` is a real development executable; native `.app`/DMG artifacts do not exist yet.

## Before publishing

Run the full [Mac QA checklist](docs/MAC_QA.md), reconcile actual Codex/Claude usage locally, measure idle resource usage, verify installation on a clean Mac, then sign/notarize with the owner's Apple Developer credentials. Request explicit authorization before publishing the release, deploying the landing or enabling analytics. Source licensing remains the owner's decision; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
