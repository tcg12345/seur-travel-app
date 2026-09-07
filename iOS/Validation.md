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

## Always-visible map sheet — September 7, 2026

- Removed the map panel's hidden state and the “Explore your world” recovery button. Opening Saved places no longer hides the panel, so returning to Map always reveals the existing sheet.
- The simulator build and expanded existing navigation regression passed in `/tmp/SeurPersistentMapQA.xcresult`, including returning from Saved places with visible, usable sheet controls and no recovery button. Both existing simulator apps were updated with saved data preserved.

## Direct new-trip button — September 7, 2026

- Replaced the Travel toolbar's plus menu with a direct New trip button that opens the existing trip creation form. Removed the JSON import option and its file picker from this page.
- The signed Debug simulator build passed. This small toolbar change was checked in the source diff; no new UI test was added.

## Cleaner trip navigation and scrolling add button — September 7, 2026

- Replaced the stacked Plan/Journal and Agenda/Calendar/Map segmented controls with one underlined navigation row: Plan, Calendar, Map and Journal. Tightened the trip heading and displayed the trip metrics directly on the page.
- Removed the full-width promotional footer. The lower-right Add to plan button animates to a compact plus after scrolling and expands again near the top. The footer reserves a constant height so the transition does not resize the scroll viewport. Separate scroll thresholds prevent flicker near the top; Reduce Motion is respected. Journal uses the same behavior for Log a place.
- The signed Debug simulator build passed. Extended the existing trip-creation UI regression to cover the direct toolbar plus, single navigation row, compact/expanded button states, opening the add flow from the compact button, and Calendar/Map/Journal navigation. It passed in `/tmp/SeurTripLayoutQA.xcresult` (1 test, 0 failures). Reviewed the expanded and collapsed screenshots, saved locally in `iOS/Preview/102-clean-trip-page.png` and `103-collapsed-trip-add.png` (ignored artifacts).

## Shared flight search for trips and map — September 7, 2026

- The trip's Flight add action now opens the same airline/number/date/results and route-search flow as Map, inside the existing add sheet. Its initial date comes from the selected itinerary day or trip start. Selecting a flight saves directly to that trip and closes the add flow without opening a review form.
- The shared flow now accepts an optional trip destination for saving. Trip flights retain airport coordinates and local time zones and appear through the map's existing trip-flight list, without also creating a standalone account flight. Save errors keep the results open; retries reuse the reservation ID. Optional manual entry still saves to the originating trip.
- The final signed Debug simulator build passed. Shared trip search/cancel/direct-save/relaunch/map-linkage and optional manual airport-entry UI checks passed in `/tmp/SeurTripFlightQA.xcresult` (2 tests, 0 failures). Search used deterministic flight fixtures. Reviewed the shared search screenshot. Updated both existing user simulator installations with saved data preserved.

## Plan views and a distinct Journal — September 7, 2026

- Combined the separate Plan/Calendar/Map navigation items into one Plan section with a compact List/Calendar/Map menu on the same row as Journal. Switching back from Journal preserves the selected Plan view; there are no stacked segmented controls.
- Journal now explains that it holds visits, photos, notes and personal ratings. Its action is Log a visit, the empty state describes recording memories, and empty summary metrics are hidden. Existing plans, journal entries, photos, ratings and the planned-place import behavior remain intact.
- The signed Debug simulator build passed. The existing plan/journal persistence and deduplication regression passed in `/tmp/SeurPlanJournalQA.xcresult`. The initial navigation check exposed a parent accessibility identifier masking the new menu; after removing it, the expanded navigation/collapsing-button regression passed in `/tmp/SeurPlanViewMenuQA.xcresult`, covering List/Calendar/Map selection and remembered view state. Both final section screenshots were reviewed.

## Visible trip items in dark mode — September 7, 2026

