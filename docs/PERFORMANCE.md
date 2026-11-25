# Performance evidence

Measurements on 2026-11-25, Debian13/Linux x86_64, AMD EPYC9V74 virtualized host, official Swift6.0.3. They describe synthetic portable-core workloads; **they do not measure the macOS UI, idle CPU, energy use or resident app memory**.

| Workload | Result |
|---|---|
| 100MiB release importer | 104,858,402 bytes; 23,028 unique Claude-format synthetic messages; four incremental passes |
| Exactness/replay | Expected disjoint token totals match; repeated import adds zero records |
| Import time | 9.345s, 10.70MiB/s |
| Whole benchmark | 15.612s including fixture creation and validation; user CPU15.044s, system CPU0.532s |
| Maximum RSS of benchmark child | 43.60MiB, measured with Python resource.RUSAGE_CHILDREN |
| 100MiB debug importer | 12.553s, 7.97MiB/s; whole child18.624s; maximum RSS50.91MiB |
| Annual release simulation | 365 synthetic days, seed42, Codex family; 45 live organs, 484 retired, serialized snapshot19,143bytes |
| Annual simulation time | Representative engine0.079s / whole child0.094s, maximum RSS18.49MiB; subsequent engine run0.067s |
| Release XCTest | 34 tests, 0 failures in0.938s; release build18.05s |

No real conversations are used. The benchmark writes a temporary synthetic JSONL plus temporary database, checks exact counts/deduplication and removes them. It is a separate development executable, not included in Pot.app. Very large roots above10,000 files have an explicit traversal coverage limitation (see BLOCKERS.md); the measured benchmark is one large file, not a claim about arbitrary directory trees.

Reproduce with `swift run -c release pot-dev benchmark-import 100` and `swift run -c release pot-dev simulate 365 42 codex`. On Linux this workspace requires the SQLite include/link flags documented in README. Do not compare debug/release or different hardware as if they were the same app measurement.

The importer uses64KiB chunks, at most4MiB parsed line,32MiB/file/pass and64MiB/source/pass; unread work resumes. The source traversal caps parsed files at10,000/pass, but a large directory tree's metadata traversal still needs profiling. Recent app statistics/biology query at most45days through SQLite's timestamp index; lifetime dedup records remain stored. FSEvents debounce is1.5s with a60s fallback. Floating pointer tracking runs at120ms only while visible; Canvas motion is a short24fps activity pulse, otherwise paused; growth interpolation is triggered only by visual organ changes.

## Unmeasured release gates

On a named Mac, measure at least30minutes idle CPU/RSS, Activity Monitor energy impact, main-window opening latency,100MiB import while keeping UI interactive, filesystem watcher wakeups, visible/hidden/reduced-motion behavior, day-long use and wake-from-sleep catch-up. The document's <1% idle CPU, <150MB resident memory and <500ms open-time are **targets**, not achieved native measurements.
