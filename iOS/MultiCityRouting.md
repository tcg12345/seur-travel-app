# Multi-city route planning

Open **Travel → a trip → Plan your route** when it has at least two stops. A single-stop trip offers **Add another destination** in the same place. The trip editor also has **Plan multi-city route**; changes there stay in the editor draft until the trip is saved.

The planner suggests an order, compares distance and total transfer allowances with the current trip, and offers drag handles plus accessible Move earlier/later controls. Choose less backtracking or less travel time, keep the first/last stop fixed, prefer rail when it is within 90 minutes of the fastest estimate, and optionally include an origin city and a return home. Missing coordinates require choosing a city search result; city names alone are never silently geocoded to an assumed location. Suggestions are computed off the main thread and discarded if their input changes while running.

## Estimates and scope

Routing is local and makes no paid provider requests. Up to eleven stops use an exact dynamic-programming solution for the selected objective and endpoints. Longer routes use bounded multi-start nearest-neighbor and segment reversal; they never replace the current order with a worse one and are explicitly described as heuristic suggestions. Distance is great-circle distance between cities, not rail track or flight-path length. Time optimization uses selected transfer allowances, accounting for reserved additional days.

Rail baselines are available for a set of operator-documented corridors, with connected journeys composed from those corridors and 45 minutes per connection. These are typical planning values, not dated departures or ticket availability. Station allowances are 45 minutes, or 90 minutes on the included London Eurostar legs. Operator figures were checked September 7, 2026:

- Copenhagen–Stockholm: roughly six hours; the baseline allows 375 minutes. [DSB](https://www.dsb.dk/find-produkter-og-services/dsb-udland/sverige/stockholm/)
- Stockholm–Oslo: under six hours; the baseline allows 330 minutes. [SJ](https://www.sj.no/en/highspeed/)
- Copenhagen–Hamburg: 275 minutes. [DSB](https://www.dsb.dk/find-produkter-og-services/dsb-udland/tyskland/hamborg/)
- Copenhagen–Gothenburg: 193 minutes. [DSB](https://www.dsb.dk/find-produkter-og-services/dsb-udland/sverige/goteborg/)
- Gothenburg–Oslo: 210 minutes. [Vy](https://www.vy.no/en/train/oslo-gothenburg)
- London–Paris: 136 minutes. [Eurostar](https://www.eurostar.com/uk-en/train/london-to-paris)
- London–Brussels: 113 minutes. [Eurostar](https://www.eurostar.com/be-en/train/london-to-brussels)
- Paris–Brussels: 82 minutes. [Eurostar](https://www.eurostar.com/be-en/train/paris-to-brussels)
- Brussels–Amsterdam: 112 minutes. [Eurostar](https://www.eurostar.com/fr-fr/train/bruxelles-amsterdam)

Flight baselines use distance / 750 km/h plus 40 minutes, rounded to five minutes with a 50-minute minimum, then add three hours for airport/ground-transfer time. This does **not** establish that a direct flight exists. Connections, available departures and date-line changes must be checked. Very short legs receive a labeled local-transfer allowance instead. Unsupported rail routes do not receive invented train times: the user can check Apple Maps transit services and enter a total allowance. Flight search and operator links open only when tapped.

Every leg supports a manual mode, total minutes and additional travel days. These overrides belong to the directed pair of city IDs, so they do not incorrectly carry across a changed leg. The UI labels model estimates, operator baselines and user allowances distinctly.

## Applying a route

Nothing changes until **Use this route**. Stop IDs and nights are retained; date-based routes reflow from the original first destination arrival. Additional transfer days shift later arrivals, while home-leg overnight allowances extend overall departure/return dates. Flexible trips remain relative. Activities stay attached to their city and local day. Hotels, flight reservations and journal records retain their existing dates/data; the preview tells the user to review bookings and timed activities when the route changes.

Optional generated transfer events reserve departure-day time, or arrival-day time for an outbound home leg. Longer transfers are all-day blocks. The 09:00 time is explicitly a planning placeholder. Notes include allowances and, for dated trips, the departure/arrival dates. Generated events have stable event, series and place identifiers; reapplying replaces only planner-owned blocks and does not create duplicates. Disabling the option removes only those generated blocks. Editing destinations directly in the trip editor clears the old generated route plan and blocks so they cannot remain attached to an obsolete route.

Route preferences and transfer metadata are optional Codable fields in the existing trip document. Existing archives decode without them. No schema migration, new secret, or backend deployment is required; the cloud document contract accepts the metadata and the existing transfer/train event types. Local persistence and share/export continue through the existing trip paths.
