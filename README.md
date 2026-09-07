# Aurum

The native **iOS 26 SwiftUI app** is now in [`iOS/`](iOS/README.md). Open `iOS/Aurum.xcodeproj` in Xcode. It uses Apple Liquid Glass, native zoom navigation, haptic feedback, and the bundled hotel/dining catalog.

The native app includes unified trip planning and journals, worldwide city discovery, a globe with trip and flight routes, and optional live FlightAware tracking. The [Python backend](backend/README.md) supports accounts, friends, cloud sharing and server-side provider integrations. Keys and local databases are excluded from Git; configure your own server environment from `backend/.env.example`.

The user wants to continue developing native flight booking with detailed cabin comparisons and seat photos. The agreed direction, provider candidates and next steps are saved in the [flight booking roadmap](iOS/FlightBookingRoadmap.md). Real ticketing and subscription payments are not enabled.

See [iOS validation](iOS/Validation.md) for build and test evidence. The earlier web version is retained below as a separate implementation; the following features and boundaries describe that web version.

## Earlier web app

A responsive luxury travel discovery app centered on hotel dining. Built with React, Vinext, TypeScript, and the Sites runtime.

## Included

- 1,513 imported hotel records and 5,755 dining entries across 12 cities.
- City, hotel, venue, and cuisine search; destination filters and dining-count sorting.
- Hotel detail sheets with the original descriptions, dining venues, price bands, source links, and official hotel booking links where supplied.
- Side-by-side dining comparisons for up to three hotels.
- Device-local saved hotels, draft itineraries, removal, and text export.
- Validated flight route/date/cabin search handoff to Google Flights.
- Destination-specific activity search handoff to GetYourGuide.
- Responsive mobile navigation and accessible Base UI dialogs, sheets, tabs, selects, checkboxes, and tables.

## Boundaries

This is a working discovery and planning app, not a reservation engine. There is no live inventory, payment collection, account synchronization, native iOS package, or in-app booking confirmation. Reservations are completed with external providers. Date selection is used for draft planning and flight queries; it does not filter hotel inventory. Provider sites require final review of dates, passengers, and availability. Experience cards are search categories, not confirmed inventory.

The hotel dataset is reproduced as provided. Awards, open/closed status, price bands, and venue details have not been independently reverified. Missing official URLs are shown without a booking action. Photos are provided for the three featured hotels; other cards explicitly indicate unavailable photography rather than depicting a different property.

Saved places and plans use browser localStorage, with in-memory fallback when unavailable. They remain only on that browser/device. Do not enter sensitive traveler information.

## Development

`npm install`, then `npm run dev`. In Codex on macOS, use `CODEX_SANDBOX=seatbelt npm run dev -- --host 127.0.0.1` for polling. `npm run build` creates the Cloudflare Worker deployment. `npx tsc --noEmit` checks types.

## Data import

CSV columns were parsed by position to preserve the two distinct `price_band` columns (hotel and venue). Hotels are grouped by `hotel_id`, and exact duplicate venue objects are excluded. All 5,755 rows were retained.

## Photography sources

- Mandarin Oriental Bangkok: https://www.wbpstars.com/hotel/mandarin-oriental-bangkok/
- The Peninsula Paris: https://www.polycor.com/fr/projets-fr/palace-peninsula-paris/
- The Savoy: https://www.architecturaldigest.in/content/8-worlds-iconic-hotels/

Images belong to their respective owners; no open reuse licenses were supplied. Review image rights before wider commercial distribution.

## Agent integration

Feature-detected read-only WebMCP `search_hotel_catalog` exposes the same catalog search function as the UI. Unsupported browsers continue normally. No supported WebMCP execution context was available during implementation, so runtime tool registration was not independently verified.
