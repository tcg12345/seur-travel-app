# Validation — September 5, 2026

- Xcode 26.6; iOS 26.5 SDK.
- Native simulator build succeeded for iPhone 17 Pro (iOS 26.5).
- Native Release build succeeded for physical iOS devices with code signing disabled. Physical-device installation and performance have not been tested.
- All 6 XCTest unit tests passed: catalog integrity, search/sorting, saved-place persistence, itinerary persistence and validation, safe provider links/flight queries, and comparison limits.
- All 4 XCUITest flows passed: hotel → save → plan → saved places → itinerary; catalog search and empty state; dining planning; invalid flight route.
- The hotel-to-itinerary UI test was repeated and passed after the final detail-screen layout adjustment.
- Native screenshots were inspected for Discover (light/dark), hotel details, stay planning, and dining planning. Screenshots and a 16-second simulator walkthrough are in `Preview/` in the working directory.
- Native glass and system transitions were exercised in Simulator. Frame-rate and haptic output have not been measured on physical hardware.
- Booking-provider payments, live inventory, and reservation confirmation are external to the app and were not exercised by tests.

The SwiftUI source uses native iOS 26 Liquid Glass APIs and system controls. The app itself is not rendered in a web view. SFSafariViewController is used only when opening booking providers or source pages.

## Concierge update

- Simulator build and selected test run passed: all 9 unit tests plus the new concierge UI test.
- Concierge tests verify actual catalog IDs/city/cuisine matching, contextual follow-up, reservation limitations, real itinerary summaries, flight handoff, empty input, duplicate-submit prevention, and cancellation on reset.
- Native UI test verifies opening Concierge, sending a suggested prompt, navigating a recommended hotel, sending a typed city follow-up, preserving messages across tabs, and clearing the conversation.
- Welcome and recommendation screenshots were visually inspected in the iPhone 17 Pro simulator.
- After the final recommendation and layout refinements, the contextual matching unit test and full concierge UI flow were rerun and passed.

## Restaurant detail update

- Full restaurant pages open through native push navigation from hotel dining rows, comparison lists and saved restaurants.
- Simulator build and physical-device Release build both succeeded; device build used code signing disabled.
- All 11 unit tests and both selected restaurant UI tests passed with zero failures.
- New coverage verifies restaurant identifiers are scoped by hotel, bookmarks and private ratings/notes persist, clearing notes works, the contextual concierge uses the selected venue, dining plans can be added from the detail page, and saved restaurants reopen after relaunch.
- All 5,755 catalog restaurant identifiers were checked for uniqueness.
- Detail and scrolled visit/location screenshots were visually reviewed on iPhone 17 Pro, iOS 26.5. Preview files: `10-restaurant-detail.png`, `11-restaurant-visit-location.png`, and `06-dining-planner.png`.
- Restaurant photographs, public ratings, live opening hours, phone numbers and map coordinates are absent from the starter catalog. Hotel exterior imagery is explicitly labeled; Apple Maps uses a place search. No live table booking is performed.

## Travel workspace — September 6, 2026

- Full signed iPhone 17 Pro / iOS 26.5 test run passed: **21 unit tests and 9 UI tests, zero failures**. The final build also passed after refining local-save error reporting and clearing stale map coordinates when airport text is edited.
- New model tests cover calendar boundaries, multi-city schedules, repeated-day events, currency-separated totals, itinerary-to-journal imports, map coordinates including airports, persistent reload, corrupt-file preservation, invalid JSON imports, score validation, CSV escaping/formula protection and long multipage PDF exports.
- New UI flows cover itinerary creation, events on multiple days, agenda/calendar navigation, saving personal ratings and native account registration against the isolated local backend. Account sessions use Keychain and require an ad-hoc-signed simulator build.
- Backend suite passed: **16 tests**, covering authentication, ownership, friend requests, groups, direct sharing, redacted booking details, revocable links, private/public transitions, stale-copy conflicts, validation, escaped shared pages, unavailable providers and AI candidate-ID constraints.
- Native dashboard, agenda, calendar, rating editor, trip journal and account screenshots were inspected. Read-only shared-trip HTML was visually checked at desktop and iPhone width. Browser QA used synthetic test accounts and a separate temporary database.
- Simulator and physical-device Release builds succeeded. Physical-device installation, performance and production hosting have not been tested.
- Tripadvisor and OpenAI adapters use server-side credentials. No keys were supplied/configured and no live paid-provider request was exercised. Apple Maps handles native city/airport/place lookup without Amadeus; flight comparison opens Google Flights and transfers search-route details to a manual booking-record form.
- The local development backend runs at `http://localhost:8787`. Public links remain unavailable until an HTTPS backend URL is deployed and configured. Cloud copies are explicit uploads; downloads/imports create separate private copies.
- Source archives exclude credentials, local databases, test accounts, build products and Xcode user settings.

