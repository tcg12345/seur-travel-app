> **Legacy backend:** Seur now runs its backend entirely on Supabase. See [the current setup](../supabase/README.md). This folder is retained for migration reference and regression fixtures; the native app no longer needs a local Python server. The instructions below describe the earlier implementation.

# Aurum backend

A working Python WSGI backend for the native Aurum iOS app. It provides accounts, friend requests, group conversations, private cloud copies, read-only sharing with revocable links, Tripadvisor search/details, and AI recommendations/overviews. It does not require Amadeus.

## Run locally

The local server uses Python 3.11+ and its standard library, with no package installation needed:

```sh
cd backend
cp -n .env.example .env
python3 server.py
```

Or double-click `run.command`. The default address is `http://localhost:8787`. The Debug iOS app uses that address in Simulator. In **Travel → Account**, connect to the server and create a username/password. Accounts are separate from Apple IDs. Local planning and journaling do not require an account.

Put your existing keys into **backend/.env**, which is ignored by Git and excluded from distribution archives:

```dotenv
GOOGLE_PLACES_API_KEY=your-key
TRIPADVISOR_API_KEY=your-key
OPENAI_API_KEY=your-key
OPENAI_MODEL=gpt-5.4-mini
```

Restart the server after changing its environment. Keys remain server-side; the app receives only a connection-status flag. A configured flag means a key is present, not that its quota or permissions have been verified. Provider failures are reported explicitly. The AI adapter uses the Responses API with a JSON schema and does not store responses with OpenAI.

## Search without Amadeus

- Places autocomplete: Google Places API (New), proxied through the backend with short, rate-limited queries. Suggestions display Google Maps attribution without a map. Selecting a suggestion runs an independent Apple Maps lookup; saved contact details and coordinates on the native map come from Apple. Google prediction data is transient. Apple autocomplete is the fallback when Google is unavailable.
- Cities and airports: native Apple Maps local search, directly on iOS.
- Hotels, restaurants and attractions with available provider ratings/contact details: Tripadvisor Content API, through this backend. Tap a result to retrieve its details. Missing provider fields remain empty.
- Hotel overviews: AI summarizes supplied hotel facts. It does not invent amenities or awards.
- Activity ideas: Tripadvisor candidates are fetched first; AI can only select actual candidate IDs. Each idea opens the normal event editor before being added.
- Flights: the native search dialog opens live comparison in Google Flights and copies the selected search route into a booking-record editor. Airline, flight number, exact times, price and confirmation details are entered from the traveler’s booking. The app does not scrape flight results, hold seats, issue tickets or verify reservations.

## Deploy for physical iPhones and public links

Deploy the included Docker image behind HTTPS, attach persistent storage at `/data`, and configure the provider keys as host environment secrets. Set `PUBLIC_BASE_URL=https://your-real-backend-host` and put the same HTTPS address into the app’s Travel account screen. This repository has not been deployed to an internet host. A Simulator localhost URL is not a public share URL, and the API will not generate links until an HTTPS public base is configured.

```sh
docker build -t aurum-backend backend
docker run --env-file backend/.env -e AURUM_DATABASE=/data/aurum.sqlite3 -p 8787:8787 -v aurum-data:/data aurum-backend
```

The container uses Gunicorn; the standard-library development server is for local use. Configure your host’s TLS termination and request-size allowance (40 MB for photo-bearing journals). Disable access logging of `/s/` paths or redact their token segment because the path is a capability link. Gunicorn access logging is disabled by default here. The SQLite database is appropriate for a small deployment on one persistent host; it is not configured as a distributed database.

## Data behavior

Native documents are saved atomically in the app’s protected Application Support directory. **Save cloud copy** performs an explicit upload. Cloud downloads/imports create separate private copies. There is no silent background merge; the server rejects an older timestamp rather than overwriting a newer cloud document.

Server documents are owned by their creator. Accepted friends can see `friends` documents; signed-in readers can open a `public` trip if they have its ID; explicit direct/group sharing grants only those recipients access. Public browser links are unguessable, read-only and revocable. Switching to Private or revoking all access removes active links and direct grants. An already downloaded/imported copy cannot be withdrawn.

Hotel confirmation numbers, hotel booking notes and flight notes are excluded from shared responses/pages. Place notes and photos are intentionally included. Local export files include the full local booking records; the app explains this before sharing an export. JSON preserves photos; PDF renders them; TXT/CSV include photo counts.

