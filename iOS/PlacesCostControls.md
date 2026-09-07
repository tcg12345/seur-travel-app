# Places API cost controls

Normal typing uses Apple Maps autocomplete after a 350 ms pause. Countries and time zones are local. City-guide/map discovery also uses Apple Maps. No Google request is triggered by typing, focus changes, Apple returning zero matches, or search errors.

For signed-in users with Google Places available, place/address fields offer **Try Google suggestions** after the Apple search settles and at least three characters have been entered. A tap makes one request; repeat taps for that active query are suppressed. Empty/failed Google searches retain available Apple matches and do not retry automatically. Selecting a suggestion still resolves its location using Apple Maps. There are no Google Place Details/photo/review calls in this path.

`GoogleAutocompleteRequests` combines simultaneous requests with equivalent whitespace/case and the same server into one in-flight task. Invalid/short queries are discarded. Completed prediction responses are not cached to disk or reused across later requests. The request has a five-second timeout. This avoids the restricted prediction caching described in [Google's Places policies](https://developers.google.com/maps/documentation/places/web-service/policies).

The current flow ends with Apple resolution, not Google Place Details. Adding a session token alone would not create a completed Google billing session; [Google charges incomplete sessions per request](https://developers.google.com/maps/documentation/places/web-service/session-pricing). Do not add an extra paid Details call merely to terminate a session without evaluating its total cost and product need.

## Automated testing

- `--ui-testing` now defaults location autocomplete, city results and collection geolocation to fixtures. Existing `--location-testing` / `--city-testing` flags remain supported.
- Explicit Apple integration tests use `--ui-testing --live-apple-places`. This opts into Apple services only; it never enables Google.
- `TravelAPI.autocompletePlaces` rejects live requests whenever UI testing or XCTest is detected. The fallback button is hidden in these runs. There is no paid-test override.
- Google behavior tests inject closures with artificial results and count calls. They do not contact Google or the production autocomplete endpoint.
- Manual app testing retains normal Apple search; use the Google fallback only when deliberately checking it. That explicit action can be billable.

These protections apply to the updated app. Existing older clients and other consumers of the Google project are unaffected. For a project-wide backstop, set appropriate request quotas in Google Cloud and billing alerts; review [Google's usage and quota documentation](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing). No cloud quota or billing settings were changed here.