## Onboarding and Reserve preview — September 6, 2026

- Final selected test run passed: **24 unit tests and 5 UI tests, zero failures**. UI coverage includes full personalization, mid-flow relaunch, back navigation, monthly preview selection, cancellation, confirmation, restoration, editing preferences, skipping without membership and largest accessibility text size. Existing Discover/stay planning and Travel/repeated-day itinerary flows also passed.
- First regression attempt encountered two simulator interaction failures. The final combined run passed both flows after allowing native transitions to settle before screenshot capture.
- Welcome, interests, cuisines, destinations, membership choices, confirmation, success and accessibility screenshots were reviewed. The welcome image fills the safe areas and both plans are visible before benefits on a standard iPhone viewport.
- Simulator and physical-iPhone Release builds succeeded. No real device installation or App Store purchase was performed.
- Onboarding and membership preview require no API keys or server. No StoreKit/payment code is connected. Confirming a plan only saves a local preview; skipping leaves all current features available.
- Final screenshots are in `Preview/21-onboarding-welcome.png` through `Preview/30-preferences-accessibility-text.png`. Source packages include `Onboarding.md` and the three new native onboarding files.

## Location autocomplete — September 6, 2026

- Final run passed: **28 unit tests and 6 UI tests, zero failures**. Coverage includes debounce cancellation, changing/clearing queries, local country/time-zone matching, selection metadata, trip destination persistence, itinerary country filling, flight airports, rated-place addresses and existing repeated-day event entry.
- A live Apple Maps UI test successfully typed Paris, displayed geographically distinct suggestions, selected Paris, France and resolved the field. This live test requires internet access. Other dedicated selection tests use explicit DEBUG-only fixtures in the isolated UI-test launch mode; fixtures are unavailable in Release builds.
- An initial test caught duplicate TextField binding writes clearing the newly selected country's value. Ignoring unchanged writes fixed this; the final stop, place and flight selection flows passed.
- Screenshots of the live suggestions, resolved destination, itinerary stop and place details were reviewed. The fields preserve manual input when suggestions fail and cancel requests on blur/disappearance.
- Simulator and physical-iPhone Release builds succeeded. The native autocomplete requires no Amadeus key, backend key or device location permission. Tripadvisor's debounced provider search remains dependent on backend configuration.

## Expanded itinerary events — September 6, 2026

- Added 16 selectable itinerary item types with native grouped cards, plus existing hotel/flight records and AI ideas.
- 31 iOS unit tests passed, including legacy JSON decoding, venue-free meeting persistence, repeated occurrences, overnight timing, all-day ordering, validation, trip-import exclusions, map titles, and all four exports (`/tmp/aurum-events-tests.xcresult`).
- The existing restaurant/repeated-day UI regression passed in that run. The new meeting/custom-event UI test passed in `/tmp/aurum-events-verified.xcresult`: create, duration, repeat, reopen, change one occurrence to all-day, custom event, and persistence after relaunch. Initial UI automation required corrections to target the switch thumb and scroll to lazy-grid items before reading their frames.
- 18 backend tests passed, including new event roundtrip, read-only shared HTML with escaped title/guests, all-day/overnight rendering and invalid event details.
- Final simulator and physical-iPhone Release builds succeeded. Preview screenshots 38–42 were exported and reviewed.
- The local backend was restarted and its status endpoint responded. External API keys and a public sharing host are still unconfigured; this change does not activate those integrations.

## Unified trips — September 6, 2026