Authentication uses salted scrypt password hashes and expiring opaque bearer tokens stored in the iOS Keychain. There is no email service/password-reset flow configured. Friend usernames are exact-match; no broad people directory is exposed. Direct conversations are reused, group members must be accepted friends, and conversation membership is checked for every message operation.

## Backups and tests

```sh
python3 backend/backup.py /path/to/new-backup.sqlite3
python3 -m unittest discover -s backend -p 'test_*.py' -v
```

The backup utility uses SQLite’s backup API, preserving committed WAL data. Restore a backup by stopping the server and replacing the configured database with the backup, then starting it again. Keep backup files private. Tests use temporary databases and mocked paid providers; they do not consume API credits or message real people.

## API outline

- `GET /v1/status`
- `POST /v1/auth/register`, `/login`, `/logout`; `GET /v1/me`
- `GET /v1/locations/autocomplete?q=`
- `GET /v1/places/search?q=&category=`; `GET /v1/places/{tripadvisorID}`
- `POST /v1/ai/activities`, `/v1/ai/hotel`
- `GET/POST /v1/friends`; `PUT/DELETE /v1/friends/{userID}`
- `GET /v1/documents`, `/v1/feed`; `GET/PUT/DELETE /v1/documents/{UUID}`
- `POST /v1/documents/{UUID}/link`, `/revoke`; anonymous `GET /s/{token}`
- `GET/POST /v1/conversations`; `GET/POST /v1/conversations/{UUID}/messages`

All JSON mutation endpoints require `application/json`. All routes except status, registration, login and explicit browser share links require a bearer session. Autocomplete also permits direct loopback development requests only when HOST is loopback and PUBLIC_BASE_URL is unset; public/remote deployments require a session. Autocomplete is limited to 60 requests per minute per account or local peer. Forwarding headers do not grant local access.

## Provider references

- [Google Places autocomplete](https://developers.google.com/maps/documentation/places/web-service/place-autocomplete) and [display policies](https://developers.google.com/maps/documentation/places/web-service/policies)
- [Apple MapKit local search](https://developer.apple.com/documentation/mapkit/mklocalsearch/request)
- [Tripadvisor search](https://tripadvisor-content-api.readme.io/reference/searchforlocations) and [location details](https://tripadvisor-content-api.readme.io/reference/getlocationdetails)
- [OpenAI Responses API](https://developers.openai.com/api/reference/cli/resources/responses/methods/create) and [structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs)

Provider data and photography remain subject to the account’s provider terms. The native UI retains source attribution and Tripadvisor rating imagery when supplied. Validate the live adapter against your enabled account before release; Google autocomplete has been exercised live with the supplied server credential. Other provider integrations remain unconfigured.


## Unified trip records

New records use `kind: "journey"`. Legacy `itinerary` and `trip` records remain accepted and keep every data field. All three types support routes, events, bookings and journal places together, optional routes/dates, and private/friends/public visibility. Shared web pages render both planning and journal sections; hotel confirmation numbers and booking notes remain redacted. Existing IDs and capability links are unchanged.

## Flight tracking

The native Map page connects through AeroAPI v4 with server-side `FLIGHTAWARE_API_KEY`. Set `FLIGHTAWARE_HISTORY_ENABLED=true` only when the account permits historical queries. Restart the server after configuration. The supplied key is configured only in the ignored local `.env`; a BA178 lookup through the restarted local backend succeeded on September 6, 2026 (local time). History remains disabled. Clones and deployments must configure their own server secrets.

- `GET /v1/flights/status?q=BA178&date=2026-09-06`
- `GET /v1/flights/history?q=BA178&date=2026-09-06`
- `GET /v1/flights/position?id=<provider-flight-id>`

These read endpoints require authentication outside direct loopback development, and are rate limited to 20 calls per minute per identity. Current status/positions cache for 60 seconds; history for one hour. Provider responses are normalized, no secret is returned, and unavailable fields are preserved as missing. History is an explicit, bounded sample rather than a complete record or prediction. Dates are matched to the origin airport's local departure day. Far-future requests do not consume provider calls.

See [WorldMap.md](../iOS/WorldMap.md) for account requirements, coverage and implemented boundaries. [FlightAware AeroAPI](https://www.flightaware.com/commercial/aeroapi/) defines pricing and permitted usage. Adapter tests use fixtures; current status has additionally been checked against the supplied account. Position, history entitlements and commercial-use permissions remain to be confirmed.
