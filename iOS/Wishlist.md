# Travel wishlist

Travel has two sections: Trips and Wishlist. The navigation-bar plus always creates a trip. Wishlist’s **Add idea** action creates an undated personal idea.

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

This feature is private and local to the device; there is no wishlist cloud sync or sharing. Extra metadata and personal ideas live in versioned `seur.wishlist.v1` UserDefaults storage in the same suite as existing bookmarks. Catalog and Explore bookmarks remain in their existing stores. Unreadable wishlist data is preserved and cannot be overwritten by a subsequent save. No new paid API calls are needed to display, search, organize or add manual ideas.

Implementation: `Travel/WishlistModels.swift`, `Travel/WishlistViews.swift`, the Travel section switcher, bookmark registration hooks and an optional callback/prefill on `TripCreationView`.
