# Traveler-created guides

## Product and research

Seur guides are independently authored collections of recommendations, organized into chapters. They have their own private drafts and public publications; they do not change the visibility of a journey.

Research reviewed September 9, 2026:

- Wanderlog's public [Write a travel guide](https://wanderlog.com/plan/create/recommendations) screen starts with a destination, offers optional dates and collaborators, and leads into writing. Seur adopts the destination-first start and adds an explicit way to begin from an existing trip. Dates are not required for a guide.
- Its [Ultimate Las Vegas Guide](https://wanderlog.com/view/guiwqgrbkh/ultimate-las-vegas-guide) shows an author/date, introduction and practical tips, a contents list, custom recommendation sections, section-filtered maps and save actions on places. Seur uses original chapter names/content, a focused reader, chapter map filtering, and saving recommendations to Wishlist or a trip.
- Wanderlog's [map creation explanation](https://wanderlog.com/embed-travel-map-on-blog) supports adding recommended places, the writer's descriptions/photos and map organization. Seur includes place lookup or manual entry, personal notes and photos, chapter/entry ordering, and an Apple Map. There is no new Google photo lookup for guides.
- Wanderlog documents [offline guide downloads](https://help.wanderlog.com/hc/en-us/articles/13545300431259-Download-guides-for-offline-reading). Seur saves complete bookmarked guide snapshots locally for offline reading. Maps/directions still need the system's map data/network.

These observations come from public pages; a private logged-in Wanderlog publishing session was not used. Seur does not copy guide text, branding or layouts. Comments, likes, collaborative authoring, route optimization and an embeddable web editor are not part of this implementation.

## Experience

Entry points: **Travel → Guides**, **Discover → Travel guides**, **Travel → + → Create a guide**, and a trip's **… → Create a travel guide**.

1. Choose a destination with Apple Maps autocomplete and an optional title, or start from a trip. Suggestions are also available when editing the guide’s destination; manual entry remains available.
2. Write an introduction; optionally add a cover and up to three themes.
3. Add chapters with notes and recommendations. Add places through search, manually, or from Wishlist. Write a recommendation and optionally attach a personal photo. Reorder chapters with their menu; reorder places using Edit.
4. Preview the complete reader before publication. Sign-in and a configured guide backend are required only for publication, not local writing.
5. Explicitly publish the guide or an update. The preview shows what is public and lets an author unpublish later. Concurrent edits are detected with revisions; the author can review the latest cloud version, keep their private draft or adopt the published version.

Main-editor changes autosave after a short debounce and on dismissal. Chapter/place sheets have explicit Save/Add and Cancel controls. Original corrupt archives are preserved. The public version does not change when a local draft changes. A failed publish leaves the draft available.

**Explore** browses published summaries with city/title search, themes and pagination. **Your guides** contains local drafts/publication state and can restore an author's cloud guides. **Saved** holds full offline reader copies. Readers can save recommendations to Wishlist or a selected trip/day, see chapter-filtered map pins, open directions/websites, share a public PDF, report a guide, hide it, and block/unblock authors. Bookmarks are snapshots; Refresh guide explicitly requests the latest public version. Existing downloaded copies cannot be recalled after unpublishing.

The public share URL opens a read-only PDF without requiring the app. Native guide links use `seur://guide/<UUID>`. There is no separate hosted HTML guide reader in this change. The PDF uses the existing Latin-font approach; native text supports Unicode, while unsupported PDF glyphs are replaced.

## Data and privacy

`TravelGuide` includes title, destination, introduction, themes, ordered chapters and recommended places. Photos are optional JPEGs. Published data is validated and rebuilt from explicit allowlists server-side; author identity comes from the authenticated profile. A trip-to-guide conversion copies only place facts, excluding private trip notes, booking confirmations, tickets, costs, attendees, ratings, provider prose and journal photos.

Cover photos are limited to approximately 1 MB, recommendation photos to 650 KB, and thumbnails to 70 KB by the iOS picker. Images are re-rendered to strip EXIF/location metadata. The public API caps the entire guide at 5 MB, 20 chapters and 100 places. The guide writer is prompted to publish only material they have permission to share.

`GuideLibrary` stores drafts, full bookmarks and local hide/block choices in `Application Support/AurumTravel/guides.json` (separate UI-test location). A draft remembers its publishing account/server and revision. `travel_guides`, `travel_guide_reports`, and `travel_guide_blocks` have RLS and no anon/authenticated table or RPC grants. Only the Edge Function's service role can access them. Security-invoker RPCs enforce ownership, publication visibility, moderation and revision checks. Foreign keys cascade through `travel_profiles`, so deleting an account deletes its publications/reports/blocks.

## API and rollout

Migration: `supabase/migrations/20260909183248_travel_guides.sql` (created with Supabase CLI).

- `GET /v1/guides?q=&tag=&offset=`: public summaries (20/page), with blocked authors filtered when authenticated.
- `GET /v1/guides/<id>`: full published guide.
- `GET /v1/guides/<id>/pdf`: public PDF; unpublished/moderated content returns 404.
- `GET /v1/my-guides[/<id>]`: authenticated author library/full publication.
- `PUT /v1/guides/<id>`: `{guide, expectedRevision}`; use revision 0 only for first publication.
- `POST /v1/guides/<id>/unpublish`: `{expectedRevision}`.
- `POST /v1/guides/<id>/report`: one of the supported report reasons.
- `POST /v1/guide-authors/<id>/block`: `{blocked: true|false}`.

`/v1/status` adds `travelGuides: true`. Older deployments leave native publication unavailable while all draft work continues. Searches debounce; list responses omit full chapters/photos and substitute the small cover thumbnail. The guide feature does not automatically fetch destination photos or make generative-AI calls.

The guide migration was applied on September 9 as remote version `20260909200003` (`travel_guides`), using the SQL in the local migration above. RLS/service-only grants and the empty public read were verified live. After explicit user approval, production `travel-api` v34 deployed the guide module/routes and now advertises `travelGuides: true`. Live guide discovery returned 200 and unauthenticated publication returned 401. Signed-in users can now publish from the updated app. No additional API secrets are required.

## Moderation operations

Reports are stored for human review; they do not automatically hide guides based on counts. Review `travel_guide_reports` joined to `travel_guides` using a privileged operator session. Setting `travel_guides.hidden = true` removes a guide from public reads/PDFs and prevents the author from republishing it while reviewed. Unhide only after review. There is no automated email or notification to an external party and no moderation dashboard in this change. Assign a reviewer before enabling public publishing.

## Local checks

- Deno: run the existing full suite, now including `supabase/tests/guides_test.ts`.
- SQL: `supabase/tests/guides_sql_check.mjs` uses an isolated PGlite PostgreSQL instance, minimal auth/profile fixtures, the exact migration file, and role/grant/ownership/revision/moderation/account-deletion checks. It does not touch a Supabase project.

```sh
npm install --prefix /tmp/seur-guide-validation --no-audit --no-fund @electric-sql/pglite@0.5.8
GUIDE_PGLITE_MODULE=/tmp/seur-guide-validation/node_modules/@electric-sql/pglite/dist/index.js node supabase/tests/guides_sql_check.mjs
```

Native tests cover private-data exclusion, publication-vs-draft persistence, complete offline bookmarks, blocking, and unreadable archives. The end-to-end UI test uses `--ui-testing --guide-publishing-testing`, an explicit in-memory fixture backend with no outgoing requests, then relaunches without it to verify local persistence. This flag is DEBUG-only and never used in normal app sessions.
