# Integrations, coverage and pricing

## Evidence and compatibility

Inspected on 2026-11-25: Debian 13 x86_64, Codex CLI **0.172.0-alpha.2**. `codex login status` returned authenticated using ChatGPT. `CODEX_HOME` pointed to `/home/agent/.codex`; no session JSONL was available there. Claude Code was not installed. Therefore neither parser has been reconciled against real usage in this workspace. Passing synthetic tests does **not** establish desktop/extension/CLI version-wide compatibility.

The installed Codex app-server JSON Schema was generated into a temporary directory for inspection. `account/read` supports `refreshToken:false`; the account union can expose email but this installed schema does not expose a stable ChatGPT account ID. A bounded probe produced no account response before timeout. No email or authentication material was printed or retained. SourceDiscovery leaves authentication/identity unknown when a command fails or times out.

Sources consulted directly (current official pages, 2026-11-25):

- [Codex App Server](https://developers.openai.com/codex/app-server/): initialize/initialized and account/read, refreshToken false.
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference): `claude auth status` returns JSON and exit status.
- [OpenAI pricing](https://developers.openai.com/api/docs/pricing): exact GPT-6/6.1/6.2, GPT-5.6, GPT-5.4/5.5 and GPT-5.2 standard API input/cache/output rates.
- [Claude pricing](https://platform.claude.com/docs/en/about-claude/pricing): Sonnet/Opus 4.6 and Sonnet/Opus/Haiku 4.5 base, output, cache read and 5-minute/1-hour cache creation rates.
- [ccusage Codex source](https://ccusage.com/guide/codex/) and [Claude source](https://ccusage.com/guide/claude/) were supplied as document references. The official ccusage repository was inspected at commit `5a60e73ddf79e2a22893120af4a52cf66dc0bd1a` (MIT); its fixture generator and Rust parser confirm modern response-ID records and fork ownership concerns. No source code was copied and no ccusage executable or telemetry was run. Numerical reconciliation against a pinned ccusage release remains pending real logs.

## Detection and account ownership

`SourceDiscovery.detect()` searches PATH, standard Homebrew/local executable directories, the Codex app Resources directory, CODEX_HOME sessions/archived_sessions, CLAUDE_CONFIG_DIR projects, `~/.claude/projects`, `~/.config/claude/projects`, and XDG_CONFIG_HOME/claude/projects. Finder may not inherit shell variables; the app provides a native folder picker for custom sources. Detection never opens auth.json or a credential store, invokes login, installs hooks, or starts an agent task.

`--version`, `codex login status` and `claude auth status` run with a bounded timeout, a 64 KiB output cap, and discarded raw results. Only version, authentication state, public email/account metadata and source availability leave the detector. The optional `includeAccountDetails:true` Codex App Server probe uses `refreshToken:false` and disables analytics; it is **off by default** because vendor startup behavior is outside Pot's offline control. Settings offers an explicit Read public details action; normal onboarding/background refresh leaves it off. Child CLI implementations may have their own behavior; the claim is no Pot network client, not a guarantee about every installed vendor executable.

Finding a directory does not establish authentication. A current account does not establish ownership of past logs. Usage without explicit per-event `account_id` stays in `local:codex:unattributed` or `local:claude:unattributed`; account IDs are provider-namespaced local pseudonyms. A user alias is only a local label. If a tool changes accounts inside a shared log folder without event identity, Pot cannot separate those accounts' history. It never silently assigns it to today's login.

## Parser semantics

Codex: session_meta provides session identity; turn_context supplies model. `event_msg/token_count/info.total_token_usage` is preferred over last_token_usage and converted into non-negative deltas. `cached_input_tokens` and modern `cache_creation_tokens` are subsets of input and are subtracted once; output reasoning details are not added again. Repeated cumulative counters add nothing. A counter decrease establishes a new baseline and is flagged partial instead of creating negative usage. A known legacy fork (`forked_from_id`) is quarantined as partial because the boundary between inherited and new cumulative history cannot be proven. Modern `token_usage_record` records require a matching thread/session owner, stable response_id and valid thread_token_usage. They share a canonical session+cumulative key with legacy snapshots (no timestamp), so partial copies containing different representations cannot double-count the same call. They suppress the accompanying legacy counter representation. Records lacking the cumulative bridge are quarantined as partial rather than risking cross-format duplicate credit. Copied parent-owned records are ignored. When only last_token_usage exists, a stable request_id is required; records without it are quarantined as partial because rate-limit updates can repeat the last call at another timestamp. A stable request deduplicates those repeats. Unknown model/session is partial. Unrecognized forks/formats can require an adapter update; unproven account attribution is never guessed.

Claude: only assistant message usage is extracted; input, output, cache_read_input_tokens and cache_creation_input_tokens are disjoint. The stable message ID deduplicates copied/streaming records even if requestId appears later. Larger later usage replaces the previous message total instead of adding a second call. Its original day/account attribution is preserved, preventing a streaming completion from moving credited usage across days. Unknown cache-creation duration keeps the priced known categories but flags the estimate partial. Prompts, responses, tool text, project names and code are discarded. Structured nested `cache_creation.ephemeral_5m_input_tokens` / `ephemeral_1h_input_tokens` enable exact cache pricing.

## Incremental import and safety

SQLite commits normalized metrics and the corresponding cursor/parser state in one transaction (WAL + synchronous FULL). A cursor tracks file identity, last complete line, structural first-line metadata fingerprint, model and cumulative counters. Fingerprints never include conversational content. Truncation, inode changes, changed first metadata, or a rewritten completed file reset the parser cursor. Existing event keys prevent duplicate totals after copied/archived files or restart. A new log containing old usage can populate statistics but the plant engine rejects pre-creation energy.

Memory limits: 64 KiB reads, 4 MiB maximum parsed line, 32 MiB file budget, 64 MiB source budget and 10,000 files per pass. Oversized lines are discarded with a persisted discard state until newline; incomplete normal lines wait for completion. Work beyond a pass resumes on a later scan. Directory traversal skips symlinks and verifies canonical containment. An unreadable source, malformed usage, unknown model or truncated work is reported partial; it is not interpreted as zero activity. Existing data is preserved.

Zstandard `.zst` files are explicitly reported unsupported/partial and are **not** silently treated as supported. No decompression runtime is installed in the user's app. Per-pass file enumeration still inspects file metadata; a very large tree has not been profiled on macOS. SQLite schema version 1 is transactional; a higher unknown schema is refused. No destructive future migration is implemented.

## Statistics and estimated API value

The app can query SQLite with a timestamp bound using the profile/time index, keeping its working event window to 45 days. All seven calendar days are emitted, including zeros, using the user's current timezone and calendar day boundaries. Future events are excluded from present statistics and growth.

The bundled catalogue is a versioned **reference snapshot**, not an asserted history of price changes. Its verified/reference date is 2026-11-25; `effectiveFrom` marks applicability of this snapshot, not the vendor's original release date. Exact model matching only; unknown models remain unpriced. USD values use Decimal and round only in UI. Current OpenAI models with publicly quoted cache-creation rates price known cache_creation_tokens separately. Known priority/fast/other nonstandard tiers keep a standard reference estimate explicitly partial; they do not claim the special-mode rate is implemented. Known categories of a partly unpriced event contribute a clearly partial amount. If every event is unpriced, amount is unavailable. For legacy Claude rates whose long-context conditions are not implemented, inputs above 200,000 tokens remain unpriced. Exact batch, priority, fast-mode, tool extras, private discounts and taxes are outside this reference estimate. The UI must call this **Estimated API value**, never a charge.

Offline price updates ship with a new app version. Recomputing displayed history with a new reference snapshot must retain the visible snapshot date; this MVP does not claim historical invoicing accuracy.

## Tests

The test suite verifies exact cumulative/cache arithmetic, ignored duplicate counters, copied/restarted/rotated logs, incomplete-line append, resets, Claude streaming, request ID arriving later, safe account separation, symlink escape rejection, oversized line recovery, persistence/erasure, unknown models, cache-price coverage, seven-day zero-fill and Santiago timezone boundaries. Synthetic sentinel transcript text never enters normalized records.

Still requires a Mac: real Codex and Claude Code reconciliation, permission-denied UI, actual FSEvents behavior, account switches in installed clients, compressed archive support decision and idle resource measurements. No credentials or complete transcript uploads are required for these checks.

Very large source-tree limit: the 10,000-file traversal bound does not maintain a persistent directory-enumeration cursor, so files beyond the first 10,000 in one root may remain unvisited and coverage stays partial. The folder picker can add smaller source subdirectories; event deduplication applies across them. Byte-limited reads within visited files do resume through their committed file cursors. This tree-size limitation must be fixed or clearly bounded before advertising complete large-history coverage.

## Measured ingestion workload (Linux only)

`pot-dev benchmark-import 100` generated 104,858,402 bytes of explicitly synthetic JSONL containing 23,028 distinct assistant IDs and disposable content filler. The debug Swift6.0.3 build imported it in four resumed passes in **12.553s (7.97MiB/s)**, verified exact non-overlapping totals, then reimported with **zero added records**. A Python `resource.getrusage(RUSAGE_CHILDREN)` wrapper measured **50.91MiB maximum RSS**, **18.128s user CPU**, **0.446s system CPU** and **18.624s total wall time** including fixture generation and validation. Temporary files/database were deleted.

These are measured Linux ingestion numbers, not AppKit idle RAM/CPU, animation performance or a macOS release benchmark. The separate development executable never ships in Pot.app.

Final optimized Linux run after parser fixes: same 104,858,402-byte/23,028-message fixture, four passes, zero replay records; **9.345s import (10.70MiB/s)**, **15.612s total wall**, **15.044s user CPU**, **0.532s system CPU**, **43.60MiB maximum RSS**. `swift build -c release --product pot-dev` succeeded in 11.31s. `pot-dev simulate 365 42 codex` produced 45 live/484 retired organs, 19,143 serialized state bytes, 0.079s engine time (0.094s process wall) and 18.49MiB max RSS. The final full XCTest run passed **34 tests, 0 failures, 2.278s** (integration24, engine8, floating policy2).