- Travel now has one Trips list. Each record provides Plan and Journal sections with all event, route, hotel/flight, AI, rating, photo, map, filtering, import, export and sharing tools available.
- Existing itinerary/trip tags remain readable without rewriting the library on load. Saving preserves IDs and every content/audience field while adopting the unified journey tag. Routes are optional until scheduling events.
- 34 iOS unit tests passed in `/tmp/aurum-unified-tests.xcresult`, including legacy record preservation, mixed plan/journal exports for every legacy kind, combined maps and additive journal import without overwriting ratings/photos.
- Five UI flows passed across `/tmp/aurum-unified-tests.xcresult` and `/tmp/aurum-unified-verified.xcresult`: custom meetings, repeated restaurant plans, destination autocomplete, personal ratings and one combined trip from journal entry through route/dinner planning and reload. The combined test needed explicit keyboard readiness and scrolling to offscreen lazy-grid journal cards; saved data was correct throughout those UI-test adjustments.
- 20 backend tests passed, including unified/legacy records containing both plans and ratings, public access/redaction, combined read-only HTML, and starting without a route before adding events.
- Simulator and physical-iPhone Release builds succeeded. Screenshots 43–45 were exported and visually reviewed. Local backend restarted successfully; external provider keys and public hosting remain unconfigured.

## Simplified Create Trip — September 6, 2026

- Creation asks only for a destination with autocomplete, departure date and return date. No title/description inputs, optional-dates toggle, timing mode, night count or route management section appears during creation.
- A destination-based name and dated first route stop are generated automatically, including selected country and map coordinates. Return dates remain after departure and within the existing 365-night route limit. Full trip editing remains available after creation.
- The isolated UI test passed in `/tmp/aurum-simple-create-complete.xcresult`: required location, minimal inputs, autocomplete selection, creation, automatic route, generated title and saved country in the route editor. The existing repeated-day event flow also passed in `/tmp/aurum-simple-create.xcresult`.
- Initial UI runs required scoping route text to the editor and correcting accessibility assertions; an isolated simulator was used for final verification. Screenshots 46–47 were exported and the minimal form visually reviewed.
- Simulator and physical-iPhone Release builds succeeded. Existing data models and backend were unchanged.

## Working add-to-trip flow and Google Places — September 6, 2026

- Replaced the chooser-to-sibling-sheet handoff with a mounted chooser that owns its editor sheet. All 19 add options opened successfully; Save returns to the trip and Cancel returns to the chooser. Hotels/flights are first in the menu, saved bookings appear before agenda events, and bookings count toward total plans.
- Existing trips with destination/dates but no route now prepare their first stop from those saved choices. Undated trips receive a minimal location/date step and resume their originally selected editor. Both paths passed UI tests without losing existing records.
- **37 iOS unit tests passed** in `/tmp/aurum-add-legacy-verified.xcresult`, including all event kinds saved/reloaded with mapped venues, legacy-route preparation, stale Google autocomplete response cancellation and existing travel regressions.
- **Six distinct UI flows passed** across `/tmp/aurum-add-verification.xcresult` and `/tmp/aurum-add-legacy-verified.xcresult`: every add option, saved hotel/restaurant/activity/meeting/flight records and map after relaunch, live Google suggestions with Apple location resolution, repeated/custom event editing, and the two legacy route cases.
- **22 backend tests passed**, covering autocomplete authentication, direct-loopback development access, rate limits, input validation, normalization and secret handling alongside existing accounts/sharing tests. Request-scoped SQLite connections now close deterministically; Google requests use a short timeout and native autocomplete falls back to Apple Maps on failure.
- The supplied Google credential lives only in ignored `backend/.env`. Google predictions are displayed with attribution without a map; the selected query is independently resolved in Apple Maps for saved details and native map coordinates. Live Savoy search and resolution succeeded. Tripadvisor/AI keys and public hosting remain unconfigured.
- Final iPhone Release compilation succeeded. Visuals of the add menu, hotel form, autocomplete and saved map were inspected. UI fixtures intentionally use shared coordinates; live search verification uses real provider results.
- Final live hotel search/save/map verification also passed in `/tmp/aurum-add-final-live.xcresult` after the layout refinements. Preview files 48–54 document the new flow.
- Single-place maps start at neighborhood scale and refresh their camera when mapped records change; users can still zoom freely.
- The final neighborhood map was visually rechecked after the passing live UI test in `/tmp/aurum-add-map-polish.xcresult`.

## Secondary place-search popup — September 6, 2026

