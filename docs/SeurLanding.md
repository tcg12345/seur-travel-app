# Seur app landing page

The root route is Seur’s iPhone marketing site. The earlier web discovery implementation remains at `/collection`; native app and backend behavior are unchanged.

## Direction and research — September 12, 2026

- [Flighty](https://flighty.com/): immediate product explanation, app imagery and a readily available download action.
- [Linear Mobile](https://linear.app/mobile): product-led storytelling, short feature explanations and focused mobile download flow.
- [Structured](https://structured.app/): clear app purpose and feature-driven progression.

The resulting direction uses Seur’s existing bronze (#8C6338), ivory (#F8F6F1) and warm charcoal identity. Editorial serif type, an original coastal scene, current native screenshots, a desktop sticky/crossfading product story, in-view reveals and gentle depth effects create the travel narrative. Mobile uses vertically stacked app screens rather than a cramped sticky stage. Reduced Motion removes parallax, reveals and looping motion. Scrolling stays native with no scroll interception.

## Download setup

The user has not published a build and explicitly requested a placeholder. `APP_DOWNLOAD_URL` in `app/seur-landing.tsx` is therefore null. Every Get the app action leads to the honest Coming soon for iPhone section; no fake App Store link, QR code, rating, testimonial, install count or email-collection workflow is used. Add the approved App Store/public TestFlight URL to activate direct download links.

Hotel booking and flight purchase capabilities are not advertised as available. Copy describes implemented discovery, itineraries, maps, journals, sharing and tracking.

## Assets

- `public/landing/coast.webp`: one original generated Mediterranean-inspired scene, not a named real hotel or destination. It is reused for hero, journal illustration and closing section.
- `public/landing/app-icon.png`: existing Seur shipping icon, resized for web.
- App screenshots must be fresh captures from the current workspace build. Older `iOS/Preview` files were rejected by the user and must not be shipped as the current interface. Capture sources are the focused `testLandingPageCurrentAppCaptures` and `testLandingPageCurrentPlanCapture` runs, using isolated sample data without personal traveler details.
- Supplemental journal/shared-plan compositions are illustrative interface vignettes, not fabricated customer testimonials.

## Behavior and accessibility

All navigation is real section links. Text remains present without JavaScript. Keyboard focus, a skip link, reserved image dimensions, lazy loading below the fold, no autoplay video, and lightweight native scroll listeners are included. The only persistent header contains the brand, section links and app action; mobile keeps the brand and app action.

## Validation

The two current-workspace native capture scenarios passed on September 12, 2026, using the SeurHotelQA simulator. App images were inspected and exported as WebP without altering the interface. No older screenshot remains in the landing asset folder. The website passes its scoped TypeScript check, focused lint and production build. Layouts have explicit phone/tablet/desktop rules and reduced-motion fallbacks; interactive browser QA was not requested. The earlier root TypeScript command also scanned unrelated Deno sources, so `tsconfig.web.json` provides a website-only check.

## Motion refinement — September 12, 2026

The header now eases into a compact rounded glass bar over the first 180 pixels of scroll, with a subtle wordmark movement and a thin bronze reading-progress line. Its outer height stays constant to avoid shifting the page. The headline enters by line; supporting text follows with a short stagger. The outgoing hero fades into ivory only as its bottom leaves the viewport, preserving content visibility on long mobile layouts. Section reveals use smaller travel distances, coordinated text timing and calmer app-screen crossfades. Scroll updates share one animation frame, and size changes refresh the progress calculation. Reduced Motion exposes content immediately and removes the decorative transforms and fades.
