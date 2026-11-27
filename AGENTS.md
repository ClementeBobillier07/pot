# Pot — project rules

- The current user specification overrides the master product document v1.1. Native Swift/SwiftUI/AppKit, macOS 14+, SQLite; no Electron/Tauri.
- UI and landing copy are English. Engineering handoff may be Spanish.
- Work autonomously; independent phases may run in parallel. Keep PLAN.md, DECISIONS.md, BASELINE.md and BLOCKERS.md honest and current.
- Never publish, deploy, push a release, enable external analytics, or request login secrets without explicit authorization.
- Never read auth.json, credential stores, API keys, cookies, prompts, responses or source code for persistence. JSONL parsers transiently encounter transcripts but retain only allowlisted metrics.
- Historical usage without per-event account evidence stays in an unattributed local profile. Current login identity does not prove ownership of historical events.
- No fictional live data, fake downloads or invented prices. Synthetic fixtures/simulations belong only in tests or the development executable.
- Transactions must commit log cursors and events together. Deduplicate across restarts and copied logs. Treat malformed/unknown data as incomplete, not inactivity.
- Pure PotCore must compile on macOS and Linux. AppKit/SwiftUI belong only to PotApp. The production app's only network client is Sparkle's signed update check (decision 31): it sends no usage, accounts or system profile, and Settings can turn it off.
- Validate core with `swift test`; landing with its tests, TypeScript and production build; macOS UI with Xcode/macOS. Do not claim macOS verification from Linux.
- Use system SQLite only. Avoid additional runtime dependencies in the macOS product.
- Respect reduced motion, keep organ counts bounded, separate historical maturity from recoverable health, never reward repeated imports or backwards clock changes.
- Do not commit attachments, real logs, generated builds, private identities, or tools downloaded to /tmp.
