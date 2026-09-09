import XCTest
@testable import Aurum

@MainActor final class AurumTests: XCTestCase {
    var store: TravelStore!
    var defaults: UserDefaults!
    override func setUp() {
        defaults = UserDefaults(suiteName: "com.aurum.travel.unittests")!
        defaults.removePersistentDomain(forName: "com.aurum.travel.unittests")
        store = TravelStore(defaults: defaults)
    }
    func testWishlistBookmarksUnifyAndRemoveWithoutDuplicateDining() throws {
        let hotel = try XCTUnwrap(store.featured.first)
        let restaurant = RestaurantPlace(hotel: hotel, venue: hotel.venues[0])
        let city = try XCTUnwrap(ExploreCity.collection.first { $0.name == hotel.city })
        store.toggleSave(hotel); store.toggleRestaurantSave(restaurant); store.toggleExploreCity(city)
        XCTAssertEqual(store.wishlistEntries.count, 3)
        XCTAssertEqual(store.wishlistEntries.filter { $0.kind == .dining }.count, 1)
        let entry = try XCTUnwrap(store.wishlistEntries.first { $0.kind == .dining })
        XCTAssertTrue(store.wishlist.update(WishlistDetails(notes: "Window table", collection: "Anniversary", topPick: true), for: entry.id))
        let reload = TravelStore(defaults: defaults)
        XCTAssertEqual(reload.wishlistEntries.count, 3)
        XCTAssertEqual(reload.wishlist.info(entry.id).notes, "Window table")
        XCTAssertTrue(reload.removeFromWishlist(entry))
        XCTAssertFalse(reload.savedRestaurants.contains(restaurant.id))
        XCTAssertFalse(reload.savedDiscoveries.contains { $0.record.id == restaurant.id })
        XCTAssertEqual(TravelStore(defaults: defaults).wishlistEntries.count, 2)
        XCTAssertTrue(reload.saved.contains(hotel.id))
    }
    func testWishlistIdeasValidationPersistenceEditingAndFilters() throws {
        var idea = WishlistIdea(name: "  Museum after hours  ", destination: " London ", website: "https://example.com/tickets")
        XCTAssertTrue(store.wishlist.saveIdea(idea, details: WishlistDetails(notes: "Book a quiet evening", collection: " Summer ", topPick: true, addedAt: 10)))
        let id = "idea:" + idea.id
        XCTAssertEqual(store.wishlistEntries.first?.title, "Museum after hours")
        XCTAssertEqual(store.wishlistCollections, ["Summer"])
        XCTAssertEqual(store.wishlistMatches(query: "quiet", kind: .experiences, collection: "Summer", topPicks: true).map(\.id), [id])
        XCTAssertTrue(store.wishlistMatches(query: "", kind: .dining).isEmpty)
        XCTAssertTrue(store.wishlistMatches(query: "", collection: "Winter").isEmpty)
        let second = WishlistIdea(name: "A table", destination: "Paris", kind: .dining)
        XCTAssertTrue(store.wishlist.saveIdea(second, details: WishlistDetails(collection: "summer", addedAt: 20)))
        XCTAssertEqual(store.wishlistCollections, ["Summer"])
        XCTAssertEqual(store.wishlistMatches(query: "").first?.title, "A table")
        XCTAssertEqual(store.wishlistMatches(query: "", sort: .destination).first?.title, "Museum after hours")
        XCTAssertFalse(store.wishlist.saveIdea(WishlistIdea(name: "museum after hours", destination: "London"), details: WishlistDetails()))
        XCTAssertFalse(store.wishlist.saveIdea(WishlistIdea(name: " "), details: WishlistDetails()))
        XCTAssertFalse(store.wishlist.saveIdea(WishlistIdea(name: "Unsafe link", website: "javascript:alert(1)"), details: WishlistDetails()))
        idea.name = "A private museum visit"
        XCTAssertTrue(store.wishlist.saveIdea(idea, details: WishlistDetails(notes: "Updated", collection: "Summer")))
        let reload = TravelStore(defaults: defaults)
        XCTAssertEqual(reload.wishlistEntries.count, 2)
        XCTAssertEqual(reload.wishlist.info(id).notes, "Updated")
        XCTAssertTrue(reload.wishlistMatches(query: "Updated").contains { $0.title == "A private museum visit" })
        XCTAssertTrue(reload.removeFromWishlist(try XCTUnwrap(reload.wishlistEntries.first { $0.id == id })))
        XCTAssertFalse(TravelStore(defaults: defaults).wishlistEntries.contains { $0.id == id })
    }
    func testWishlistPlanningIdentityAndCorruptDataProtection() throws {
        let idea = WishlistIdea(name: "Museum", destination: "London")
        XCTAssertTrue(store.wishlist.saveIdea(idea, details: WishlistDetails()))
        let entry = try XCTUnwrap(store.wishlistEntries.first)
        let stop = JourneyStop(name: "London")
        var document = JourneyDocument(title: "London", stops: [stop])
        document.events = [JourneyEvent(stopID: stop.id, place: entry.place)]
        XCTAssertTrue(entry.isPlanned(in: document))
        XCTAssertTrue(store.removeFromWishlist(entry)); XCTAssertEqual(document.events.count, 1)
        document.events[0].place.source = "Different source"
        XCTAssertFalse(entry.isPlanned(in: document))
        let destination = WishlistIdea(name: "Paris", destination: "France", kind: .destinations)
        XCTAssertTrue(store.wishlist.saveIdea(destination, details: WishlistDetails()))
        let city = try XCTUnwrap(store.wishlistEntries.first)
        XCTAssertEqual(city.subtitle, "France"); XCTAssertEqual(city.tripDestination, "Paris, France")
        XCTAssertTrue(city.isPlanned(in: JourneyDocument(title: "Paris", stops: [JourneyStop(name: "Paris, France")])))
        XCTAssertFalse(city.isPlanned(in: JourneyDocument(title: "Paris", stops: [JourneyStop(name: "Paris, Texas")])))
        let corrupt = Data("unreadable wishlist".utf8); defaults.set(corrupt, forKey: "seur.wishlist.v1")
        let blocked = WishlistLibrary(defaults: defaults)
        XCTAssertNotNil(blocked.error)
        XCTAssertFalse(blocked.saveIdea(idea, details: WishlistDetails()))
        XCTAssertEqual(defaults.data(forKey: "seur.wishlist.v1"), corrupt)
    }
    func testImportedCatalogIntegrity() {
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.hotels.count, 1513)
        XCTAssertEqual(Set(store.hotels.map(\.id)).count, 1513)
        XCTAssertEqual(store.hotels.reduce(0) { $0 + $1.venues.count }, 5755)
        XCTAssertEqual(Set(store.hotels.map(\.city)).count, 12)
    }
    func testCuisineAndCitySearch() {
        let results = store.search(query: "Cantonese", city: "Paris", sort: .dining)
        XCTAssertTrue(results.contains { $0.id == "par-peninsula" })
        XCTAssertTrue(results.allSatisfy { $0.city == "Paris" })
        XCTAssertEqual(results.map { $0.venues.count }, results.map { $0.venues.count }.sorted(by: >))
        XCTAssertTrue(store.search(query: "__missing_hotel__").isEmpty)
        XCTAssertEqual(store.search(query: "  savoy  ", city: "London").first?.id, "lon-savoy")
    }
    func testSavedHotelsPersist() {
        let hotel = store.featured[0]
        store.toggleSave(hotel)
        XCTAssertTrue(TravelStore(defaults: defaults).saved.contains(hotel.id))
        store.toggleSave(hotel)
        XCTAssertFalse(TravelStore(defaults: defaults).saved.contains(hotel.id))
    }
    func testRestaurantPersistenceAndHotelScoping() {
        let hotel = store.featured[0]
        let place = RestaurantPlace(hotel: hotel, venue: hotel.venues[0])
        let other = RestaurantPlace(hotel: store.featured[1], venue: hotel.venues[0])
        XCTAssertNotEqual(place.id, other.id)
        store.toggleRestaurantSave(place)
        store.saveRestaurantVisit(RestaurantVisit(rating: 5, note: "Quiet table"), for: place)
        let restored = TravelStore(defaults: defaults)
        XCTAssertEqual(restored.savedDiningPlaces.map(\.id), [place.id])
        XCTAssertEqual(restored.restaurantVisits[place.id]?.rating, 5)
        XCTAssertEqual(restored.restaurantVisits[place.id]?.note, "Quiet table")
        XCTAssertNil(restored.restaurantVisits[other.id])
        store.toggleRestaurantSave(place)
        store.saveRestaurantVisit(RestaurantVisit(), for: place)
        XCTAssertTrue(TravelStore(defaults: defaults).savedRestaurants.isEmpty)
        XCTAssertTrue(TravelStore(defaults: defaults).restaurantVisits.isEmpty)
    }

    func testTripPersistenceDuplicateAndInvalidDates() {
        let hotel = store.featured[0]
        let dates = BookingDates()
        XCTAssertTrue(store.addPlan(name: hotel.name, city: hotel.city, kind: "Stay", hotelID: hotel.id, dates: dates))
        XCTAssertFalse(store.addPlan(name: hotel.name, city: hotel.city, kind: "Stay", hotelID: hotel.id, dates: dates))
        XCTAssertEqual(TravelStore(defaults: defaults).plans.count, 1)
        var invalid = dates; invalid.end = invalid.start
        XCTAssertFalse(store.addPlan(name: "Invalid", city: "Paris", kind: "Stay", hotelID: nil, dates: invalid))
        store.removePlan(store.plans[0])
        XCTAssertTrue(TravelStore(defaults: defaults).plans.isEmpty)
    }
    func testSafeLinksAndFlightValidation() {
        XCTAssertNil(validatedURL("javascript:alert(1)"))
        XCTAssertNil(validatedURL("n/a"))
        XCTAssertNotNil(validatedURL("https://www.google.com"))
        var flight = FlightSearch()
        XCTAssertNotNil(flight.url)
        let query = URLComponents(url: flight.url!, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!
        XCTAssertTrue(query.contains("returning"))
        XCTAssertTrue(query.contains("2 adults Business"))
        flight.oneWay = true
        XCTAssertFalse(URLComponents(url: flight.url!, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!.contains("returning"))
        flight.destination = flight.origin
        XCTAssertNil(flight.url)
    }
    func testComparisonLimit() {
        for hotel in store.hotels.prefix(4) { store.toggleCompare(hotel) }
        XCTAssertEqual(store.compared.count, 3)
        store.toggleCompare(store.hotels[0])
        XCTAssertEqual(store.compared.count, 2)
    }
}