- Replaced near-black system backgrounds on trip events, hotel/flight bookings, journal entries and the budget panel with a shared warm-charcoal surface in dark mode and white in light mode. Added a subtle outline that strengthens with Increase Contrast, and increased itinerary time-label weight. Card dimensions and interactions remain unchanged.
- The signed Debug simulator build passed. The existing plan/journal persistence and deduplication UI regression passed in dark mode in `/tmp/SeurTripContrastQA.xcresult` (1 test, 0 failures). Visually reviewed dark itinerary and journal screenshots; item surfaces and outlines are clearly separated from the canvas. No new test was added for the styling change.

## Contextual trip search icons — September 7, 2026

- Inline place suggestions now use the selected place category's symbol, including restaurant cutlery, hotel beds, museum columns, parks, cafes and other supported categories. Optional event-venue searches use the event's symbol, such as meetings, concerts, trains or transfers. Airport, city, address and time-zone fields retain their existing search-kind icons. These symbols describe the add/search context; provider results and selection behavior are unchanged.
- The signed Debug simulator build and existing inline restaurant/hotel/attraction/journal search regression passed in `/tmp/SeurSearchIconsQA.xcresult` (1 test, 0 failures). Visually confirmed the restaurant suggestion's cutlery icon in a dark-mode screenshot. No new test was added for this small presentation change.

## Clearer Journal entry workflow — September 7, 2026

- Journal cards now include an explicit Add visit details or Edit entry action. The introductory copy explains the flow, and empty journals no longer show unused filter/grid controls.
- From your plan opens a place picker and then the entry editor before saving. It includes planned place visits and hotel stays, deduplicates candidates, and reopens an existing matching journal entry. Cancel does not create placeholders or change the itinerary. The trip menu uses the same flow.
- The entry editor identifies the place type and place visited first, then presents optional visit date, notes, overall rating and photos. Additional category ratings, price range and personal Michelin records are collapsed under Detailed ratings & more. New/Edit journal entry titles and Save entry clarify where changes are made. Empty place names cannot be saved; existing data and photo import behavior are preserved.
- The final signed Debug simulator build passed. The updated plan/journal selection, cancellation, notes persistence and deduplication regression passed in `/tmp/SeurJournalEntryQA.xcresult`. The final new-entry/date/rating/notes/save/reopen regression passed in `/tmp/SeurJournalDetailsVerifiedQA.xcresult`; earlier attempts exposed a date-control test query, a misrouted simulator startup tap, and a switch-label tap. Tests now wait for navigation and tap the switch thumb. Reviewed final entry/card screenshots. Photo selection control visibility was checked; no new photo-library import was exercised. Both user simulators were updated with saved data preserved.

## Stable map sections and attribution — September 7, 2026

- Explore, Trips and Flights already share one native map and map style. Removed mode-dependent bottom padding that reframed the camera on section changes and hid Explore attribution under the sheet.
- Map and panel now share resting-height calculations. Native attribution is positioned above compact/medium sheets, including the bottom tab-bar inset. Fully expanded sheets retain a bounded map viewport to avoid pushing content beyond the screen. Pins, routes and deliberate city/trip/flight focus remain supported.
- Final signed simulator build passed. Both existing map regressions passed in `/tmp/SeurMapViewportFinalQA.xcresult` (2 tests, 0 failures): repeated compact/expanded section switches, stable attribution position, city-search retention, flight details/history, trip selection and Saved navigation. Earlier checks exposed an accessibility label-frame assertion and an oversized fully expanded map inset; both were corrected. Removed extra screenshot captures and completed final verification through terminal results at the user's request. Installed on both user simulators with saved data preserved.

## Explore dining preferences and compact detail actions — September 7, 2026

- Added a Filters control to the map's Explore section, with restaurant cuisine and price preferences, sorting, website-only and saved-result filters, active summaries and reset. Visible map pins use the filtered results. City guides share cuisine/price controls and include preferences in their search/cache identity.
- Cuisine and price preferences refine Apple Maps natural-language searches. Price is explicitly presented as a preference, not a verified price range; current menu prices still need confirmation with each venue. No new provider keys or backend changes are required. Restaurant preferences do not leak into searches for other interests.
- Replaced the large bottom banners on Explore place details and dining-collection restaurant details with a compact trailing action. Its label collapses to a plus after scrolling down and expands near the top, with a fixed bottom inset and Reduce Motion support. Existing add-to-trip and visit-planning flows remain intact.
- Signed simulator build and all seven CityExplorerTests passed using terminal verification, including search preferences, stale search responses, caching, saved-place persistence and map data. No browser or screenshot verification was performed for this change. Updated both user simulators without clearing saved data.

