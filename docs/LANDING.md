# Pot landing

## Implemented

Independent Next.js App Router / TypeScript website in `landing/`, designed in English around original reusable botanical SVG illustrations. Ten requested content sections are present: hero, transparent desktop illustration, three-step explanation, interactive growth illustration, honest statistics layout, provider families, local privacy, download, FAQ and footer. Responsive CSS supports the system's light/dark preference and reduced motion; keyboard focus, semantic sections, native FAQ disclosures, a skip link and labeled interactive growth buttons are provided.

Illustrations are explicitly labeled as previews. No actual app screenshots, invented usage totals, API prices, download counts, testimonials, or release availability are asserted. The page states native validation is still pending and points to public release availability. The native app's actual compatibility must be verified before updating the release copy.

## Run locally

```sh
cd landing
npm ci
npm run dev
```

For an optimized local production server: `npm run build && npm start`. The build output is `landing/.next/`; this is a Next.js site, not a native macOS installer.

On the managed environment, use `sites-preview start /workspace/pot/landing` instead of a separate preview server. The checked-in `scripts/dev.mjs` translates the preview daemon's `--host`/`--strictPort` arguments to Next's hostname arguments while retaining the daemon's exact host and port.

## Download metadata

`GET /api/releases` reads public GitHub Releases metadata server-side. Default repository: `ClementeBobillier07/pot`, overridable with the server-only `POT_GITHUB_REPOSITORY`. No token is required or exposed.

Rule version 1 counts distinct asset IDs across all published, stable, non-draft releases and only `Pot.dmg` or `Pot-<semver>-macOS-<arm64|x86_64|universal>.dmg`. ZIP files, signatures, update artifacts, unrelated DMGs, drafts, prereleases and invalid counts are excluded. The asset download URL must belong to the same repository's GitHub release-download path. A maximum of 20 pages with 100 releases each bounds retrieval; hitting the limit reports unavailable rather than a partial count.

The counter appears only when at least one eligible installer exists. A real zero count is allowed for a real eligible asset. The label says installer downloads and explicitly distinguishes files from people. A one-hour process-local cache coalesces requests; failures retain the last verified snapshot with its timestamp and stale label, retrying after one minute. CDN response caching is five minutes with one-hour stale-while-revalidate. Cold starts have no prior snapshot and hide the counter on error. 404 means no available public release metadata; nothing is fabricated. The counter fetch is a public website integration and never receives native usage data.

## Privacy and hosting

No analytics, cookies, third-party fonts, images, tracking scripts, user database or authentication service is configured. No Vercel analytics package is installed. Analytics remains explicitly unconfigured in `.env.example`; enabling any external service requires the owner's authorization and a reviewed privacy policy.

Ready for ordinary Vercel Next.js hosting by selecting `landing` as the project root. **No project, public site, deployment, or scheduled job was created.** Robots indexing is disabled for the development build and should only be enabled after public release approval.

## Verification on 2026-11-25

- `npm test`: 7 tests pass (eligible assets, real zero/missing data, deduplication, complete pagination, rate limiting, repository validation, cache/coalescing/stale failures).
- `npm run typecheck`: passes.
- `NEXT_TELEMETRY_DISABLED=1 npm run build`: optimized build passes; homepage prerendered and `/api/releases` dynamic.
- `npm audit --omit=dev`: zero reported production dependency vulnerabilities at this check.
- Live public GitHub release retrieval using the environment’s configured proxy succeeded and returned no eligible public installer (`snapshot: null`). Initial direct Node fetch was refused by the managed network; `NODE_USE_ENV_PROXY=1` allowed the standard configured proxy on Node 24. No download count is shown.
- React best-practices review: static sections remain server rendered, only download lookup and growth selector hydrate; direct imports, typed props, bounded shared client metadata request for both CTAs, effect cleanup, no third-party UI/runtime library, semantic controls, polite download-status announcements, readable product copy and reduced-motion styles.
- Follow-up preview status remained stopped. Troubleshooting explicitly disallows retry without a concrete repair or infrastructure recovery; the relay timeout has no safe prescribed application fix. Browser QA therefore remains unverified.
- Native macOS app verification is independent of these website checks.

Browser QA remains unverified: managed `sites-preview` reached a relay failure (`relay could not open browser port 4173: timed out waiting for relay readiness`). Preview status returned stopped. No alternate server or browser-routing bypass was used. Responsive layout, dark mode and interactions have not yet been visually checked in a browser.

## Download counter and the tree idea (2026-11-26)

Under each download button the site shows the real number of installer downloads from public GitHub Releases (only `Pot-<version>-macOS-<arch>.dmg` assets of stable releases; see `lib/releases.ts`). Before the first release it says "The counter starts with the first release" instead of showing a number. The tooltip explains it counts files, not people.

`lib/trees.ts` holds the future "every N downloads we plant a tree" idea: set `TREE_EVERY` (for example `1000`) and the counter adds "· N trees planted · next in M". It stays hidden at `0`, so nothing is promised before a planting partner exists.

## Variants stay a mystery (2026-11-26, owner)

The website does not show the plant variations, their odds or the copihue. It only says every seed is its own; people discover their plant as it grows.
