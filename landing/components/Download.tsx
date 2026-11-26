'use client';
import { useEffect, useState } from 'react';
import type { DownloadSnapshot } from '@/lib/releases';

// The hero and closing CTA share one public metadata request in this browser.
// No personal state is stored, and this is called only from client effects.
let publicDownloads: Promise<DownloadSnapshot | null> | undefined;
function loadPublicDownloads() {
  publicDownloads ??= fetch('/api/releases', { signal: AbortSignal.timeout(15_000) })
    .then(response => response.ok ? response.json() : null)
    .then(data => data?.snapshot ?? null)
    .catch(() => null);
  return publicDownloads;
}

export default function Download({ compact = false }: { compact?: boolean }) {
  const [snapshot, setSnapshot] = useState<DownloadSnapshot | null>(null);
  useEffect(() => {
    let mounted = true;
    loadPublicDownloads().then(value => { if (mounted) setSnapshot(value); });
    return () => { mounted = false; };
  }, []);
  return <div className={`download ${compact ? 'download-compact' : ''}`}>
    {snapshot ? <a className="button" href={snapshot.downloadURL}><Apple />Download for macOS</a> : <a className="button" href="#download"><Apple />Download for macOS</a>}
    {!compact && <p className="download-note" aria-live="polite">{snapshot ? <><span>{snapshot.total.toLocaleString('en-US')} installer downloads</span> · {snapshot.stale ? 'Last verified' : 'Updated'} {new Date(snapshot.updatedAt).toLocaleDateString('en-US')}<br />Downloads count files, not unique people.</> : <>Free. Local. A little more alive.<br /><span className="availability">For macOS 14 or later.</span></>}</p>}
  </div>;
}

function Apple() { return <svg aria-hidden="true" width="18" height="20" viewBox="0 0 20 24" fill="currentColor"><path d="M14 4c1-1.1 1.6-2.6 1.4-4-1.4.1-3 1-3.9 2.1C10.6 3 10 4.5 10.2 5.9 11.7 6 13 5.2 14 4ZM18.5 18.4c-.5 1.2-.8 1.7-1.5 2.8-1 1.4-2.3 3.2-3.9 3-1.5 0-1.9-1-3.9-1s-2.4 1-3.9 1c-1.6.1-2.8-1.5-3.8-3C-1.3 17.2-.7 11 1.3 8c1.4-2 3.5-3.2 5.5-3.2 1.7 0 2.8 1 4.2 1s2.2-1 4.1-1c1.7 0 3.5 1 4.8 2.4-4.2 2.3-3.5 8.4.6 10.1l-2 1.1Z" transform="scale(.85) translate(1 1)"/></svg> }
