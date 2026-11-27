import type { Metadata } from 'next';
import StartDownload from '@/components/StartDownload';

export const metadata: Metadata = {
  title: 'Downloading Pot',
  description: 'Your download of Pot for macOS is starting.',
  // A transit page: keep it out of search results and point engines at the home page.
  robots: { index: false, follow: true },
  alternates: { canonical: '/' },
};

/** Every "Download for macOS" button lands here. Its page view, counted by cookieless Vercel Web
 *  Analytics, is how downloads are measured (country, referrer, device), without identifying anyone. */
export default function DownloadPage() {
  return <main id="main" className="download-page wrap">
    <a className="wordmark" href="/" aria-label="Pot home">pot<span className="brand-period">.</span></a>
    <section className="download-start" aria-labelledby="download-title">
      <span className="eyebrow">Something good is taking root</span>
      <h1 id="download-title">Your download<br/>is <em>starting.</em></h1>
      <StartDownload />
      <ol className="install-steps">
        <li><strong>Open</strong> the downloaded <code>Pot-…-macOS-universal.dmg</code>.</li>
        <li><strong>Drag Pot</strong> into the <strong>Applications</strong> folder.</li>
        <li><strong>Open Pot</strong> from Applications and plant your first seed. From then on it updates itself.</li>
      </ol>
      <p className="download-note">Free. Signed and notarized by Apple. <span className="availability">For macOS 14 or later.</span></p>
    </section>
  </main>;
}
