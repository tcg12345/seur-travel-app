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

For local cutover regression coverage without live accounts or provider requests:

```sh
npm exec --yes --package=deno@2.9.6 -- deno test --allow-env --allow-read=iOS/Aurum/Resources/TripTemplates.json --config supabase/functions/travel-api/deno.json supabase/tests/
```

`cutover_test.ts` exercises the actual Edge handler with mocked upstream responses: summary/detail photo contracts, denied access, unavailable photos, owner-scoped paginated deletion and cleanup retries. Account deletion enumerates the owner's private Storage folder, including abandoned uploads, and removes photos in batches before deleting Auth. A Storage failure leaves the account available to retry. Storage and Auth cannot share a transaction: an Auth failure after cleanup leaves the account active with those cloud photos already removed; retrying finishes deletion. Local iOS journeys are preserved.

The September 8 cutover hardening was deployed with budget support in `travel-api` version 32 (including `account-deletion.ts`); no new migration was needed. Deployed version 30 and all eleven migration versions matched this checkout's baseline during the read-only review. The existing `recap_cleanup_triggers` migration already avoids service-only DELETE trigger work during Auth's restricted-role cascade.

Use `supabase secrets set --env-file <ignored-secret-file>` to configure provider credentials. Never commit passwords, service keys, provider keys or session tokens. `config.toml` contains local development defaults and function deployment settings; it is not a complete remote Auth configuration. Apply reviewed migrations before enabling GitHub production deployment.

## Migration evidence and rollback reference

The previous local SQLite database had zero users, cloud documents, friendships, conversations, messages or share links. A private snapshot is retained at ignored `backend/data/before-supabase.sqlite3`. There were therefore no existing backend accounts or cloud records to import. Device libraries are preserved and can be uploaded after the traveler signs in.

`backend/` is the legacy Python implementation and test reference. It is not used by the shipped native client or required to run Seur Cloud. See `iOS/Validation.md` for the current build, live integration and security checks.

## Standalone flights

`travel_flights` stores private flight records under a composite `(owner_id, id)` key, with cascading account deletion, RLS and server-only grants. The Edge Function derives the owner from the authenticated session for every read, upsert and deletion. `/v1/my-flights` lists the owner's flights; `/v1/my-flights/:id` supports PUT and DELETE. No trip is created or required.

New authenticated FlightAware routes: `/v1/flights/route` (origin, destination, local date), `/v1/flights/airport` (code) and `/v1/flights/airport-nearby` (selected airport coordinates). Lookups share existing provider rate limits; airport metadata is cached for 24 hours. Nearby airport normalization accepts both current and legacy FlightAware code fields. Route searches request one nonstop provider page and disclose their limited date window.

Run `python3 supabase/tests/flights_smoke.py --providers` for disposable-account ownership/CRUD tests and four bounded live provider queries. Verified September 7, 2026: one BA178 departure, two JFK–LHR route results, airport details and autocomplete resolution. Temporary users and their flights are deleted afterward.

## Flight push monitoring

`/v1/flight-notifications` provides authenticated per-installation watch listing, registration, token refresh and removal. Live flight identity is validated against FlightAware before following. Device-token rotation preserves the existing Live Activity token. Registrations are tied to the originating session, and logout revokes them transactionally through a foreign-key cascade.

