# Onboarding and membership preview

Aurum opens a native first-run welcome, followed by three optional personalization steps and a simulated Reserve membership flow. Existing hotels, saved places, plans and accounts are preserved.

## Experience

1. An immersive hotel photograph introduces stays, dining and journeys.
2. Travel interests let people choose what matters to them, with no minimum selection.
3. Cuisine preferences introduce the hotel's dining collection.
4. A first destination offers featured cities, the complete catalog city list, or no preference.
5. Reserve presents illustrative annual/monthly plans, a cancellable confirmation, local preview success and restoration. Continue without membership and close controls remain available.

Back navigation preserves choices. First-run progress resumes after closing the app. Completion is saved whether the traveler skips membership or confirms a preview. Preferences create destination/cuisine shortcuts in Discover, and a dining interest opens the dining category when onboarding finishes. The app never silently restricts the full catalog to these choices.

Discover → Your workspace provides preference editing, membership preview reopening, and clearing a preview. Preferences are saved as they change. Editing them never deletes travel documents or changes account credentials.

## Subscription simulation

**There is no StoreKit integration, payment processing, subscription entitlement, billing, trial or renewal.** Confirmation writes only an optional plan name to this device. Restore preview reads only this local value. All current app functionality remains available when membership is skipped. The example prices are USD $79.99/year and $9.99/month; these are design placeholders, not live offers. No real legal or commercial subscription agreement is presented.

A future production subscription implementation will need App Store Connect products, verified StoreKit transactions and entitlements, final pricing/terms/privacy links, and independent purchase/restore testing before this design can become a real paywall.

## Persistence and accessibility

The versioned `aurum.travelerProfile.v1` UserDefaults value stores interests, cuisines, destination, current onboarding step, completion and an optional preview plan. Onboarding sends no network request and requests no notification, tracking or location permissions. The app recovers from unreadable drafts and bounds restored steps/selections.

Native controls include VoiceOver labels/selection values, scalable text, scrollable content, touch targets, and Reduce Motion-aware transitions. UI test data uses a separate UserDefaults suite. Existing UI regression tests bypass first-run onboarding; dedicated flows launch with `--ui-testing --onboarding-testing` and test resuming with `--preserve-state`.
