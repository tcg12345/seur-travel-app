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
