import type { Metadata, Viewport } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Pot — A little plant on your Mac.',
  description: 'You code. It grows. A quiet, local-first macOS companion for Codex and Claude Code. Follow your tokens and their estimated API value.',
  robots: { index: false, follow: false },
  icons: { icon: '/icon.svg' },
};
export const viewport: Viewport = { themeColor: '#f7f7ee' };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
