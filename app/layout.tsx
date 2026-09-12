import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {
  icons: { icon: '/landing/app-icon.png', apple: '/landing/app-icon.png' },
  title: 'Seur — Go somewhere. Feel everything.',
  description: 'Your places, plans, and favorite moments. Together in one beautiful travel app. Discover Seur, coming soon for iPhone.',
};
export default function RootLayout({children}: Readonly<{children: React.ReactNode}>) {
  return <html lang="en"><body>{children}</body></html>;
}
