# LiteAPI follow-up — sandbox booking and native iOS payment

Prepared September 10, 2026; updated September 11, 2026. **This document remains an unsent draft.** The user has separately consulted LiteAPI’s chatbot. No API key, payment secret or real guest details are included.

## 1. Sandbox booking details differ from the accepted prebook

Provider booking: `OBcWcW2dZ`

Client reference: `seur-test-611f4080-3d72-46f7-bfa7-cf5d5bc22460`

Prebook: `GNV8XlRfj`

Property: `lp1aae8` — Mandarin Oriental, Bangkok

Dates: October 10–13, 2026

Flow: sandbox rates → prebook with `usePaymentSdk: false` → explicit confirmation → `ACC_CREDIT_CARD` sandbox simulation. Synthetic contact details only; no real charge.

| Field | Accepted prebook | Retrieved booking |
| --- | --- | --- |
| Adults | 2 | 1 |
| Meal plan | Breakfast Included | Room Only |
| Cancellation penalty | USD 503.40 from October 9, 08:00 GMT | USD 1,509.90 from October 10, 23:59:59 GMT |
| Room subtotal | USD 1,509.90 | USD 1,509.90 |

The provider reports `CONFIRMED`, but Seur correctly leaves the attempt in `needs_support`, because the booked product does not match the accepted quote. The stable reference was reused for retrieval, with no second booking submission.

Is the sandbox intentionally returning placeholder room/occupancy/cancellation data? If so, please provide a documented test fixture/property that preserves the full prebook contract, and clarify how production differs. We need to verify a successful booking without bypassing room, meal, occupancy, fee or cancellation checks.

## 2. Package restriction disagrees with structured flags

The same prebook had `isPackageRate: false` but its room remarks explicitly said it must only be sold as part of a package. The search classified the offer as `standard`. Seur now rejects explicit package-only restrictions even when the structured flag says standard. Please confirm the authoritative eligibility rule and whether these inconsistent offers are sandbox-specific.

## 3. Response format differences

Observed prebook `suggestedSellingPrice` can be a scalar number in the response currency, while the reference describes an amount/currency object. Seur handles both with decimal checks. Booking-list responses omit the sandbox flag and room details; full booking retrieval supplies `data.sandbox: 1`. Seur uses lists only to discover the original booking ID, then verifies the full details and sandbox marker. Please confirm these shapes are contractual.

## 4. Native iOS customer payment

Please confirm support for **Stripe iOS PaymentSheet**, including 3DS app return handling, using your prebook PaymentIntent. The current direct integration guide demonstrates web Elements. We have not substituted a webview.

We need:

- Your account-specific sandbox publishable key and approved iOS SDK setup. No provider Stripe secret key should be shared with the app.
- The supported payment methods, return URL configuration and any Apple Pay merchant/certificate requirements.
- Authoritative server-side payment-status retrieval for the stored prebook/transaction pair, so an app crash or client callback cannot be mistaken for paid status.
- Confirmation of `TRANSACTION_ID` for this flow. The current OpenAPI payment schema and direct Stripe guide agree on that value, although introductory reference prose still says `TRANSACTION`.
- Supported void/refund recovery when payment succeeds but the hotel booking fails or returns different terms.

Relevant official documentation: [Prebook](https://docs.liteapi.travel/reference/post_rates-prebook), [Book](https://docs.liteapi.travel/reference/post_rates-book), [Retrieve booking](https://docs.liteapi.travel/reference/get_bookings-bookingid), [Direct Stripe integration](https://docs.liteapi.travel/docs/direct-stripe-integration-stripe-elements).


## September 11 follow-up: retrieved prebook and booking comparison

Read-only retrieval of `GET /prebooks/GNV8XlRfj` and `GET /bookings/OBcWcW2dZ` confirms both records reference **GNV8XlRfj**. No new prebook, booking, payment or cancellation was submitted. The allowlisted comparison is saved in `work/hotel-booking-comparison-20260911.json`; it excludes guest contacts, payment data and keys.

The retrieved prebook reports `boardChanged: false`, `cancellationChanged: false`, and `priceDifferencePercent: 0`. It still specifies two adults, breakfast included (`BI`) and a USD 503.40 cancellation penalty beginning October 9, 08:00 GMT. The booking is marked sandbox/CONFIRMED but still specifies one adult, room only (`RO`) and a USD 1,509.90 penalty beginning October 10, 23:59:59 GMT. The price and stay dates agree.

There is an additional mapping question: the retrieved prebook rate now reports `occupancyNumber: 0`, while our single-room booking payload uses one lead guest with `occupancyNumber: 1`. Our current prebook normalizer requires one-based occupancy numbering and verifies adult/child counts. Without the original raw POST prebook response, the freshly retrieved GET response cannot establish what numbering was originally returned. The original local validation report records `prebookChanged: true`; that is our combined flag/terms comparison, not a record of each original provider flag. Today's clear flags do not prove what their original values were.

Please investigate these exact records and confirm:

1. Why do meal, adult count and cancellation terms differ between this stored prebook and the booking referencing it?
2. Is occupancy numbering zero-based or one-based in each of POST prebook, GET prebook and POST book? Does GET prebook transform the original room index?
3. Your [guest-entry guide](https://docs.liteapi.travel/docs/adding-guests-during-the-booking-step) explicitly requires one primary contact per room and occupancyNumber starting at 1. Our request follows that rule. Please explain the retrieved prebook index of 0 and whether it has any relationship to the changed booking details.
4. Please inspect the original request/response logs for these IDs and identify the point of divergence, rather than recommending another booking with the same checks.

These observations warrant investigation; they do not yet establish whether the cause is client mapping, response serialization, sandbox simulation or supplier substitution. Seur continues to retain the needs-support result rather than presenting it as a verified booking.
