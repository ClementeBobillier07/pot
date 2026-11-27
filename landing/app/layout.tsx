import type { Metadata, Viewport } from 'next';
import { Analytics } from '@vercel/analytics/next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Pot — A little plant on your Mac.',
  description: 'You code. It grows. A quiet, local-first macOS companion for Codex and Claude Code. Follow your tokens and their estimated API value.',
  metadataBase: new URL('https://agentpots.com'),
  alternates: { canonical: '/' },
  openGraph: {
    type: 'website', url: '/', siteName: 'Pot', locale: 'en_US',
    title: 'Pot — A little plant on your Mac.',
    description: 'You code. It grows. A free, local macOS companion that turns your Codex and Claude Code work into a living plant.',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Pot — A little plant on your Mac.',
    description: 'You code. It grows. A free, local macOS companion for Codex and Claude Code.',
  },
  icons: { icon: '/icon.svg' },
};
export const viewport: Viewport = { themeColor: '#f7f7ee' };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  // Cookieless, aggregated Vercel Web Analytics (decision 32): pages, referrers, countries, devices.
  return <html lang="en"><body>{children}<Analytics /></body></html>;
}
