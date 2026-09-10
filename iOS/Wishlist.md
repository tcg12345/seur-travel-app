# Wishlist

## Save trips and places

The empty wishlist asks **What would you like to save?** and offers six compact choices: **Trip, Destination, Hotel, Restaurant, Activity, Sight**. The former oversized “Add your first idea” card is removed. The same choices live in the top-right plus menu once content is saved; Explore destinations remains a secondary menu action. Choice tiles become a single column at accessibility text sizes.

Trip opens the existing complete itinerary planner with flexible dates and nights per stop. The other five choices open a category-specific search with the existing destination/Apple Maps autocomplete. An optional city narrows place searches. Selecting a result goes to a short review; users can also continue with a typed name when an activity or place is not listed. One **Save to wishlist** button completes the flow. Notes, collection, website and Top pick are behind an optional disclosure.

Resolved place IDs, addresses, coordinates and source are retained for later trip planning. Changing a saved place's name, destination or type clears stale resolved-location metadata. Existing wishlist archives still decode: the new selected-place field is optional, old kind raw values remain unchanged, and Sights is an additional type. No backend migration is needed.

Saved content is grouped into **Trip plans** and **Saved places**, with search and a single filter menu shown only when useful. Existing bookmarked hotels, restaurants, cities and Explore places continue appearing automatically. Legacy custom items remain editable; no saved data is removed.

## Saving and organizing

- Existing saved hotels, restaurant bookmarks, Explore places and saved cities appear automatically. Restaurant bookmarks and their Explore representation appear once, using the same underlying saved record.
- Personal ideas support a name, destination, type, optional web link, notes, collection and Top pick flag. They can be edited or removed.
- Collections are created by entering a name when adding or editing an idea. Select an existing name to group ideas together; clear the name to return an item to Unsorted. Empty collections disappear from the filter.
- Search matches names, destinations, types, notes and collections. Filters narrow by type, collection or Top picks. Sorting supports recent saves, name and destination.
- Opening a saved place preserves access to its original place or city detail page. Unbookmarking there updates the wishlist. Removing from Wishlist removes the original bookmark and its wishlist notes; it never deletes an itinerary entry.

## Planning

Places and personal ideas can be added to an existing trip or to a new one. Creation returns directly to the appropriate hotel-stay or itinerary editor, with notes and valid links carried over. Dates and details remain reviewable before saving. Adding the same source/place again to the same trip opens its existing record, avoiding an accidental duplicate. Trips without a route first acquire a destination.

Destination ideas and saved cities offer **Plan a trip here**, opening trip creation with the destination filled in. Saved city coordinates are retained when using that destination unchanged. Wishlist details show links to trips containing the saved item. Items stay in the wishlist after planning.

## Storage and privacy

Saved places and ideas are private and local to the device; they have no separate wishlist cloud sync. Full wishlist trip plans use JourneyLibrary and the existing explicit journey sharing/backup flow. Extra metadata and personal ideas live in versioned `seur.wishlist.v1` UserDefaults storage in the same suite as existing bookmarks. Catalog and Explore bookmarks remain in their existing stores. Unreadable wishlist data is preserved and cannot be overwritten by a subsequent save. No new paid API calls are needed to display, search, organize or add manual ideas.

Implementation: `Travel/WishlistModels.swift`, `Travel/WishlistViews.swift`, the Travel section switcher, bookmark registration hooks and an optional callback/prefill on `TripCreationView`.

## Full wishlist trip plans

Wishlist → Trip (or plus → Trip) creates a complete JourneyDocument with `dateMode = .nights`. Add destinations and choose nights per stop, then plan activities, restaurants, hotel stays and flight ideas using relative days. No calendar date is required. Hotels use check-in/check-out day selectors; flight ideas are editable itinerary items until actual dates are chosen.

Regular trip creation and route editing expose arrival/departure dates only. The timing mode switch and dated-stop nights stepper are removed. Existing non-template length-of-stay documents appear in Wishlist automatically; the archive format is unchanged.

Choose dates & move to Trips asks for a departure date, previews the route, and converts the same document in place. Stop/event IDs, notes, stays and daily offsets are preserved. Stays move with their destination; shortening a destination below an existing stay is rejected without discarding the stay. Explicit transfer-day allowances remain in the route. Dated trips appear in Trips; flexible plans appear in Wishlist. Templates remain separate.

Wishlist places can be attached to either a dated trip or a wishlist trip plan. Plans are stored in the existing JourneyLibrary archive; saved-place metadata keeps its existing storage.
