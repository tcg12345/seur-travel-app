# Seur cloud backend

The production backend runs entirely on Supabase in **tcg12345's Org**.

- Project: **Seur** (`bwrodcxmdzrpyrshrlfd`), US East (Ohio).
- [Dashboard](https://supabase.com/dashboard/project/bwrodcxmdzrpyrshrlfd)
- API: `https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api`
- Postgres: trips, profiles, friendships, conversations, grants, link hashes, session hashes, limits and flight cache.
- Auth: password storage and verification. The existing username/password experience uses internal `@accounts.seur.invalid` identifiers; these are not real email addresses, and no email is sent. Email recovery is not enabled.
- Storage: private `journey-photos` bucket. Photos retain their original IDs and JPEG bytes on download.
- Edge Functions: all `/v1` API endpoints and `/s/` public share links.

## Native app connection

The native client defaults to the HTTPS Edge Function in both Debug and Release. Existing blank/localhost configurations automatically adopt this endpoint. The development override remains in Debug. No service credential is embedded in iOS.

Create an account in Travel → Your travel account, then use **Save cloud copy** in a trip's sharing controls. Local trips remain available offline. Cloud saves and imports are explicit, as before; this migration does not silently upload the device's private library. Cloud lists omit photo bytes, and opening/importing a trip fetches the full authorized record.

## Access model

Supabase Auth validates credentials. After sign-in, the Edge Function issues an opaque 30-day app session, storing only its SHA-256 hash in Postgres; the native app stores the token in Keychain. Logout immediately deletes that app session. Deleting an account removes its Supabase Auth identity, cloud records, sessions and current photos.

Private routes validate that session before accessing data. The gateway JWT check is disabled **because the function implements its own authentication**, allowing register/login, status and capability share URLs to have explicit public behavior. It is not an unauthenticated database proxy.

All app tables have RLS with explicit deny policies for `anon` and `authenticated`, no client grants, and server-only RPC grants. The service role is available only inside the function. Transactional RPCs enforce ownership, accepted friendships, group membership, grants, redaction, revocation and stale-write checks. Callers cannot choose their actor ID. Storage objects have no public or client read policy; the function checks journey access before loading photos.

Shared hotel confirmation numbers and booking notes are redacted. Public links contain random capability tokens; only their hashes are stored. Deleting/revoking a link or making a previously shared trip private removes access. Previously downloaded copies cannot be recalled.

## Public sharing on Supabase

Supabase's standard domains rewrite HTML responses as plain text. Public links therefore open an inline, read-only PDF hosted by the Edge Function, including plans, hotel/flight details, costs, journal ratings, photos and clickable map/website links. Add `?format=txt` for original UTF-8 text or `?format=json` for the complete shared record. The PDF also embeds the complete shared journey JSON. Its portable font has limited script coverage; UTF-8 downloads preserve all names exactly. Native in-app previews and imports retain full Unicode and photos.

A branded HTML sharing page would require a Supabase custom domain or a separate frontend host; neither has been purchased or deployed. The backend and current PDF links require neither.

## Providers and limits

Google Places and FlightAware credentials are configured as **Supabase Edge Function secrets** and have been verified with live requests. Flight history remains disabled pending account entitlement confirmation. OpenAI and Tripadvisor secrets are now detected by the deployed function. Live verification on September 7, 2026: OpenAI hotel overview returned HTTP 200 with a valid app response; Tripadvisor location search was rejected upstream with HTTP 403 (exposed as HTTP 502 by the adapter). Tripadvisor access is not yet verified: check the key’s domain/IP restrictions and endpoint access. Domain-restricted Tripadvisor keys require a matching HTTP Referer header, which the current adapter does not send. Activity recommendations depend on Tripadvisor candidates as well as OpenAI, so that combined flow remains blocked. Apple Maps discovery and the local concierge preview remain available.

Authenticated provider limits: autocomplete 60/minute per account, flights 20/minute per account with a 600/hour application cap, place search 30/minute and AI 10/hour per account. Auth and public routes have additional limits. These are application safeguards, not a provider billing guarantee.

Flight status/position cache lasts 60 seconds; historical results last one hour. Historical calls are opt-in; far-future flights return a saved-schedule explanation without an upstream lookup. Expired session/cache metadata is cleaned on sign-in. Successful trip saves remove superseded immutable photo objects and sweep up to 100 unreferenced objects older than one day. Request-time cleanup does not run while the app is completely idle.

## Deploy and verify

CLI used: Supabase 2.116.0. Deno tests use pinned runtime 2.9.6; PDF dependency 1.17.1 and a dependency lockfile are committed.

```sh
supabase link --project-ref bwrodcxmdzrpyrshrlfd
supabase db push --linked --skip-vault
supabase functions deploy travel-api --project-ref bwrodcxmdzrpyrshrlfd --use-api
npm exec --yes --package=deno@2.9.6 -- deno test --allow-env --config supabase/functions/travel-api/deno.json supabase/tests/contracts_test.ts
python3 supabase/tests/live_smoke.py
```

The live test creates temporary test accounts, shares only among them, and deletes those accounts in `finally`. Pass `--providers` to additionally make one live FlightAware and one Google Places lookup. The script saves a temporary shared PDF under `/tmp` for visual review.

Use `supabase secrets set --env-file <ignored-secret-file>` to configure provider credentials. Never commit passwords, service keys, provider keys or session tokens. `config.toml` contains local development defaults and function deployment settings; it is not a complete remote Auth configuration. Apply reviewed migrations before enabling GitHub production deployment.

## Migration evidence and rollback reference

The previous local SQLite database had zero users, cloud documents, friendships, conversations, messages or share links. A private snapshot is retained at ignored `backend/data/before-supabase.sqlite3`. There were therefore no existing backend accounts or cloud records to import. Device libraries are preserved and can be uploaded after the traveler signs in.

`backend/` is the legacy Python implementation and test reference. It is not used by the shipped native client or required to run Seur Cloud. See `iOS/Validation.md` for the current build, live integration and security checks.

## Standalone flights

`travel_flights` stores private flight records under a composite `(owner_id, id)` key, with cascading account deletion, RLS and server-only grants. The Edge Function derives the owner from the authenticated session for every read, upsert and deletion. `/v1/my-flights` lists the owner's flights; `/v1/my-flights/:id` supports PUT and DELETE. No trip is created or required.

New authenticated FlightAware routes: `/v1/flights/route` (origin, destination, local date), `/v1/flights/airport` (code) and `/v1/flights/airport-nearby` (selected airport coordinates). Lookups share existing provider rate limits; airport metadata is cached for 24 hours. Nearby airport normalization accepts both current and legacy FlightAware code fields. Route searches request one nonstop provider page and disclose their limited date window.

Run `python3 supabase/tests/flights_smoke.py --providers` for disposable-account ownership/CRUD tests and four bounded live provider queries. Verified September 7, 2026: one BA178 departure, two JFK–LHR route results, airport details and autocomplete resolution. Temporary users and their flights are deleted afterward.
