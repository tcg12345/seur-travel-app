import type { NextConfig } from 'next';

const nextConfig: NextConfig = process.env.SEUR_BUILD_TARGET === 'vercel'
  ? { output: 'export' }
  : {};

export default nextConfig;
