# Onboarding and membership preview

Seur opens a native first-run welcome, followed by three optional personalization steps, real cloud account creation/sign-in, a simulated Reserve membership flow, and a final notifications page. Existing hotels, saved places, plans and accounts are preserved.

## Experience

1. An immersive hotel photograph introduces stays, dining and journeys.
2. Travel interests let people choose what matters to them, with no minimum selection.
3. Cuisine preferences introduce the hotel's dining collection.
4. A first destination offers featured cities, the complete catalog city list, or no preference.
5. Use Apple, Google or email through the shared account welcome. Email registration is split into three focused pages: name/username, email, then password, followed by verification. A three-part progress indicator, local validation and Back navigation guide the flow. Entries remain in memory when moving between pages; only the final Create account action sends a signup request. Back on the first email page returns to provider choices. Skip remains available throughout. Existing email/username sign-in remains available, along with continuing without an account.
6. Reserve presents illustrative annual/monthly plans, a cancellable confirmation, local preview success and restoration. Continue without membership and close controls remain available.
7. A notifications page explains flight alerts and automatically requests standard iOS alert, sound and badge authorization when permission is undetermined. Existing permission is respected. Declining shows a notification Settings link, and Explore Seur completes onboarding either way. Returning from Settings refreshes the displayed status.

The welcome screen has a direct sign-in shortcut. Explore first skips personalization and account creation. Returning signed-in travelers see their account and can continue without entering credentials again.

Back navigation preserves choices. First-run progress resumes after closing the app. After membership is skipped or previewed, the notifications step is saved for resuming. Completion is saved when the traveler continues from notifications, regardless of their permission choice. Previously completed onboarding stays complete. Preferences remain available in the profile and can inform Concierge requests; a dining interest opens the dining category when onboarding finishes. The app never silently restricts the full catalog to these choices.

Discover → Your workspace provides preference editing, membership preview reopening, and clearing a preview. Preferences are saved as they change. Editing them never deletes travel documents or changes account credentials.

## Subscription simulation

**There is no StoreKit integration, payment processing, subscription entitlement, billing, trial or renewal.** Confirmation writes only an optional plan name to this device. Restore preview reads only this local value. All current app functionality remains available when membership is skipped. The example prices are USD $79.99/year and $9.99/month; these are design placeholders, not live offers. No real legal or commercial subscription agreement is presented.

A future production subscription implementation will need App Store Connect products, verified StoreKit transactions and entitlements, final pricing/terms/privacy links, and independent purchase/restore testing before this design can become a real paywall.

## Persistence and accessibility

The versioned `aurum.travelerProfile.v1` UserDefaults value stores interests, cuisines, destination, current onboarding step, completion and an optional preview plan. Account creation and sign-in use the same deployed Supabase Edge Function and Keychain sessions as Travel → Account. Passwords exist only in form memory, are cleared on success/exit, and are never saved in the onboarding draft. Existing sessions are restored when entering the account step. Only the final notifications page requests notification permission. Onboarding requests no tracking or location permissions. Permission does not automatically follow flights or enroll the traveler in alerts; flight following remains explicit. iOS permission state is read from the system rather than stored in the onboarding profile. The app recovers from unreadable drafts and bounds restored steps/selections (0–6).

Native controls include VoiceOver labels/selection values, scalable text, scrollable content, touch targets, and Reduce Motion-aware transitions. UI test data uses a separate UserDefaults suite. Existing UI regression tests bypass first-run onboarding; dedicated flows launch with `--ui-testing --onboarding-testing` and test resuming with `--preserve-state`.

Account creation is real and independent of the simulated membership selection.

The first-time system notification prompt UI test is opt-in with `SEUR_NOTIFICATION_PROMPT_TEST=1` in the test runner environment and requires a fresh simulator. Routine onboarding UI tests accept or decline an existing prompt and continue; permission state transitions also have injected unit tests.
