# Procedural plant engine (v3, 2026-11-26)

## Botanical variants and steady growth (engine 3, current)

Drawn after the owner's references ("Pot — growth & recovery", "Botanical variation 02/03", "The copihue").

- **Variant at birth, by seed:** variation 01 (40 %), variation 02 (35 %), variation 03 (24 %), copihue (1 %). Codex plants live in a sage planter, Claude Code plants in a terracotta pot.
  - Codex: 01 oval leaves with small white/pink/yellow/lilac flowers; 02 round leaves with roses, daisies and lilac stars; 03 broad leaves with camellias, navy and burgundy blooms and small yellow stars.
  - Claude Code: 01 lance leaves with orange/peach/lilac stars; 02 long leaves with orange daisies, lilac stars and white bells; 03 slender leaves with orange/yellow/burgundy daisies.
  - Copihue: a wooden stake from day 1, a sprout until ~day 14, the vine from ~day 14–30, buds from ~day 30, first bell ~day 45, up to four bells by day 90 (white with red rim for Codex, red for Claude Code).
- **Steady growth.** `PlantState.growth` adds each day's energy × vigor. Growth progress = growth ÷ 90, so one reference day of use per day gives a full plant at day 90: seedling (days 1–3), first leaves (7), small plant (14), bush (30), first flowers (≈45), lush (60), full (90). Heavier days get there sooner (up to 3× faster) and light days much later. Once full, flowers keep renewing on a staggered 14-day cycle.
- **Drawing is derived, not stored.** `PlantFormBuilder` turns seed + growth + health into stems, leaves, flowers and fallen leaves. Every leaf and flower has its own stable random stream, so nothing jumps between days. The engine's organ graph (below) still runs but no longer drives the picture.
- **Wilting at half the reference timeline:** nothing for the first idle day, then health ≈ 0.85 at 1.5 days (leaves soften), 0.65 at 3.5 days (droop, paler, flowers hang), 0.40 at 7 days (yellow, flowers wither, leaves start falling) and 0.15 at 15 days (dry brown stems, dried pods, leaves on the ground). Never dead.
- **Return:** with use again, fresh green leaves come back first among a few dry remnants ("1 day back"), and flowers return once health is above ≈ 0.72 (≈ 3.5 days back).
- `Pot --render-plants DIR` writes one sheet per variant (Codex and Claude Code growth by day, rest & return), from synthetic usage.

## Engine 2 (superseded in part)

## Growth and wilting (engine 2, current)

One rhythm for everyone, chosen by the owner: no personal calibration.

- **Work of a day** (work units) = new input + cache writes + cache reads ÷ 10 + output × 5, summed over the day's calls. The weights follow the usual price ratios between categories without depending on the model, so long cached contexts do not dominate and expensive models do not grow faster.
- **Daily energy** = log2(1 + work ÷ 10 M), at most 3. 10 M (a reference day, between a measured light Codex day of ~1.7 M and a heavy Claude Code day of ~20 M) gives 1; 1.5 M gives 0.2; 70 M or more gives 3. The reference is a hypothesis to tune in the beta (`PlantEngine.referenceDailyWork`).
- **Growth costs energy.** Energy is banked as the day's work is observed, flows into expanding leaves and opening buds, and pays for new organs: leaf 0.35, branch 0.8 (from maturity 3), flower 1.2 (from maturity 12, health ≥ 0.75). Once flowering age is reached, 1.2 is kept for the next bud. Typical renders (weekdays only): light use adds a few leaves in 3 months; a reference day flowers around day 60; heavy use flowers around day 30 and grows taller.
- **Wilting.** The first day without use changes nothing; then health falls 0.18 per idle day (2 days ≈ 0.81, 3 ≈ 0.63, 4 ≈ 0.45, a week → 0.15) and never goes below 0.15: wilted, never dead. Leaves droop and yellow with health. Below 0.6 no new organs appear; growth stops entirely near 0.35.
- **Recovery.** Days with use restore health at ≈ 0.3/day, up to 0.42 on fuller days: about three days of coding bring a wilted plant back. Missing or unreadable logs freeze health (a reading problem is not a day off). There is no pause: a trip simply wilts the plant.
- Plants from engine 1 are re-grown from their birth with these rules (same seed and birth date).

