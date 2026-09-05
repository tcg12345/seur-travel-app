import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {
  icons: { icon: '/favicon.svg' },
  title: 'Aurum — Exceptional stays. Remarkable tables.',
  description: 'Discover 1,513 hotels and their dining across 12 cities. Find your next stay, memorable meal, flight, and experience.',
};
export default function RootLayout({children}: Readonly<{children: React.ReactNode}>) {
  return <html lang="en"><body>{children}</body></html>;
}
