# Private beta (5–10 people)

Goal (master document §2): a new person reaches their plant with standard sources, without Terminal or secrets, understands what is read and what "Estimated API value" means, and notices visual variety within a week without watching the app.

## Who

Mix of rhythms: 2–3 heavy daily agent users, 2–3 occasional users, 1–2 people using only Codex or only Claude Code, at least one Intel Mac if available, at least one person who has never opened `~/.codex` or `~/.claude`.

## What each tester does

1. Install the build you send them (until Developer ID signing exists: a local DMG; they must right-click → Open once — explain this is a beta-only step).
2. Complete onboarding without help. Note the time it took and anything confusing.
3. Use their agents normally for 7 days. Leave the plant in the default display mode.
4. Optional, for count validation (requires Xcode command-line tools and the repository):
   ```bash
   swift run -c release pot-dev reconcile
   ```
   It reads their logs into a throwaway database and prints only aggregate counts per model, then deletes it. Nothing leaves the Mac unless they paste it.
5. File one "Beta report" issue at day 1 and day 7 (template in `.github/ISSUE_TEMPLATE`).

## What we measure (no telemetry — only what testers report)

| Question | Signal | Hypothesis to validate |
|---|---|---|
| Onboarding is self-serve | Time to first plant, help requests | < 2 minutes, no Terminal |
| Counts are trusted | `reconcile` vs their own expectation / provider dashboards | No unexplained gaps; unknown models clearly unpriced |
| Value label is understood | Ask: "what does the dollar figure mean?" | Nobody reads it as their bill |
| Growth feels alive but calm | Day-7 description, screenshots | Visible change most days; light and heavy users both see growth |
| Rest is not punished | Weekend / day-off behaviour | Plant looks calm, not dying |
| Floating plant is welcome | Kept visible vs hidden, focus complaints | No stolen focus; hover controls discoverable |
| Footprint | Activity Monitor CPU/Memory after a day | < 1 % idle CPU, < 150 MB |

## Exit criteria

- No count discrepancy that we cannot explain, across at least 3 Codex and 3 Claude testers.
- No crash or lost garden after restart, sleep, or update.
- Health/energy thresholds (DECISIONS 19, master doc §7/§9) adjusted from day-7 feedback.
- Decide D04 (energy/health formula) and D08 (initial visual variants) with this evidence.
