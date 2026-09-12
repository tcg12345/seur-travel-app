# Vercel deployment

Deploy the Seur website as a single static application. The native app continues to call its existing Supabase API. The Python `backend/` directory is retained for reference and is not a Vercel service.

## Import settings

1. Import `tcg12345/seur-travel-app`, branch `main`, or refresh an import started before this configuration was pushed.
2. Select **Other** for Application/Framework Preset. If the import still shows **Services**, change it to **Other**; this project does not use Vercel's multi-service configuration.
3. Keep Root Directory at `./`.
4. The committed `vercel.json` supplies Install Command `npm ci`, Build Command `npm run build:vercel`, and Output Directory `dist/client`. Remove conflicting manual overrides if present.
5. No environment variables are needed. Do not copy LiteAPI or Supabase server credentials into this website project.
6. Deploy. Check `/`, `/collection`, and an unknown path after Vercel supplies the deployment URL.

## Build behavior

`build:vercel` sets `SEUR_BUILD_TARGET=vercel` and uses Vinext's static export. Both website routes are prerendered into `dist/client` with browser JavaScript, styles, images and catalog data. The 404 page is exported too. `cleanUrls` serves `collection.html` at `/collection`. Only the public client output is served; no server bundle is deployed.

The normal `npm run build` retains the Sites/Cloudflare plugin path. No dependencies, lockfile versions, native app configuration or Supabase deployments change. `.vercelignore` excludes native/backend sources and local environment/output files from upload. A future website feature requiring server-side requests, secrets or user sessions needs a separately designed server deployment; it cannot be added to this static export implicitly.

## Validation — September 12, 2026

The Vercel export prerendered all three generated routes with zero skips. Checked the root, collection and 404 HTML and every local script/link/image reference; all referenced files exist. Confirmed the hotel catalog is included and the public output contains no Python, Swift, SQL or environment files. The scoped web TypeScript check passed. The local renderer requires a temporary loopback listener, so it was run outside the restricted filesystem execution sandbox. This verifies the build artifact; an actual Vercel deployment is not claimed until its hosted URL is checked.

The existing Sites/Cloudflare build also passed after the configuration change.

Configuration follows [Vercel's framework/build/output settings](https://vercel.com/docs/project-configuration/vercel-json) and the installed Vinext static-export implementation. Selecting `framework: null` explicitly means **Other** and overrides framework autodetection.
