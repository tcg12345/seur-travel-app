# Your world — Map

Map replaces the Saved tab. The globe connects worldwide city discovery, saved trips, and flight booking records. The bookmark at the top opens all existing saved collections.

## Using the map

- Spin and zoom the native Apple Maps globe. The display menu switches between satellite globe and standard map, or resets the camera.
- Explore: search any city, open its guide, choose an interest, or search around the current map center. Found places can be saved or added to an existing trip.
- Trips: choose a trip to see its mapped destinations, plans, hotel stays, airports and journal places. Open the full trip from its card.
- Flights: view saved flights and their direct great-circle airport routes, then tap a card or airport marker for details. Lines represent planned routes, not actual tracks. Invalid or missing coordinates are never replaced by invented positions.
- The persistent map panel floats with 12-point side margins when compact, then its background widens continuously to both edges as it rises. The content width and expanded scroll layout stay fixed during dragging; only the visible portion changes. This avoids relaying out long flight details on every frame. The standard material extends behind the original system tab bar. Dragging the header or collapsed content adjusts the sheet; expanded content scrolls normally and a downward pull at the top lowers it. The panel cannot be dismissed. Explore / Trips / Flights share the same panel and map instance, and panel movement does not change the MapKit viewport. Only settling into a detent uses a spring; active dragging follows the finger directly.

## Add a flight directly

Use **Flights → +** on the map. The native modal starts with airline autocomplete (name or code), flight number and local departure date. Route search accepts airport codes or airport autocomplete, resolving the selected airport to a FlightAware code. Any valid IATA/ICAO airline code can be entered even when absent from the suggestion catalog.

Choose a returned departure to review its airline, airports, scheduled airport-local dates/times, price, booking link and notes before saving. A Back action returns to search. Manual entry supports later bookings and unreported schedules; live estimates never replace the booked schedule. Selected result airports are resolved before review so saved flights draw routes immediately.

Standalone flights are private records in Supabase, independent of trip documents. Signed-in users can reload, edit and remove them from the map. They appear alongside flights already attached to trips. Guests get an in-flow sign-in entry point. Tracking and cloud storage need a connection; trip-local booking records still retain their existing offline behavior.

Route lookup covers local dates from eight days ago through tomorrow, with one provider page of nonstop departures. Search by flight number when a departure is missing. Later dates offer manual entry. FlightAware controls coverage; this is tracking and schedule entry, not ticket purchase.

## Flight information

Saved schedules and booking details work without a provider. The connected view supports scheduled, estimated and actual departure/arrival times; delays; cancellation/diversion status; gates and terminals; baggage claim; aircraft type and registration; a requested aircraft position; and a recent completed-flight delay sample. Missing provider fields stay unavailable. Airport times use their local time zones.

Status refreshes every 90 seconds while the flight detail view is active in the foreground, with a manual refresh button. Position and history load on request. The backend caches status/position for 60 seconds and history for an hour. Cache timestamps reflect the actual provider fetch. Multiple departures returned for the same flight number require selecting the correct leg.

### Cloud connection

The supplied FlightAware key is deployed as a Supabase Edge Function secret. Both Debug and Release apps default to Seur Cloud over HTTPS; no local server or manual URL is required. Sign in under Travel → Account to use authenticated live flight requests.

A live BA178 status lookup through Supabase succeeded on September 7, 2026, returning a real flight record. History remains disabled pending confirmation of account entitlements; live position and historical coverage have not been verified. Enable `FLIGHTAWARE_HISTORY_ENABLED=true` in Supabase secrets only when the account supports historical queries. Provider credentials must remain on the server.

Development UI fixtures are explicitly labeled and only enabled by paired UI-test flags; normal launches and Release builds do not show them. See `../supabase/README.md` for deployment, limits and credentials.

As checked September 6, 2026, AeroAPI Personal is limited to personal/academic use. Standard supports commercial consumer apps and historical data with a $100 monthly minimum and usage-based pricing. Premium lists Foresight predictive arrivals and a $1,000 monthly minimum and usage-based pricing. Confirm the current terms with [FlightAware AeroAPI](https://www.flightaware.com/commercial/aeroapi/) before subscribing; no plan has been purchased.

### Scope and limits

- Recent status queries cover the provider's near-term window. Far-future bookings retain saved schedules. Older dates and history need the appropriate entitlement.
- History is a bounded sample from one provider page over up to seven preceding days, filtered to the selected route. Its on-time percentage is descriptive, not a delay prediction or complete lifetime history.
- Provider-reported positions can be unavailable or stale; their timestamps are displayed. The app does not animate a guessed aircraft position.
- This integration does not reproduce Flighty's proprietary predictions, monitor inbound aircraft chains, or implement background alerts, APNs or ActivityKit Live Activities. Those need additional implementation and appropriate provider/push services.
- Maps require network access for imagery and discovery. Device performance and provider coverage vary.

## Flight detail organization

The flight detail sheet uses wide sections with 12-point outer margins: current status/refresh, departure, arrival, tracking/alerts, and expandable additional information. Each section uses one shared adaptive surface; gates and terminals are unboxed within their airport section.

Punctuality is evaluated independently for departure and arrival. Actual timestamps take precedence over estimates, then reported delay seconds provide a fallback. Green means on time, blue early, amber late/diverted, red cancelled, and neutral means timing is not confirmed. Text and symbols repeat the meaning so color is never the only cue. Before departure the status accent accounts for either endpoint’s delay; after departure it follows arrival timing. The saved countdown remains explicitly labeled as scheduled.
