# Native flight booking and cabin experience

## User direction — September 6, 2026

The user wants to continue this idea: search, compare and book flights inside the native iOS app, with detailed information about the actual cabin and seat being sold. This is a saved product direction for future work. Real booking and payment implementation is deferred; supplying the FlightAware key enables tracking, not ticketing.

The defining example is Delta One: distinguish newer suites from older seats on a particular flight, and show representative photos of the matched cabin product. Aircraft model or age alone is insufficient because the same model can have multiple configurations and refurbishment states.

## Intended experience

- Native search, fare comparison, passenger entry, seat selection, checkout and booking confirmation, followed by management of the booking in the trip.
- A cabin detail page with licensed seat/interior photos, seat layout, seat width and pitch, legroom, bed length, recline or lie-flat capability, privacy doors and direct aisle access where verified.
- Wi-Fi, charging, entertainment, meals and applicable lounge benefits, plus baggage allowances, seat-selection charges and change/refund conditions for the exact fare.
- Side-by-side comparisons that make cabin differences clear before purchase.
- Match the operating airline, dated flight segment, aircraft subtype/configuration and seat map. Incorporate tail assignment and refurbishment data when reliable information becomes available.
- Clearly distinguish a matched current configuration, an expected product and an unconfirmed cabin. Aircraft substitutions can change the product even after booking; refresh the match and explain meaningful changes.
- Use verified provider data and appropriately licensed photos. Do not present guesses or AI-generated seat imagery as the actual product.

## Provider approach to validate

The initial candidate is **Duffel for flight retailing**, paired with **ATPCO Routehappy for cabin amenities and licensed visual content**. Validate Delta coverage, point-of-sale availability, fare families, seat-map coverage and servicing support with the actual provider account before committing to this combination. Travelport is another candidate with a published Delta distribution agreement. Provider access and coverage are not yet confirmed.

Duffel offer data can include some seat/amenity information; seat maps are not available for every airline or flight. Routehappy can supply richer seat and amenity content, subject to a commercial agreement and supported targeting. Neither an aircraft type nor a generic airline photograph guarantees a specific interior.

FlightAware remains a separate tracking integration: status, estimates, aircraft identifiers and optional position/history. It does not supply a native ticketing engine or guarantee exact cabin-product identification.

## Implementation sequence

1. Confirm airline coverage and obtain booking-provider sandbox access plus cabin-content access and image rights.
2. Build a complete native sandbox journey with explicit test offers, passenger forms, seat selection, payment simulation, confirmation and trip integration. No real charges or ticket issuance.
3. Add cabin matching and comparison with source provenance, confidence and fallback states; validate representative Delta configurations against provider responses.
4. Deploy the HTTPS backend and implement offer repricing, expiry handling, secure payment integration, idempotent order creation, reconciliation and authenticated webhooks.
5. Complete production provider onboarding and establish refunds, changes, cancellations, schedule-change handling and customer support before enabling real purchases.

## Needed before production

- A booking-provider business account and live activation, with confirmed airline coverage and payment/funding arrangements.
- Licensed cabin amenities and imagery, and permission to display/cache that content in this app.
- A deployed backend with secrets managed on the server, operational monitoring and a servicing process for ticketed bookings.
- A supported payment integration. Do not promise Apple Pay through Duffel Payments without rechecking support; the previously reviewed guide did not support it. A compatible alternative payment provider may be needed.

No production plan, paid content contract or live-ticketing capability has been activated as part of saving this note.

## Reference material from the feasibility review

- [Duffel offers](https://duffel.com/docs/api/offers), [seat maps](https://duffel.com/docs/api/v2/seat-maps/get-seat-maps), [getting started](https://duffel.com/guides/getting-started) and [collecting payments](https://duffel.com/guides/collecting-payments-from-your-customers).
- [Routehappy amenities through Travelport](https://support.travelport.com/webhelp/uAPI/Content/Air/Shared_Air_Topics/RouteHappy_Amenities.htm) and [ATPCO seat-characteristic targeting](https://www.atpco.net/sites/atpco-public/files/all_pdfs/atpco-seat-characteristic-targeting-solution-sheet.pdf).
- [Travelport–Delta distribution agreement](https://www.travelport.com/press-releases/travelports-renewed-distribution-agreement-with-delta-air-lines-confirms-ndc-integration).
- [Delta aircraft overview](https://www.delta.com/us/en/aircraft/overview), [A350 configurations](https://www.delta.com/us/en/aircraft/airbus/a350) and [announced cabin updates](https://news.delta.com/suite-spot). Announced future cabins must not be labeled as currently operating.

Recheck provider coverage and product specifications when implementation begins.
