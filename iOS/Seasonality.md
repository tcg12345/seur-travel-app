# City seasonality

`Aurum/Resources/CitySeasonality.json` contains hand-curated, offline guidance for the twelve hotel-catalog cities: Bangkok, Paris, London, Tokyo, New York, Singapore, Hong Kong, Dubai, Shanghai, Istanbul, Macau and Kuala Lumpur. It is bundled with the app; no account, provider request, Supabase migration or Edge Function deployment is needed.

## In the app

Seasonality appears beside dates in trip creation, destination editing, legacy trip destination setup, template scheduling and wishlist scheduling. Flexible trips offer a month comparison without treating their internal January 2000 dates as real travel dates. Each multi-city route row uses the **projected stop dates**, including transfer allowances, so moving a city updates its months and holiday notices immediately. Route suggestions continue to optimize transfers; seasonality is guidance for the user's choice.

The month calendar shows all twelve months, highlights months touched by the stay, and includes holiday descriptions, source links and a review date. Unsupported cities have no curated card. City matching ignores case, diacritics and extra whitespace, recognizes explicit aliases, and checks a supplied country code. Region-qualified Maps names can match their complete first city component only when the country is known; arbitrary substrings do not match.

## Data contract and editorial limits

- `schemaVersion: 1`, `reviewedOn: YYYY-MM-DD`, and twelve unique `cities`.
- Each city includes a stable `id`, `name`, ISO `countryCode`, explicit `aliases`, twelve ordered `months`, `notices`, and named HTTPS `sources`.
- Each month has `month: 1...12`, `season: peak | shoulder | quieter`, `weather`, and `rain`. Seasons are editorial estimates of the visitor pattern, informed by tourism guidance and climate. Weather bands describe broad daytime feel and rainfall patterns; they are not numeric climate normals, temperature limits, forecasts or guarantees of prices. Events can override the monthly pattern.
- Notices use `annual` for recurring month/day windows, `dated` for explicitly researched occurrences, and `checkCalendar` when exact local dates have not been verified. Every notice includes a direct source URL and carefully scoped opening-hours or travel advice.
- `annual` has `start`/`end` in `MM-DD`; windows may wrap New Year. Golden Week entries describe the core recurring travel window, with explicit reminders that observed days and official allocations can extend it. They do not claim a complete public-holiday schedule.
- `dated` has `occurrences: [{start, end}]` with inclusive ISO dates. Current entries cover 2026 for Shanghai, Istanbul and Macau, and 2026–2027 for Singapore and Hong Kong Lunar New Year. Hong Kong's 2027 substitute holiday is included. A trip touching an unlisted year gets an explicit calendar-check prompt even if there is no known overlap; last year's Gregorian dates are never repeated automatically.
- `checkCalendar` always prompts for local dates. Dubai and Kuala Lumpur Ramadan guidance uses this mode rather than presenting estimated moon-sighting dates as confirmed. The Singapore Ramadan/Hari Raya entry also asks for the local calendar. The dataset is a selection of important travel considerations, not an exhaustive holiday or closure feed.

Assessment uses Gregorian calendar days independent of the device's time zone, includes both arrival and departure days, covers every touched month in travel order, and handles New Year crossings. Missing, reversed or invalid dates return no dated assessment. A ten-year range cap prevents unbounded work on malformed imports. No itinerary dates, bookings or persisted documents are mutated by the layer.

## Maintaining the JSON

Review city climate guidance and local holiday calendars before changing an entry. Preserve source URLs, add each verified moving-holiday year explicitly, and update `reviewedOn`. Do not turn venue-specific reports into citywide closures: the Paris August note concerns **some independent restaurants and shops**, while the Dubai note explains that daytime dining remains available. Confirm substitute days against each jurisdiction rather than copying a neighboring country's calendar.

The bundled catalog test enforces city/month coverage, valid dates, unique identifiers and HTTPS sources. Additional tests cover aliases and country mismatches, overlap boundaries, all touched months, cross-year windows, Golden Week, lunar dates, unknown-year prompts, flexible/invalid dates and projected route changes. Simulator UI tests cover opening the calendar during date selection and moving Paris out of August. The existing route suggestion/apply/persistence flow is included in regression validation.
