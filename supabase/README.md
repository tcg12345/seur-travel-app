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

Google Places and FlightAware credentials are configured as **Supabase Edge Function secrets** and have been verified with live requests. Flight history remains disabled pending account entitlement confirmation. OpenAI and Tripadvisor secrets are detected by the deployed function. OpenAI hotel overview has passed a live request. Activity recommendations now use a bounded Apple Maps shortlist supplied by the native app; they no longer depend on Tripadvisor. Legacy requests without candidates return an update-required response.

Tripadvisor's most recent pre-change recheck returned upstream HTTP 403. The adapter supports an optional `TRIPADVISOR_REFERER` secret for domain-restricted keys; it must be a URL matching the hostname allowed in Tripadvisor’s credentials settings. Apple search continues independently. Place details are an explicit optional lookup, with user confirmation of the matching listing. See `iOS/PlacesCostControls.md` for the routing and cost policy.

Authenticated provider limits: autocomplete 60/minute per account, flights 20/minute per account with a 600/hour application cap, place search 30/minute, hotel/activity AI 10/hour per account, and concierge 40 requests/hour per account plus 1,000/hour application-wide. A concierge turn uses one request, or two when it requests Apple Maps lookups. Auth and public routes have additional limits. These are application safeguards, not a provider billing guarantee.

### Live AI concierge

`POST /v1/ai/concierge` uses the existing authenticated app session and server-only `OPENAI_API_KEY`. The model is `OPENAI_CONCIERGE_MODEL`, defaulting to `gpt-5.4-mini` independently of the older hotel/activity `OPENAI_MODEL` setting. Responses use strict structured output, medium reasoning effort, a 6,500-token output ceiling and `store: false`. The model generates the structured itinerary before its explanation to improve consistency between the saved draft and the reply. No additional key is required for native Apple Maps search.

The native app sends bounded recent conversation history, prior draft itineraries, the selected trip's schedule and enabled preference/saved-place context. It omits booking references, private booking notes, journal notes and photos. Map candidates are validated and stripped to supported fields. At most two Apple Maps searches and a single final AI call follow the initial response; no Google or Tripadvisor requests occur in this chat flow. Outputs contain readable advice, follow-up suggestions and an optional draft of up to fourteen days. Users review and save drafts into local Travel themselves; the model has no booking, payment, account mutation or cloud-save tools.

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
