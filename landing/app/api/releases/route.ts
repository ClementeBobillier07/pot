import { createDownloadCache, fetchDownloads } from '@/lib/releases';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
const cached = createDownloadCache();

export async function GET() {
  const repository = process.env.POT_GITHUB_REPOSITORY || 'ClementeBobillier07/pot';
  const snapshot = await cached(() => fetchDownloads(repository, url => fetch(url, {
    headers: { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' },
    signal: AbortSignal.timeout(8_000), cache: 'no-store',
  })));
  return Response.json({ snapshot }, { headers: { 'Cache-Control': 'public, s-maxage=300, stale-while-revalidate=3600' } });
}
