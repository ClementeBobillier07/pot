# Native macOS acceptance checklist

Simulated QA run, 2026-11-26 (real HID mouse events + the Accessibility API that VoiceOver uses):
- PASS close button hides the floating plant without opening Pot or taking focus; the menu bar item's "Show floating plant" brings it back.
- PASS launch at login: installed in /Applications, the toggle registers Pot as a login item (listed by System Events, persists across relaunch) and unregisters cleanly. A real reboot was not performed.
- PASS full screen: the floating plant stays visible over a full-screen app and clicking it opens Pot on that Space, in front.
- PASS missing monitor: a position saved on a disconnected display is pulled back onto the Mac's screen.
- PASS VoiceOver labels: every control in the window and Settings has a spoken name (toggles/pickers via their title element; the chart reads "Today, Thursday, 26 Nov").
- PASS light/dark: both readable after making the brand green lighter in dark mode.
- NOT SIMULATED: sleep/wake (would put the Mac to sleep) and the system-wide Reduce Motion switch; both paths are covered in code (wake rescans and re-clamps; reduce motion pauses sway, dance and transitions).

Verified with real (HID-level) synthetic input on macOS 27.0.1, 2026-11-26: hovering the floating plant does not take focus from the active app; dragging moves the panel (a press that starts on the plant keeps the panel until release) and does not open Pot; a click opens Pot's window in front; a long two-finger swipe switches exactly one plant; the close badge appears on hover.

Status (2026-11-25): build, tests, launch, real-data import/reconciliation, transparent floating panel rendering, universal local DMG, and idle footprint verified on macOS 27.0.1 / Apple Silicon (see BASELINE.md). **Interactive items below remain pending** (hover, drag, click-through, focus, Spaces, displays, sleep, login items, VoiceOver). Do not mark an item passed solely because Swift core tests succeed.

Quick start for a QA run: `swift run Pot` (development, defaults domain `Pot`) or install `artifacts/Pot-*-local.app` into /Applications (defaults domain `com.pot.mac`). `swift run Pot --show-window` opens the garden window directly. Reset with Settings → Delete local data, or `rm -rf ~/Library/Application\ Support/Pot && defaults delete Pot`.

For each run record hardware, CPU architecture, macOS version, Xcode/Swift version, Pot commit, Codex/Claude versions and whether an installed `.app` or `swift run` was used. Do not include personal log contents, email addresses or secrets in the report.

## Install and startup

- Build using `scripts/build-macos.sh --dmg`; confirm tests, resource bundles, icon, Info.plist and binary architecture checks pass.
- Open from `/Applications`, complete onboarding and quit/relaunch. Verify no terminal, login or runtime installation is required for normal use.
- Test launch at login using the installed application and the system's real Login Items state; test registration error reporting and disabling.
- Close the main window and confirm the menu-bar item remains usable. Quit must actually terminate Pot.
- For release candidates, install an actual quarantined downloaded notarized DMG on a clean Mac without bypassing Gatekeeper.

## Detection, accounts and ingestion

- Run with only Codex, only Claude, both clients and neither client installed. Verify actionable retry and custom-folder selection, including nonstandard executable/log paths.
- Confirm existing login is reused through safe public status interfaces, never reading credential files or causing a login/refresh prompt.
- Compare displayed counts with a manually counted allowlisted usage sample or a trusted offline reader. Never upload entire transcripts for debugging.
- Test active append, incomplete final line, malformed record, stream update, cumulative counter, two concurrent sessions, same-size replacement, truncation, archive move and duplicated folders. Restart during ingestion; counts must remain unchanged on replay.
- Change an agent's active account. Verify any identified account gets its own plant and historical events without explicit account evidence stay unattributed. A current email must not relabel shared historical logs.
- Revoke source permissions and replace a source with a symlink outside its authorized folder. The app must report incomplete/unavailable data and freeze deterioration rather than silently count zero.
- Test daylight saving and time-zone changes around daily aggregation, including days with no events; confirm totals include each event once.

## Main interface and settings