## Remove nested content cards — September 7, 2026

- Removed the tinted outer card and inner restaurant boxes from city-guide dining collections. Entries now sit directly on the page with vertical separators and a divider above the full-collection link. Removed their fixed height and extra inset padding, and let the section heading wrap naturally.
- Removed the outer box around Explore's city-search section, leaving one clear input surface. Removed decorative icon tiles from shared Explore rows.
- Audited rounded content containers and shared row usage across Explore, Discover, hotel/restaurant details, trips, flights, onboarding and concierge/social screens. The two explicit nested rounded content blocks found by the source scan were removed; the follow-up scan found zero. Native sheets, input controls, status badges and photo clipping are separate from content-card grouping. Documented the single-surface rule in DesignSystem.swift.
- Signed arm64 simulator build and git diff checks passed. This styling-only change used terminal/source verification without new UI tests, browser use or screenshots. Installed on both user simulators with data preserved.

## Simplified city guides and shared map handoff — September 7, 2026

- Replaced the large editorial header/map with a compact city heading, Open map action and saved-place count/toggle. Search is followed by one category chooser and labeled filters; removed the horizontal category strip and duplicate List/Map control.
- Results use flat rows with dividers, shorter category previews and clear empty/retry actions. The hotel-dining collection is a compact navigation row linking to its existing searchable collection. Restaurant preferences, sort/website/wider-area filters, saving places and adding to trips remain available.
- Open map navigates to the existing root Explore map, centers the city and transfers current results, search, interest and filters without issuing a duplicate place search. An explicit request resets nested Map navigation so this also works from a guide opened inside Map. Ordinary tab/section changes retain their current map. Later Search area actions retain the transferred search context, with a visible Clear action.
- Signed arm64 simulator build, eight CityExplorerTests and the updated city saved-filter/map-navigation UI regression passed through terminal verification. Coverage includes saved-place filtering, empty search, carrying saved results to Map, opening Map again from a nested guide, and preventing older async searches from overwriting transferred results. No browser or screenshot inspection was used. Both user simulators were updated with saved data preserved.

## Organized Explore map sheet — September 7, 2026

- Grouped city search with a single aligned category/filter row. Removed the separate glass Filters pill, consolidated active search/filter summaries and reset into one line, and moved Search this area into the results header.
- Replaced the selected city's boxed guide card with a compact navigation row, and made general city-guide browsing a secondary link. Results use flat rows/dividers; selecting a map pin no longer repeats the same place in the list.
- Reset clears transferred text/wider-area context along with filters, refreshing place search only when necessary. Category choice, city selection, filters, map-area search, bookmarking and add-to-trip actions remain available. The map renderer and sheet geometry are unchanged.
- Final signed arm64 simulator build and git diff checks passed using terminal/source verification. No new UI tests, browser use or screenshots were needed for this focused layout change. Installed on both user simulators with saved data preserved.

## Reduce Google Places request volume — September 7, 2026

- Replaced Google-first place/address autocomplete with debounced Apple-first search. Google is an explicit fallback for signed-in users with at least three characters; normal typing/focus/empty Apple results never call it. Repeat taps for an active query are suppressed, and failed/empty Google searches retain Apple matches without automatic retries.
- Added service-level in-flight request deduplication, normalized query validation and a hard live-Google block during XCTest/UI testing. Completed Google predictions are not persisted or cached. City/place UI tests default to fixtures; intentional Apple integration tests now opt in with --live-apple-places, which does not enable Google.
- Signed simulator build and 18 focused tests passed in terminal output: 10 LocationAutocompleteTests and 8 CityExplorerTests. Verified request counts, debounce, simultaneous duplicates, failure fallback, stale responses, short/non-place queries, service-boundary paid-request rejection, fixture selection and existing city data behavior. Google responses were injected stubs; no billable Google calls were made for verification. Both user simulators were updated with saved data preserved. Backend/quota settings are unchanged.

