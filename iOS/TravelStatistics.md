# Your travel

Profile starts with a four-number Your travel section; the Trips library has a compact version. Both open TravelStatsView with All time and individual-year filters. The page includes Michelin stars and distinct starred restaurants, countries/cities, nights, miles/kilometers, favorite brands, most-visited cities, longest completed trip, average scores, recorded spending by currency, a visited/planned globe, and native Swift Charts trends.

## Recorded versus planned

TravelStatistics is a deterministic local aggregation over JourneyLibrary documents. Templates are excluded; repeated document IDs use the newest local revision. A trip contributes once its dated end is past, or once it has a journal and has begun. Finished trips count their stops. During a trip, stops require a matching journal entry and must not have a future arrival date. Flights never create country or city visits. Upcoming destinations have separate counters and lighter map annotations.

Only recognized country codes contribute to country totals. City names are case/diacritic folded. Hotel nights count elapsed calendar nights, not rooms, and use the hotel destination’s time zone when known. Trips without hotel records use recorded stop nights, explicitly labeled nights away. Flights contribute great-circle distance only after their arrival day has passed in the arrival zone. This is a conservative recorded-flight estimate, not independently verified flight history.

Year filters split nights at January 1 and include visits overlapping that year. Finished-trip counts and longest trips use the trip end year. Visits use their journal date or the finished trip’s end date; otherwise undated entries are lifetime-only and are called out in the UI. Michelin stars count restaurant journal entries; distinct starred restaurants are counted separately. Repeated same-place/day entries and repeated flight/stay records do not inflate those metrics. Favorite hotel brands require at least three known-brand stays; ties are shown explicitly. Independent/unknown hotels are not combined into a pretend brand.

Costs retain their entered currencies and use event dates, hotel check-in dates and flight departure dates for the year filter. There is no currency conversion. Spending and booking details never appear on the share card.

## Metadata and storage

JourneyStop.countryCode and PlaceRecord.brand are optional Codable fields, so legacy archives retain their decode path. Country codes are captured from Apple Maps selections, normalized during local saves, and retained by route editing. The catalog already has hotel brands: catalog wishlist selections carry them directly; older matching stays are enriched locally. Manual hotel records have an editable brand field.

TravelStatsMetadata coalesces work across the profile, library and stats views. It resolves known country names offline before attempting a CLGeocoder reverse lookup for older coordinate-bearing stops. Successful/no-result lookups are cached per coordinate on device; network failures back off for 24 hours. Requests are paced, skip UI tests, and never use Google Places. A late response cannot overwrite an edited stop. Brand lookup in chart aggregation uses prebuilt indexes rather than scanning the hotel catalog for each year.

Stats work from the local library offline. There is no automatic cloud-library merge or extra photo download. Restore your own saved cloud trips from Account after reinstalling. The existing backend preserves the optional fields, validates their types/lengths, and retains them in reusable templates.

## Sharing and checks

Share your travel card produces a 1080×1920 JPEG through ImageRenderer and ActivityShareSheet, filtered to All time or the selected year and respecting the distance unit. It needs no API or map snapshot request.

Verified with 40 JourneyTests, 18 backend contract tests, a disposable-account live private save/restore test, and successful simulator and signed-device builds. Coverage includes future Tokyo plans, connection airports, journaled in-progress stops, year boundaries, hotel-local dates, country aliases, brand thresholds, duplicate flights, undated memories, optional-field decoding and image dimensions. No paid place/flight providers were called by these tests.
