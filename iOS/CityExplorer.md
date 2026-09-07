# Worldwide city exploration

Open **Discover → Explore a city**, use the city shortcut in Search, or revisit a saved city in **Saved → Your city collection**. City lookup uses live Apple Maps autocomplete, without a fixed city list. The twelve catalog cities are optional shortcuts, not a search boundary.

Each city has its own guide with an overview, live search, thirteen interests, list/map views, distance/name sorting, website and saved-place filters, and a wider-area option. Interests cover restaurants, attractions, museums, parks, cafés, nightlife, shopping, entertainment, wellness, beaches, landmarks and hotels. Search a specific place or a phrase such as “art galleries” within the selected city. Pull to refresh; errors have a retry action and empty results offer a wider search.

## Hotel dining

Matching catalog cities put the Aurum dining collection before live results. The complete supplied restaurant/venue data is browsable by venue, hotel and cuisine, including source descriptions, price bands and hotel context. City matching checks both name and geography, so Paris, Texas does not inherit Paris, France’s restaurants. Bookmarking a catalog venue stays synchronized with existing restaurant favorites.

The CSV has no restaurant coordinates. Opening or adding a collection venue attempts to independently resolve its exact hotel name with Apple Maps. A successful pin identifies the hotel address. An unresolved address remains visibly unmapped, with a Maps search available; no coordinates or ratings are invented.

## From discovery to trip

Every place offers Save and Add to trip. The chooser lists existing trips, prioritizes matching destinations, and supports searching the library or creating a trip.

- **Plan a visit:** opens the existing event editor with the selected place, coordinates and contact details. Choose day(s), time, duration, price and notes.
- **Hotel stay:** hotel discoveries open the stay editor with dates and booking fields.
- **Log a visit:** opens the journal editor for ratings, category scores, notes, photos and visit details. An existing journal entry for the same provider/place is edited rather than duplicated.

Saving returns to the place detail or discovery list. Cancelling leaves the current selection intact. Located records participate in the trip’s map and existing exports, totals and sharing. Existing trips without a planning route use their saved destination/dates, or receive the normal minimal destination step before the chosen event editor resumes.

Cities, recent searches and bookmarked places persist locally. Bookmarks are independent of trip records: removing a bookmark does not delete a scheduled visit. A city’s saved filter includes bookmarked CSV venues as well as live discoveries.

## Providers and limits

MapKit supplies live places, addresses, coordinates, phone numbers and websites when available. No Amadeus key, account, backend, or location permission is required for city exploration. Availability depends on Apple Maps coverage and connectivity; searches return a provider-ranked set, not an exhaustive inventory. The category and free-text tools refine that set. The supplied CSV is available offline.

Bookings, opening hours, prices and availability must be confirmed with the venue. Unavailable public ratings, imagery, reviews and hours are not fabricated. Existing backend sharing and AI setup boundaries remain unchanged. New discovery preferences are local; trip records can use the existing explicit cloud-sharing workflow.

## Implementation

`Explore/CityExploreModels.swift` contains city/interest/place models and the MapKit service. The observable loader debounces typing, rejects stale responses, deduplicates places, caches successful searches in a bounded in-memory cache, and isolates per-category failures. MapKit’s no-match error is treated as an empty result. Short category queries and a required geographic region keep searches scoped to the selected city.

`Explore/CityExploreViews.swift` contains discovery, city guides, dining collection, place details, saved collection and add-to-trip screens. Presenters own their sheets at stable NavigationStack/root views, preserving the previous secondary search-popup fix. Native Liquid Glass controls, serif typography, warm surfaces and system navigation match Aurum’s existing design.

DEBUG fixtures require both `--ui-testing` and `--city-testing`; Release builds always use MapKit. UI tests use isolated storage and a temporary simulator.