## Shared dark-mode card contrast — September 7, 2026

- Replaced black system-background cards and inconsistent card fills with one warm charcoal surface and a subtle bronze edge in dark mode. Applied across Discover, hotel/restaurant details, trips and journal, saved items, flight entry, Explore input/inset rows, concierge and account/social screens. Consolidated the earlier trip-only surface into the shared modifier.
- Tinted and selected surfaces now tint an opaque base instead of blending into the canvas. Increase Contrast strengthens the fill and edge. Kept flat Explore/flight rows unboxed and preserved photo treatments, card dimensions and navigation.
- Signed arm64 simulator build and git diff checks passed through terminal/source verification. No new tests or paid API calls were needed for this styling-only change. Installed on both existing user simulators without clearing saved data.


## OpenAI and Tripadvisor secret verification — September 7, 2026

- Confirmed the native app targets the active Seur Supabase project and deployed travel-api version 8 reads OPENAI_API_KEY and TRIPADVISOR_API_KEY. Public status reports both present; this checks presence only, not provider access. No provider secrets were retrieved or printed.
- Used a disposable authenticated account for one Tripadvisor location search and one OpenAI hotel overview. Tripadvisor rejected search with upstream HTTP 403; the planned detail lookup was skipped. OpenAI returned HTTP 200 with nonempty text and the expected places array. The temporary account was successfully deleted. No Google or FlightAware calls were made.
- Tripadvisor’s documented domain restrictions require a matching Referer header, absent from the deployed adapter. The configured allowlist is not available through the connected Supabase tools, so its exact restriction and the cause of the 403 remain unconfirmed. No secrets, provider restrictions or deployed code were changed.

## Apple-first activity ideas and optional Tripadvisor details — September 7, 2026

- Activity ideas now search with native MapKit, deduplicate a shortlist of at most eight mapped places, and send it to the authenticated AI route. Supabase validates and strips the supplied data, makes one OpenAI request, and returns selected candidates in visiting order. Removed Tripadvisor search/detail fan-out from recommendations. Empty results incur no AI request; outdated clients receive an update-required response. No Apple Server API credential is needed for this native flow.
- Added optional Ratings & more details links on Explore, restaurant and hotel pages. Tripadvisor lookup runs only after opening that view; the traveler confirms the listing before fetching one detail. Provider data is not saved into Apple/collection records. Included the official attribution logo, provider rating graphic and review source link. No photo/review endpoints or bulk enrichment are used.
- Added server-only TRIPADVISOR_REFERER support with URL validation and a useful access-denied message. Live Tripadvisor/OpenAI calls are blocked during automated iOS tests; existing Google protections remain. Service settings now distinguish a configured Tripadvisor key from a verified connection.
- Signed simulator build, 3 focused iOS tests and 15 backend tests passed via terminal. Backend tests use injected fetch responses without network permission. Deployed the existing travel-api after verifying its current source matched the local baseline; custom authentication and unrelated routes are preserved. Both user simulators updated with saved data intact; QA simulator shut down.
- Live verification passed authentication, legacy-input and empty-shortlist guards and one valid OpenAI response using synthetic test candidates. An initial unauthenticated request timed out before account creation or any provider call; the retry passed. Tripadvisor still rejects the deployed request (upstream 403, exposed as 502). The temporary account was deleted successfully. The exact allowed domain/IP in the user's Tripadvisor settings is still needed to finish that connection; no secret or restriction values were changed.

## Remove fixed coverage totals — September 7, 2026

