/** Public GitHub release metadata only. No account or usage data enters this module. */
export interface ReleaseAsset { id: number; name: string; download_count: number; browser_download_url: string }
export interface Release { id: number; draft: boolean; prerelease: boolean; published_at: string | null; assets: ReleaseAsset[] }
export interface DownloadSnapshot { total: number; updatedAt: string; assetIDs: number[]; downloadURL: string; ruleVersion: 1; stale: boolean }

// One distribution format avoids counting a DMG and ZIP for the same installation.
const installerName = /^Pot(?:-v?\d+\.\d+\.\d+(?:\.\d+)?-macOS-(?:arm64|x86_64|universal))?\.dmg$/i;

export function countDownloads(releases: Release[], repository: string, now = new Date()): DownloadSnapshot | null {
  const assets = new Map<number, ReleaseAsset>();
  let downloadURL: string | null = null;
  const prefix = `https://github.com/${repository}/releases/download/`;
  const stable = releases.filter(r => !r.draft && !r.prerelease && r.published_at).sort((a, b) => Date.parse(b.published_at!) - Date.parse(a.published_at!));
  for (const release of stable) {
    for (const asset of release.assets ?? []) {
      if (!installerName.test(asset.name) || !asset.browser_download_url.startsWith(prefix) || !Number.isSafeInteger(asset.download_count) || asset.download_count < 0) continue;
      if (!downloadURL) downloadURL = asset.browser_download_url;
      assets.set(asset.id, asset);
    }
  }
  if (!downloadURL) return null;
  return { total: [...assets.values()].reduce((sum, a) => sum + a.download_count, 0), updatedAt: now.toISOString(), assetIDs: [...assets.keys()].sort((a,b) => a-b), downloadURL, ruleVersion: 1, stale: false };
}

export type ReleaseFetcher = (url: string) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;

export async function fetchDownloads(repository: string, fetcher: ReleaseFetcher, now = new Date()): Promise<DownloadSnapshot | null> {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) throw new Error('Invalid public repository');
  const all: Release[] = [];
  for (let page = 1; page <= 20; page++) {
    const response = await fetcher(`https://api.github.com/repos/${repository}/releases?per_page=100&page=${page}`);
    if (response.status === 404 && page === 1) return null;
    if (!response.ok) throw new Error(`Public release metadata unavailable (${response.status})`);
    const data: unknown = await response.json();
    if (!Array.isArray(data)) throw new Error('Invalid public release metadata');
    for (const release of data) {
      if (!release || typeof release !== 'object' || typeof release.id !== 'number' || !Array.isArray(release.assets)) throw new Error('Invalid release entry');
    }
    all.push(...data as Release[]);
    if (data.length < 100) return countDownloads(all, repository, now);
  }
  // Never display an incomplete historical count if the safety bound is reached.
  throw new Error('Release pagination limit reached');
}

export function createDownloadCache(ttl = 3_600_000, retryDelay = 60_000) {
  let snapshot: DownloadSnapshot | null = null;
  let validUntil = 0;
  let inFlight: Promise<DownloadSnapshot | null> | null = null;
  return async (load: () => Promise<DownloadSnapshot | null>, now = Date.now()) => {
    if (now < validUntil) return snapshot;
    if (inFlight) return inFlight;
    inFlight = (async () => {
      try { snapshot = await load(); validUntil = now + ttl; }
      catch { snapshot = snapshot ? { ...snapshot, stale: true } : null; validUntil = now + retryDelay; }
      finally { inFlight = null; }
      return snapshot;
    })();
    return inFlight;
  };
}
