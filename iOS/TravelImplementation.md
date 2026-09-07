# Travel implementation

## Scope
A native Travel dashboard with one Trips library. Every trip combines forward-looking plans and retrospective journaling under the same record. Preserve the existing hotel/dining catalog, saved restaurants, concierge, and legacy draft plans.

## Work
- [x] Versioned local documents, routes/dates/nights, events, hotel/flight records, rated places, mixed-currency totals and versioned import validation.
- [x] Native dashboard, itinerary editor, multi-city route editor, repeated-day event editor, day/calendar/map views, booking forms and searches.
- [x] Trip journal editor, category ratings, photos, stats, filters/list/grid/maps, itinerary and rated-restaurant imports.
- [x] PDF/TXT/CSV/JSON exports, JSON reload and system email/message sharing.
- [x] Backend authentication, ownership, friend requests, conversations/groups, shared documents, revocable read-only links and browser pages.
- [x] Apple Maps cities/airports/places, Google Flights handoff, Tripadvisor hotel/place details and AI recommendations/overviews through server-side credentials.
- [x] Native account/friends/chat/sharing and provider configuration/status screens.
- [x] Swift unit/UI tests, backend integration/security tests, visual review, simulator refresh and source archive.

## External configuration
No provider credentials or existing backend configuration were present at task start. User confirmed they have Tripadvisor and AI keys but no Amadeus account, and authorized building the backend without Amadeus. User has been asked where these are configured. Provider adapters are implemented with explicit configuration errors. Live provider acceptance and internet-accessible sharing remain pending credentials and a deployed HTTPS backend. Google Flights opens external live search; booking-record details are entered manually. No supplier booking or payment is performed.

## Trip add flow and Places search
The add chooser remains mounted while each selection opens its own native editor. Saving dismisses the editor and chooser in order; cancelling returns to the chooser. Hotels and flights appear first and inherit trip dates. Restaurant and activity are separate choices; all custom event types remain available. Legacy trips without routes receive a minimal destination/date step and resume the original add choice.

Google Places autocomplete is now configured on the local backend. Google suggestions are transient and attributed; selected queries are resolved independently with Apple Maps for saved location records and pins. The app falls back to native Apple suggestions if the backend is unavailable. Hotel, restaurant, activity, event-venue and airport coordinates participate in the trip map and persist with local records. No credentials are packaged in the app or source archives.

Existing dated trips without stops now prepare their route from the destination and dates already saved. Undated trips receive the minimal destination/date sheet and then continue into the original selected event editor. Existing IDs, journals and bookings are preserved.

## City discovery integration

Worldwide city guides feed Apple Maps places and catalog hotel dining into the existing event, hotel and rated-place editors through a stable nested presenter. The chooser supports all existing trips and creation, prefills place metadata, preserves coordinates, and resumes route preparation for older trips. The full feature and provider boundaries are documented in `CityExplorer.md`.

## Global map and flights

The Map tab connects worldwide discovery and existing trip records. Trip maps combine saved places, plans, hotel stays and airport locations; flight routes use valid coordinates and geodesic polylines. Flight detail views use the optional server-proxied AeroAPI connection for current status, positions and a bounded delay-history sample. Saved schedules remain usable without a provider.

The map's panel lives in the map view, behind the original fixed system tab bar. It appears already lowered on entry and expands through three positions. Continuous header drag state is local to the panel rather than the map; scrolling and editor sheets retain native controls. Saved collections remain accessible through the map's bookmark. See `WorldMap.md` for usage, configuration and boundaries.