- Removed the hotel, city and dining-entry catalog totals from Discover and the profile, plus the concierge’s fixed destination count. Replaced the city-guide collection-size label with descriptive dining copy and presented suggested cities as Featured destinations.
- Kept actual search-result counts, individual hotel dining options and personal saved/trip counts. Search capabilities, source attribution and catalog data are unchanged; no universal availability claims were added.
- Native Swift source scan found no remaining fixed 1,513-hotel, 5,755-entry or 12-city/destination marketing strings. Signed arm64 simulator build and git diff checks passed through terminal verification. Updated both existing simulators with saved data preserved.

## Live AI concierge and saveable trip drafts — September 7, 2026

- Replaced the scripted native chat with authenticated OpenAI conversation through Supabase. Added readable long replies, relevant follow-up actions, selected-trip schedule context, optional preferences/saved places, progress, cancellation and retry. Prior structured drafts are included in bounded conversation history so follow-ups can revise the proposed activities. Restaurant questions carry the actual selected venue context.
- Added a bounded Apple Maps discovery phase: at most two searches and one final model response after an initial request. Chat makes no Google or Tripadvisor requests. Server input/output validation, strict time formatting, activity/day bounds and account/application limits constrain requests. The concierge uses its own model setting and produces the structured draft before explaining it, with medium reasoning effort for planning constraints. It has no booking or cloud-mutation tools.
- Draft review supports new trips with flexible/exact dates and compatible existing routes. Saves preserve existing events, reject route mismatches and skip duplicate draft events. Booking references, private booking notes, journal notes and photos are omitted from automatic context. Chat remains in memory across tabs; saved plans use the existing persistent JourneyLibrary.
- Signed simulator build, six focused native unit tests, the concierge chat/review/save UI regression and twenty-one backend tests passed using terminal verification. Tests cover history, bounded discovery, retries/cancellation, private context omissions, draft dates/routes, persistence, duplicates, schema validation and provider requests. Automated tests use fixtures/stubbed fetch without live paid provider calls. No screenshots or browser UI verification were used.
- Updated and launched both existing user simulators with data preserved; the isolated QA simulator was shut down. Deployed the travel API after verifying the previous deployed source matched the local baseline. Live synthetic-trip checks use temporary authenticated accounts and delete them afterward; native Apple lookups are covered separately by injected orchestration tests, while live checks deliberately mark unavailable map data as unverified.
- Final deployed live check passed authentication/invalid-role guards, a detailed three-day Paris plan with vegetarian food, limited walking and a stated budget, and a contextual revision reducing day two to exactly one museum and lunch. Both responses contained valid saveable drafts; the response identified unmapped venues and unverified access. The temporary account was deleted. Earlier evaluation exposed invalid time formatting and prose/draft inconsistencies; strict schema constraints and drafting before explanation corrected those cases. Individual model recommendations still require traveler review, especially operating hours, accessibility and reservations.

## Apple flight notifications, Live Activities and WeatherKit — September 7, 2026

- Signed physical-device Debug build and simulator test build passed with the new embedded WidgetKit extension. Signed app entitlements verified: development APNs, WeatherKit and team `669SG3MPU7`; bundle `com.seurapp.travel`.
- Installed successfully on Tyler’s iPhone 16 Pro. Terminal-only, opt-in diagnostics obtained a real device token and Live Activity push token. Apple APNs accepted one test notification and an ending Live Activity push using key `39Q9C69Z63` and the shared backend sender. Notification permission was still not requested, so this verifies APNs acceptance, not visible notification-banner delivery. The regular Follow flight action requests permission.
- The first native WeatherKit call failed authentication. WeatherKit was missing under the identifier’s App Services tab. After the owner enabled it, the same signed app successfully fetched a ten-day forecast and Apple Weather attribution on the physical iPhone.
- Final focused native run: **8 tests passed**, covering ActivityKit state/time zones, weather date bounds and six existing concierge regressions. Final backend run: **26 tests passed**, including signed APNs requests, flight-change detection, token rotation preserving activity registration, malformed inputs and existing concierge/place/contract regressions. Automated checks used no paid live providers.
- Live Supabase integration checks passed: unauthenticated access denial; owner-only listing, update and deletion; cross-account isolation; single-use worker ticket replay rejection; logout session revocation and cascading watch deletion. Both temporary accounts were deleted. The seeded watch was never due, so it caused no FlightAware lookup or push.
- Notification migrations and the final Edge Function were deployed. The five-minute cron and server-only tables/RPCs are installed. Security advisors report no new findings; the pre-existing Auth leaked-password-protection warning remains outside this change.
- Private APNs signing material is stored in Edge Function secrets, never source control or the app. The debug activity and protected diagnostic file are removed after testing. Live airline-change delivery through the scheduled worker and TestFlight/production APNs have not been exercised; only development APNs was tested. Layout/performance were not verified through screenshots or browser automation.

