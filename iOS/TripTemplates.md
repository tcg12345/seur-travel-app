# Trip templates

Travel → Templates contains saved local templates and public starting points. Discover and city guides link into the same library. A template preview shows its route, hotels, day-by-day pacing, author, season and optional ratings before a departure-date-only clone flow creates a private editable trip. Normal trip lists, map routes, wishlist planning, Concierge trip selection and Today exclude template documents.

Trip → Share → Save as template creates a separate local document. Review the cleaned preview, then optionally publish from the template page. Publishing is an explicit user action; saving a template never uploads the source trip. Sharing & audience manages a published copy, including withdrawal or deletion. Friends' published templates use the existing shared feed and open the same clone flow.

`JourneyDocument` retains its existing kinds and gains optional `isTemplate` and `templateMeta` fields. `templated()` preserves stops and event references, normalizes the route into night counts, clears free-form notes, attendees, photos, booking references, room/guest details and flight reservations. Costs and author ratings are opt-in. Hotel stays retain their offset within their original stop; unmatched or ambiguous stays require correction instead of silently moving. `usingTemplate(departure:)` chains stops, shifts hotel dates across calendar boundaries, drops flights, creates a new private document ID and records source ID/title/author. Original trips remain untouched.

Templates are suggestions, not reservations; seasonal opening dates, minimum stays and availability must be checked before booking. Included costs are historical planning estimates, not current quotes. No flights or hotels are booked by either conversion.

## Public API

- `GET /v1/templates?city=&tags=`: public summaries, maximum 100, tags are comma-separated and conjunctive. Summaries retain stops/metadata and omit itinerary arrays.
- `GET /v1/templates/:id`: full public template, 404 after withdrawal.
- Existing authenticated `PUT /v1/documents/:id`: server-side template allowlists remove private fields and derive authorship from the session's profile.
- `POST /v1/templates/:id/uses`: authenticated, rate-limited, idempotent on template/user/clone ID. Counts represent signed-in trip starts; offline or signed-out clones remain fully usable but are not counted.

A partial index serves public template documents. A server-only uses table supplies authoritative counts without trusting client metadata. Functions are SECURITY INVOKER and client roles have no direct table or RPC grants. No existing private trip was used as seed content. The starter library has a dedicated non-login editorial owner.

The ten bundled itineraries work without a provider lookup. Public discovery is coalesced in memory for five minutes; a failed initial fetch leaves bundled content available. User-saved templates and cloned trips persist in the existing local archive. Opening a community template requires a connection to retrieve the full itinerary before cloning.

## Editorial content

`scripts/build_trip_templates.py` contains the hand-written titles, taglines, styles, seasons and daily plans. It assembles the bundled JSON from the existing hotel/venue catalog. The Riviera and Copenhagen additions use official hotel and restaurant references:

- [Hôtel de Paris Monte-Carlo](https://www.montecarlosbm.com/en/hotel-monaco/hotel-de-paris-monte-carlo)
- [Hôtel du Cap-Eden-Roc](https://www.oetkerhotels.com/hotels/hotel-du-cap-eden-roc/questions-answers/)
- [Cheval Blanc St-Tropez](https://www.chevalblanc.com/en/maison/st-tropez/restaurants-and-bars/la-vague-d-or-st-tropez)
- [Hotel d’Angleterre](https://www.dangleterre.com/)
- [Aamanns 1921](https://aamanns.dk/restaurant/aamanns-1921/)
- [Høst](https://cofoco.dk/en/restaurant/hoest)

No invented ratings, prices or clone counts are seeded. Restaurant websites/addresses are carried into the resulting plan; free afternoons deliberately leave room for personalization.

## Verification

Native tests cover sanitization, source immutability, opt-in costs/ratings, legacy compatibility, all ten seed clones, hotel offsets, multi-city gaps, leap dates, year boundaries, invalid mappings, offline persistence and exclusion from active trips. XCTest also exercises Travel discovery → preview → departure date → private trip → save own template. Deno contracts cover the public sanitizer and summary shape. `supabase/tests/templates_live.py` checks live city/style filters, authenticated publish, authorship, retry-safe counts, privacy and withdrawal, cleaning up its temporary account.

Post-migration Supabase advisors reported no new table/RPC issues. The existing project-wide [leaked password protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remains unrelated to these migrations.