`Pot --render-plants DIR` renders light / typical / heavy rhythms and the wilting sequence from synthetic usage.

## Engine 1 (historical)


`PlantState` is a Codable snapshot; seed plus serial generate stable SplitMix-style values without system randomness during rendering. Every organ has a stable identifier, birth/age, bounded current and maximum size, position, orientation, geometry/palette variant, health, growth rate and independent maturation. Coordinates are normalized; soil is (0.5, 0.80). A branch segment's current tip is `endpoint`; `endX/endY` are its fully grown tip. Leaves attach along mature segments and flowers attach to their tips.

The engine receives a canonical deduplicated usage snapshot for a single profile. It counts input, output and cache categories once, does not use dollar prices, ignores events before the plant's creation and never grants future events. Repeated snapshots and duplicate IDs within a snapshot cannot increase a day's credit. Canonical stable event IDs across copied files are the integration layer's responsibility. Caller should retain canonical event snapshots; passing independent delta batches undercounts rather than granting duplicate energy.

UTC days anchor energy budgets independently of presentation timezone. A 45-day bounded credit journal stores maximum observed daily token totals and already credited energy. Days compacted out of that journal can never be credited again. A daily entitlement is `min(1, log1p(tokens/reference)/log(2))`; a calibration multiplier rises continuously from 0.25 to 1 over the first 72 elapsed hours, independently of midnight crossings. Later the cap is 1. The reference combines a prudent 100,000-token provisional baseline with median nonzero prior days in a trailing 30-day window, increasing confidence over seven active days and limiting each day's adjustment to 15%. These are behavioral hypotheses, not productivity goals.

The reserve is capped at three daily units and growth consumes at most 0.035 per hour, plus bounded organ-birth costs. Leaf growth uses individual genetic rates and staggered allocation. New leaves appear only with reserve; new stems/branches require historical maturity. Flowers have independent sprout, bud, partial, bloom, mature, wilted and fallen stages. Opening uses reserve and genetics; completed blooms age toward fall without requiring further work.

Visible structure is bounded at 32 leaves, six flowers and 12 total stems/branches. Old leaves and flowers retire; unused terminal branches can be replaced without disconnecting descendants. Lifetime maturity and retired-organ count survive replacement. Nothing resets the plant or imposes a maximum maturity.

Health has a 72-hour inactivity grace period, then declines slowly toward a recoverable floor of 0.3. Recent real activity recovers health. Missing data freezes deterioration. Every update has a persisted time high-water mark; moving the clock backward cannot repeat simulation or credit. A forward clock jump cannot produce more growth than actual token entitlements plus existing reserve, and unbounded time alone grants no energy. Without trusted external time, the app cannot distinguish an authentic long absence from changing the system clock; it does not claim tamper-proof elapsed age.

Offline catch-up simulates at most the latest 45 days in hourly steps and ages earlier absences analytically. Energy from older history is intentionally not stockpiled. A fresh plant never matures instantly from imported history. Hourly interpolation and persisted organ maturation permit smooth UI transitions without a continuously running simulation. Update partitioning can affect subhour allocation/organ birth timing; seed/state/input/update timeline deterministically reproduces the result. This v1 does not promise bit-identical biological trajectories between differently timed online and offline update schedules.

`swift run pot-dev simulate 365 42 codex` exercises a year of clearly labelled synthetic weekday sessions. This separate executable has no access to the production database and is not included in the app bundle. `POT_SIMULATION_OUTPUT=/tmp/plant.json` explicitly exports a development snapshot. `swift run pot-dev --detect` performs real local agent discovery and prints sanitized availability/version/authentication/root counts, without email addresses, account identifiers or paths. Tests cover restart replay, duplicate and historical events, clock rollback/large forward jumps, calibration caps and elapsed-time boundaries, independent leaves/flowers, weekend grace, data gaps, recovery, bounded geometry and a full simulated year.