## Automatic aircraft position on Map — September 7, 2026

- Opening a saved flight automatically requests its reported position once the selected FlightAware departure has left the gate and has not landed or been cancelled. Position polling runs every 90 seconds only with Map selected and the app active; duplicate attempts within 60 seconds are suppressed. No new API key or backend deployment is needed.
- The aircraft marker uses reported coordinates and heading. The first timestamped report centers the map; later updates preserve the traveler’s camera. A visible Show on map action recenters it. Reports older than five minutes, future-dated by over one minute, or missing a timestamp are treated as last-known positions. Failed refreshes retain the last report with an explicit message; no position is extrapolated along the route.
- Focused terminal checks passed: six FlightMapTests, including airborne eligibility, timestamp freshness, request throttling, stale response rejection after changing departures and existing map regressions. Signed physical-device build passed. No screenshots/browser QA or paid provider requests were used; current FlightAware position coverage for a real airborne flight remains unverified in this run.

## Stable map beneath the bottom sheet — September 7, 2026

- MapKit now reserves a consistent compact-sheet inset. Sheet detents and flight-detail selection no longer change the map viewport, eliminating their implicit camera refits during snap animations.
- Replaced the large moving refractive glass sheet with standard material and a canvas tint. The sheet keeps a constant horizontal inset so its content does not change width and reflow throughout a drag. Drag translation remains local to the sheet.
- Terminal-driven UI regression passed with zero failures: repeated expand/collapse gestures in Explore, Trips and Flights preserved camera latitude/longitude within 0.0001 degrees, camera distance within 20 meters, heading/pitch within 0.01 degrees, the system tab bar position and a single scroll surface. DEBUG-only camera measurement is available only in the map test fixture mode. No screenshots were taken by this test.
- Signed iPhone build passed. This verifies camera stability and gesture regression; physical-device frame timing and network-dependent map tile rendering were not benchmarked.

## Subtle, readable trip weather and an off switch — September 7, 2026

- Weather now uses a flat accented row, a larger condition symbol and explicit High/Low labels with aligned, rounded temperatures and locale-appropriate units. This fixes the excessive decimal digits that looked like coordinates. No geographic coordinates are displayed.
- Apple Weather attribution remains linked as required by WeatherKit. The small mark uses template rendering with the system secondary foreground, preserving contrast in either appearance without a button background.
- Discover → profile → Trip weather is a persistent, default-on toggle alongside Appearance. Turning it off hides all destination-weather rows and rain suggestions, cancels pending service tasks, clears the forecast cache and prevents new weather fetches. Other trip features remain usable.
- Four focused Apple feature tests passed, including whole-degree Fahrenheit/Celsius output, persistent preference behavior and existing activity/weather-window coverage. Signed iPhone build passed after the explicit High/Low label adjustment. Verification used terminal checks; no live weather requests or screenshots were needed.

## Dedicated Friends tab — September 7, 2026

