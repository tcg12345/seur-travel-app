# Trip recap

Open a local trip → Recap, next to Plan and Journal. Finished trips promote it with a banner after the final calendar day in the last stop’s time zone. Earlier trips show a growing recap. No schema change is needed for saved iOS documents.

- `TripRecap` assembles days, matching hotel stays, ratings and route legs without network calls. Shared arrival/departure days merge into one entry; empty days and undated journal entries remain visible. Missing city coordinates never create a shortcut across an unknown stop.
- `RecapMapView` replays numbered stops on MapKit, with geodesic booked flights and city route strokes. Reduce Motion shows the full route statically. Replay stops when the view leaves the screen or the app backgrounds.
- Metrics distinguish journal records from actual ratings (`overall > 0`), count Michelin stars on restaurant entries, and label flight distance as approximate great-circle miles. Unknown airport coordinates are excluded.
- `RecapShareView` selects photos and creates a 1080×1920 JPEG with up to three selected photos, or an immutable recap link with up to 60 selected photos. Images are re-encoded at up to 800 pixels before upload. Capturing a map for sharing needs a map connection; viewing the local journal timeline does not.

## Sharing architecture

The recap does not upload or change the audience of the full trip. `POST /v1/recaps` validates a document and photo allowlist, constructs a second server-side allowlist projection, and atomically saves it and only its selected media. Booking references, booking links, private notes, costs, attendees, provider descriptions and unknown fields are excluded. The source visibility is recorded without being changed. As with the existing journey links, anyone possessing an explicitly created capability link can open it, even when the source trip is private.

The Edge Function stores SHA-256 hashes of random 320-bit link tokens. Recap tokens cannot fall through to the full-document export path, including `?format=json` or altered `view` parameters. Photos are fetched lazily through the same token and are not in a public storage bucket. Responses disable caching and referrers. The separate public Sites viewer receives the token in the URL fragment; it has no trip directory or analytics. Existing private website access is unchanged.

- `GET /s/TOKEN?view=recap` redirects to `RECAP_WEB_URL#TOKEN`.
- `GET /s/TOKEN?format=json` returns only the immutable projection.
- `GET /s/TOKEN?asset=PHOTO_UUID` or `asset=map` returns only media bound to that capability.
- `DELETE /v1/recaps/DOCUMENT_UUID` revokes all recap links for the signed-in owner’s document. Existing trip-sharing revocation and explicit cloud document deletion also revoke recaps. Making a cloud source private withdraws recaps. Account deletion cascades snapshots and their media. Locally deleting a trip does not revoke cloud links; the existing deletion confirmation explains this.

The service-only recap tables have RLS enabled, no client grants and no permissive policies. Media lives in separate rows, so loading the page metadata does not load every JPEG. Links are limited to 20 per owner/document, with publishing and read rate limits. Selected-photo changes apply to newly created links; existing links are immutable until revoked.

Web source: `recap-site/`. Hosting metadata there identifies the separate public recap viewer. The parent `.openai/hosting.json` remains the existing private website. `RECAP_WEB_URL` is a non-secret Edge runtime setting. Publish the nested site from its own repository (or a temporary source copy rooted there), not the native app’s parent repository.

## Verification

34 JourneyTests passed, including merged days, undated memories, missing-coordinate flight distances, antimeridian fitting, destination time zones, personal-data stripping and exact image dimensions. Three Deno recap contract tests verify server redaction and photo selection. `supabase/tests/recaps_live.py` exercises real scoped links, alternate formats, excluded-photo retrieval, owner-only revocation, source privacy withdrawal and account cleanup with disposable accounts. Both signed device and simulator builds pass; the web build and strict TypeScript check pass.

Video export is intentionally deferred to a separate implementation. The pure recap model and poster renderer can supply a future AVAssetWriter pipeline.
