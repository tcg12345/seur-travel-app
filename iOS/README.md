# Seur for iOS

A native SwiftUI travel app for **iOS 26 and later**, designed around hotel dining and the supplied Aurum iOS reference. This is an Xcode iOS application, not a website or WebView wrapper.

## Open and run

1. Open `Aurum.xcodeproj` in Xcode 26 or later.
2. Choose the **Aurum** scheme and an iPhone running iOS 26+.
3. Press Run.

The app works in Simulator without an Apple developer account. To install on your physical iPhone, choose your Apple development team under **Aurum → Signing & Capabilities**, then select your connected iPhone. TestFlight and App Store distribution require signing and provisioning through your Apple Developer account.

Simulator builds used for account testing and installation must retain code signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`) so the app has its application identifier for Keychain session storage. Do not install a simulator build produced with `CODE_SIGNING_ALLOWED=NO`; reserve that option for compile-only physical-device checks.

Guests can open **Discover → profile → Sign in / Create account**, or use **Sign in** at the top of Travel. Both routes open a full native account page, with travel photography, an adaptive form, and no sheet or tab bar covering the fields. Contextual sign-in from friends, sharing, and flight search also uses a full-screen page. Accounts use a Seur username and password; signing in preserves local trips.

There are no external Swift packages. Offline travel planning works immediately. The Supabase backend enables accounts, friends, cloud copies, private photos, provider search and sharing; see [the cloud setup](../supabase/README.md). The app defaults to the deployed HTTPS service.

The installed app is named **Seur**. The existing Xcode project/scheme and bundle identifier are retained so upgrades preserve local trips and Keychain sessions. [Brand assets and generation prompt](Brand/README.md).

## Native design and motion

- Apple’s iOS 26 Liquid Glass tab bar with a separate system Search tab and a stable position across tabs.
- Actual SwiftUI `glassEffect`, `GlassEffectContainer`, interactive glass, and glass button styles.
- Matched-source zoom navigation into hotel details; native interactive back gestures and editor sheets.
- Spring category transitions, press feedback, animated save symbols, and haptic selection feedback.
- Warm ivory, bronze, editorial serif type, and immersive hotel photography, following the supplied reference.
- System, light, and dark appearances. Dynamic Type, VoiceOver labels, native date controls, and Reduce Motion support for custom category/toast/press animations.
- Native Safari presentation is used only for external booking-provider websites.

## Working features

- Offline catalog: 1,513 hotels, 5,755 dining entries, 12 cities.
- Interactive Map tab: native globe, city discovery, mapped trips, great-circle flight routes and flight detail sheets. Saved collections are accessible from the map bookmark. Optional AeroAPI status, position and delay-history integration; see `WorldMap.md`.
- Worldwide city guides: city autocomplete, thirteen discovery interests, live place search, list/maps, filters, prominent CSV hotel dining, saved cities/places, and add-to-existing-trip planning, hotel stays or visit ratings. See `CityExplorer.md`.
- Search hotels, destinations, restaurants, brands, and cuisines.
- Filter by city/cuisine and sort by featured, dining variety, or name.
- Hotel details, original dining descriptions, source links, Maps links, and official hotel websites where available.
- Side-by-side comparison of up to three hotel dining collections.
- Saved hotels and restaurants persisted on device.
- Full restaurant pages from hotel lists, dining comparisons, and Saved: immersive headers, native glass actions, dining descriptions, directions, hotel websites, private visit ratings/notes, contextual concierge, and dining planning.
- Date and guest planning for hotel stays and dining; editable local itinerary with removal and native sharing/export.
- Flight route, dates, cabin, and traveler validation, with a Google Flights handoff.
- Destination-specific experience discovery through GetYourGuide; save experience ideas to the itinerary.

## Booking boundaries

Seur does not process payments, hold inventory, create supplier reservations, or confirm bookings. Hotel and dining dates are planning preferences; confirm them on the hotel website. Live flight and experience inventory is shown by the external provider. Saved hotels and earlier draft plans stay on the device. Travel trips support explicit cloud upload and private-copy import through the backend. Experience cards are ideas/search categories, not confirmed tours.

Native flight booking with detailed cabin comparisons and matched seat photos is the user's intended next direction. See [FlightBookingRoadmap.md](FlightBookingRoadmap.md) for the saved requirements, provider candidates and rollout sequence. FlightAware powers tracking separately from future ticketing.

## Data and imagery

`Aurum/Resources/hotels.json` was imported from the supplied CSV. Both hotel and venue price-band columns were preserved. Award claims, opening status, and menus are source data and have not been independently reverified. No dining quality scores or nightly rates are invented.

Photos are bundled for Mandarin Oriental Bangkok, The Peninsula Paris, and The Savoy. Hotels without imagery are explicitly labeled. Photography sources: WBP Stars, Polycor, and Architectural Digest India. Photos belong to their respective owners; review licensing before commercial distribution.

## Testing

The shared Aurum scheme includes XCTest unit and UI test targets. Press **Command-U** in Xcode.

Unit tests cover catalog integrity, city/cuisine search, sorting, persistence, duplicate/invalid itinerary prevention, URL validation, flight handoff, and comparison limits. UI tests cover hotel navigation, saved places, itinerary creation, search, dining planning, and flight validation. UI tests use a dedicated UserDefaults suite and do not clear the normal app’s plans.

Build products, result bundles, and simulator recordings are excluded from source control. See `Validation.md` for the checks actually completed.

## Concierge preview

The native **Concierge** tab is an on-device chat demo. It includes suggested prompts, a glass composer, animated messages and a preparation indicator, catalog-based hotel/dining cards, simple weekend ideas, follow-up city/cuisine context, and links into the existing Flights, Experiences, and Trips screens. It can summarize the device’s saved places and draft itinerary. Recommended hotel cards open the normal hotel details and planning flow.

The demo uses local intent matching and response templates, not a connected AI model. It makes no network calls and does not book anything. The interface labels this explicitly. Chat remains in memory while the app runs and across tab switches; “New conversation” clears the chat and cancels any pending reply. Saved places and plans are unaffected. Input is limited to 1,000 characters. An AI service can later replace `ConciergeEngine` without replacing the native chat interface.

## Restaurant details

Restaurant pages use the supplied venue descriptions, cuisine, price bands and location within the hotel. Header photos are explicitly labeled hotel exteriors; venues without hotel imagery use an editorial placeholder. The catalog does not include restaurant photographs, verified opening hours, restaurant phone numbers, coordinates or public review scores. These are not fabricated. Directions open an Apple Maps place search, and website actions open the official hotel website. Personal ratings and notes are local, editable, and private. Restaurant bookmarks appear in Saved independently of hotel favorites.

## Travel workspace

The **Travel** tab has one **Trips** library and a **Friends** area. Every trip includes both a **Plan** and a **Journal**, with the same identity, dates, visibility and sharing settings. Plan supports multi-city routes with exact dates or nights, events repeated across selected days, live place lookup and autocomplete, hotel and flight booking records, agenda/calendar/maps, AI activity ideas and separate totals for each currency. Journal supports categorized places, overall/category scores, visit dates, notes, six photos per place, personal Michelin-star records, stats, maps and list/grid filtering.

Create a trip by choosing only a location and departure/return dates. Aurum generates the trip name and first route stop automatically, ready for day-by-day planning. Rename the trip, add notes, or adjust a multi-city route later through Edit journey. Bring planned restaurants and attractions into that trip's journal without duplicating or overwriting reviews. Meetings, custom events and booking records are excluded from this transfer. Long-press a planned place or hotel to log/rate a visit. You can also import planned places from another trip or copy existing restaurant ratings.

Existing itineraries and journals appear together in Trips with all original data and IDs intact. Legacy file tags remain readable; records adopt the unified type when saved. All exports, shared previews and read-only web pages include both plans and journal entries. Maps can show destinations, events, hotels, airports and journal places together.

JSON exports can be reloaded as private copies. PDF/TXT/CSV exports and the native Apple share sheet support Files, Mail, Messages and AirDrop. JSON and PDF include photos; TXT/CSV include photo counts. New travel data is atomically saved in Application Support, independently of the original hotel favorites and earlier draft plans.

Apple Maps replaces Amadeus for cities/airports/place search. Tripadvisor search/details and AI use server-side keys. The flight dialog performs a live Google Flights handoff and transfers route details to a manual booking-record editor; it does not import live offers automatically. The backend supports username accounts, accepted friends, group conversations, explicit cloud copies, read-only browser links, private/friends/public audiences where applicable, and access revocation. Public links now open read-only PDFs from the Supabase Edge Function; no local server is required. Native shared previews and imports retain the complete trip.

## Welcome and Reserve preview

First launch now includes an optional native onboarding flow for travel interests, dining tastes and a first destination, followed by real Supabase account creation/sign-in and a simulated subscription experience. The welcome screen also offers a direct sign-in shortcut and guest exploration. Progress resumes after relaunch and preferences feed Discover shortcuts. Revisit preferences and the Reserve preview in **Discover → Your workspace**.

Reserve's monthly/annual prices are illustrative. Confirmation and restoration only save/read a local preview plan; no payment, trial, renewal, StoreKit purchase or real entitlement exists. Skipping membership keeps all current features available. See `Onboarding.md` for details.

## Location autocomplete

Location entry now suggests matches as you type in trip destinations, itinerary stops, cities/countries, place names and addresses, both flight search tools, flight booking airports/time zones, and AI activity destinations. Apple Maps powers live geographic suggestions and resolves the selected place's available coordinates/contact details. Country and time-zone matching works locally. Tripadvisor search results also update after a typing pause when that provider is selected and configured.

No extra key or location permission is required for Apple Maps autocomplete. Two or more characters start a debounced lookup. Suggestions include context to distinguish similarly named places. Selecting one fills the field and applicable metadata; clearing/changing a query cancels older lookups. Manual text remains usable offline or when no match is available. Editing a resolved location clears its stale coordinates.

Google suggestions are now an explicit fallback, not part of routine typing. Automated tests block live Google calls and default to local search fixtures. See [Places API cost controls](PlacesCostControls.md) for request deduplication, testing flags and billing safeguards.

## Flexible itinerary events

Use **Travel → a trip → Plan → Add to plan**, or the plus beside a day, to choose from 16 types: restaurant/activity, meeting, appointment, conference, celebration, concert, performance, sporting event, tour, car transfer, train, boat/ferry, shopping, wellness, free time, and custom event. Hotel and flight booking records remain available in the same picker.

Scheduled events have a title, optional guests and venue with Apple Maps autocomplete, all-day or start-time scheduling, optional duration (up to 24 hours), notes, links, and a price per occurrence. Select multiple days to repeat a plan. Tap an agenda item to edit or delete that occurrence. Venue-free online events are supported. Times follow the destination's local schedule; this feature does not send calendar invitations or reminders.

Event types and details persist locally and through cloud sharing/import, and appear in TXT, PDF, JSON and CSV exports. Mapped venues show the event title. Trip-journal import excludes scheduled meetings and custom events, even when their venue is a restaurant. Existing itineraries open without migration.

## Reliable add-to-trip editors
Hotels and flights lead the add menu, followed by separate restaurant and activity choices and all custom event types. Each choice opens a dedicated sheet in a stable parent flow. Save persists the item and returns to the trip; Cancel returns to the menu. New bookings inherit trip dates. Older trips without a route can add a destination and dates before continuing into their selected editor.

Place and venue fields now use server-proxied Google Places autocomplete, with Apple Maps fallback. Selecting a prediction independently resolves available Apple Maps details and coordinates; a confirmation indicates the place will appear on the trip map. The supplied Google key is deployed as a Supabase Edge Function secret and is never embedded in iOS. The legacy local credential file remains ignored. Google search now uses the deployed Supabase Edge Function after sign-in, including on physical iPhones.

Existing dated trips without stops now prepare their route from the destination and dates already saved. Undated trips receive the minimal destination/date sheet and then continue into the original selected event editor. Existing IDs, journals and bookings are preserved.

### Place-search popup stability
The “Find a restaurant or place” and “Search hotels” buttons present search from the editor’s NavigationStack. The reusable place form only requests presentation; it no longer owns a sheet on a Form section. Restaurant/activity plans, hotel records, and journal entries use this shared presenter, so form row recycling cannot dismiss the search popup. Selecting a result returns it to the current draft; cancelling keeps the draft intact.