- Reproduced the reported auto-dismissal by tapping “Find a restaurant or place” in `/tmp/aurum-search-sheet-repro.xcresult`; the popup disappeared before its query field could be used. Earlier autocomplete coverage exercised the inline field, not this secondary button.
- Moved the search state and sheet ownership out of the reusable Form section to each editor’s NavigationStack. Restaurants/activities, hotel bookings and journal places share the same root-level presenter and retain their category when applying a selection.
- Flight search and both airport-search popups passed their new regression in `/tmp/aurum-search-sheet-fixed.xcresult`. The first extended place test needed its scrolling corrected to return to an offscreen search row after selecting another day; that was a test-navigation failure before opening search.
- Physical-iPhone Release compilation passed. No backend, provider credentials, persistence model or booking behavior changed.
- The final four-form place-popup test passed in `/tmp/aurum-search-sheet-verified.xcresult`: popup remains visible, autocomplete selection fills the draft and map coordinates, reopen/cancel retains the selection, an extra selected event day is preserved, and restaurant/hotel/activity/journal records save successfully. Preview 55 shows the stable popup.

## Worldwide city exploration — September 6, 2026

- Added unrestricted city autocomplete and individual city guides, thirteen interests, live place searches, list/map views, sorting, website/saved filters, wider-area searches, local city/place bookmarks and trip integration. The twelve CSV cities remain optional shortcuts with prominent hotel dining collections.
- **43 iOS unit tests passed** in `/tmp/aurum-city-verified.xcresult`, including geography-aware CSV matching, catalog metadata, persistent bookmarks synchronized with legacy restaurant favorites, partial provider failures, cache reuse, stale-response rejection, filters and every place category preserving trip map coordinates.
- The live non-catalog Lisbon test passed in that run: actual Apple Maps city suggestions, 25 museum results, a real museum detail page and contact/map information. A direct MapKit probe identified combined category phrases as no-match errors; short category queries scoped to the selected city fixed live browsing. No-match responses now show an empty state rather than a network failure.
- The city map/saved-filter/search-empty-state UI flow passed in `/tmp/aurum-city-complete.xcresult`. Initial assertions needed to target the correct accessibility element and native search presentation. The collection and saved lists now use always-visible inline search fields, avoiding hidden search controls in this navigation context. Collection identifiers are applied to the heading rather than inherited by every child button.
- The final physical-iPhone Release build passed in `/tmp/aurum-city-release-final.log`. Existing Swift 6 migration warnings in onboarding remain; the project uses Swift 5 language mode. No physical-device installation was performed.
- Live provider coverage is not exhaustive. The CSV does not contain restaurant coordinates; independent exact-hotel resolution supplies hotel-address pins where available. Unresolved addresses are disclosed and not assigned invented pins. Public ratings, opening hours, imagery and prices are shown only when present in source data.
- No backend schema, credentials, payment or supplier-booking integration changed. City exploration uses native MapKit without an API key or location permission. Source archives exclude `.env`, databases, test data and build products.
- The final dining collection and complete save/plan/hotel/journal UI tests both passed in `/tmp/aurum-city-delivery.xcresult`. The collection was searched by hotel, a restaurant was opened/bookmarked, and a non-catalog discovery was saved, scheduled, rated and reloaded alongside a hotel stay. The saved trip map retained the discovery. Across the final successful runs, **four distinct city UI flows passed**.
- Preview screenshots 56–62 cover the worldwide guide, Paris dining collection, discovery details, saved collection, real Lisbon museums and map/saved filters. The regular simulator build is installed without UI-test flags; existing user data is preserved.

## Globe, flight information and persistent map panel — September 6, 2026

