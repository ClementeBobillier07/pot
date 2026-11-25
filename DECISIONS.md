# Decisions

1. The prompt supersedes the document's Tauri/Rust proposal. Swift Package Manager organizes a portable PotCore and a macOS 14+ PotApp using system frameworks and SQLite.
2. No macOS host is available in this task. Install an official Swift Linux toolchain for genuine core compilation/tests; never represent these as an AppKit build.
3. Account APIs may report public identity, but legacy JSONL without identity belongs to a provider-local unattributed profile. Do not bind history to the account currently signed in.
4. System SQLite has no third-party package dependency. Sources/cursors/usage/plants persist in a private Application Support folder.
5. Landing is Next.js/TypeScript, local only, no analytics enabled and no public download button claiming an artifact exists.
6. Product source licensing remains owner-reserved pending the creator's choice; notices enumerate dependencies rather than assuming permission to publish under an open-source license.
7. App status commands are bounded subprocesses, not auth implementations. Public Codex account/read is an explicit action inside Connected agents, uses refreshToken:false and times out safely. Default detection uses local status. Vendor subprocess behavior is documented separately from Pot's lack of network code.
8. Calendar statistics use the Mac's current timezone. Energy uses anchored UTC day budgets, a 45-day journal and monotonic persisted high-water time, so timezone changes and repeated imports cannot replenish old budgets. Calibration is elapsed 72h, independent of calendar midnights.
9. Plant biology catches up in at most 45 days of hourly steps and ages older absences analytically. The reserve is capped and distant usage cannot produce instant unlimited maturity. Offline clock manipulation cannot be perfectly authenticated without a trusted time source; the garden favors conservative high-water behavior.
10. Logs without reliable identity stay unattributed. A detected public account can have a separate plant, without claiming it owns past local usage. Account email is optional; aliases and provider-local identity are supported.
11. The app refreshes through debounced recursive FSEvents and a 60-second fallback on a utility queue. Statistics/engine queries are restricted to 45 days rather than decoding lifetime history each minute.
12. Unsupported compressed Zstandard archives and ambiguous schemas report partial coverage and protect health. No heavy decompression/runtime dependency is silently introduced.
13. Two provider families share a persistent graph renderer. Straight vector branch segments align with the engine's attachment geometry; leaves and flowers interpolate individually. Rendering sleeps when idle and movement stops after a short pulse.
14. Installers use `Pot-<version>-macOS-<arch>.dmg`; local unsigned/ad-hoc development variants have `-local` and are excluded by the public counter. No release, analytics, website or schedule has been published/activated.
