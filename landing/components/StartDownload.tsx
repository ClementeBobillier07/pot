'use client';
import { useEffect, useState } from 'react';
import { loadPublicDownloads } from '@/components/Download';

const LATEST = 'https://github.com/ClementeBobillier07/pot/releases/latest';

/** Starts the real installer download from GitHub Releases. Runs only in a browser with JavaScript,
 *  so link previews and crawlers neither download the DMG nor inflate the counter. */
export default function StartDownload() {
  const [url, setURL] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    loadPublicDownloads().then(snapshot => {
      if (!snapshot) { setFailed(true); return; }
      setURL(snapshot.downloadURL);
      // A short pause lets the page view be recorded before the browser starts the file transfer.
      timer = setTimeout(() => { window.location.href = snapshot.downloadURL; }, 700);
    });
    return () => clearTimeout(timer);
  }, []);
  if (failed) return <p className="download-status">We couldn’t reach GitHub just now. <a href={LATEST}>Download Pot from GitHub Releases</a>.</p>;
  return <p className="download-status" aria-live="polite">
    {url ? <>Not starting? <a href={url}>Download Pot directly</a>.</> : 'Preparing your download…'}
    <noscript> <a href={LATEST}>Download Pot from GitHub Releases</a>.</noscript>
  </p>;
}