- Map replaces Saved in the original system tab bar. The top bookmark keeps existing saved collections accessible. The map supports worldwide discovery, trip locations, great-circle flight routes and flight details.
- The final map panel is integrated into the page, behind the original tab bar. It does not present a second navigation bar or hide/recreate the original one. Tab-bar minimization is disabled for consistent positioning. Entering Map resets the panel to its compact position without an entrance animation.
- Drag state is isolated from the map renderer and uses global gesture coordinates to prevent feedback as the panel moves. Compact glass, intermediate and full-width opaque layouts use spring settling and honor Reduce Motion. Scrolling is native; resizing uses the handle/header or chevron.
- **46 iOS unit tests passed** in `/tmp/aurum-map-native-complete.xcresult`, including airport-local times, unknown delay values, valid/date-line routes and clearing prior-flight position/history. **29 backend tests passed** in `/tmp/aurum-map-backend-final.log`, including normalized responses, caching, history entitlement, date validation and endpoint authentication.
- The final flight and navigation UI flows passed in `/tmp/aurum-map-navigation-verified.xcresult`: flight selection/details/history, trip selection, Saved navigation, expansion/collapse, unchanged original tab-bar height, switching to Travel and back, header dragging and closing the panel. Frame checks read actual CGRect values rather than unsupported predicate key paths.
- The final city UI flow passed in `/tmp/aurum-map-city-final.xcresult`: start typing in the compact panel, automatic expansion, autocomplete selection and opening the city guide. Across these runs, three distinct Map UI flows passed.
- Final physical-iPhone Release compilation passed in `/tmp/aurum-map-release-delivery.log`. Screenshots were inspected for the globe, both route endpoints, flight information/history and compact/expanded/dragged panels. This is simulator interaction validation, not physical-device frame-rate profiling.
- At the time of the Map UI validation, FlightAware was not configured. Status, history and position adapters were fixture-tested; normal launches showed saved schedules and explained unavailable live data. See the subsequent live connection check below. No APNs/Live Activities service is implemented.
- A fresh normal Debug build passed in `/tmp/aurum-map-simulator-delivery.log` and was installed/launched on the user's iPhone 17 Pro iOS 26.5 simulator (`5420F443-F08A-4876-87F1-117B659584D0`) without test flags or test plugins. Existing app data was preserved. The temporary Globe QA simulator was deleted; other simulators were left intact. Updated source archives pass ZIP integrity checks and exclude `.env`, databases and build products.

## FlightAware connection and saved booking direction — September 6, 2026

- Saved the user's intention to continue native booking and detailed cabin-product comparisons in `FlightBookingRoadmap.md`. No native ticketing or real payment flow was added in this step.
- Configured the supplied FlightAware credential in the ignored, mode-0600 local backend `.env` and restarted the local development server. Credentials are not embedded in iOS source or committed to Git.
- `/v1/status` reports flight tracking enabled and history disabled. One bounded current-date BA178 lookup through `/v1/flights/status` returned a real JFK–LHR flight record, including scheduled departure, estimated arrival and B772 aircraft type. This validates the credential and status integration; live position, history entitlements and commercial-use permissions have not been verified. No historical query was made.
- All **29 backend tests passed** again with `python3 -m unittest discover -s backend -p 'test_*.py' -v`. This step changes backend configuration and documentation; the previously validated native binary remains installed.


## Supabase backend migration — September 7, 2026

- Deployed the complete travel API to the Seur Supabase project in tcg12345's organization. Postgres holds cloud records and permissions; Supabase Auth verifies passwords; a private Storage bucket holds journal JPEGs; Edge Functions host API routes, provider adapters and public PDF links. Two versioned SQL migrations are applied remotely.
- The old SQLite database contained zero backend users, documents, friendships, conversations, messages and links. An ignored private SQLite snapshot was created before migration. No existing cloud records required conversion. Device libraries remain local and can be explicitly saved to the cloud after sign-in.
- Live integration tests passed for temporary accounts, authentication, logout/account deletion, full trip/photo round trips, summary lists, stale writes, ownership, private access, accepted friendships, group membership, messaging, redacted sharing, public PDF/TXT/JSON links and revocation. Direct Data API/RPC access was denied for both anonymous and authenticated client roles. The test shared only between its own temporary accounts and deleted them afterward. Final database checks found zero test profiles, documents, sessions and stored photos.
- One live Google Places autocomplete and one live FlightAware BA178 request succeeded through Supabase. Flight history remained disabled. Tripadvisor and OpenAI routes are implemented but cannot be accepted live until their keys are configured.
- Eight Deno contract tests passed, including trip validation, injected storage/URL rejection, airport time-zone boundaries and shared PDF generation. Final Edge Function type checking passed. Supabase's security advisor returned an empty findings list after the access-hardening migration.
- All 46 existing iOS unit tests passed in `/tmp/aurum-supabase-verified.xcresult`. The final native account UI test passed in `/tmp/aurum-supabase-ui-submit.xcresult`: real Supabase sign-in, connected services, cloud refresh and sign-out. Earlier UI attempts targeted the wrong duplicate Sign in label; the submit control now has a unique accessibility identifier. Session responses are scoped to their starting server/token so stale requests cannot clear a newer account.
- Final Debug and Release simulator builds succeeded in `/tmp/aurum-supabase-final-build.log` and `/tmp/aurum-supabase-final-release.log`. The normal Debug build was installed and launched without test flags on the active iPhone 17 Pro iOS 26.4 simulator (`C1948426-38A2-4886-933A-3DC6C89303DC`). The original iPhone 17 Pro iOS 26.5 travel-app simulator (`5420F443-F08A-4876-87F1-117B659584D0`) was also updated and launched. Existing simulator data was preserved. The temporary Supabase QA simulator was deleted.
- The signed-in native account screen and three-page public PDF were visually inspected. Standard Supabase domains rewrite HTML as plain text, so public links use inline PDFs; full UTF-8 TXT/JSON downloads and native previews retain script coverage beyond the PDF's portable font. No separate hosting service or custom domain was added.
- Cloud save/import remains explicit. This migration does not add automatic library synchronization, email recovery, supplier ticketing, real subscriptions, live flight position acceptance, historical flight entitlement or push alerts. The retained Python backend is a legacy reference and is no longer required by the app.


