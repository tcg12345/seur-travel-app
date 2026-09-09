# Friends

Friends is a top-level tab immediately after Travel. The five visible destinations are Discover, Map, Travel, Friends and Concierge. Search opens from the magnifying-glass action in Discover or Map; Discover’s existing search shortcuts use the same presentation. Travel now focuses on trips without a second Friends selector.

## Trips

Trips shows itineraries shared by accepted friends, plus private itineraries explicitly shared with the signed-in account through a conversation. Search by traveler, username, trip title or destination. Filter all, upcoming, traveling now, past or saved trips. Saving keeps an account-scoped shortcut on this device; it does not create a copy or bypass revoked access.

“Your paths cross” quietly shows current/upcoming city-and-date overlaps above the shared feed. It compares local dated trips with currently accessible itineraries from accepted friends only. Templates and flexible dates are excluded. City matching folds case, whitespace and accents, normalizes countries to ISO codes, and rejects conflicting countries or distant coordinates. Without coordinates, matching known countries are required so identically named cities do not generate false alerts. Checkout/arrival days are included as possible same-day overlaps, not claims of an overnight stay.

Equivalent city/date notices are deduplicated. Dismissals remain stable as today advances; changes to the overlapping dates can surface a fresh notice. Preferences and dismissals are scoped to the signed-in account on this device. Use the Friends + menu to disable notices or restore dismissed ones. The overlap section disappears when there is nothing to show. These are planning hints, not live location tracking or push notifications. No additional API is called to compute them.

Opening a shared trip fetches its current authorized cloud version and presents day-by-day events, flights, stays, journal notes and photos. A private copy can be imported for personal editing. Pull to refresh to see the latest version the owner has published. If authorization fails, the plan content is cleared and access must be retried.

## People and messages

Add a traveler by their exact Seur username, accept or decline incoming invitations, cancel sent invitations and remove friends. Share your username through the system share sheet. Friend profiles show only their itineraries already shared with you and provide a private message action.

Messages lists private and family/group conversations. Create a named group with accepted friends, discuss plans and attach itineraries. One-to-one actions reuse an existing conversation with the exact two members. Group member counts are not treated as a direct conversation. No contact-book upload, automatic invites, fabricated unread counts or public location discovery is added.

## Trip requests

Choose **Friends → + → Ask about a trip**, the same action on a friend’s profile, or **Conversation actions → Ask about a trip**. Pick the friend, destination and travel month, optionally choosing a stop from an existing trip. An optional note replaces the suggested question. Sending reuses the exact direct conversation or posts in the chosen existing group; nothing is sent until the Send request button is tapped.

A typed request card shows the city/month, waiting/answered state and **Reply with a trip or template**. The reply sheet separates local Trips and Templates, displays whom/where it answers, and uses the existing document-sharing permissions. Recipients open the live authorized document and can use a shared template with their own dates. Conversation rows display real outstanding request counts for the recipient. One itinerary reply answers a group request; more replies remain possible.

Optional `tripRequest`, `replyTo`, `documentIsTemplate` and `pendingRequests` fields preserve older message/conversation decoding. `travel_send_message` checks membership before inspecting request IDs, accepts only city/month intent fields, requires accepted friends for requests and attachments, and restricts replies to someone else’s request in the same conversation. It delegates attachment ownership and grants to `travel_dispatch` in the same transaction. The RPC is invoker/service-only, with RLS unchanged; the Edge Function supplies the authenticated actor. No public request feed or paid provider dependency is introduced.

## Sharing and control

Share an itinerary chooses a local trip and an accepted friend or existing group, then publishes it and sends the attachment only after the user taps Share. Photos and journal notes are included. Hotel confirmation numbers, hotel booking notes and flight notes are redacted by the backend. Existing friends/public visibility is disclosed and preserved. Success is confirmed after the server accepts the share.

Shared plans are owner-managed: recipients can view, discuss and import a private copy. Simultaneous editing of one itinerary is not implemented. The owner shares again after local edits to publish an update. Manage your shared itineraries opens audience/link/revocation controls already used by Travel. Removing a friend or revoking sharing removes applicable grants; previously imported/exported copies cannot be recalled.

## Implementation and testing

The Friends page refreshes its three small account endpoints together on entry, pull-to-refresh and once per minute while active. It uses no paid place, AI or flight-provider API. Loading is deduplicated, late responses from another account are discarded and account changes clear in-memory social data. Bookmarks are isolated by account and intersected with the currently accessible feed.

The new `travel_social_feed(actor)` RPC is SECURITY INVOKER with an empty search path and service-role-only execution. The Edge Function derives the actor from the session, applies existing redaction/photo-summary rules and returns at most 200 accessible itineraries. Public/anonymous and native authenticated database clients cannot call the RPC directly. The query adds explicitly granted private shares without turning the feed into a global public directory.

Automated UI tests use DEBUG-only synthetic accounts and block real network/mutation requests in that fixture mode. See Validation.md for the exact build, UI, unit and live-backend results.
