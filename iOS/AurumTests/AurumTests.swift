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
    func testRestaurantConciergeUsesSelectedVenue() {
        let hotel = store.featured[0], venue = store.featured[0].venues[0]
        var context = ConciergeContext()
        let reply = ConciergeEngine.reply(to: "Tell me about \(venue.name) at \(hotel.name)", context: &context, store: store)
        XCTAssertTrue(reply.text.contains(venue.description))
        XCTAssertTrue(reply.text.contains("doesn’t reserve a table"))
        XCTAssertEqual(context.city, hotel.city)
        XCTAssertTrue(store.plans.isEmpty)
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
    func testConciergeRecommendationsAndContext() {
        var context = ConciergeContext()
        let reply = ConciergeEngine.reply(to: "Find a hotel in Paris with great dining", context: &context, store: store)
        XCTAssertEqual(context.city, "Paris")
        XCTAssertFalse(reply.hotelIDs.isEmpty)
        XCTAssertTrue(reply.hotelIDs.allSatisfy { id in store.hotels.contains { $0.id == id && $0.city == "Paris" } })
        let followUp = ConciergeEngine.reply(to: "Japanese dining instead", context: &context, store: store)
        XCTAssertEqual(context.city, "Paris")
        XCTAssertEqual(context.cuisine, "Japanese")
        XCTAssertFalse(followUp.hotelIDs.isEmpty)
        XCTAssertTrue(followUp.hotelIDs.allSatisfy { id in store.hotels.first { $0.id == id }!.venues.contains { $0.cuisine.localizedCaseInsensitiveContains("Japanese") } })
    }
    func testConciergeDoesNotBookAndUsesRealPlans() {
        var context = ConciergeContext(city: "Bangkok")
        let booking = ConciergeEngine.reply(to: "Book it for me", context: &context, store: store)
        XCTAssertTrue(booking.text.contains("can’t make reservations"))
        XCTAssertTrue(store.plans.isEmpty)
        let emptyPlans = ConciergeEngine.reply(to: "Show my itinerary", context: &context, store: store)
        XCTAssertTrue(emptyPlans.text.contains("fresh page"))
        let hotel = store.featured[0]
        store.addPlan(name: hotel.name, city: hotel.city, kind: "Stay", hotelID: hotel.id, dates: BookingDates())
        XCTAssertTrue(ConciergeEngine.reply(to: "Show my itinerary", context: &context, store: store).text.contains(hotel.name))
        XCTAssertEqual(ConciergeEngine.reply(to: "Help me find flights", context: &context, store: store).action, .flights)
    }
    func testConciergeResetCancelsReply() async throws {
        let chat = ConciergeConversation()
        chat.send("Paris", store: store)
        chat.send("Tokyo", store: store)
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertTrue(chat.isReplying)
        chat.reset()
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertFalse(chat.isReplying)
        XCTAssertNil(chat.context.city)
        chat.send("  ", store: store)
        XCTAssertTrue(chat.messages.isEmpty)
    }

}