## Real onboarding accounts — September 7, 2026

- Added a cloud account step between optional preferences and the simulated membership preview. Travelers can create a real Supabase-backed username/password account, sign in from the welcome screen, or continue as a guest. Successful authentication uses the existing Keychain session and advances to membership. Passwords are held only in form state and cleared on success/exit.
- Native Form rows handle keyboard avoidance and focus. Display name, username, password length and confirmation have local validation; server failures stay visible for correction. Existing authenticated sessions restore automatically. Decorative headers and fixed controls remain usable at accessibility text sizes while form content can scroll.
- All 46 iOS unit tests passed in the initial onboarding run. Personalization/resume, simulated subscription and guest flows passed in `/tmp/aurum-onboarding-account-complete.xcresult`; the final native-form large-text flow passed in `/tmp/aurum-onboarding-native-form.xcresult`.
- The complete live account UI test passed in `/tmp/aurum-onboarding-cloud-delivery.xcresult`: mismatch rejection, actual account creation, membership skipping, account display, Keychain restoration after relaunch, logout, welcome-screen sign-in, incorrect-password rejection and successful retry. It used a temporary test account and deleted it in teardown. Earlier attempts encountered iOS's Strong Password prompt and keyboard movement; the test now explicitly dismisses the optional prompt and uses native Next controls.
- Final normal Debug simulator and physical-iPhone Release builds passed in `/tmp/aurum-onboarding-delivery-debug.log` and `/tmp/aurum-onboarding-delivery-release.log`. Both existing iPhone 17 Pro simulators (iOS 26.4 and 26.5) were updated and launched without test flags or erasing data. Normal and large-text account screens were visually reviewed.
- No backend schema, account format, subscription billing or provider configuration changed. Accounts remain username-based; email recovery and Apple sign-in are not implemented in this step.


## Seur name and flight-ribbon identity — September 7, 2026

- Renamed the installed app, bundle name and executable to Seur, and the build product to `Seur.app`. Kept the existing bundle identifier, Swift module, project/scheme, local library paths, preferences and Keychain service to preserve updates and saved data. Updated test host paths and scheme product references; existing test targets build successfully.
- Added the original generated flight-ribbon / S logo as an opaque 1024 × 1024 app icon and a shared native logo asset. Replaced the old letter-circle mark in welcome, Discover and workspace, and added the new mark to Reserve and concierge branding. Updated visible names, collection labels, share/export headings and membership copy to Seur. Full original artwork and the built-in generation prompt are in `Brand/`.
- Final Debug simulator and physical-iPhone Release builds passed in `/tmp/seur-brand-product-debug.log` and `/tmp/seur-brand-product-release.log`. Test-target compilation passed in `/tmp/seur-brand-test-build.log`; behavioral tests were not rerun for this branding-only update. Compiled metadata confirms display name, bundle name and executable are all Seur. The app icon is 1024 × 1024 with no alpha channel.
- Installed and launched the final normal build on the existing iOS 26.4 and 26.5 iPhone 17 Pro simulators without erasing data. Visually checked the welcome-screen mark and wordmark. No backend, account, booking or subscription behavior changed.

## Map sheet refinement and standalone flights — September 7, 2026