- Added Friends immediately after Travel, with Trips/People/Messages sections, friend invitation management, profiles, shared-trip search and period/saved filters, account-scoped bookmarks, exact-date overlap hints, private/group conversations, a direct sharing composer, confirmations and audience-management entry points. Removed the old nested Friends selector from Travel.
- Shared itineraries now show readable flights, stays, day-by-day events and journal entries/photos. The viewer fetches current authorization before displaying plan contents and clears them on refresh failure. Recipient copies remain explicitly private; shared editing is owner-managed and published updates require sharing/uploading again.
- Per the owner’s preference, all five main tabs remain visible. Search now opens from Discover/Map magnifying-glass actions and existing Discover shortcuts; no More tab is introduced.
- Simulator build, final signed iPhone build and **five Friends unit tests plus one UI flow passed**. Tests cover period/date logic, flexible dates, filtering/bookmarks, country/date overlap boundaries, exact-member conversation reuse, account data clearing, five-tab placement, shared itinerary navigation, People/invitations, Messages, Travel simplification and Search presentation. No screenshot capture or real invitations were used in the native flow; synthetic fixture mode blocks network mutations.
- **Fourteen backend contract/notification tests passed.** The extended live smoke suite passed against Supabase: authentication, cross-account access, photos/redaction, stale updates, friend requests, groups, direct private itinerary feed inclusion, third-party exclusion, anonymous/authenticated direct-RPC denial, removal after friendship revocation, links, PDFs and logout. All temporary accounts were deleted. An initial test assertion incorrectly compared uppercase fixture UUIDs to normalized database UUIDs; case normalization fixed the test and the final full run passed.
- Deployed source matched the committed baseline before the one-route update. Applied the new service-only feed RPC migration and deployed the Edge Function. Security advisors reported no new findings; the pre-existing leaked-password-protection warning remains unchanged. No paid provider requests or messages to existing users were made.

## Discover redesign — September 7, 2026

- Replaced the category-dependent promotional feed with a stable destination-first home: city search, four direct browse actions, one latest-trip/create-trip row, restrained stay inspiration, and a Concierge shortcut. Sections use open space and dividers rather than nested cards. City entry copy now explains the next action directly.
- Dining and Things to do retain their category when a city is selected; Stays clears stale collection filters. Existing hotel details, city guides, flight search, personalization, profile and global search remain reachable. Trip continuation includes older trip document kinds.
- Two focused terminal-driven UI tests passed (0 failures): destination/category navigation, city-guide category propagation, new-trip entry, large accessibility text, existing-trip continuation, hotel details and Concierge navigation. No browser or screenshot review was used. The shortcut grid adapts to two columns at accessibility sizes.
- Final signed generic-iPhone Debug build succeeded and installed successfully on Tyler’s connected iPhone 16 Pro. No new provider requests, subscriptions, credentials or backend changes were introduced.

## Travel wishlist — September 7, 2026

- Added Trips/Wishlist navigation within Travel. Existing hotel, restaurant, Explore-place and city bookmarks feed the wishlist; collection-backed restaurant representations are deduplicated. Custom ideas include destination/type, notes, web links, collections and Top picks. Search, filtering, sorting, editing, removal and original-place navigation are functional.
- Wishlist places continue into existing or newly created trip editors, carrying notes and links. Destination ideas prefill trip creation. Existing matching itinerary records are reused, planned items link back to their trips, and wishlist removal preserves itinerary records.
- All three new data tests and both selected end-to-end UI flows passed across the final runs. Coverage includes bookmark persistence/deduplication, custom-idea validation and editing, collection normalization/filtering, destination identity, corrupt-data preservation, notes and Top picks across relaunch, event planning/removal, saved-hotel planning with new-trip continuation and destination-to-trip creation.
- Initial UI attempts exposed test-only issues: the in-memory map fixture was relaunched before being persisted, and iOS exposed duplicate accessibility representations of its confirmation control. The test now persists the trip before relaunch and targets the visible confirmation control. Final tests passed with zero failures.
- Final signed iPhone Debug build succeeded. Device installation was attempted twice but could not complete: the connection interrupted, then reset by the iPhone. The build is ready for installation once the device reconnects. Verification used terminal builds/XCTest; no browser or manual screenshot review. Wishlist storage is private and local, with no new backend dependencies or paid requests for wishlist operations. See `Wishlist.md`.

## Flight detail sections and punctuality colors — September 7, 2026

