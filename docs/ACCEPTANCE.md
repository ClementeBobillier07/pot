# MVP acceptance evidence

This is an implementation handoff, **not a declaration that the macOS MVP is release-ready**. The provided execution host is Linux; unavailable native checks are deliberately open.

| User criterion | Evidence / state |
|---|---|
| Compiles and runs on macOS | Open: requires Xcode/macOS. Native source parses, but SDK type checking has not run. |
| Detects installed agents | Real sanitized CLI discovery detects authenticated Codex 0.172.0-alpha.2; Claude absent. |
| Real usage without duplicates | Fixture suite verifies counting/dedup; real usage reconciliation open because this host has no JSONL sessions. |
| Daily tokens and API values | Portable tested core: seven days, zeros, Santiago boundary, disjoint cache categories, exact-model reference catalog and partial/unavailable cases. Native display implemented. |
| Provider-specific plants | Native Canvas source: sage cylindrical Codex pot/round leaves and terracotta trapezoidal Claude pot/pointed leaves. Website SVG previews are illustrative. |
| Persistent procedural evolution | Core tests cover serialization/restart, genetic variation, independent organ growth, renewal and a simulated year. |
| Individual leaves | Sizes 1–10, independent genetic rates and staggered allocation; tested. Native interpolation source implemented. |
| Flower lifecycle | Seven ordered stages and concurrent different progress; tested. Native continuous opening source implemented. |
| Wither and recover | Core weekend grace, data-gap protection, vacation-length dormancy and recovery tests. Native appearance unverified. |
| Transparent floating plant | Nonopaque clear borderless NSPanel source; actual compositing/hit testing open on Mac. |
| Hover-only X/arrows | Source implemented with no background card; runtime, VoiceOver and pointer tests open. |
| Change plant / click opens / X hides | Source implemented with separate controls, native click-vs-drag threshold and stable selection. Manual Mac checks open. |
| Three display modes | Portable visibility policy tests pass, including manual dismissal through current activity session. Native windows open. |
| Survives restart | SQLite and plant serialization tested. Packaged app restart, launch at login and OS restart open. |
| Personal usage stays local | No networking API in PotCore/PotApp. Allowlisted persistence; synthetic sensitive-content sentinel test. Packaged traffic observation still open. Vendor status commands and manual browser update links have separate documented behavior. |
| Landing works locally | Next production build and TypeScript pass; release logic tests pass; real public metadata lookup returns no eligible installer. Browser visual QA blocked by managed relay. |
| Errors documented | BLOCKERS.md, docs/INTEGRATIONS.md, ENGINE.md and MAC_QA.md describe limits. |
| Development simulation | Separate pot-dev executable: synthetic time jump/year, growth/activity fixtures and import benchmark; never bundled into Pot.app. |
| Distribution | Scripts prepare arm64/x86_64/universal .app/DMG, local or Developer ID signing and explicit notarization; no native artifact produced here. |

Do not mark these open native gates green from a successful Linux `swift test` or a Next build. Run docs/MAC_QA.md and attach measured evidence before releasing.