- Replaced stacked map tabs with a compact animated section switcher and an Explore interest menu. Section changes preserve panel height; returning to Map resets compact placement without an entrance animation.
- The sheet's continuous Liquid Glass surface extends to the physical bottom edge behind the original system tab bar. Its content is clipped to the safe-area viewport. Full-surface swipes use the native scroll pan, with scroll-to-sheet handoff at the top, velocity-based settling, and reduced-motion support.
- Added Flights → + with airline autocomplete, flight number/local date lookup, airport autocomplete and route lookup, manual entry, review/back, and in-flow sign-in. Saved standalone flights are private Supabase records, independently editable/removable, and appear alongside trip routes.
- All 48 iOS unit tests passed. Focused simulator UI coverage verifies city guides, trip and flight details, delay-history display, content swipes, native navigation-bar stability, bottom-edge material, airline/route search, review/save, and the final detail row remaining above the navigation controls. Screenshots were visually reviewed. QA used a separate simulator, without modifying existing trip libraries.
- Nine Deno contract tests and Edge Function type checks passed. Live standalone-flight tests passed for create/reload/update/delete, authenticated access, and cross-account isolation. Four bounded FlightAware lookups verified one BA178 departure, two JFK–LHR route results, airport details and airport autocomplete resolution. Temporary test accounts were removed. Supabase security advisors returned no findings; the flight table has RLS and no client-role grants.
- Debug simulator and physical-iPhone Release builds passed. Supabase migration `20260907120525_standalone_flights.sql` and the updated travel-api function are deployed. Route search remains limited to the provider's recent/near-term window and one page of nonstop departures; later flights support manual schedules. No ticket purchase or subscription billing was enabled.


## Simpler trip additions — September 7, 2026

- The chooser and editors now use one sheet with native navigation. Place search is inline for hotels, restaurants, activities, journal places and optional event venues. A single selected place supplies the address and map coordinates; latitude/longitude fields and duplicate place-search routes are removed. Booking details, notes, prices and duration expand in place. Repeated-day cards and all existing event categories remain available.
- All 48 iOS unit tests passed. Eight focused UI flows passed across `/tmp/SeurTripEditorsQA1.xcresult` and `/tmp/SeurTripEditorsQA2.xcresult`: every add option/back navigation, save/reload/map persistence across bookings and venues, inline searches preserving repeat selection, flight airports, meeting duration/all-day/custom events, dated and undated legacy trips, and standalone map-flight regression. The initial duration check exposed a parent accessibility identifier masking child identifiers; the corrected flow passed.
- A live Google-attribution assertion was invalid for a signed-out guest: the existing cloud autocomplete endpoint requires sign-in, so guest search uses the Apple Maps fallback. The provider-independent live UI flow passed in `/tmp/SeurTripEditorsQA3.xcresult`, selecting The Savoy in London, resolving its address/coordinates, saving the stay and opening its trip map. This brings focused UI coverage to nine passing flows. No provider authorization behavior changed.
- Native restaurant, hotel and expanded meeting screenshots were visually reviewed. Debug simulator and physical-iPhone Release builds passed. Both existing iPhone 17 Pro simulators were updated and launched without test flags or erasing data. Real-device performance was not measured.
- No backend schema, account behavior, ticket purchasing or subscription billing changed.


## Map and Travel copy refinement — September 7, 2026

- Removed introductory paragraphs, duplicate flight actions, coordinate explanations and promotional Travel headings. Map empty states use a short label plus one action; flight explanations are available through the options menu. Travel hides unused filters when the library is empty and provides a clear-filters action for no matches. Booking/budget headings and the add chooser are shorter.
- The existing native sheet/tab-navigation UI check passed in `/tmp/SeurDeclutterQA.xcresult`, including compact/expanded placement, dragging, tab-bar stability, return to Travel and closing the panel. Screenshots of Travel and each map section were visually reviewed. No new behavioral tests were added for this copy/layout change.
- Final Debug simulator and physical-iPhone Release builds passed. Both existing user simulators were updated without erasing data.


## Stable Explore transitions — September 7, 2026

- Frame inspection of the supplied recording showed overlapping old/new scroll surfaces and a bright rectangular material flash on returning to Explore. The panel now preserves one ScrollView and its native pan observer across sections, resets content to the top without animation, and animates only the selected-section indicator. Sheet height and the original tab bar retain their existing ownership and gesture behavior.
- The standalone-flight/body-drag regression passed in `/tmp/SeurExploreTransitionQA.xcresult`. Repeated Trips/Flights/Explore switching passed in `/tmp/SeurExploreTransitionVerified.xcresult` at compact and expanded heights, checking one scroll surface, stable header/tab-bar positions, visible search, city selection and selection persistence. The first run sampled the expansion mid-animation; the test now waits for it to settle. A simulator recording was reviewed alongside the supplied recording.
- Final Debug simulator and physical-iPhone Release builds passed; both existing user simulators were updated without erasing saved data.


