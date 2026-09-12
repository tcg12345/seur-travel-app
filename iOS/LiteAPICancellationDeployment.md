# Sandbox cancellation deployment

The cancellation feature is implemented, tested and deployed as travel-api v53 on September 12, 2026, following explicit user approval. The previous automatic approval rejection was resolved by that approval. The deployed bundle was retrieved and verified byte-for-byte against the reviewed files.

## Proposed behavior

- A signed-in owner opens a full-page cancellation review for a verified sandbox booking.
- LiteAPI booking details are checked before review and again before submission. The user explicitly confirms a versioned review that expires within five minutes or at the next known policy deadline.
- The existing durable worker submits at most one sandbox cancellation request, then only retrieves the original booking after a timeout or restart.
- Changed terms require a fresh review; unresolved attempts require support. Cancellation is verified by retrieving the matching booking and its sandbox marker.
- Both CANCELLED and CANCELLED_WITH_CHARGES are recognized. Neither establishes a refund, and no real card or production key is used.
- A server capability flag hides cancellation in normal app use until the supporting API is deployed. Existing pending operations remain accessible.

## Exact deployment scope

The deployed v52 function was fetched and compared with the proposed bundle. Twenty files are byte-for-byte unchanged. The function-upload API requires all dependency files, even for this narrow change.

Changed files: hotel-checkouts.ts, index.ts, and new hotel-cancellations.ts. The diff is in [cancellation-api.patch](../work/cancellation-api.patch). The previous v52 bundle is retained in ignored work/cancellation-v52-baseline.json for rollback. No new credential or authentication system is introduced, and the existing gateway/custom app-session authentication setting is preserved.

The additive database migration 20260912104954_hotel_sandbox_cancellation.sql has already been applied and verified. It adds a cancellation JSON state, attempt count, partial queue index and three service-only RPCs, and extends the existing worker wakeup. It is compatible with v52 while no cancellation requests are accepted. RLS and revoked client grants remain in force.

## Verification

225 native unit tests, 126 backend tests, the cancellation review/confirmation UI test and pending-cancellation app-restart test passed. The SQL transaction tests cover account isolation, stale versions, repeated confirmation, exclusive claims, lookup-only crash recovery and account detachment. Screenshots were visually reviewed. Final Release compilation and final capability-gated app verification are recorded in Validation.md.

No actual supplier booking or cancellation was submitted during this implementation. Provider calls were mocked in tests. A real sandbox happy-path acceptance still depends on resolving the original LiteAPI booking mismatch.

## Deployment verification

Deployed the exact reviewed bundle, preserving verify_jwt=false and the existing custom app-session authentication. Live smoke checks passed sandbox cancellation capability, production booking disabled, unauthenticated rejection on both routes, owner-scoped missing-record rejection and explicit-intent validation. The disposable account was deleted. No owned booking existed for a live cross-owner attempt; cross-owner behavior is covered by the rollback-only SQL acceptance tests. No supplier request, booking or cancellation was submitted.

Real payments, real refunds, production booking activation, and native flight booking are outside this deployment.
