# Places API cost controls

Destination/city fields immediately show matching cities from the existing Seur worldwide directory, then merge Apple Maps autocomplete after a 350 ms pause. Bare names such as London and Paris prioritize the major travel city; explicit regions such as London Ontario or Paris Texas do not receive that promotion. Exact city names precede longer names, equivalent directory/provider matches are deduplicated, and the merged list remains limited to five. Countries and time zones are local. City-guide/map discovery also uses Apple Maps. No Google request is triggered by typing, focus changes, Apple returning zero matches, or search errors.

For signed-in users with Google Places available, place/address fields offer **Try Google suggestions** after the Apple search settles and at least three characters have been entered. A tap makes one request; repeat taps for that active query are suppressed. Empty/failed Google searches retain available Apple matches and do not retry automatically. Selecting an Apple or Google suggestion still resolves its location using Apple Maps. Directory city selections use bundled coordinates, country codes and time-zone identifiers without a resolution request; they remain available offline and are labeled as Seur destinations. There are no Google Place Details/photo/review calls in this path.

`GoogleAutocompleteRequests` combines simultaneous requests with equivalent whitespace/case and the same server into one in-flight task. Invalid/short queries are discarded. Completed prediction responses are not cached to disk or reused across later requests. The request has a five-second timeout. This avoids the restricted prediction caching described in [Google's Places policies](https://developers.google.com/maps/documentation/places/web-service/policies).

The current flow ends with Apple resolution, not Google Place Details. Adding a session token alone would not create a completed Google billing session; [Google charges incomplete sessions per request](https://developers.google.com/maps/documentation/places/web-service/session-pricing). Do not add an extra paid Details call merely to terminate a session without evaluating its total cost and product need.

## Automated testing

- `--ui-testing` now defaults location autocomplete, city results and collection geolocation to fixtures. Existing `--location-testing` / `--city-testing` flags remain supported.
- Explicit Apple integration tests use `--ui-testing --live-apple-places`. This opts into Apple services only; it never enables Google.
- `TravelAPI.autocompletePlaces` rejects live requests whenever UI testing or XCTest is detected. The fallback button is hidden in these runs. There is no paid-test override.
- Google behavior tests inject closures with artificial results and count calls. They do not contact Google or the production autocomplete endpoint.
- Manual app testing retains normal Apple search; use the Google fallback only when deliberately checking it. That explicit action can be billable.

These protections apply to the updated app. Existing older clients and other consumers of the Google project are unaffected. For a project-wide backstop, set appropriate request quotas in Google Cloud and billing alerts; review [Google's usage and quota documentation](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing). No cloud quota or billing settings were changed here.


## Apple-first recommendations and optional Tripadvisor

Activity ideas first resolve the destination and search its region with native MapKit (one destination lookup and at most two regional searches). The app deduplicates and sends at most eight mapped candidates to the authenticated AI route. Supabase validates and sanitizes that shortlist, makes one OpenAI request, and returns only selected candidate IDs in the model’s suggested order. Empty results make no OpenAI request. No Google or Tripadvisor calls are made as part of this flow; the former Tripadvisor search plus up to five detail calls have been removed. Older clients without a shortlist receive an update-required response rather than triggering paid fallback searches.

Apple Maps Server API is not required for this native app flow, and no additional Apple credential is needed. If future jobs need to discover places without an active iPhone, add a separately authenticated server-side Apple search adapter then. Do not move working native searches to the backend merely to duplicate them.

Place, restaurant and hotel pages provide a secondary **Ratings & more details** link. Opening it makes one Tripadvisor name/city search; the user confirms the matching address before requesting one location detail. No detail request is made for every search result or map pin. Provider content lives only in that view and never overwrites saved Apple/collection records. Content is attributed with the official Tripadvisor logo, provider-supplied rating bubbles and a source link. No review/photo API endpoints are requested.

`TravelAPI` blocks live Tripadvisor and OpenAI calls during XCTest/UI tests as well as Google calls. Backend provider tests replace fetch with stubs and run without network permission. Manual bounded provider smoke checks are separate from automated app tests.

## AI concierge

Each submitted chat turn makes one OpenAI request, with at most one additional request after up to two native Apple Maps searches when place discovery is useful. General advice and follow-ups using existing results can finish in one request. No Google or Tripadvisor calls are used. Recent history is limited to twelve messages/24,000 characters; mapped candidates are limited to sixteen. Server limits are forty requests per account per hour and 1,000 per hour across the app, with at most 6,500 output tokens per request. Search errors still allow an explicitly unverified general-knowledge answer without paid place-provider fallbacks.

The automated concierge UI test opts into a deterministic `--concierge-testing` fixture together with `--ui-testing`; it never uses the live OpenAI key. The service-level paid-provider guard remains in force for all other automated tests. Stop cancels client work and prevents late messages; a provider request already underway may still incur cost.

For domain-restricted Tripadvisor keys, configure `TRIPADVISOR_REFERER` in Supabase with an HTTPS URL whose exact hostname is allowed in Tripadvisor (for example, `https://your-allowed-domain.example/`). The backend sends it only to Tripadvisor; it does not accept client-provided referring domains. See [Tripadvisor security](https://tripadvisor-content-api.readme.io/reference/api-security). Do not guess the allowed domain or remove key restrictions.

## Pexels destination covers (September 9 update)

All destination trip covers use Pexels, with no bundled/Google/Commons fallback in the updated app. One visible-trip request and image download are retained per installation; scroll, grid and relaunch reuse the saved image and credits. The Edge Function shares 24-hour city responses across trips and bounds Pexels cache misses to 180/hour and 500/day, with a single landscape search (up to 30 candidates) per miss. No pagination or secondary searches. See [TripCards.md](TripCards.md) for exact attempt, failure, selection and attribution behavior. User-provided journal photos and business/place details are unchanged.


## Supplied 16:9 destination catalog

The 300-destination supplied catalog now takes priority over saved Pexels images, with the separately supplied Tokyo photo still first for Tokyo. Matching usable local assets make zero photo calls and do not consume a Pexels attempt. Missing or unreadable assets and noncatalog locations retain the daytime Pexels fallback and its existing cache/rate limits. The app checks actual image availability, so a metadata match alone cannot suppress fallback. See `TripCards.md` for import size, attribution and matching details.
