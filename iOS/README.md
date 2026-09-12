# Seur for iOS

A native SwiftUI travel app for **iOS 26 and later**, designed around hotel dining and the supplied Aurum iOS reference. This is an Xcode iOS application, not a website or WebView wrapper.

## Open and run

1. Open `Seur.xcodeproj` in Xcode 26 or later.
2. Choose the **Seur** scheme and an iPhone running iOS 26+.
3. Press Run.

The project, app target and shared run scheme are named Seur. Existing source folders, the internal Swift module and test targets retain their Aurum names; bundle identifiers and saved-data keys are unchanged.

The app works in Simulator without an Apple developer account. To install on your physical iPhone, choose your Apple development team under **Seur → Signing & Capabilities**, then select your connected iPhone. TestFlight and App Store distribution require signing and provisioning through your Apple Developer account.

Simulator builds used for account testing and installation must retain code signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`) so the app has its application identifier for Keychain session storage. Do not install a simulator build produced with `CODE_SIGNING_ALLOWED=NO`; reserve that option for compile-only physical-device checks.

Guests can open **Discover → profile → Sign in / Create account**, or use **Sign in** at the top of Travel. Both routes open one native welcome page with aligned Apple, Google and email options. Provider buttons are present immediately, independent of status/configuration requests; the server checks provider availability when sign-in is attempted. Email sign-in uses a compact form; registration uses three pages for name/username, email and password, with progress and Back navigation. The text link between sign-in and registration preserves email while clearing the password. New email accounts require verification; existing usernames remain supported for sign-in. Contextual sign-in from friends, sharing, and flight search uses the same page. Signing in preserves local trips.

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

The shared Seur scheme includes XCTest unit and UI test targets. Press **Command-U** in Xcode.

Unit tests cover catalog integrity, city/cuisine search, sorting, persistence, duplicate/invalid itinerary prevention, URL validation, flight handoff, and comparison limits. UI tests cover hotel navigation, saved places, itinerary creation, search, dining planning, and flight validation. UI tests use a dedicated UserDefaults suite and do not clear the normal app’s plans.

Build products, result bundles, and simulator recordings are excluded from source control. See `Validation.md` for the checks actually completed.

## AI concierge

The native **Concierge** tab connects to OpenAI through the authenticated Supabase travel API. Sign in, then ask for a destination comparison, detailed itinerary, restaurant ideas, practical travel advice or improvements to an existing trip. Select a trip above the conversation to include its schedule; travel preferences and saved places can be enabled independently. Restaurant detail pages can open the concierge with that venue's supplied context.

Replies support readable Markdown, contextual follow-ups and Apple Maps place discovery. Draft itineraries have a **Review & add to a trip** action with daily activities, proposed local times and notes. Save to a new trip with flexible or exact dates, or add a compatible draft to an existing route without overwriting its plans. The concierge does not make bookings or verify live availability. Provider lookups and estimated advice are distinguished in responses.

Chat remains in memory while the app runs and across tab switches; **New conversation** clears it and cancels pending client work. Saved trips are unaffected. Input is limited to 4,000 characters, with bounded recent history and prior draft context sent for follow-ups. Stop/Retry controls handle slow or failed replies. Booking references, journal notes, photos and private booking notes are omitted from automatic trip context. See `PlacesCostControls.md` for call limits and paid-test protections.

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

## Flight alerts and destination weather

Flight detail pages now offer **Follow flight** for push alerts and **Show on Lock Screen** for Live Activities. Upcoming itinerary days use native WeatherKit forecasts with rain-aware concierge suggestions. See [AppleServices.md](AppleServices.md) for setup, permissions, monitoring costs and platform limits.

## Friends

The dedicated Friends tab contains shared trip discovery, invitations, friend profiles, private/group conversations, date-overlap hints, saved trip shortcuts and itinerary sharing controls. Shared itineraries have a readable day-by-day preview. Search is available from magnifying-glass buttons in Discover and Map so all five primary tabs remain visible. See [Friends.md](Friends.md) for sharing behavior and privacy details.

## Travel wishlist

Travel now includes a Wishlist section for saved places, destinations and personal ideas. Add notes, organize collections, mark Top picks, search/filter and turn ideas into existing or new trips. The wishlist uses existing bookmarks and private on-device storage. See [Wishlist.md](Wishlist.md) for behavior and storage details.

## Trip budget and companion splits

Budgeting is optional: choose **••• → Add budget** on a trip, then expand its compact summary and open the **budget tracker**. The dedicated dashboard includes a spending ring, category breakdown, itinerary-day chart, searchable history, quick expense entry, and daily home-currency estimates. Add companions from friends, conversation members or by name, then choose who paid and who shares each cost. Companion balances and **Settle up** keep original currencies separate throughout and after the trip. Today actions let you mark an event done and update spending immediately. [Usage, conversion and sharing details](TripBudget.md).

City seasonality is bundled for the twelve catalog cities and appears beside trip dates and projected multi-city stops. Compare peak/shoulder months, broad weather bands, holiday periods and possible closures offline. Moving holidays explicitly prompt for unverified years. See [Seasonality.md](Seasonality.md) for coverage, sources and the JSON maintenance contract.

Home Screen widgets now include Today in Seur, Next Trip, Trip Budget and Travel Profile, with Lock Screen variants for Today/Next Trip. Open **Discover → Your workspace → Widgets** for previews and placement instructions; a one-time invitation also appears after saving a dated trip. They use an offline App Group snapshot of local trips. See [Widgets.md](Widgets.md) for refresh behavior, supported sizes and the required App Group signing setup.

Trip cards now use destination photo covers, clear dates and quieter summaries in list and grid layouts. See [TripCards.md](TripCards.md) for the one-time Commons lookup, permanent on-device covers, credits, fallbacks and the deployed photo endpoint.

Traveler-created guides are available from **Travel → Guides** and **Discover → Travel guides**. Users can write private drafts, organize recommendations into chapters, preview and publish, save guides offline, and add recommendations to a trip. See [TravelGuides.md](TravelGuides.md) for the Wanderlog research, usage, privacy boundaries, and deployed backend behavior.

### LiteAPI hotel discovery

The native Home and Stays search now use the authenticated hotel-content endpoints on the default Supabase backend. Sign in to browse the sandbox collection beyond the bundled CSV; the offline stay-and-dine collection remains available. Hotel details include property and room galleries, amenities and paginated guest reviews. Saving and Add to trip create planning records, not reservations.

The backend reads `LITEAPI_SANDBOX_KEY` exclusively from its server secret store. Never add it to the iOS target or an Info.plist. `/v1/status` reports hotel configuration and explicitly reports `hotelBooking: false`. Dated sandbox prices and room packages are now available. Checkout and flights remain later stages documented in [LiteAPIDesign.md](LiteAPIDesign.md).

Global Search now opens **Explore**: cities, destination photography, recent places, Dining, Things to do and Guides. Open a city and choose **Find a hotel** to enter dates → guests → results. The Stays shortcut remains an explicit hotel entry. Calendar, guests, nationality, filters, room review and sandbox checkout use full-page navigation, with automatic progression after complete inputs, draft-preserving cancellation, subtle haptics and Reduce Motion support. See `LiteAPIDesign.md` section 22. Final booking confirmation always remains an explicit action.


Hotel rates require dates, room-by-room occupancy, child ages, lead guest nationality and currency. Cards show test stay totals, and View rooms opens distinct meal/cancellation packages. Quote review separates included charges from fees due at the property. Prices expire after five minutes and refresh explicitly; no reservation or charge is created. The server uses the existing account pricing configuration, labels all rates as sandbox, and retains public selling-price restrictions for the later checkout stage.

Sandbox hotel checkout now includes guest details, provider prebook/repricing, explicit test confirmation, saved attempts and recovery. Open the clock control beside Search dates/guests for **Test bookings**. No real card or reservation is charged. The live sandbox returned inconsistent booking details; those attempts show needs attention instead of success. See `LiteAPISandboxQuestions.md` for the provider follow-up required before payment activation.


Hotel results now include total-stay price sliders and filters for stars, guest scores, review counts, distance, photos, checked availability, breakfast and cancellation. Their loaded-results/checked-offer scope is stated in the filter page. Hotel and room photography is edge to edge; tapping a photo opens Individual mode, with a Gallery grid available. Provider average scores and review counts are shown explicitly. Room details and primary action bars use full-page, bottom-anchored layouts. The repeated country picker has been removed from the sandbox flow; a fixed US test nationality supplies the provider-required field until verified traveler nationality is wired for production. See `LiteAPIDesign.md` section 23.

Global Search now supports Destinations and Hotels. Hotel-name autocomplete resolves the location automatically, then shows matching LiteAPI listings with addresses before opening the existing full-page booking flow. Direct Stays entry also offers Search a specific hotel.

Travel → My bookings now lists recent account-owned sandbox checkouts with status/reference filters, full booking records, shareable test receipts and support summaries. It reuses the existing server ledger and does not enable payment, cancellation or refunds.

City discovery now uses one integrated city page across Explore, Dining and Things to do. Categories, search, filters, See all and saved places update that page in place, with the city header, map and hotel booking entry retained.

My bookings includes Upcoming and Past date filters for verified test confirmations, prioritizes unresolved records in All, and loads older records in batches of 30. Search and filters apply to loaded records until the complete history has been loaded.

Saved travelers are available in Travel and Account for signed-in users. Add yourself or companions, choose a default, and reuse contact details at hotel checkout. Nationality is saved once and applied before checking rates; choosing a different nationality requires fresh prices. Profiles sync through the private account API, support edit/delete, and clear from memory on sign-out. Existing bookings are unaffected. This supplies hotel lead-guest details; flight/passport profiles are outside this release.

Booking records now offer explicit LiteAPI status refresh, show the last provider check and distinguish provider-cancelled test bookings from confirmed stays. Refresh does not submit a cancellation or establish refund status. Live customer payment, production booking activation and native flights remain unfinished pending the LiteAPI setup described in `LiteAPIDesign.md`.

Sandbox cancellation now has full-page review and explicit confirmation, durable pending recovery, and verified completion. The normal app only exposes it when the backend advertises `hotelSandboxCancellation`; travel-api v53 now advertises this sandbox capability following approved deployment and live route checks. See `LiteAPICancellationDeployment.md`.
