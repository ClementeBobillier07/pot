'use client';
import { useEffect, useState } from 'react';
import type { DownloadSnapshot } from '@/lib/releases';
import { treeProgress } from '@/lib/trees';

// The hero and closing CTA share one public metadata request in this browser.
// No personal state is stored, and this is called only from client effects.
let publicDownloads: Promise<DownloadSnapshot | null> | undefined;
export function loadPublicDownloads() {
  publicDownloads ??= fetch('/api/releases', { signal: AbortSignal.timeout(15_000) })
    .then(response => response.ok ? response.json() : null)
    .then(data => data?.snapshot ?? null)
    .catch(() => null);
  return publicDownloads;
}

export default function Download({ compact = false }: { compact?: boolean }) {
  const [snapshot, setSnapshot] = useState<DownloadSnapshot | null>(null);
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    let mounted = true;
    loadPublicDownloads().then(value => { if (mounted) { setSnapshot(value); setLoaded(true); } });
    return () => { mounted = false; };
  }, []);
  return <div className={`download ${compact ? 'download-compact' : ''}`}>
    <a className="button" href={snapshot ? '/download' : '#download'}><Apple />Download for macOS</a>
    <DownloadCounter snapshot={snapshot} loaded={loaded} />
    {!compact && <p className="download-note">Free. Local. A little more alive. <span className="availability">For macOS 14 or later.</span></p>}
  </div>;
}

/** Real installer downloads from GitHub Releases. Never an invented number: before the first release it says so. */
function DownloadCounter({ snapshot, loaded }: { snapshot: DownloadSnapshot | null; loaded: boolean }) {
  const total = useCountUp(snapshot?.total ?? 0);
  const trees = snapshot ? treeProgress(snapshot.total) : null;
  if (!loaded) return <p className="download-counter is-loading" aria-hidden="true"><Sprout /><span>&nbsp;</span></p>;
  if (!snapshot) return <p className="download-counter"><Sprout /><span>The counter starts with the first release.</span></p>;
  const updated = new Date(snapshot.updatedAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  return <p className="download-counter" aria-live="polite" title={`Installer files downloaded from GitHub Releases, not unique people. ${snapshot.stale ? 'Last verified' : 'Updated'} ${updated}.`}>
    <Sprout />
    <span><strong>{total.toLocaleString('en-US')}</strong> {snapshot.total === 1 ? 'download' : 'downloads'}{snapshot.stale ? <span className="counter-stale"> · last verified {updated}</span> : null}</span>
    {trees && <span className="counter-trees"> · {trees.trees.toLocaleString('en-US')} {trees.trees === 1 ? 'tree' : 'trees'} planted · next in {trees.toNext.toLocaleString('en-US')}</span>}
  </p>;
}

/** A short count-up when the number arrives; instant with reduced motion. */
function useCountUp(target: number) {
  const [value, setValue] = useState(0);
  useEffect(() => {
    if (target <= 0 || typeof window === 'undefined' || window.matchMedia('(prefers-reduced-motion: reduce)').matches) { setValue(target); return; }
    let frame = 0; const start = performance.now(); const duration = 900;
    const step = (now: number) => {
      const t = Math.min(1, (now - start) / duration);
      setValue(Math.round(target * (1 - Math.pow(1 - t, 3))));
      if (t < 1) frame = requestAnimationFrame(step);
    };
    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
  }, [target]);
  return value;
}

function Sprout() { return <svg className="counter-sprout" aria-hidden="true" viewBox="0 0 32 32" fill="none"><path d="M16 28V13" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round"/><path d="M16 20C5 21 4 8 16 15M17 14C17 3 30 5 17 16" fill="currentColor"/></svg>; }

function Apple() { return <svg aria-hidden="true" width="18" height="20" viewBox="0 0 20 24" fill="currentColor"><path d="M14 4c1-1.1 1.6-2.6 1.4-4-1.4.1-3 1-3.9 2.1C10.6 3 10 4.5 10.2 5.9 11.7 6 13 5.2 14 4ZM18.5 18.4c-.5 1.2-.8 1.7-1.5 2.8-1 1.4-2.3 3.2-3.9 3-1.5 0-1.9-1-3.9-1s-2.4 1-3.9 1c-1.6.1-2.8-1.5-3.8-3C-1.3 17.2-.7 11 1.3 8c1.4-2 3.5-3.2 5.5-3.2 1.7 0 2.8 1 4.2 1s2.2-1 4.1-1c1.7 0 3.5 1 4.8 2.4-4.2 2.3-3.5 8.4.6 10.1l-2 1.1Z" transform="scale(.85) translate(1 1)"/></svg> }