## Full-page account access — September 7, 2026

- Guests can sign in or create an account from Discover's profile or the Travel toolbar after skipping onboarding. Both use native page navigation; contextual account access in friends, sharing and flight search is full screen. The shared form has travel photography, adaptive typography, inline errors and native keyboard focus. Transparent navigation keeps Back and Done floating above scrolling content without an opaque header block.
- Root navigation restores existing sessions from Keychain. Account settings retain cloud imports, sign-out and deletion; development service settings are separated from sign-in. Local trips are preserved.
- Three focused tests passed in `/tmp/SeurFullPageAccountQA.xcresult`: full-page navigation without a presented sheet or covering tab bar, accessibility text size, and live Supabase registration/login. The live flow verifies mismatched passwords, wrong-password recovery, guest-trip preservation and Keychain restoration after relaunch, then deletes its temporary account.
- Simulator account builds must use `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` for application-identifier/Keychain metadata. Unsigned simulator delivery builds omit it. Final signed simulator and compile-only physical-iPhone Release builds succeeded. The existing iOS 26.4 and 26.5 installations retain their original app identifier through a build-time override, preserving their on-device data without altering concurrent Xcode project settings.
- No Supabase schema or authentication contract changed. Accounts remain username/password based; membership remains a preview.

- After the transparent-header refinement, the terminal-only navigation test passed in `/tmp/SeurGuestPageTerminal.xcresult` (1 test, 0 failures). Follow-up runs initially encountered misrouted simulator taps and a restored signed-in session. The final run resets the QA simulator, allows native navigation to settle, and isolates the guest session namespace; it captures no screenshots. Both existing user simulators were updated and launched through `simctl`.

## Compact flight flow and details — September 7, 2026

- Flight search now uses separate native pages for airline, flight number, departure date and results. Route search separates departure and arrival airports. Back navigation preserves input, every page has a close action, and selecting a result saves through the existing API before returning directly to the map. Failed saves remain on the results page; retries reuse the reservation ID. Manual entry remains available.
- Replaced boxed flight cards with compact rows on the map surface, subtle dividers, airline color accents and a small route graphic. Departure countdowns refresh every minute from the saved airport-local schedule and its time zone. Missing time zones remain unavailable; past schedules do not imply that the aircraft departed. Overnight arrival dates remain explicit.
- Flight details use an integrated departure/arrival timeline with the appropriate gates and terminals beside each airport. Full schedules, aircraft information and recent performance expand on demand. Short content transitions preserve the existing map scroll surface and tab bar; camera movement is quicker, and Reduce Motion is respected. Navigation controls stay on one line at extreme accessibility sizes.
- All 49 existing/updated unit checks passed in `/tmp/SeurFlightFlowQA.xcresult`, including the new duration test. The additional countdown test and the full flight-number/route/direct-save UI flow passed in `/tmp/SeurCompactFlights.xcresult`. Detail/history navigation and large-text input/back/close checks passed in `/tmp/SeurFlightCompactDetails.xcresult`. Screenshots were reviewed. Early iOS 26.4 runs had simulator launch/input failures; final UI verification used an isolated iOS 26.5 simulator. The large-text test restores normal text sizing when it finishes.
- Final signed Debug simulator and compile-only physical-iPhone Release builds passed. Both existing user simulators were updated and launched without testing flags, preserving `com.aurumapp.travel`, accounts and local trips. Normal-size previews are in `iOS/Preview/98-compact-flight-detail.png`, `99-expanded-flight-detail.png` and `100-compact-flight-rows.png` (ignored local artifacts).
- No backend schema or provider integration changed. Live flight calls used existing deterministic test fixtures during UI verification; real-device animation performance was not measured.

## Map header cleanup — September 7, 2026

- Removed the bottom sheet's expand button and three-dot actions menu. Dragging the sheet and its accessible height adjustment remain available. Updated existing UI checks to resize through the handle.
- The simulator build and existing expand/collapse/tab-navigation regression passed in `/tmp/SeurMapHeaderQA.xcresult`, including assertions that both removed buttons are absent. Both existing simulator installations were updated without changing their app identifiers or saved data.
