# Seur widgets

The existing `SeurFlightActivity` WidgetKit extension now contains four Home Screen widgets alongside the original flight Live Activity. Its bundle identifier remains `com.seurapp.travel.FlightActivity`; its display name is Seur Widgets.

| Widget | Home Screen sizes | Lock Screen sizes | Behavior |
| --- | --- | --- | --- |
| Today in Seur | Small, medium, large | Inline, rectangular | Active trip's remaining saved activities, flight times and date-only hotel reminders, in the appropriate local time zones. Completed activities disappear after saving. |
| Next Trip | Small, medium | Inline, rectangular, circular | Destination-calendar-day countdown to the earliest upcoming trip; shows the active trip if there is no upcoming trip. |
| Travel Profile | Small, medium, large | — | All-time countries, cities, trips and nights from the existing travel-statistics engine. Medium adds the last completed journey; large adds three recent completed journeys, most-visited cities and Michelin stars. Tap to open the full profile. |
| Trip Budget | Small, medium | — | Completed-event and paid-booking spending against the target, with elapsed-calendar-day burn rate in medium size. Uses cached FX and displays its date; missing conversion rates preserve original-currency amounts. |

Tap Travel Profile to open the full travel statistics screen through `seur://profile`; other widgets open the trip, Today view or budget. Missing/deleted trip links display an unavailable state. The existing `seur://flights` Live Activity route remains intact.

## Visual design

All four widgets share a restrained warm-neutral palette: soft ivory/stone in light mode and warm charcoal in dark mode, with muted champagne accents. Subtle gradients and fine linework keep the backgrounds consistent. Their layouts retain individual character: Today has a local-date badge and itinerary rail; Next Trip has a departure-ticket countdown; Budget has a spending dial or segmented bar; Travel Profile has globe linework and passport-style statistics. The flight Live Activity uses the same palette, and Lock Screen widgets retain compact typography and route/date motifs.

Artwork is drawn locally with SwiftUI vectors, with no downloaded imagery or new provider requests. Full-color, dark, tinted and background-removed presentations use the appropriate foreground treatment; iOS can replace the palettes when a tinted or clear Home Screen appearance is selected. Existing widget kinds, App Group, timelines, links and flight update data remain unchanged. Existing placements update after the app publishes and iOS reloads the widgets.

## Adding widgets

In the app, **Discover → Your workspace → Widgets** shows illustrative previews and instructions. The repeated Travel promotion has been removed. A one-time invitation with a preview from saved trip data appears on Trips once a dated trip exists, after any trip editor has closed. Empty libraries, templates and flexible wishlist plans do not trigger it. Dismissing the invitation, opening the guide or following a widget link retires it on that device, including across app relaunches. Existing travellers can receive the invitation on their next visit to Trips.

On the Home Screen, hold an empty area, choose **Edit → Add Widget**, search for **Seur**, select a size and tap **Add Widget**. For Lock Screen widgets, hold the Lock Screen, choose **Customize**, and select **Add Widgets**. iOS controls placement; the app cannot place widgets on a user's Home Screen automatically.

## Shared data and refresh behavior

Both targets declare App Group `group.com.seurapp.travel`. The app atomically writes `journey-widgets-v1.json` to that group's container after changes to the saved library or cached rates, and on foreground activation. It then requests reloads for all four widget kinds. The extension never reads the private journey archive or calls a backend/provider.

The itinerary portion of the snapshot contains at most twelve current/upcoming dated trips, prioritized with the same active-trip rules as Today. Templates, flexible wishlist trips and ended trips are excluded. It holds thirty days of projected schedule data plus budget aggregates. Photos, notes, booking references, authentication/session data and companion identities are omitted. Saved local trips remain available after cloud sign-out, just as they do in the app. Removing a local trip replaces the snapshot; publication failure attempts to remove the previous cache rather than leave deleted plans on display.

The optional profile portion summarizes the entire deduplicated local history, independently of the twelve-trip itinerary limit. It uses the same all-time statistics engine as the in-app travel profile, excludes templates and unvisited future plans, and includes at most three completed journey titles/routes/end dates. History remains available when there is no active or upcoming trip. Counts are labelled with the snapshot’s as-of date and update when the app publishes; they do not predict future visits. Older version-1 caches without a profile remain readable and prompt opening Seur to refresh it.

The cache is protected until first device unlock. Widget content is marked `privacySensitive` for system privacy/redaction settings. Empty, unreadable, incompatible and expired caches show an app-opening/empty state. A snapshot expires after thirty days without opening the app. Cache reads and writes are limited to 5 MB, and test libraries cannot overwrite the user's shared cache.

The provider creates hourly entries for the next six hours, with additional item-end and local-midnight boundaries, capped at 48 entries. Each rendered entry retains only the chosen active/upcoming trips and today's items, plus the compact profile summary. WidgetKit schedules actual delivery and may defer updates. These are saved itinerary times, not live flight status; the separate flight Live Activity retains its existing live behavior. Budget FX is a saved estimate, not a fresh widget network quote.

## Xcode signing

The project has App Groups enabled for **Seur** and **SeurFlightActivity**, with matching entitlement files:

- `Aurum/Aurum.entitlements`
- `Aurum/Widgets/Widgets.entitlements`

A physical-device build requires an Apple Developer account signed into Xcode. Register/select `group.com.seurapp.travel` for both App IDs under Signing & Capabilities, then regenerate both provisioning profiles with automatic signing. The initial signing blocker was resolved on September 9, 2026. A signed Debug build with the shared App Group in both targets was successfully installed and launched on Tyler’s iPhone 16 Pro. Xcode can now obtain the required provisioning profiles for this team; another Mac or developer account still needs the setup above.

## Source layout

- `WidgetData.swift`: minimal Codable contract, calendar selection, timeline boundaries, strict deep links and atomic shared store. Compiled in app and extension.
- `WidgetProjection.swift`: projects existing Today/budget/travel-statistics models into the shared contract and publishes changes. App only.
- `WidgetViews.swift`, `WidgetSample.swift`: common presentations and explicitly fictional gallery/guide samples.
- `TravelWidgets.swift`: WidgetKit providers/configurations. Extension only.
- `WidgetHelpView.swift`: in-app guide, one-time discovery state/invitation and deep-link destinations.

Apple references: [widget extensions](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension), [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups), [timeline updates](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

The device-level gallery/placement UI test is opt-in: set `SEUR_WIDGET_GALLERY_TEST=1` in the Xcode test scheme to run it. It changes the test device's Home Screen by adding a widget. Routine tests skip it and retain the guide/deep-link flow. The real gallery and placement flow were verified on the iOS 26.5 simulator; an empty-state Today widget remains on that test simulator because UI fixtures are intentionally not published to the shared cache.
