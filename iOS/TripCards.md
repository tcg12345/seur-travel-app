# Destination trip cards

The supplied `Travel_Destinations_300_16x9` collection is now the first choice for destination cards. The user wrote “33” but attached 300 entries; after asking for clarification, implementation proceeded with the stated assumption that the complete folder was intended. The explicit selection is recorded in `scripts/destination_cover_selection.json`.

All 300 files passed source SHA-256 and exact 16:9 dimension checks. `scripts/import_16x9_covers.swift` resizes them proportionally to 1280×720 JPEGs without cropping, stretching or upscaling. Bundled JPEGs total 76,567,105 bytes, down from 401,302,998 source bytes. Original Desktop files are untouched. `DestinationCoverCatalog` retains city/country aliases, source checksum, photographer, license and source URLs; full supplied credits are in `DestinationCoverCredits.txt`.

Tokyo keeps the separately requested `tokyo.avif` image (Tokyo Tower/Mount Fuji), bundled at its original 1008×567 size. This wins over the new collection's Tokyo image. Other supplied images are used exactly as selected in the folder, including any evening scenes; the daytime-only rule remains on the Pexels fallback.

`BundledDestinationCover` resolves available images synchronously before any retained Pexels photo. Both the visible-card gate and API client skip Pexels when an actual local image is available. Missing, unreadable or unmatched assets allow the existing Pexels fallback. Normalized names handle common aliases, accents, punctuation, country names and ISO codes; country qualifiers distinguish Paris, Texas from Paris, France and London, Canada from London, England. Merely containing a catalog city name is not enough to match.

Bundled cards display linked photographer/Wikimedia Commons credit and the correct individual license in the photo sheet. The custom Tokyo image remains labeled “Supplied photo.” Pexels results retain their own photographer/Pexels credit.

## Layout and image selection

Both list and grid cards have a 16:9 image area. Local images use their existing 16:9 framing. For fallback images, the server requests a 1200×675 Pexels CDN rendition; SwiftUI fits that entire rendition without additional cropping or portrait blur fills. Trip names, routes, dates and planning details sit below the photograph, so compact cards preserve the view. The CDN may crop the original landscape photograph to 16:9.

Every Pexels fallback search includes daytime. Selection requires affirmative daylight wording in the photo description or source-page title and rejects night, dawn, sunrise, sunset, dusk, twilight, golden/blue hour, illuminated and neon scenes. Unclear time-of-day matches use the monogram.

For destinations requiring the fallback, the backend uses explicit defining-landmark searches for 32 major destinations (including Eiffel Tower, Statue of Liberty, Tokyo Tower and Big Ben), respecting country qualifiers. Other destinations search the supplied city/country plus skyline/landscape. A single Pexels search retrieves up to 30 landscape candidates. Selection requires matching landmark/city description text, sufficient resolution and landscape proportions, rejects signs, plaques, interiors, replicas and silhouettes, and favors scenic views and ratios near 16:9. Unknown or unsuitable results yield a neutral destination monogram. Text metadata is a relevance check, not proof of geographic accuracy or a guarantee of attractive composition for every destination.

Each card links directly to the photographer's image on Pexels; the information sheet includes author, photo title, source and license. [Pexels API attribution requirements](https://www.pexels.com/api/documentation/).

## Requests and persistence

`GET /v1/cities/pexels-photo?city=...` uses `PEXELS_API_KEY` stored only in Supabase Edge secrets. `/v1/status` advertises `pexelsCityPhotos`; a missing key doesn't consume a trip's attempt. No Google photo calls are made by the updated app.

The daytime update starts a new server cache and on-device cache namespace, so existing covers are replaced once as their trips become visible. After that transition, a visible trip makes at most one lookup attempt per installation. An exclusive on-disk claim precedes the request; concurrent card views share the pending task. Successful image bytes and credits are kept together in Application Support (`AurumTravel/PexelsDaytimeTripCovers-v1`) and loaded synchronously on subsequent visits and app launches. Previous providers' caches are not reused. Failed, interrupted or empty attempts retain their claim, honoring the user's request not to repeat a trip lookup. First-ever downloads still require a network connection; reinstallation or deleting app data removes the retained cover and claim.

The Edge Function caches selections and private review candidates by normalized destination query for 24 hours in the existing service-only `travel_provider_cache`. Different trips to the same city reuse that response. In-flight requests are coalesced within each Edge isolate; global provider limits bound cross-isolate races. Cache misses allow one search with no pagination/fallback query; global caps are 180/hour and 500/day (below the default 200/hour and 20,000/month Pexels quota). Per-network endpoint reads are capped at 30/minute. Null results are also cached. Routine XCTest and backend tests never call the live provider.

[Pexels caching guidance](https://help.pexels.com/hc/en-us/articles/900006470063-What-steps-can-I-take-to-avoid-hitting-the-rate-limit) recommends caching API responses for 24 hours. The saved photo copy is retained with its Pexels license and attribution; it does not require searching again each time a trip opens.