The `seur-flight-notifications` database cron runs every five minutes and skips Edge Function calls when no watches are due. Its internal worker endpoint requires an expiring, single-use database ticket. Work uses row-lock leases, shared flight lookups, bounded polling and an additional 120/hour provider limit. Tables have explicit deny policies for client roles and service-only grants. Secrets: `APNS_PRIVATE_KEY_B64`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`; never deploy a `.p8` file as function source. [Native setup and operating details](../iOS/AppleServices.md).

## Friends tab feed

`GET /v1/feed` now uses the service-only `travel_social_feed(actor)` RPC. It includes accepted friends’ friends/public itineraries and private itineraries explicitly granted to the current account. The actor comes from the authenticated Seur session. Existing document redaction, photo summaries, grants and revocation rules apply; unrelated public itineraries are excluded. No new client database grants or public profile directory are added. The extended live smoke test verifies private-share inclusion, third-party exclusion, redaction, direct-RPC access denial and removal after revocation.

## Budget, splits and daily currency rates

`GET /v1/exchange-rates` requires an authenticated Seur session. It uses a USD pivot and a shared daily cache in `travel_provider_cache`, with a 20/minute per-account limit and 100/hour upstream limit. Frankfurter v2 supplies reference rates without an API key. Responses include publication dates and a stale flag; an upstream failure can fall back to data fetched within seven days. iOS preserves original amounts and refuses partial combined totals when a required rate is missing.

Journey JSON now validates optional `budgetTarget`, `homeCurrency`, `companions`, event `isDone`, and cost `paidBy`, `splitBetween` and `isPaid`. Companion IDs are references within the owner-managed ledger, never authentication or authorization claims. Existing cloud ownership, stale-write, sharing and revocation rules remain in force. Templates retain optional estimated amounts only, stripping targets, completion and companion/payment fields. No schema migration is required.

Run the local Deno suite above for rate-cache and ledger validation tests. `python3 supabase/tests/budget_live.py` exercises authenticated rates, cache reuse, budget/split/photo persistence, malformed split rejection and account cleanup with one disposable account. It sends no messages and makes no paid-provider calls. [Native behavior](../iOS/TripBudget.md).

## Destination card photography

`GET /v1/cities/photo?city=Athens%2C%20Greece` is a guest-accessible route with one Wikimedia Commons API query for landmark imagery and reusable-image credits. The 12 catalog cities plus Athens have curated landmark targets and matching-title checks; Paris also has an exact curated file and is bundled on iOS for zero runtime requests. There are no Google calls or photo API keys. The app claims one attempt per trip on disk before requesting, then downloads the image file once and saves bytes and credits permanently in Application Support. Failures never retry. Unknown licenses and untrusted URLs fail closed. The route keeps 20/network/minute and 500/global/day limits and no-store HTTP responses. `/v1/status` advertises `cityPhotos: true`, so clients do not consume attempts before rollout. See [the native card guide](../iOS/TripCards.md) for the exact request counts and local-storage lifetime.

Production v34 includes the curated photo endpoint and guide routes, deployed September 9 after explicit user approval. All other existing dependency modules remain byte-identical to v33. The 68 backend tests and live status/New York photo/guide-read/auth-boundary checks passed. No photo migration was required.

## Traveler-created guides

The `20260909183248_travel_guides.sql` migration, applied remotely as `20260909200003`, adds publications, reports, and author blocks with service-role-only access. `travel-api` validates public content, enforces ownership/revisions, and serves public guide summaries, details and PDFs. Account deletion cascades through the author profile. `/v1/status` advertises `travelGuides` after rollout; local drafts work before deployment. See [the guide feature notes](../iOS/TravelGuides.md) for routes, local validation and moderation operations. Guide publishing is deployed in v34; the tables retain service-only access.

### Google destination photos

Updated iOS cards use guest `GET /v1/cities/google-photo?city=Paris` and the `googleCityPhotos` status flag. This uses the existing server-only `GOOGLE_PLACES_API_KEY`: one landmark Text Search, at most one Photo Media request, no photo-content cache, no retry, 20/network/minute and 500/global/day limits. Legacy `/v1/cities/photo` remains Commons for clients that persist photographs. No migration or new secret is needed. See [TripCards.md](../iOS/TripCards.md) for attribution, fallback and request lifetime.


## Pexels destination covers

The updated iOS app uses `/v1/cities/pexels-photo` for all destination cards. Configure `PEXELS_API_KEY` in Edge secrets; status exposes `pexelsCityPhotos`. Landmark-oriented landscape selection returns a 1200×675 rendition and linked photographer/Pexels attribution. Service-only 24-hour `travel_provider_cache` entries share city results and retain candidates for editorial review. Provider cache misses are capped at 180/hour and 500/day; endpoint reads at 30/network/minute. No migration is needed. Existing Google/Commons routes remain for older clients. Tests: `supabase/tests/pexels_city_photos_test.ts`.


## Sandbox hotel rates

`POST /v1/hotel-rates` uses the existing opaque app session and server-only `LITEAPI_SANDBOX_KEY`. It validates date-only stay criteria, room occupancy and child ages, guest nationality, currency and up to 20 hotel IDs. Requests share the existing two-per-second hotel provider cap and an additional ten-per-minute per-account cap. Only explicitly sandbox-marked rate responses are accepted. No new markup, schema or authentication configuration is introduced.

`POST /v1/hotel-quotes/inspect` validates a short-lived owner-bound encrypted quote without contacting the provider. It cannot create a reservation, initialize payment or reprice an offer. Quote expiry is five minutes; AES-GCM keys are domain-separated from the existing server credential. No provider offer tokens are written into public tables, saved trips or logs. Actual checkout must add its durable ledger and provider revalidation before payment.

Run the ordinary Deno suite for deterministic coverage. The separate explicit `python3 supabase/tests/hotel_rates_live.py --sandbox-rates` run creates two temporary accounts, makes five bounded rate searches, verifies quote isolation and removes its accounts. It never calls booking, prebook or payment endpoints. Aggregate results are stored under ignored `work/hotel-rates-validation.json`.

Hotel sandbox checkout adds owned `/v1/hotel-checkouts` create/list/detail/confirm routes, encrypted guest payloads, explicit versioned final intent and a minute cron worker. Only the `sand_` LiteAPI key and documented no-charge `ACC_CREDIT_CARD` simulation are permitted. The existing app-session middleware and gateway settings are unchanged. Tables/RPCs are server-only. Deploy migration `20260910172548_hotel_sandbox_checkouts.sql` before the function; the migration provisions the worker's one-use tickets and schedule.

Run `hotel_checkout_schema.sql` as a rolled-back administrative check. `python3 supabase/tests/hotel_checkout_live.py --sandbox-booking` explicitly requests one synthetic sandbox booking; it must not be used as routine CI. The September 10 live attempt exposed differing supplier room/meal/cancellation data and remains `needs_support`, so the complete live happy-path acceptance is unresolved. See `iOS/LiteAPISandboxQuestions.md`. Never bypass product matching to make a sandbox test appear successful.

### Hotel checkout history pagination

`GET /v1/hotel-checkouts` returns `{ checkouts, nextCursor }` with at most 30 records. Pass the returned opaque cursor as the URL-encoded `cursor` query parameter for the next page; null means the end. Each request is authenticated and owner-filtered. The cursor binds the precise creation timestamp and UUID tie-breaker to the account. Invalid, altered and cross-account cursors return 400 before the database query. Refresh without a cursor to see newly created records. The response is backward-compatible with clients that read only `checkouts`.

The native app preserves loaded pages on detail return and offers a retry for page failures. It displays that search/status/date filters apply to loaded records, until all retained history is loaded. The v50 deployment adds this read-only behavior without database migrations or changes to booking/payment capabilities.

### Saved traveler profiles

Migration `20260911120559_saved_traveler_profiles.sql` and travel-api v51 add private account profiles. Authenticated GET `/v1/travelers`, PUT `/v1/travelers/{uuid}` and DELETE `/v1/travelers/{uuid}` return `{profiles}`. Writes contain `expectedVersion` (0 for new), `isDefault`, `firstName`, `lastName`, `email`, international `phone` and ISO nationality; delete contains `expectedVersion`. Conflicting edits/deletes return 409. Up to 20 profiles per account; the first is default, changing default is serialized per account, and deleting it selects a remaining profile. Account deletion cascades profiles.

PII is stored only in AES-GCM ciphertext bound to the owner/profile with a traveler-specific authenticated context. The table/RPCs revoke anon/authenticated access and retain RLS; the API derives the actor from its existing app session. No provider credentials reach the client. Profile payloads reuse the checkout encryption helper: credential rotation must retain the old key long enough to re-encrypt existing profiles and checkout payloads. Responses use no-store, with per-account read/write limits of 60/20 per minute.

Tests: `travelers_test.ts`, the traveler routing regression in `cutover_test.ts`, and rolled-back `travelers_schema.sql`. Opt-in `python3 supabase/tests/travelers_live.py --saved-travelers` creates/deletes two temporary accounts and validates profile CRUD, defaults, conflicts and isolation. It makes no supplier, booking or payment requests.

### Explicit provider booking refresh

travel-api v52 adds POST `/v1/hotel-checkouts/{id}/sync`, backed by migration `20260912103919_hotel_booking_sync.sql`. It retrieves an already submitted sandbox booking by its stored provider ID; it never submits book/prebook/cancel. It verifies complete identity and, for confirmation, the accepted product. Conditional owner/state/updated_at writes reject stale results. Cancelled is terminal and distinct from refunded. Existing worker leases remain authoritative for in-progress attempts. Ordinary GET stays provider-free. The new refresh action is limited to once per record per 15 seconds, in addition to existing account/provider limits.

### Sandbox cancellation (v53)

Migration `20260912104954_hotel_sandbox_cancellation.sql` adds durable cancellation review/accept/claim operations to the existing sandbox ledger and worker wakeup. The new `hotel-cancellations.ts` handles fresh booking verification, versioned explicit intent, one PUT submission, GET-only recovery and charged-cancellation status. App routes are POST `/v1/hotel-checkouts/{id}/cancellation` and POST `/v1/hotel-checkouts/{id}/cancellation/confirm`. Confirmation accepts `{version, acceptTestCancellation:true}`. No real refund operation is implemented.

The migration and approved API bundle are deployed as `travel-api` v53. The `hotelSandboxCancellation` status flag controls the native entry point. Live route smoke checks passed; the temporary account was deleted. See `iOS/LiteAPICancellationDeployment.md` for deployment scope and verification. Tests: `hotel_cancellations_test.ts`, `hotel_cancellation_schema.sql`, native cancellation intent tests and two UI scenarios. The implementation did not submit actual supplier cancellations or bookings.
