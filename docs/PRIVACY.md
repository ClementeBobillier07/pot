# Pot privacy and local data

Pot has no user backend, sign-up, payment, remote database or telemetry client. The native target contains no network fetch implementation. Prices ship in a local catalog. Its garden can operate offline.

JSONL files can contain conversations and source code. Pot must transiently read complete JSON lines to find usage metadata; it discards content and stores only allowlisted timestamps, model identifiers, disjoint token counters, local profile identifiers, identity confidence represented by identified/unattributed profiles, cursors, deduplication metadata and procedural plant state. Errors never log raw lines. Paths selected for sources are local preferences, not analytics.

Pot never directly opens auth.json, Keychain credentials, API keys, cookies or authentication tokens. It runs the installed clients' own bounded status commands (`claude auth status`, `codex login status`, and Codex App Server `account/read` with `refreshToken:false`) to show, in Settings → Connected agents, which email, sign-in method and plan each agent is using. This is display-only: the email is kept in memory, never stored with usage, and never assigns past logs to an account. Pot does not log in or request token renewal. Installed vendor executables have behavior outside Pot's implementation and may communicate with their provider. The app does not upload usage through those commands.

The database lives at `~/Library/Application Support/Pot/garden.sqlite` with local-only SQLite WAL/SHM siblings. The containing directory is private to the macOS account (0700) and the database is 0600. SQLite is not encrypted by this app. macOS account isolation and FileVault, when enabled by the owner, are independent protections.

Preferences live in the app's UserDefaults domain `com.agentpots.pot`. The user can explicitly delete Pot data and plants, with confirmation; agent files are never deleted or modified. Reimporting available external logs can rebuild statistics but creates a new small garden. Data already deleted by the agent cannot be reconstructed by Pot.

Local usage and dedup keys are retained; no automatic retention cleanup is implemented that could permit old events to be credited again. Statistics/biology query only a bounded recent window. The compressed archive format is not supported yet and reports partial coverage.

Check for updates opens the repository's releases page in the user's default browser and installs nothing. Public website downloads use GitHub; those network services see ordinary request metadata. The website's release-counter API reads public asset counts only and receives no native account/usage data. The website has no enabled analytics, external fonts or tracking scripts. Next CLI telemetry is disabled in the supplied commands.

Before publishing: observe traffic from the packaged app offline/online on a Mac, inspect its persisted files with synthetic sentinels, verify file permissions including WAL/SHM, and review this document against any new integration.