- Verify ordered provider, alias/email, centered plant, today's tokens, “Estimated API value”, seven-day chart and account navigation. Chart selection, totals and token/USD switching must work.
- Navigate several accounts with keyboard arrows and horizontal trackpad gestures; selected account and plant must stay synchronized across surfaces and relaunch.
- Unknown models/prices show unavailable or partial values; estimates never claim to be actual charges. Verify the price reference date/version appears where appropriate.
- Test light/dark/system appearance, large text, VoiceOver, keyboard focus, contrast and macOS Reduce Motion. No movement should continue for invisible surfaces.
- Confirm destructive deletion requires confirmation, affects only Pot data, and recreates an empty onboarding state without deleting agent logs.

## Floating NSPanel

- Exactly one plant, transparent with no card, shadow, title or visible background in light/dark mode.
- Two-finger horizontal swipe over the floating plant switches to the next/previous plant once per gesture, with a soft fade; the main window follows the same selection.
- Window: the plant keeps a fixed stage (no layout shift as it grows); the weekly chart runs Monday–Sunday with today highlighted and previous-week arrows; opening Pot from a full-screen app shows the window on that Space.
- Window: arrows beside the plant name and page dots switch plants; the grid button (⌘G) shows every plant gently swaying; clicking a card opens it. Settings → Connected agents shows each signed-in email, method and plan.
- Hover shows only the close button (black ✕ in a white circle with black outline) just above the plant's top-right edge; leaving the plant fades it. Clicking it never opens the main app. There are no arrows on the desktop; plants are switched inside Pot.
- A plant click opens the main window with the corresponding account. A drag changes position without opening the window; position survives restart.
- The panel appearing, hovering or dragging must not steal focus from the active application. Test typing into another application while activity begins.
- Empty transparent regions must not unnecessarily obstruct interaction with underlying windows. Test control hit targets and cursor tracking along the silhouette.
- X hides the panel while Pot stays alive. Recover it using the menu item. In “While I work”, closing it suppresses the current activity session and new activity after idle may show it again.
- Onboarding corner picker and Settings → Corner place the plant in each of the four corners inside the visible frame (Dock/menu bar excluded).
- Menu bar: Presentation submenu switches the three modes.
- Growth (engine 2): a light-use plant grows visibly slower than a heavy one; after 2–4 idle days leaves droop and yellow; a few days of use restore it.
- Test all three display modes; idle timeout/hysteresis; manual hide; agent bursts; activity on a different selected provider. Historical import must not trigger a welcome dance or switch the selected plant.
- Test scaling, all screen corners, Dock at bottom/left/right, menu-bar autohide, Retina/non-Retina monitors, resolution changes and unplugging the saved monitor. Ensure panel remains reachable.
- Test Spaces, full-screen applications and Stage Manager separately. Record any intentional visibility limitation; do not assume collectionBehavior alone proves support.

## Biology, privacy and reliability

- Development-only simulations can show days 1/3/30/365 and flower stages without altering production data. Production has no fake-data switch.
- Restart after activity and after several offline days. Plant seed, historical maturity, individual organs and health persist; clock rollback/repeated imports award no new energy.
- Verify gentle weekend grace, recovery after vacation, data-gap freeze and no permanent death. Long-run organ count stays bounded while renewal remains visible.
- Disable network access and complete normal Pot flows; inspect app traffic using system tools. No app usage, identities or transcripts should leave the machine.
- Inspect Pot's SQLite/diagnostic files for allowlisted metrics only. Verify private file permissions and that no credentials, prompts, outputs or code are retained.
- Force quit during a scan and reopen. Database/cursor transaction integrity must survive without duplicate usage or plant reset.

## Record resource measurements

Measure the **installed release `.app`** on a named Mac, not the Linux simulator: idle and active CPU, resident memory, energy impact, first-open panel latency, 100 MB log import wall time and peak memory. Sample multiple minutes in Activity Monitor or Instruments, document sample duration and test data shape. Targets from the master document (<1% average idle CPU, <150 MB resident memory, <500 ms panel latency, <30 s for 100 MB ingestion) remain hypotheses until measured.
