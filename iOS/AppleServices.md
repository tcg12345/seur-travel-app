# Apple flight alerts, Live Activities and weather

The app identifier is `com.seurapp.travel`, signed by team `669SG3MPU7`. The Live Activity extension is `com.seurapp.travel.FlightActivity`. Keep these identifiers consistent with provisioning and the APNs topic.

## Using the features

Open a flight’s details, select a live departure, and choose **Follow flight**. Sign-in and notification permission are required. Seur monitors followed flights for departure reminders, gate/terminal changes, delays, cancellation, diversion, departure and arrival. **Turn off** stops that device’s watch. Signing out or deleting the account removes its server registrations; sign-out requires connectivity to confirm revocation.

**Show on Lock Screen** starts a Live Activity with airport-local times, the departure countdown and the last reported gate/terminal. Live Activities must be enabled in iPhone settings. Start it near departure; Apple limits an activity’s active lifetime to eight hours. A stale indicator appears if updates stop. Notification delivery and airline data can be delayed; this is not an airline boarding alert guarantee. Tapping the activity opens Map → Flights.

Trip days within Apple’s available forecast window show destination conditions, high/low temperatures and rain probability. Rainy forecasts offer an indoor-alternative prompt for Concierge with the selected trip and forecast context. Forecasts share a 30-minute in-memory cache and concurrent requests are deduplicated. Weather uses destination coordinates; it does not request access to the traveler’s location. Apple Weather attribution links appear alongside forecasts. Far-future and flexible-date trips explain when forecasts become available.

## Apple setup

Enable Push Notifications for the app identifier. Enable WeatherKit under **both Capabilities and App Services** in Apple Developer → Identifiers, and keep WeatherKit enabled in Xcode. Native WeatherKit uses the signed app entitlement and needs no separate weather API key.

The APNs signing key is stored only as Supabase Edge Function secrets: `APNS_PRIVATE_KEY_B64`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`. The configured key supports both environments. Debug builds use development/sandbox; Release uses production. `.p8` files are excluded from Git and must never be embedded in the app. Device/activity tokens stay in private server tables and are not logged.

The widget is a separate embedded WidgetKit target sharing `FlightActivityAttributes.swift` with the app. Keep its ContentState keys/types synchronized with `activityState()` in the backend.

## Monitoring and costs

A five-minute database cron checks whether work is due. It invokes the worker only for pending watches, using a short-lived, single-use ticket. The worker claims at most 20 rows with a lease and batches identical flight lookups. Far-away departures poll every 30 minutes; nearer flights every five. FlightAware requests reuse its existing cache and provider caps, with an additional 120/hour monitoring limit. No followed flights means no monitoring provider traffic. This limits spending but is not a provider billing cap; more active travelers will require capacity and budget review.

Flight watches belong to an account, installation and session. RLS, server-only grants and authenticated ownership checks protect registration endpoints. Expired sessions cannot claim work; logout/account deletion cascades registrations. Arrival/cancellation ends successful monitoring, and watches expire automatically.

## Verification

See `Validation.md` for actual results. Automated tests never use real Apple or paid provider credentials. DEBUG-only `--apple-service-check` can create a temporary `SEUR TEST` Live Activity and request one destination forecast. It stores private diagnostic tokens in the app’s protected cache; do not print or commit that file. `--apple-service-cleanup` ends only that test activity and deletes the diagnostic file. Neither diagnostic path is present in Release builds.