- Flight details now use wide status, departure, arrival, tracking/alerts and extra-information sections with 12-point outer margins. Gates/terminals stay inside their airport section as plain metrics, without nested cards. Shared adaptive surfaces preserve dark-mode contrast.
- Independent departure/arrival labels and times use green (on time), blue (early), amber (late/diverted), red (cancelled) and neutral (unknown). Actual/estimated timestamps take precedence over reported delay values; missing timing is never assumed on time. Text and symbols accompany each color.
- Punctuality unit coverage passed for separate endpoint delays, early arrival following late departure, actual timestamp precedence, on-time, cancellation/diversion and missing-data states. The terminal UI test passed for displayed 30/35-minute delays, expandable performance details and returning to the flight list. Its initial attempt used an identifier hidden by SwiftUI's parent accessibility representation; the final selector checks the visible timing labels.
- Signed iPhone build succeeded and installation completed on the connected iPhone 16 Pro. This installation also includes the preceding Wishlist update. No browser or manual screenshot verification was used, and polling/provider behavior is unchanged.

## Map sheet drag and edge expansion repair — September 7, 2026

- Removed the permanently inset surface. Its side margins interpolate continuously from 12 points at compact height to zero at full expansion; the content width stays fixed.
- Kept the inner scroll layout at expanded height and changed only its visible outer height during dragging. Active drag updates disable implicit animations; detent settling retains a spring. MapKit's viewport/insets remain independent of sheet movement.
- Signed iPhone build succeeded and installed on the connected iPhone 16 Pro. All three targeted terminal checks passed: interpolation/bounds unit coverage, actual full-width expansion and collapse after scrolling flight details, and repeated Explore/Trips/Flights dragging with unchanged map camera, viewport and tab-bar position. No browser or manual screenshot checks were used.

## Immersed flight details and detailed timetable — September 7, 2026

- Replaced large airport cards with open route/time sections, a restrained status ribbon and compact gate/terminal tiles. Aircraft and registration use small independent tiles; tracking, alerts, performance and notes remain accessible below. Endpoint timing colors retain text labels and actual/estimated/scheduled distinctions.
- Added an always-visible six-stage timetable with scheduled, estimated and actual columns, local dates and safe paired-timestamp taxi durations. Missing data remains explicit. Accessibility sizes stack columns. Supabase and Python flight adapters now preserve provider runway estimates without extra requests or changes to polling/cache behavior.
- One native timetable unit test and one terminal-driven UI flow passed with zero failures, covering stage order, taxi calculations/missing values, local times, field round trips, timetable navigation, performance disclosure and returning to Flights. Ten Supabase contract tests and seven Python flight-provider tests passed. No browser or manual screenshots were used.
- Deployed travel-api; remote source verification confirmed both runway-estimate fields, and the status endpoint returned valid JSON. Verification did not request paid flight data.
- Final signed iPhone build succeeded and installed successfully on Tyler’s connected iPhone 16 Pro. Map sheet geometry and gesture implementation were unchanged.

## Map sheet gesture handoff refinement — September 7, 2026

- Sheet drags now anchor to measured visible height instead of the previous detent target. Drag limits rebase immediately when reversing direction; horizontal header gestures no longer trigger a detent change. Removed the blanket detent animation in favor of explicit settling animations.
- The scroll bridge holds the current content position during resizing and cancels unused scroll momentum after the sheet takes ownership. Section/detail navigation resets its scroll state deliberately. Native vertical pans remain enabled for short content; an initial attempt to disable bounce blocked short-list expansion and was corrected before installation.
- Final terminal test run passed all four targeted checks: interrupted-drag/boundary state coverage, expanding/collapsing through short-list content, preserving scrolled flight detail position across header resizing, and stable map camera/viewport/tab-bar position across all three map sections. No browser or screenshot review was used. These checks verify gesture behavior and geometry, not physical-device frame-rate performance.
- Final signed iPhone build succeeded and installed on Tyler’s connected iPhone 16 Pro. No backend or paid provider requests were introduced.
