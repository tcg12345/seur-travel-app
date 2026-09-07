# Friends

Friends is a top-level tab immediately after Travel. The five visible destinations are Discover, Map, Travel, Friends and Concierge. Search opens from the magnifying-glass action in Discover or Map; Discover’s existing search shortcuts use the same presentation. Travel now focuses on trips without a second Friends selector.

## Trips

Trips shows itineraries shared by accepted friends, plus private itineraries explicitly shared with the signed-in account through a conversation. Search by traveler, username, trip title or destination. Filter all, upcoming, traveling now, past or saved trips. Saving keeps an account-scoped shortcut on this device; it does not create a copy or bypass revoked access.

Date-overlap hints compare the traveler’s local trip dates with a friend’s shared itinerary. They require matching destination names/countries and overlapping exact dates. Flexible dates never produce a match. These are planning hints, not live location tracking.

Opening a shared trip fetches its current authorized cloud version and presents day-by-day events, flights, stays, journal notes and photos. A private copy can be imported for personal editing. Pull to refresh to see the latest version the owner has published. If authorization fails, the plan content is cleared and access must be retried.

## People and messages

Add a traveler by their exact Seur username, accept or decline incoming invitations, cancel sent invitations and remove friends. Share your username through the system share sheet. Friend profiles show only their itineraries already shared with you and provide a private message action.

Messages lists private and family/group conversations. Create a named group with accepted friends, discuss plans and attach itineraries. One-to-one actions reuse an existing conversation with the exact two members. Group member counts are not treated as a direct conversation. No contact-book upload, automatic invites, fabricated unread counts or public location discovery is added.

## Sharing and control

Share an itinerary chooses a local trip and an accepted friend or existing group, then publishes it and sends the attachment only after the user taps Share. Photos and journal notes are included. Hotel confirmation numbers, hotel booking notes and flight notes are redacted by the backend. Existing friends/public visibility is disclosed and preserved. Success is confirmed after the server accepts the share.

Shared plans are owner-managed: recipients can view, discuss and import a private copy. Simultaneous editing of one itinerary is not implemented. The owner shares again after local edits to publish an update. Manage your shared itineraries opens audience/link/revocation controls already used by Travel. Removing a friend or revoking sharing removes applicable grants; previously imported/exported copies cannot be recalled.

## Implementation and testing

The Friends page refreshes its three small account endpoints together on entry, pull-to-refresh and once per minute while active. It uses no paid place, AI or flight-provider API. Loading is deduplicated, late responses from another account are discarded and account changes clear in-memory social data. Bookmarks are isolated by account and intersected with the currently accessible feed.

The new `travel_social_feed(actor)` RPC is SECURITY INVOKER with an empty search path and service-role-only execution. The Edge Function derives the actor from the session, applies existing redaction/photo-summary rules and returns at most 200 accessible itineraries. Public/anonymous and native authenticated database clients cannot call the RPC directly. The query adds explicitly granted private shares without turning the feed into a global public directory.

Automated UI tests use DEBUG-only synthetic accounts and block real network/mutation requests in that fixture mode. See Validation.md for the exact build, UI, unit and live-backend results.
