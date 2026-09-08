import XCTest
import PDFKit
import MapKit
@testable import Aurum

@MainActor final class JourneyTests: XCTestCase {
    var directory: URL!
    override func setUp() { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }
    func itinerary() -> JourneyDocument {
        let stop = JourneyStop(name: "Paris", arrival: "2026-10-01", nights: 3)
        var d = JourneyDocument(title: "Paris, thoughtfully", startDate: "2026-10-01", endDate: "2026-10-04", stops: [stop])
        d.events = [JourneyEvent(stopID: stop.id, place: PlaceRecord(id: "dinner", name: "Dinner", category: .restaurant), cost: TravelMoney(amount: Decimal(string: "85.50")!, currency: "EUR"))]
        return d
    }
    func testMultiCitySuggestionMatchesExhaustiveSearchAndPreservesEndpoints() throws {
        let stops = (0..<6).map { i in JourneyStop(name: "City \(i)", nights: 2, latitude: [48.8,52.3,50.8,55.6,53.5,59.3][i], longitude: [2.3,4.9,4.3,12.5,9.9,18.0][i]) }
        func permutations(_ items: [JourneyStop]) -> [[JourneyStop]] {
            if items.isEmpty { return [[]] }
            return items.indices.flatMap { i in var rest = items; let first = rest.remove(at: i); return permutations(rest).map { [first] + $0 } }
        }
        for objective in RouteObjective.allCases {
            var plan = JourneyRoutePlan(); plan.objective = objective; plan.keepLast = true
            plan.home = .init(id: "home", name: "London", latitude: 51.5, longitude: -0.1)
            let suggested = try XCTUnwrap(MultiCityRouting.suggest(stops, plan: plan))
            XCTAssertEqual(suggested.first?.id, stops.first?.id); XCTAssertEqual(suggested.last?.id, stops.last?.id)
            let minimum = permutations(Array(stops.dropFirst().dropLast())).map { [stops[0]] + $0 + [stops.last!] }.map { MultiCityRouting.cost($0, plan: plan) }.min()!
            XCTAssertEqual(MultiCityRouting.cost(suggested, plan: plan), minimum, accuracy: 0.001)
        }
        var open = JourneyRoutePlan(); open.keepFirst = false
        let suggestion = try XCTUnwrap(MultiCityRouting.suggest(stops, plan: open))
        let minimum = permutations(stops).map { MultiCityRouting.cost($0, plan: open) }.min()!
        XCTAssertEqual(MultiCityRouting.cost(suggestion, plan: open), minimum, accuracy: 0.001)
    }
    func testMultiCityDateReflowRetainsCityPlansAndBookedReservations() throws {
        var original = MultiCityRouteFixtures.trip
        original.hotels = [HotelReservation(place: PlaceRecord(name: "Booked hotel", category: .hotel), checkIn: "2026-10-04", checkOut: "2026-10-06")]
        original.flights = [FlightMapFixtures.trip.flights[0]]
        let proposed = try XCTUnwrap(MultiCityRouting.suggest(original.stops, plan: .init()))
        XCTAssertEqual(proposed.map(\.name), ["Paris", "Brussels", "Amsterdam"])
        let result = try MultiCityRouting.applying(proposed, plan: .init(), to: original)
        XCTAssertEqual(result.stops.map(\.arrival), ["2026-10-01", "2026-10-04", "2026-10-06"])
        XCTAssertEqual(result.startDate, original.startDate); XCTAssertEqual(result.endDate, original.endDate)
        XCTAssertEqual(result.events.first { $0.id == original.events[0].id }, original.events[0])
        XCTAssertEqual(result.date(for: original.events[0]), "2026-10-07")
        XCTAssertEqual(result.hotels, original.hotels); XCTAssertEqual(result.flights, original.flights)
        XCTAssertEqual(Set(result.stops.map(\.id)), Set(original.stops.map(\.id)))
        XCTAssertNil(result.validationError())
    }
    func testMultiCityTransfersPersistWithoutDuplicatesAndCanBeRemoved() throws {
        let original = MultiCityRouteFixtures.trip, plan = JourneyRoutePlan()
        let once = try MultiCityRouting.applying(original.stops, plan: plan, to: original)
        let twice = try MultiCityRouting.applying(once.stops, plan: plan, to: once)
        XCTAssertEqual(once.events, twice.events)
        XCTAssertEqual(twice.events.filter { $0.routeLegID != nil }.count, 2)
        let library = JourneyLibrary(url: directory.appendingPathComponent("route.json"))
        XCTAssertTrue(library.save(twice))
        let restored = try XCTUnwrap(JourneyLibrary(url: directory.appendingPathComponent("route.json")).documents.first)
        XCTAssertEqual(restored.routePlan, plan); XCTAssertEqual(restored.events, twice.events)
        var noBlocks = plan; noBlocks.reserveTransfers = false
        let cleared = try MultiCityRouting.applying(restored.stops, plan: noBlocks, to: restored)
        XCTAssertEqual(cleared.events, original.events)
        let old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        XCTAssertNotNil(try JSONDecoder().decode(JourneyDocument.self, from: JSONSerialization.data(withJSONObject: old)))
    }
    func testMultiCityOvernightAndFlexibleDates() throws {
        let original = MultiCityRouteFixtures.trip
        let firstLeg = MultiCityRouting.legs(original.stops, plan: .init())[0]
        var plan = JourneyRoutePlan()
        plan.choices = [.init(key: firstLeg.id, mode: .train, minutes: 1500, extraDays: 1)]
        let dated = try MultiCityRouting.applying(original.stops, plan: plan, to: original)
        XCTAssertEqual(dated.stops[1].arrival, "2026-10-05"); XCTAssertEqual(dated.stops[2].arrival, "2026-10-07")
        XCTAssertEqual(dated.endDate, "2026-10-09")
        XCTAssertEqual(dated.events.first { $0.routeLegID == firstLeg.id }?.durationMinutes, 1440)
        XCTAssertEqual(dated.events.first { $0.routeLegID == firstLeg.id }?.allDay, true)
        var flexible = original; flexible.dateMode = .nights; flexible.startDate = nil; flexible.endDate = nil
        let result = try MultiCityRouting.applying(Array(flexible.stops.reversed()), plan: plan, to: flexible)
        XCTAssertNil(result.startDate); XCTAssertNil(result.endDate)
        for stop in result.stops { XCTAssertEqual(stop.nights, original.stops.first { $0.id == stop.id }?.nights) }
    }
    func testMultiCityRailEstimatesAndHomeLegsAreExplicit() throws {
        let stops = MultiCityRouteFixtures.trip.stops
        let paris = try XCTUnwrap(RoutePoint(stops[0])), brussels = try XCTUnwrap(RoutePoint(stops[2]))
        let rail = try XCTUnwrap(MultiCityRouting.options(paris, brussels).first { $0.mode == .train })
        XCTAssertEqual(rail.rideMinutes, 82); XCTAssertEqual(rail.bufferMinutes, 45); XCTAssertNotNil(rail.source)
        let remote = RoutePoint(id: "remote", name: "Remote city", latitude: -33.8, longitude: 151.2)
        XCTAssertFalse(MultiCityRouting.options(paris, remote).contains { $0.mode == .train })
        XCTAssertTrue(MultiCityRouting.options(paris, remote)[0].explanation.contains("not verified"))
        var plan = JourneyRoutePlan(); plan.home = remote
        let roundTrip = MultiCityRouting.legs(stops, plan: plan)
        XCTAssertEqual(roundTrip.count, stops.count + 1); XCTAssertEqual(roundTrip.first?.from, remote); XCTAssertEqual(roundTrip.last?.to, remote)
        plan.returnHome = false
        XCTAssertEqual(MultiCityRouting.legs(stops, plan: plan).count, stops.count)
        let cph = RoutePoint(id: "cph", name: "Copenhagen", latitude: 55.6761, longitude: 12.5683)
        let oslo = RoutePoint(id: "osl", name: "Oslo", latitude: 59.9139, longitude: 10.7522)
        let connecting = try XCTUnwrap(MultiCityRouting.options(cph, oslo).first { $0.mode == .train })
        XCTAssertTrue(connecting.explanation.contains("Gothenburg")); XCTAssertGreaterThan(connecting.total, 420)
    }
    func testMultiCityOvernightHomeLegsExtendTripWithoutChangingFirstStay() throws {
        let original = MultiCityRouteFixtures.trip
        var plan = JourneyRoutePlan(); plan.home = .init(id: "home", name: "Sydney", latitude: -33.8, longitude: 151.2)
        let legs = MultiCityRouting.legs(original.stops, plan: plan)
        plan.choices = [.init(key: legs.first!.id, mode: .flight, minutes: 1500, extraDays: 1), .init(key: legs.last!.id, mode: .flight, minutes: 1500, extraDays: 2)]
        let result = try MultiCityRouting.applying(original.stops, plan: plan, to: original)
        XCTAssertEqual(result.startDate, "2026-09-30"); XCTAssertEqual(result.endDate, "2026-10-10")
        XCTAssertEqual(result.stops.first?.arrival, "2026-10-01")
        XCTAssertEqual(result.events.filter { $0.routeLegID != nil }.count, 4)
        XCTAssertEqual(result.events.first { $0.routeLegID == legs.first!.id }?.displayTitle, "Arrive in Paris")
    }
    func testMultiCityMissingCoordinatesAndInvalidChoicesFailSafely() throws {
        let original = MultiCityRouteFixtures.trip
        var missing = original.stops; missing[0].latitude = nil
        XCTAssertNil(MultiCityRouting.suggest(missing, plan: .init()))
        XCTAssertThrowsError(try MultiCityRouting.applying(missing, plan: .init(), to: original))
        var invalid = JourneyRoutePlan(); invalid.home = .init(id: "bad", name: "Invalid", latitude: .nan, longitude: 0)
        XCTAssertNil(MultiCityRouting.suggest(original.stops, plan: invalid))
        invalid.home = nil; invalid.choices = [.init(key: "bad", mode: .flight, minutes: 1500, extraDays: 0)]
        XCTAssertThrowsError(try MultiCityRouting.applying(original.stops, plan: invalid, to: original))
        invalid.choices = [.init(key: "boundary", mode: .flight, minutes: 1440, extraDays: 0)]
        XCTAssertFalse(invalid.valid)
        invalid.choices[0].extraDays = 1; XCTAssertTrue(invalid.valid)
        invalid.choices = [.init(key: "bad", mode: .flight, minutes: -50)]
        XCTAssertThrowsError(try MultiCityRouting.applying(original.stops, plan: invalid, to: original))
        XCTAssertThrowsError(try MultiCityRouting.applying(Array(original.stops.dropFirst()), plan: .init(), to: original))
    }
    func testMultiCityLargeRouteNeverRegressesOrDropsStops() throws {
        let stops: [JourneyStop] = (0..<16).map { i in
            let latitude = Double((i * 23) % 130 - 65)
            let longitude = Double((i * 47) % 340 - 170)
            return JourneyStop(name: "City \(i)", latitude: latitude, longitude: longitude)
        }
        var plan = JourneyRoutePlan(); plan.keepLast = true
        let result = try XCTUnwrap(MultiCityRouting.suggest(stops, plan: plan))
        XCTAssertEqual(result.first, stops.first); XCTAssertEqual(result.last, stops.last)
        XCTAssertEqual(Set(result.map(\.id)), Set(stops.map(\.id)))
        XCTAssertLessThanOrEqual(MultiCityRouting.cost(result, plan: plan), MultiCityRouting.cost(stops, plan: plan))
    }
    func testFlightSearchConversionUsesScheduledAirportLocalTimes() throws {
        var flight = FlightMapFixtures.snapshot
        flight.originZone = "America/New_York"; flight.destinationZone = "Europe/London"
        let saved = flight.reservation(airline: "British Airways")
        XCTAssertEqual(saved.departureDay, "2026-09-06"); XCTAssertEqual(saved.departureTime, "18:00")
        XCTAssertEqual(saved.arrivalDay, "2026-09-07"); XCTAssertEqual(saved.arrivalTime, "06:00")
        XCTAssertEqual(saved.flightNumber, "BA178")
        XCTAssertNil(MapFlight(tripID: nil, tripTitle: "My flights", flight: saved).route)
        flight.scheduledIn = nil; flight.scheduledOn = nil
        XCTAssertEqual(flight.reservation(airline: "BA").arrivalTime, "")
    }
    func testFlightDurationRespectsAirportTimeZonesAndMissingData() {
        var saved = FlightMapFixtures.snapshot.reservation(airline: "British Airways")
        XCTAssertEqual(FlightDisplay.duration(saved), "7h 0m")
        saved.departureZone = ""
        XCTAssertNil(FlightDisplay.duration(saved))
        saved.departureZone = "America/New_York"; saved.arrivalDay = "2026-09-05"
        XCTAssertNil(FlightDisplay.duration(saved))
        XCTAssertEqual(FlightDisplay.clock("2026-09-06T22:30:00Z", zone: "America/New_York"), "18:30")
        XCTAssertEqual(FlightDisplay.clock(nil, zone: "America/New_York"), "—")
    }
    func testFlightCountdownUsesDepartureZoneAndNeverInventsFlightStatus() throws {
        var flight = FlightMapFixtures.snapshot.reservation(airline: "British Airways")
        let departure = try XCTUnwrap(FlightDisplay.localDate(day: flight.departureDay, time: flight.departureTime, zone: flight.departureZone))
        XCTAssertEqual(FlightDisplay.countdown(flight, now: departure.addingTimeInterval(-5 * 3600 - 42 * 60)), "In 5h 42m")
        XCTAssertEqual(FlightDisplay.countdown(flight, now: departure.addingTimeInterval(-2 * 86400 - 3 * 3600)), "In 2d 3h")
        XCTAssertEqual(FlightDisplay.countdown(flight, now: departure.addingTimeInterval(-25)), "In 1m")
        XCTAssertEqual(FlightDisplay.countdown(flight, now: departure), "Scheduled time passed")
        flight.departureZone = ""
        XCTAssertEqual(FlightDisplay.countdown(flight, now: departure), "Departure time unavailable")
    }
    func testAirlineAutocompleteSupportsNamesCodesAndUnlistedCodes() {
        XCTAssertEqual(FlightAirline.matches("delta").first?.code, "DL")
        XCTAssertTrue(FlightAirline.matches("BA").contains { $0.name == "British Airways" })
        XCTAssertEqual(FlightAirline.matches("ZZZ").first?.code, "ZZZ")
        XCTAssertEqual(FlightAirline.identified(by: "BA178")?.name, "British Airways")
        XCTAssertEqual(FlightAddView.airportCode(" jfk "), "JFK")
        XCTAssertNil(FlightAddView.airportCode("New York"))
    }
    func testLegacyTripPreparesRouteFromExistingChoices() throws {
        var trip = JourneyDocument(kind: .trip, title: "Old trip", destination: "Paris", startDate: "2026-10-01", endDate: "2026-10-04")
        trip.places = [RatedPlace(place: PlaceRecord(name: "A favourite table", category: .restaurant), overall: 9)]
        let originalID = trip.id, places = trip.places
        XCTAssertTrue(trip.preparePlanningRoute())
        XCTAssertEqual(trip.stops.first?.name, "Paris"); XCTAssertEqual(trip.stops.first?.nights, 3)
        XCTAssertEqual(trip.id, originalID); XCTAssertEqual(trip.places, places)
        XCTAssertFalse(trip.preparePlanningRoute()); XCTAssertEqual(trip.stops.count, 1)
        var undated = JourneyDocument(title: "Later", destination: "Paris")
        XCTAssertFalse(undated.preparePlanningRoute()); XCTAssertTrue(undated.stops.isEmpty)
    }
    func testEveryEventKindSavesReloadsAndMapsItsVenue() throws {
        var document = itinerary(); document.events = []
        for kind in ItineraryItemKind.allCases {
            let venue = PlaceRecord(id: kind.rawValue, name: "Venue for " + kind.title, category: kind == .place ? .restaurant : .other, latitude: 48.85, longitude: 2.35)
            document.putEvent(JourneyEvent(stopID: document.stops[0].id, place: venue, kind: kind, title: kind.title), on: [0, 1])
        }
        let url = directory.appendingPathComponent("every-kind.json")
        let library = JourneyLibrary(url: url)
        XCTAssertTrue(library.save(document))
        let saved = try XCTUnwrap(JourneyLibrary(url: url).documents.first)
        XCTAssertEqual(saved.events.count, ItineraryItemKind.allCases.count * 2)
        XCTAssertEqual(Set(saved.events.compactMap(\.kind)), Set(ItineraryItemKind.allCases))
        XCTAssertEqual(saved.mapPlaces.filter(\.hasCoordinate).count, saved.events.count)
    }
    func testMeetingPersistenceAndLegacyDecoding() throws {
        var d = itinerary()
        let legacy = try JSONDecoder().decode(JourneyDocument.self, from: JSONEncoder().encode(d))
        XCTAssertNil(legacy.events[0].kind); XCTAssertTrue(legacy.events[0].isPlaceVisit)
        XCTAssertEqual(legacy.events[0].displayTitle, "Dinner")
        let event = JourneyEvent(stopID: d.stops[0].id, minute: 23 * 60 + 30, kind: .meeting, title: "Design review", durationMinutes: 90, attendees: "Alex & Sam")
        d.putEvent(event, on: [0, 2])
        XCTAssertNil(d.validationError())
        let library = JourneyLibrary(url: directory.appendingPathComponent("library.json"))
        XCTAssertTrue(library.save(d))
        let restored = try XCTUnwrap(JourneyLibrary(url: directory.appendingPathComponent("library.json")).documents.first)
        XCTAssertEqual(restored, library.documents[0])
        XCTAssertEqual(restored.events.filter { $0.kind == .meeting }.count, 2)
        XCTAssertEqual(event.scheduleLabel, "23:30 – 01:00 (+1 day)")
        XCTAssertEqual(restored.copyAsTrip().places.count, 1)
    }
    func testEventValidationAllDayAndImportExclusions() {
        var d = itinerary()
        var event = JourneyEvent(stopID: d.stops[0].id, place: PlaceRecord(name: "A restaurant venue", category: .restaurant), kind: .meeting, title: "Team lunch", allDay: true, durationMinutes: 60)
        d.events.append(event)
        XCTAssertNil(d.validationError()); XCTAssertEqual(d.copyAsTrip().places.count, 1)
        XCTAssertEqual(event.scheduleLabel, "All day"); XCTAssertEqual(event.sortMinute, -1); XCTAssertNil(event.endTimeLabel)
        d.events[1].title = "  "; XCTAssertNotNil(d.validationError())
        d.events[1].title = "Team lunch"; d.events[1].durationMinutes = 0; XCTAssertNotNil(d.validationError())
        d.events[1].durationMinutes = 1441; XCTAssertNotNil(d.validationError())
        event.place.latitude = 48.85; event.place.longitude = 2.35
        d.events = [event]
        XCTAssertTrue(d.mapPlaces.contains { $0.name == "Team lunch · A restaurant venue" && $0.hasCoordinate })
    }
    func testCustomEventsAppearInEveryExport() throws {
        var d = itinerary()
        d.events = [JourneyEvent(stopID: d.stops[0].id, minute: 600, links: ["https://example.com/meeting"], kind: .custom, title: "Private preview", durationMinutes: 90, attendees: "Alex")]
        let text = JourneyExporter.text(d)
        XCTAssertTrue(text.contains("10:00 – 11:30 — Private preview [Custom event]")); XCTAssertTrue(text.contains("Alex"))
        let csv = JourneyExporter.csv(d)
        XCTAssertTrue(csv.contains("event_type")); XCTAssertTrue(csv.contains("Private preview")); XCTAssertTrue(csv.contains("\"90\""))
        let pdf = try XCTUnwrap(PDFDocument(url: JourneyExporter.export(d, format: .pdf)))
        XCTAssertTrue(pdf.string?.contains("Private preview") == true)
        let json = try JSONDecoder().decode(JourneyArchive.self, from: Data(contentsOf: JourneyExporter.export(d, format: .json)))
        XCTAssertEqual(json.document, d)
    }
    func testUnifiedTripsPreserveLegacyRecordsAndBothHalves() throws {
        var oldPlan = itinerary(); oldPlan.kind = .itinerary
        oldPlan.hotels = [HotelReservation(place: PlaceRecord(name: "Quiet Hotel", category: .hotel), confirmation: "ABC123", cost: TravelMoney(amount: 650))]
        oldPlan.flights = [FlightReservation(airline: "Airline", departureAirport: "JFK", arrivalAirport: "CDG", cost: TravelMoney(amount: 400))]
        let visit = RatedPlace(place: PlaceRecord(name: "A Paris cafe", category: .cafe, latitude: 48.85, longitude: 2.35), overall: 9.2, scores: ["Service": 9], notes: "Window table", visitedOn: "2026-10-02", photos: [JournalPhoto(jpeg: Data([1, 2, 3]))])
        oldPlan.places = [visit]
        var oldJournal = JourneyDocument(kind: .trip, title: "Past Paris", destination: "Paris", startDate: "2025-10-01", endDate: "2025-10-04", visibility: .public, places: [visit])
        oldJournal.description = "Keep this description"
        let url = directory.appendingPathComponent("library.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(JourneyLibraryArchive(documents: [oldPlan, oldJournal])).write(to: url)
        let library = JourneyLibrary(url: url)
        XCTAssertEqual(library.documents, [oldPlan, oldJournal])
        XCTAssertTrue(library.save(oldPlan)); XCTAssertTrue(library.save(oldJournal))
        let restored = JourneyLibrary(url: url)
        XCTAssertEqual(restored.documents.count, 2)
        for original in [oldPlan, oldJournal] {
            let trip = try XCTUnwrap(restored.documents.first { $0.id == original.id })
            XCTAssertEqual(trip.kind, .journey)
            XCTAssertEqual(trip.stops, original.stops); XCTAssertEqual(trip.events, original.events)
            XCTAssertEqual(trip.hotels, original.hotels); XCTAssertEqual(trip.flights, original.flights)
            XCTAssertEqual(trip.places, original.places); XCTAssertEqual(trip.visibility, original.visibility)
            XCTAssertEqual(trip.description, original.description); XCTAssertEqual(trip.startDate, original.startDate)
        }
        XCTAssertTrue(oldPlan.mapPlaces.contains { $0.name == visit.place.name })
        XCTAssertNil(oldJournal.validationError())
        oldJournal.stops = oldPlan.stops; oldJournal.events = oldPlan.events
        XCTAssertNil(oldJournal.validationError())
        XCTAssertTrue(oldJournal.mapPlaces.contains { $0.name == "Dinner" })
    }
    func testJournalImportWithinTripIsAdditiveAndIdempotent() {
        var trip = itinerary()
        var rated = RatedPlace(place: trip.events[0].place, overall: 9, notes: "Keep my review")
        rated.photos = [JournalPhoto(jpeg: Data([1]))]
        trip.places = [rated]
        let events = trip.events
        XCTAssertEqual(trip.addPlannedPlacesToJournal(), 0)
        XCTAssertEqual(trip.places, [rated]); XCTAssertEqual(trip.events, events)
        let attraction = JourneyEvent(stopID: trip.stops[0].id, place: PlaceRecord(name: "Garden", category: .attraction))
        trip.events.append(attraction)
        trip.events.append(JourneyEvent(stopID: trip.stops[0].id, place: PlaceRecord(name: "Restaurant venue"), kind: .meeting, title: "Meeting"))
        XCTAssertEqual(trip.addPlannedPlacesToJournal(), 1)
        XCTAssertEqual(trip.places.count, 2); XCTAssertNil(trip.places.last?.visitedOn)
        XCTAssertEqual(trip.places.first, rated); XCTAssertEqual(trip.addPlannedPlacesToJournal(), 0)
        XCTAssertEqual(trip.events.count, 3)
    }
    func testEveryExportIncludesPlansAndJournalRegardlessOfLegacyKind() throws {
        for kind in [JourneyKind.itinerary, .trip, .journey] {
            var trip = itinerary(); trip.kind = kind
            trip.places = [RatedPlace(place: PlaceRecord(name: "Wonderful museum", category: .museum), overall: 8.7, scores: ["Experience": 9], notes: "Worth revisiting")]
            let text = JourneyExporter.text(trip)
            XCTAssertTrue(text.contains("Dinner")); XCTAssertTrue(text.contains("Wonderful museum")); XCTAssertTrue(text.contains("Worth revisiting"))
            let csv = JourneyExporter.csv(trip)
            XCTAssertTrue(csv.contains("Dinner")); XCTAssertTrue(csv.contains("Wonderful museum"))
            let pdf = try XCTUnwrap(PDFDocument(url: JourneyExporter.export(trip, format: .pdf)))
            XCTAssertTrue(pdf.string?.contains("Dinner") == true); XCTAssertTrue(pdf.string?.contains("Wonderful museum") == true)
            let library = JourneyLibrary(url: directory.appendingPathComponent(UUID().uuidString))
            let id = try library.importData(JSONEncoder().encode(JourneyArchive(document: trip)))
            let imported = try XCTUnwrap(library.documents.first { $0.id == id })
            XCTAssertEqual(imported.events, trip.events); XCTAssertEqual(imported.places, trip.places)
            XCTAssertEqual(imported.visibility, .private); XCTAssertEqual(imported.kind, .journey)
        }
    }
    func testCalendarDaysAndMultiCityValidation() {
        XCTAssertEqual(TravelDay.adding(1, to: "2028-02-28"), "2028-02-29")
        XCTAssertEqual(TravelDay.adding(1, to: "2026-12-31"), "2027-01-01")
        XCTAssertNil(TravelDay.date("2026-02-30"))
        XCTAssertEqual(TravelDay.distance("2026-03-07", "2026-03-10"), 3)
        var d = itinerary(); d.stops.append(JourneyStop(name: "London", arrival: "2026-10-04", nights: 2))
        XCTAssertNil(d.validationError())
        d.stops[1].arrival = "2026-10-03"; XCTAssertNotNil(d.validationError())
        d.dateMode = .nights; d.startDate = nil; d.endDate = nil
        XCTAssertNil(d.validationError()); XCTAssertTrue(d.days.allSatisfy { $0.date == nil }); XCTAssertEqual(d.nights, 5)
    }
    func testRepeatedEventsAvoidDuplicatesAndCountCosts() {
        var d = itinerary(); var event = d.events[0]
        d.putEvent(event, on: [0, 1, 2])
        XCTAssertEqual(d.events.count, 3)
        XCTAssertEqual(d.eventTotals["EUR"], Decimal(string: "256.50"))
        event.description = "Updated"
        d.putEvent(event, on: [0, 1, 2])
        XCTAssertEqual(d.events.count, 3); XCTAssertEqual(Set(d.events.map(\.id)).count, 3)
        XCTAssertTrue(d.events.allSatisfy { $0.description == "Updated" })
        d.putEvent(event, on: [])
        XCTAssertEqual(d.events.count, 3)
    }
    func testMixedCurrencyTotalsAndInvalidPrices() {
        var d = itinerary()
        d.hotels = [HotelReservation(place: PlaceRecord(name: "Hotel", category: .hotel), cost: TravelMoney(amount: 500, currency: "USD"))]
        XCTAssertEqual(d.totals["EUR"], Decimal(string: "85.50"))
        XCTAssertEqual(d.totals["USD"], 500)
        d.events[0].cost?.amount = -1; XCTAssertNotNil(d.validationError())
        d.events[0].cost = nil; XCTAssertNil(d.eventTotals["EUR"])
    }
    func testItineraryMapIncludesStopsHotelsEventsAndAirports() {
        var d = itinerary(); d.stops[0].latitude = 48.85; d.stops[0].longitude = 2.35
        d.hotels = [HotelReservation(place: PlaceRecord(name: "Hotel", category: .hotel, latitude: 48.86, longitude: 2.36))]
        d.flights = [FlightReservation(airline: "Airline", departureAirport: "JFK", arrivalAirport: "CDG", departureLatitude: 40.64, departureLongitude: -73.78, arrivalLatitude: 49.0, arrivalLongitude: 2.55)]
        XCTAssertEqual(d.mapPlaces.count, 5)
        XCTAssertEqual(d.mapPlaces.filter(\.hasCoordinate).count, 4)
        XCTAssertTrue(d.mapPlaces.contains { $0.name == "JFK" })
    }
    func testImportItineraryOnlyBringsPlacesToRate() {
        var d = itinerary(); let stop = d.stops[0]
        d.events += [JourneyEvent(stopID: stop.id, day: 1, place: d.events[0].place), JourneyEvent(stopID: stop.id, place: PlaceRecord(id: "museum", name: "Attraction", category: .attraction)), JourneyEvent(stopID: stop.id, place: PlaceRecord(name: "Shopping", category: .shopping))]
        d.flights = [FlightReservation(airline: "Test Air", departureAirport: "JFK", arrivalAirport: "CDG")]
        let trip = d.copyAsTrip()
        XCTAssertEqual(trip.kind, .trip); XCTAssertEqual(trip.visibility, .private)
        XCTAssertEqual(trip.places.count, 2); XCTAssertTrue(trip.places.allSatisfy { $0.overall == 0 && $0.visitedOn == nil })
        XCTAssertTrue(trip.events.isEmpty); XCTAssertTrue(trip.flights.isEmpty); XCTAssertTrue(trip.hotels.isEmpty)
        XCTAssertNotEqual(trip.id, d.id)
    }
    func testLibraryPersistenceImportAndCorruptFileProtection() throws {
        let url = directory.appendingPathComponent("library.json")
        let library = JourneyLibrary(url: url)
        var d = itinerary(); d.visibility = .friends
        XCTAssertTrue(library.save(d))
        let restored = JourneyLibrary(url: url)
        XCTAssertEqual(restored.documents.first?.title, d.title)
        let newID = try restored.importData(JSONEncoder().encode(JourneyArchive(document: d)))
        XCTAssertNotEqual(newID, d.id); XCTAssertEqual(restored.documents.first?.visibility, .private)
        XCTAssertTrue(restored.remove(newID)); XCTAssertEqual(JourneyLibrary(url: url).documents.count, 1)
        try Data("corrupt but must not be destroyed".utf8).write(to: url)
        let corrupt = JourneyLibrary(url: url)
        XCTAssertNotNil(corrupt.error); XCTAssertFalse(corrupt.save(d))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "corrupt but must not be destroyed")
    }
    func testImportRejectsInvalidReferencesAndFutureSchema() throws {
        let library = JourneyLibrary(url: directory.appendingPathComponent("library.json"))
        var d = itinerary(); d.events[0].stopID = UUID()
        XCTAssertThrowsError(try library.importData(JSONEncoder().encode(JourneyArchive(document: d))))
        XCTAssertThrowsError(try library.importData(JSONEncoder().encode(JourneyArchive(version: 900, document: itinerary()))))
        XCTAssertTrue(library.documents.isEmpty)
    }
    func testExportsPreserveDataAndNeutralizeCSVFormulas() throws {
        var d = itinerary(); d.title = "=SUM(A1:A9)"; d.description = "Comma, quote \" and\nnew line"
        let csv = JourneyExporter.csv(d)
        XCTAssertTrue(csv.contains("\"'=SUM(A1:A9)\"")); XCTAssertTrue(csv.contains("quote \"\""))
        XCTAssertEqual(JourneyExporter.csvCell("  @danger"), "\"'  @danger\"")
        let jsonURL = try JourneyExporter.export(d, format: .json)
        XCTAssertEqual(try JSONDecoder().decode(JourneyArchive.self, from: Data(contentsOf: jsonURL)).document, d)
        let txtURL = try JourneyExporter.export(d, format: .txt)
        XCTAssertTrue(try String(contentsOf: txtURL, encoding: .utf8).contains("85.50"))
        let pdfURL = try JourneyExporter.export(d, format: .pdf)
        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
        XCTAssertGreaterThan(pdf.pageCount, 0); XCTAssertTrue(pdf.string?.contains("Paris") == true)
    }
    func testLongPDFPaginatedAndReadable() throws {
        var d = itinerary(); d.description = String(repeating: "An unforgettable journey with beautiful places. ", count: 250) + "END OF LONG DESCRIPTION"
        let url = try JourneyExporter.export(d, format: .pdf)
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(pdf.pageCount, 2)
        XCTAssertTrue(pdf.string?.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").contains("END OF LONG DESCRIPTION") == true)
        XCTAssertTrue(pdf.string?.contains("Dinner") == true)
    }
    func testRatedPlaceValidationAndUnknownScores() {
        var d = JourneyDocument(kind: .trip, title: "My trip")
        d.places = [RatedPlace(place: PlaceRecord(name: "A table"), overall: 8, scores: ["Food & drink": 9])]
        XCTAssertEqual(d.averageScore, 8)
        d.places.append(RatedPlace(place: PlaceRecord(name: "Not rated")))
        XCTAssertEqual(d.averageScore, 8)
        d.places[0].scores["Value"] = 12; XCTAssertNotNil(d.validationError())
    }
}


@MainActor final class OnboardingTests: XCTestCase {
    private func isolated(_ run: (UserDefaults) -> Void) {
        let name = "AurumOnboardingTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        run(defaults)
    }
    func testResumePreferencesAndCompletion() {
        isolated { defaults in
            let store = OnboardingStore(defaults: defaults)
            XCTAssertFalse(store.profile.completed)
            store.toggleInterest("Memorable dining"); store.toggleCuisine("Japanese"); store.chooseDestination("Paris"); store.move(to: 2)
            let resumed = OnboardingStore(defaults: defaults)
            XCTAssertEqual(resumed.profile.step, 2)
            XCTAssertEqual(resumed.profile.cuisines, ["Japanese"])
            XCTAssertEqual(resumed.profile.destination, "Paris")
            resumed.complete()
            XCTAssertTrue(OnboardingStore(defaults: defaults).profile.completed)
            XCTAssertNil(resumed.profile.previewPlan)
        }
    }
    func testPreviewPlanIsOptionalAndCanBeCleared() {
        isolated { defaults in
            let store = OnboardingStore(defaults: defaults)
            store.selectPreview(.monthly)
            XCTAssertFalse(store.profile.completed)
            XCTAssertEqual(OnboardingStore(defaults: defaults).profile.previewPlan, .monthly)
            store.selectPreview(.annual); store.complete(); store.selectPreview(nil)
            let restored = OnboardingStore(defaults: defaults)
            XCTAssertNil(restored.profile.previewPlan)
            XCTAssertTrue(restored.profile.completed)
        }
    }
    func testInvalidDraftAndSelectionRecovery() {
        isolated { defaults in
            defaults.set(Data("invalid json".utf8), forKey: OnboardingStore.key)
            let store = OnboardingStore(defaults: defaults)
            XCTAssertEqual(store.profile, TravelerProfile())
            store.move(to: 999); store.chooseDestination("Not in collection"); store.toggleCuisine("Unsupported")
            XCTAssertEqual(store.profile.step, 5)
            XCTAssertTrue(store.profile.destination.isEmpty)
            XCTAssertTrue(store.profile.cuisines.isEmpty)
            store.toggleInterest("Exceptional stays"); store.toggleInterest("Exceptional stays")
            XCTAssertTrue(store.profile.interests.isEmpty)
        }
    }
}


@MainActor final class LocationAutocompleteTests: XCTestCase {
    func testGoogleAutocompleteAndStaleNetworkResponse() async throws {
        var paidCalls = 0
        var appleCalls = 0
        let model = LocationAutocompleteModel(appleSearch: { _, _ in appleCalls += 1; return [] })
        model.update("Savoy", kind: .place)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(paidCalls, 0)
        XCTAssertEqual(appleCalls, 1)
        model.requestGoogle { _ in
            paidCalls += 1
            // Simulate a provider that finishes after cancellation.
            try? await Task.sleep(for: .milliseconds(300))
            return [GooglePlaceSuggestion(id: "old", title: "Old result", subtitle: "London")]
        }
        model.requestGoogle { _ in paidCalls += 1; return [] }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(paidCalls, 1, "Repeated taps must not issue another request")
        model.update("Paris", kind: .place)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(model.suggestions.isEmpty, "Old Google response cannot replace new Apple search")
        model.requestGoogle { _ in paidCalls += 1; return [GooglePlaceSuggestion(id: "new", title: "Paris venue", subtitle: "France")] }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.suggestions.first?.google?.id, "new")
        XCTAssertEqual(paidCalls, 2)
        model.stop()
        XCTAssertTrue(model.suggestions.isEmpty)
    }
    func testTypingDebouncesAndDuplicateUpdatesDoNotRestartSearch() async throws {
        var calls: [String] = []
        let model = LocationAutocompleteModel(appleSearch: { query, _ in
            calls.append(query)
            return [LocationSuggestion(title: "The Savoy", subtitle: "London")]
        })
        model.update("Sa", kind: .place, context: "London")
        model.update("Sav", kind: .place, context: "London")
        model.update("Savoy", kind: .place, context: "London")
        try await Task.sleep(for: .milliseconds(400))
        model.update("Savoy", kind: .place, context: "London")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(calls, ["Savoy London"])
        XCTAssertTrue(model.canRequestGoogle)
        XCTAssertNil(model.suggestions.first?.google)
        model.stop()
    }
    func testGoogleFailureKeepsAppleMatchesWithoutAutomaticRetry() async throws {
        var calls = 0
        let model = LocationAutocompleteModel(appleSearch: { _, _ in [LocationSuggestion(title: "Apple result", subtitle: "London")] })
        model.update("Savoy", kind: .place)
        try await Task.sleep(for: .milliseconds(400))
        model.requestGoogle { _ in calls += 1; throw JourneyError.message("Offline") }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.suggestions.first?.title, "Apple result")
        XCTAssertFalse(model.canRequestGoogle)
        model.requestGoogle { _ in calls += 1; return [] }
        XCTAssertEqual(calls, 1)
    }
    func testShortAndNonPlaceQueriesCannotRequestGoogle() async throws {
        var calls = 0
        let model = LocationAutocompleteModel(appleSearch: { _, _ in [] })
        for (query, kind) in [("Sa", LocationSearchKind.place), ("Paris", .city), ("CDG", .airport)] {
            model.update(query, kind: kind)
            try await Task.sleep(for: .milliseconds(400))
            model.requestGoogle { _ in calls += 1; return [] }
        }
        XCTAssertEqual(calls, 0)
    }
    func testConcurrentGoogleRequestsCoalesceWithoutRetainingResults() async throws {
        let gate = GoogleAutocompleteRequests()
        var calls = 0
        let request: (String) async throws -> [GooglePlaceSuggestion] = { query in
            calls += 1
            try await Task.sleep(for: .milliseconds(50))
            return [GooglePlaceSuggestion(id: query, title: query, subtitle: "Test")]
        }
        let first = Task { try await gate.fetch(" Savoy   London ", server: "test", request: request) }
        let second = Task { try await gate.fetch("savoy London", server: "test", request: request) }
        let a = try await first.value, b = try await second.value
        XCTAssertEqual(a.first?.id, b.first?.id)
        XCTAssertEqual(calls, 1)
        _ = try await gate.fetch("Savoy London", server: "test", request: request)
        XCTAssertEqual(calls, 2, "Completed prediction content is not cached")
        _ = try await gate.fetch("Sa", server: "test", request: request)
        XCTAssertEqual(calls, 2)
    }
    func testAutomatedTestsBlockGoogleAtTheAPIServiceBoundary() async {
        XCTAssertTrue(PlaceSearchTestPolicy.blocksPaidRequests)
        do {
            _ = try await TravelAPI().autocompletePlaces("Savoy London")
            XCTFail("Automated tests must never call the live Google endpoint")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("disabled during automated tests"))
        }
    }
    func testCountriesAndTimeZonesMatchPartialInput() {
        XCTAssertTrue(LocationAutocompleteModel.localSuggestions("Fran", kind: .country).contains { $0.localValue == "France" })
        XCTAssertTrue(LocationAutocompleteModel.localSuggestions("New York", kind: .timeZone).contains { $0.localValue == "America/New_York" })
        XCTAssertTrue(LocationAutocompleteModel.localSuggestions("", kind: .country).isEmpty)
    }
    func testCancelledQueryCannotRepopulateSuggestions() async throws {
        let model = LocationAutocompleteModel(fixtures: true)
        model.update("Par", kind: .destination); model.stop()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(model.suggestions.isEmpty); XCTAssertFalse(model.loading)
    }
    func testNewInputReplacesEarlierQuery() async throws {
        let model = LocationAutocompleteModel(fixtures: true)
        model.update("Par", kind: .destination); model.update("Missing", kind: .destination)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.query, "Missing"); XCTAssertTrue(model.suggestions.isEmpty)
        model.update("Par", kind: .destination)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.suggestions.count, 1)
        model.update("", kind: .destination)
        XCTAssertTrue(model.suggestions.isEmpty)
    }
    func testSelectionIncludesResolvedCoordinatesAndCountry() async throws {
        let model = LocationAutocompleteModel(fixtures: true)
        model.update("Par", kind: .destination)
        try await Task.sleep(for: .milliseconds(400))
        let suggestion = try XCTUnwrap(model.suggestions.first)
        var selected: LocationSelection?
        model.select(suggestion, kind: .destination, category: .other) { selected = $0 }
        XCTAssertEqual(selected?.text, "Paris, France")
        XCTAssertEqual(selected?.country, "France")
        XCTAssertEqual(selected?.timeZone, "Europe/Paris")
        XCTAssertTrue(selected?.place.hasCoordinate == true)
    }
}

@MainActor final class CityExplorerTests: XCTestCase {
    func testMapHandoffKeepsResultsAndInvalidatesOlderSearch() async {
        let model = CityExploreModel { [self] _, _, _, _ in
            try? await Task.sleep(for: .milliseconds(50))
            return [sample("old")]
        }
        let pending = Task { await model.load(city: lisbon, interest: .museums, term: "", wider: false) }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(10))
        let selected = sample("selected")
        model.present([selected], interest: .museums)
        await pending.value
        XCTAssertEqual(model.places.map(\.id), [selected.id])
        XCTAssertFalse(model.loading)
        XCTAssertTrue(lisbon.contains(selected))
        var elsewhere = selected
        elsewhere.city = ExploreCity(name: "Lisbon", country: "United States", latitude: 45, longitude: -100)
        XCTAssertFalse(lisbon.contains(elsewhere))
    }

    func testDiningPreferencesRefineRestaurantSearchWithoutLeakingToOtherInterests() {
        var preferences = DiningSearchPreferences()
        XCTAssertEqual(preferences.searchTerm("rooftop", interest: .restaurants), "rooftop")
        preferences.cuisine = "Italian"
        preferences.price = .budget
        XCTAssertEqual(preferences.searchTerm(" rooftop ", interest: .restaurants), "inexpensive Italian restaurants rooftop")
        XCTAssertEqual(preferences.searchTerm("gardens", interest: .parks), "gardens")
        XCTAssertEqual(preferences.searchTerm(interest: .restaurants), "inexpensive Italian restaurants")
        XCTAssertTrue(preferences.active)
        preferences = DiningSearchPreferences()
        XCTAssertFalse(preferences.active)
        XCTAssertEqual(preferences.searchTerm(interest: .restaurants), "")
    }

    let lisbon = ExploreCity(name: "Lisbon", country: "Portugal", latitude: 38.7223, longitude: -9.1393)
    func sample(_ id: String, category: PlaceCategory = .museum) -> ExplorePlace {
        ExplorePlace(record: PlaceRecord(id: id, name: "Place " + id, category: category, city: "Lisbon", address: "Lisbon, Portugal", website: "https://example.com", latitude: 38.72, longitude: -9.14, source: "Test"), city: lisbon)
    }
    func testCityCatalogMatchesGeographyNotJustNames() {
        XCTAssertNil(lisbon.collectionName)
        XCTAssertEqual(ExploreCity.collection[0].collectionName, "Paris")
        XCTAssertNil(ExploreCity(name: "Paris", country: "United States", latitude: 33.6609, longitude: -95.5555).collectionName)
        XCTAssertEqual(ExploreCity(name: "New York City", country: "United States", latitude: 40.7128, longitude: -74.006).collectionName, "New York")
        XCTAssertEqual(ExploreInterest.allCases.count, 13)
    }
    func testCatalogPreservesRestaurantsAndHotelContext() throws {
        let store = TravelStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let paris = ExploreCity.collection[0]
        let venues = ExplorePlace.collection(store.hotels, city: paris)
        XCTAssertEqual(venues.count, store.hotels.filter { $0.city == "Paris" }.reduce(0) { $0 + $1.venues.count })
        XCTAssertEqual(Set(venues.map(\.id)).count, venues.count)
        XCTAssertTrue(venues.allSatisfy { $0.isCollection && !$0.hotelName.isEmpty && $0.record.city == "Paris" && !$0.record.hasCoordinate })
        XCTAssertTrue(ExplorePlace.collection(store.hotels, city: lisbon).isEmpty)
    }
    func testSavedDiscoveriesCitiesAndLegacyBookmarksStayInSync() throws {
        let name = "city-save-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!; defer { defaults.removePersistentDomain(forName: name) }
        let store = TravelStore(defaults: defaults)
        var museum = sample("museum")
        store.toggleDiscovery(museum); store.toggleExploreCity(lisbon); store.rememberExploreCity(lisbon); store.rememberExploreCity(lisbon)
        museum.record.latitude = 38.724; store.refreshSavedDiscovery(museum)
        let restaurant = try XCTUnwrap(ExplorePlace.collection(store.hotels, city: ExploreCity.collection[0]).first)
        store.toggleDiscovery(restaurant)
        XCTAssertTrue(store.savedRestaurants.contains(restaurant.record.id))
        let loaded = TravelStore(defaults: defaults)
        XCTAssertEqual(loaded.savedDiscoveries.count, 2); XCTAssertEqual(loaded.recentExploreCities.count, 1)
        XCTAssertTrue(loaded.isExploreCitySaved(lisbon)); XCTAssertEqual(loaded.savedDiscoveries.first { $0.id == museum.id }?.record.latitude, 38.724)
        let oldBookmark = try XCTUnwrap(loaded.savedDiningPlaces.first { $0.id == restaurant.record.id })
        loaded.toggleRestaurantSave(oldBookmark)
        XCTAssertFalse(loaded.isDiscoverySaved(restaurant)); XCTAssertFalse(loaded.savedDiscoveries.contains { $0.id == restaurant.id })
        loaded.toggleRestaurantSave(oldBookmark); XCTAssertTrue(loaded.isDiscoverySaved(restaurant))
        XCTAssertEqual(loaded.savedDiscoveries.filter { $0.id == restaurant.id }.count, 1)
    }
    func testPartialSearchFailuresAndCache() async {
        var calls = 0
        let model = CityExploreModel { [self] _, interest, _, _ in
            calls += 1
            if interest == .museums { throw JourneyError.message("Offline") }
            return [sample(interest.id, category: interest.category)]
        }
        await model.load(city: lisbon, interest: .highlights, term: "", wider: false)
        XCTAssertEqual(model.sections.count, 4); XCTAssertEqual(model.places.count, 3)
        XCTAssertNotNil(model.sections.first { $0.interest == .museums }?.error)
        XCTAssertFalse(model.loading)
        await model.load(city: lisbon, interest: .restaurants, term: "", wider: false)
        let before = calls
        await model.load(city: lisbon, interest: .restaurants, term: "", wider: false)
        XCTAssertEqual(calls, before)
    }
    func testLateCitySearchCannotOverwriteNewResults() async throws {
        let model = CityExploreModel { [self] _, interest, term, _ in
            if term == "old" { try? await Task.sleep(for: .seconds(1)) }
            return [sample(term, category: interest.category)]
        }
        let old = Task { await model.load(city: lisbon, interest: .museums, term: "old", wider: false) }
        try await Task.sleep(for: .milliseconds(420))
        await model.load(city: lisbon, interest: .museums, term: "new", wider: false)
        await old.value
        XCTAssertEqual(model.places.map(\.record.name), ["Place new"])
        XCTAssertFalse(model.loading)
    }
    func testFiltersAndAllPlaceCategoriesPreserveMapDataInTrip() async throws {
        let a = sample("a"), b = sample("b", category: .park)
        let model = CityExploreModel { _, _, _, _ in [b, a] }
        await model.load(city: lisbon, interest: .parks, term: "", wider: false)
        XCTAssertEqual(model.visible(sort: .name, savedOnly: false, websiteOnly: true, savedIDs: []).map(\.record.id), ["a", "b"])
        XCTAssertEqual(model.visible(sort: .suggested, savedOnly: true, websiteOnly: false, savedIDs: [a.id]).map(\.id), [a.id])
        let stop = JourneyStop(name: "Lisbon", arrival: "2026-10-01", nights: 3)
        var trip = JourneyDocument(title: "Existing trip", stops: [stop])
        for category in PlaceCategory.allCases {
            let place = sample(category.rawValue, category: category)
            trip.putEvent(JourneyEvent(stopID: stop.id, place: place.record, kind: .place), on: [1])
        }
        XCTAssertNil(trip.validationError()); XCTAssertEqual(trip.mapPlaces.filter(\.hasCoordinate).count, PlaceCategory.allCases.count)
    }
}

@MainActor final class FlightMapTests: XCTestCase {
    func testPositionPollingOnlyForDepartedUnfinishedFlights() {
        var flight = FlightMapFixtures.snapshot
        XCTAssertFalse(flight.canTrackPosition)
        flight.actualOut = flight.scheduledOut; XCTAssertTrue(flight.canTrackPosition)
        flight.actualOn = flight.scheduledIn; XCTAssertFalse(flight.canTrackPosition)
        flight.actualOn = nil; flight.cancelled = true; XCTAssertFalse(flight.canTrackPosition)
    }
    func testPositionFreshnessRequiresRecentProviderTimestamp() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var position = FlightPosition(latitude: 40, longitude: -30)
        XCTAssertFalse(position.isRecent(at: now))
        position.timestamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-120)); XCTAssertTrue(position.isRecent(at: now))
        position.timestamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600)); XCTAssertFalse(position.isRecent(at: now))
    }
    func testPositionRequestsAreThrottledAndOldSelectionCannotOverwriteNewOne() async {
        let tracker = FlightTracker(); tracker.choose("first")
        let now = Date.now; var calls = 0
        await tracker.locate(now: now) { _ in calls += 1; return FlightPosition(latitude: 40, longitude: -30) }
        await tracker.locate(now: now.addingTimeInterval(10)) { _ in calls += 1; return FlightPosition(latitude: 41, longitude: -30) }
        XCTAssertEqual(calls, 1); XCTAssertEqual(tracker.position?.latitude, 40)
        await tracker.locate(now: now.addingTimeInterval(90)) { _ in tracker.choose("second"); return FlightPosition(latitude: 42, longitude: -30) }
        XCTAssertNil(tracker.position); XCTAssertEqual(tracker.selectedID, "second"); XCTAssertFalse(tracker.positionLoading)
    }
    func testRoutesUseValidCoordinatesAndCrossDateLine() {
        var reservation = FlightReservation(departureLatitude: 35.5, departureLongitude: 139.7, arrivalLatitude: 37.6, arrivalLongitude: -122.4)
        var flight = MapFlight(tripID: UUID(), tripTitle: "Across the Pacific", flight: reservation)
        XCTAssertNotNil(flight.route); XCTAssertGreaterThan(flight.distance ?? 0, 7000); XCTAssertLessThan(flight.distance ?? 0, 10_000)
        reservation.departureLatitude = .nan; flight.flight = reservation
        XCTAssertNil(flight.route); XCTAssertNil(flight.distance)
        XCTAssertNil(MapFlight.coordinate(91, 20)); XCTAssertNil(MapFlight.coordinate(20, nil))
    }
    func testMapPanelSurfaceExpandsContinuouslyWithoutChangingItsContentHeight() {
        for flightDetail in [false, true] {
            let layout = MapPanelLayout(availableHeight: 760, flightDetail: flightDetail)
            XCTAssertEqual(layout.surfaceInset(for: layout.compact), 12)
            XCTAssertEqual(layout.surfaceInset(for: layout.maximum), 0)
            XCTAssertEqual(layout.surfaceInset(for: (layout.maximum + layout.compact) / 2), 6, accuracy: 0.001)
            XCTAssertEqual(layout.surfaceInset(for: layout.maximum + 100), 0)
            XCTAssertEqual(layout.surfaceInset(for: layout.compact - 100), 12)
            XCTAssertGreaterThan(layout.medium, layout.compact)
            XCTAssertLessThan(layout.medium, layout.maximum)
        }
    }
    func testMapPanelDragRebasesInterruptedSettlingAndOvershoot() {
        var drag = MapPanelDrag()
        // The old target can be 752 while its visible spring is still at 510.
        drag.update(distance: 12, presentedHeight: 510, bounds: 260...752)
        XCTAssertEqual(drag.height, 498)
        drag.update(distance: 32, presentedHeight: 498, bounds: 260...752)
        XCTAssertEqual(drag.height, 478)
        drag.update(distance: -500, presentedHeight: 478, bounds: 260...752)
        XCTAssertEqual(drag.height, 752)
        drag.update(distance: -490, presentedHeight: 752, bounds: 260...752)
        XCTAssertEqual(drag.height, 742, "Reversal must respond without crossing the overshoot again")
        drag.update(distance: 600, presentedHeight: 742, bounds: 260...752)
        XCTAssertEqual(drag.height, 260)
        drag.update(distance: 590, presentedHeight: 260, bounds: 260...752)
        XCTAssertEqual(drag.height, 270)
        drag.finish()
        XCTAssertNil(drag.height); XCTAssertNil(drag.origin)
        drag.update(distance: -20, presentedHeight: 340, bounds: 260...752)
        XCTAssertEqual(drag.height, 360)
    }
    func testDetailedFlightTimetableUsesRealStagesAndSafeTaxiDurations() throws {
        var flight = FlightMapFixtures.snapshot
        flight.scheduledOff = "2026-09-06T22:10:00Z"; flight.estimatedOff = "2026-09-06T22:57:00Z"
        flight.scheduledOn = "2026-09-07T04:50:00Z"; flight.estimatedOn = "2026-09-07T05:25:00Z"
        flight.actualOut = "2026-09-06T22:31:00Z"; flight.actualOff = "2026-09-06T22:51:00Z"
        let rows = FlightTimetableRow.rows(flight)
        XCTAssertEqual(rows.map(\.id), ["gate-out", "taxi-out", "takeoff", "landing", "taxi-in", "gate-in"])
        XCTAssertEqual(rows[1].scheduled, .duration(600)); XCTAssertEqual(rows[1].estimated, .duration(1620)); XCTAssertEqual(rows[1].actual, .duration(1200))
        XCTAssertEqual(rows[4].scheduled, .duration(600)); XCTAssertEqual(rows[4].estimated, .duration(600)); XCTAssertNil(rows[4].actual)
        XCTAssertEqual(rows[2].estimated?.text(zone: flight.originZone), "18:57")
        XCTAssertEqual(rows[3].estimated?.text(zone: flight.destinationZone), "06:25")
        let roundTrip = try JSONDecoder().decode(FlightSnapshot.self, from: JSONEncoder().encode(flight))
        XCTAssertEqual(roundTrip.estimatedOff, flight.estimatedOff); XCTAssertEqual(roundTrip.estimatedOn, flight.estimatedOn)
        flight.actualOff = "2026-09-06T22:00:00Z"
        XCTAssertNil(FlightTimetableRow.rows(flight)[1].actual)
        flight.estimatedOff = nil
        XCTAssertNil(FlightTimetableRow.rows(flight)[1].estimated)
    }
    func testFlightDetailPunctualitySeparatesDepartureAndArrival() {
        var flight = FlightMapFixtures.snapshot
        XCTAssertEqual(flight.timing(departure: true), .late(30))
        XCTAssertEqual(flight.timing(departure: false), .late(35))
        flight.estimatedIn = "2026-09-07T04:50:00Z"
        XCTAssertEqual(flight.timing(departure: false), .early(10))
        XCTAssertEqual(flight.summaryTiming, .late(30))
        flight.actualOut = flight.estimatedOut
        XCTAssertEqual(flight.summaryTiming, .early(10))
        flight.actualIn = flight.scheduledIn
        XCTAssertEqual(flight.timing(departure: false), .onTime)
        flight.cancelled = true
        XCTAssertEqual(flight.timing(departure: false), .cancelled)
        flight.cancelled = false; flight.diverted = true
        XCTAssertEqual(flight.summaryTiming, .diverted)
        flight.diverted = false; flight.actualIn = nil; flight.estimatedIn = nil; flight.arrivalDelay = nil
        XCTAssertEqual(flight.timing(departure: false), .unknown)
        flight.arrivalDelay = -300
        XCTAssertEqual(flight.timing(departure: false), .early(5))
        flight.arrivalDelay = 0
        XCTAssertEqual(flight.timing(departure: false), .onTime)
    }
    func testFlightTimesUseAirportZonesAndUnknownDelayStaysUnknown() throws {
        let date = "2026-09-07T01:00:00Z"
        XCTAssertTrue(FlightSnapshot.time(date, zone: "America/New_York").contains("21:00"))
        XCTAssertTrue(FlightSnapshot.time(date, zone: "Europe/London").contains("02:00"))
        XCTAssertNotNil(FlightSnapshot.date("2026-09-07T01:00:00.123Z")); XCTAssertEqual(FlightSnapshot.time(nil, zone: "UTC"), "—")
        var snapshot = FlightMapFixtures.snapshot
        snapshot.arrivalDelay = nil; XCTAssertNil(snapshot.delayMinutes)
        snapshot.arrivalDelay = -300; XCTAssertEqual(snapshot.delayMinutes, -5)
        let decoded = try JSONDecoder().decode(FlightSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
    }
    func testSelectingAnotherDepartureClearsAircraftAndHistory() {
        let tracker = FlightTracker(); tracker.feed = FlightMapFixtures.feed; tracker.selectedID = FlightMapFixtures.snapshot.id; tracker.history = FlightMapFixtures.history
        tracker.position = FlightPosition(latitude: 40, longitude: -30)
        tracker.choose("another-leg")
        XCTAssertNil(tracker.position); XCTAssertNil(tracker.history); XCTAssertNil(tracker.selected)
    }
}

@MainActor final class AppleActivityIdeasTests: XCTestCase {
    func testShortlistDeduplicatesBoundsAndRetainsAppleCoordinates() async throws {
        let places = (0..<12).map { PlaceRecord(id: "apple-\($0)", name: "Museum \($0)", category: .museum, latitude: 48.85, longitude: 2.35, source: "Apple Maps") }
        var searches = 0
        let payload = try await AppleActivityIdeas.prepare(city: " Paris ", interests: " Art ") { city, interests in
            searches += 1; XCTAssertEqual(city, "Paris"); XCTAssertEqual(interests, "Art")
            return [places[0], places[0], PlaceRecord(name: "Unmapped")] + places
        }
        XCTAssertEqual(searches, 1); XCTAssertEqual(payload.candidates.count, 8)
        XCTAssertEqual(Set(payload.candidates.map(\.id)).count, 8)
        XCTAssertTrue(payload.candidates.allSatisfy { $0.hasCoordinate && $0.source == "Apple Maps" })
    }
    func testInvalidInputDoesNotSearchAndEmptySearchStaysEmpty() async throws {
        do {
            _ = try await AppleActivityIdeas.prepare(city: "x", interests: "") { _, _ in XCTFail("Invalid input searched"); return [] }
            XCTFail("Invalid city accepted")
        } catch {}
        let payload = try await AppleActivityIdeas.prepare(city: "Paris", interests: "") { _, _ in [] }
        XCTAssertTrue(payload.candidates.isEmpty)
    }
    func testPaidPlacesAndAIBlockedInAutomatedTests() async {
        let api = TravelAPI()
        do { _ = try await api.searchPlaces("Museum Paris", category: .museum); XCTFail("Tripadvisor should be blocked") } catch { XCTAssertTrue(error.localizedDescription.contains("automated tests")) }
        do { _ = try await api.placeDetails("123"); XCTFail("Tripadvisor details should be blocked") } catch { XCTAssertTrue(error.localizedDescription.contains("automated tests")) }
        do { _ = try await api.recommendations(city: "Paris", interests: "Art"); XCTFail("AI should be blocked") } catch { XCTAssertTrue(error.localizedDescription.contains("automated tests")) }
        do { _ = try await api.hotelOverview(PlaceRecord(name: "Hotel")); XCTFail("Hotel AI should be blocked") } catch { XCTAssertTrue(error.localizedDescription.contains("automated tests")) }
    }
}

@MainActor final class AppleTravelFeatureTests: XCTestCase {
    func testActivityUsesAirportTimeZonesAndActualState() {
        var flight = FlightMapFixtures.snapshot
        flight.scheduledOut = "2026-10-01T22:00:00Z"; flight.originZone = "America/New_York"
        flight.actualOut = nil; flight.estimatedOut = nil; flight.actualIn = nil; flight.cancelled = false
        let state = FlightNotifications.state(flight, now: Date(timeIntervalSince1970: 123))
        XCTAssertEqual(state.departureTime, "18:00"); XCTAssertEqual(state.phase, "scheduled"); XCTAssertEqual(state.updatedAt, 123)
        flight.actualOut = flight.scheduledOut
        XCTAssertEqual(FlightNotifications.state(flight).phase, "departed")
        flight.cancelled = true
        XCTAssertEqual(FlightNotifications.state(flight).phase, "cancelled")
    }
    func testWeatherTemperaturesAreRoundedAndUseLocalUnits() {
        let value = Measurement(value: 76.160895, unit: UnitTemperature.fahrenheit)
        let us = WeatherDisplay.temperature(value, locale: Locale(identifier: "en_US"))
        let uk = WeatherDisplay.temperature(value, locale: Locale(identifier: "en_GB"))
        XCTAssertTrue(us.contains("76")); XCTAssertTrue(us.contains("F")); XCTAssertFalse(us.contains("160895"))
        XCTAssertTrue(uk.contains("25")); XCTAssertTrue(uk.contains("C")); XCTAssertFalse(uk.contains("."))
    }
    func testWeatherPreferenceDefaultsOnAndPersistsOff() {
        let name = "seur.weather.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(WeatherPreferences.isEnabled(in: defaults))
        defaults.set(false, forKey: WeatherPreferences.key)
        XCTAssertFalse(WeatherPreferences.isEnabled(in: UserDefaults(suiteName: name)!))
        defaults.set(true, forKey: WeatherPreferences.key)
        XCTAssertTrue(WeatherPreferences.isEnabled(in: defaults))
    }
    func testWeatherAvoidsRequestsForFlexibleAndDistantDates() {
        let now = TravelDay.date("2026-09-07")!
        XCTAssertFalse(DestinationWeatherService.canForecast(day: nil, now: now))
        XCTAssertFalse(DestinationWeatherService.canForecast(day: "2026-12-01", now: now))
        XCTAssertFalse(DestinationWeatherService.canForecast(day: "2025-09-07", now: now))
        XCTAssertTrue(DestinationWeatherService.canForecast(day: "2026-09-08", now: now))
    }
}

@MainActor final class ConciergeLiveTests: XCTestCase {
    private var reply: ConciergeReply { .init(text: "A detailed and thoughtful plan.", suggestions: ["Refine it"], searches: [], itinerary: ConciergeFixtures.plan) }
    func testTripContextOmitsBookingReferencesJournalNotesAndPrivateFields() {
        var trip = JourneyDocument(title: "Paris", destination: "Paris")
        trip.hotels = [HotelReservation(place: PlaceRecord(name: "Hotel"), confirmation: "PRIVATE-CODE", notes: "PRIVATE-NOTES")]
        trip.places = [RatedPlace(place: PlaceRecord(name: "Journal"), notes: "PRIVATE-JOURNAL")]
        trip.flights = [FlightReservation(flightNumber: "BA178", notes: "PRIVATE-FLIGHT")]
        let context = ConciergeContext.tripSummary(trip)
        XCTAssertTrue(context.contains("Hotel")); XCTAssertTrue(context.contains("BA178")); XCTAssertFalse(context.contains("PRIVATE"))
    }
    func testDraftCreatesValidTripAndDuplicateSaveDoesNotDuplicateActivities() throws {
        let draft = ConciergeFixtures.plan
        let trip = try draft.applying(to: nil, places: [], startDate: "2026-10-01")
        XCTAssertNil(trip.validationError()); XCTAssertEqual(trip.events.count, 2)
        XCTAssertEqual(trip.startDate, "2026-10-01"); XCTAssertEqual(trip.endDate, "2026-10-02")
        XCTAssertThrowsError(try draft.applying(to: trip, places: [], startDate: nil))
        XCTAssertEqual(trip.events.count, 2)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let library = JourneyLibrary(url: url); XCTAssertTrue(library.save(trip)); XCTAssertEqual(JourneyLibrary(url: url).documents.first?.events.count, 2)
    }
    func testDraftRouteMismatchNeverOverwritesExistingPlans() throws {
        let original = JourneyDocument(title: "Tokyo", stops: [JourneyStop(name: "Tokyo", nights: 3)])
        XCTAssertThrowsError(try ConciergeFixtures.plan.applying(to: original, places: [], startDate: nil))
        XCTAssertTrue(original.events.isEmpty); XCTAssertEqual(original.stops.first?.name, "Tokyo")
    }
    func testMultiCityDraftPreservesDatesAndMappedPlaces() throws {
        var draft = ConciergeFixtures.plan; draft.days[1].city = "London"; draft.days[0].items[0].placeID = "mapped"
        let place = PlaceRecord(id: "mapped", name: "Museum", category: .museum, latitude: 48.8, longitude: 2.3, source: "Apple Maps")
        let trip = try draft.applying(to: nil, places: [place], startDate: "2026-10-01")
        XCTAssertNil(trip.validationError()); XCTAssertEqual(trip.stops.count, 2)
        XCTAssertEqual(trip.date(for: trip.events[1]), "2026-10-02")
        XCTAssertEqual(trip.events[0].place.id, "mapped"); XCTAssertTrue(trip.events[0].place.hasCoordinate)
    }
    func testSearchPhaseIsBoundedAndFollowupReceivesHistory() async throws {
        let chat = ConciergeConversation(); var calls = 0, searches = 0
        let response = reply
        let respond: ConciergeConversation.Respond = { request in
            calls += 1
            if calls == 1 { return .init(text: "Searching", suggestions: [], searches: Array(repeating: .init(city: "Paris", query: "museums"), count: 5), itinerary: nil) }
            if calls == 2 { XCTAssertFalse(request.allowSearch); XCTAssertEqual(request.places.count, 1) }
            if calls == 3 {
                XCTAssertEqual(request.messages.count, 3); XCTAssertEqual(request.messages.last?.text, "Slower please")
                XCTAssertTrue(request.messages[1].text.contains("Previously proposed draft"))
                XCTAssertTrue(request.messages[1].text.contains(response.itinerary!.days[0].items[0].title))
            }
            return response
        }
        let search: ConciergeConversation.Search = { _ in searches += 1; return [.init(id: "map", name: "Museum", latitude: 48.8, longitude: 2.3, source: "Apple Maps")] }
        chat.send("Plan Paris", context: .init(), respond: respond, search: search)
        for _ in 0..<100 where chat.isReplying { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(calls, 2); XCTAssertEqual(searches, 2); XCTAssertEqual(chat.messages.count, 2)
        chat.send("Slower please", context: .init(), respond: respond, search: search)
        for _ in 0..<100 where chat.isReplying { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(calls, 3); XCTAssertEqual(chat.messages.count, 4)
    }
    func testFailureRetryAndResetNeverInsertFakeOrLateReplies() async throws {
        let chat = ConciergeConversation(); let response = reply
        chat.send("Paris", context: .init(), respond: { _ in throw JourneyError.message("Offline") }, search: { _ in [] })
        for _ in 0..<100 where chat.isReplying { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(chat.messages.count, 1); XCTAssertEqual(chat.error, "Offline")
        chat.retry(context: .init(), respond: { _ in response }, search: { _ in [] })
        for _ in 0..<100 where chat.isReplying { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(chat.messages.count, 2)
        chat.send("London", context: .init(), respond: { _ in try? await Task.sleep(for: .milliseconds(80)); return response }, search: { _ in [] })
        chat.reset(); try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(chat.messages.isEmpty); XCTAssertFalse(chat.isReplying)
    }
}

@MainActor final class FriendsFeatureTests: XCTestCase {
    func testTripPeriodsAndFlexibleDates() {
        var trip = FriendsFixtures.trip
        trip.stops[0].arrival = "2026-09-10"
        XCTAssertEqual(FriendsTravel.phase(trip, today: "2026-09-07"), .upcoming)
        XCTAssertEqual(FriendsTravel.phase(trip, today: "2026-09-11"), .traveling)
        XCTAssertEqual(FriendsTravel.phase(trip, today: "2026-09-14"), .past)
        trip.dateMode = .nights
        XCTAssertNil(FriendsTravel.phase(trip)); XCTAssertEqual(FriendsTravel.dates(trip), "Dates flexible")
    }
    func testSharedTripSearchAndSavedFilter() {
        let remote = FriendsFixtures.remote
        XCTAssertTrue(FriendsTravel.matches(remote, query: "maya", filter: .all, saved: []))
        XCTAssertFalse(FriendsTravel.matches(remote, query: "Tokyo", filter: .all, saved: []))
        XCTAssertFalse(FriendsTravel.matches(remote, query: "", filter: .saved, saved: []))
        XCTAssertTrue(FriendsTravel.matches(remote, query: "Paris", filter: .saved, saved: [remote.id]))
    }
    func testOverlapRequiresSameDestinationCountryAndMatchingDates() {
        var other = FriendsFixtures.trip; other.stops[0].arrival = "2026-09-10"
        var own = other; own.id = UUID(); own.stops[0].arrival = "2026-09-12"
        XCTAssertNotNil(FriendsTravel.overlap(other, with: [own], today: "2026-09-07"))
        own.stops[0].country = "United States"; XCTAssertNil(FriendsTravel.overlap(other, with: [own], today: "2026-09-07"))
        own.stops[0].country = "France"; own.stops[0].arrival = "2026-09-20"; XCTAssertNil(FriendsTravel.overlap(other, with: [own], today: "2026-09-07"))
        own.dateMode = .nights; XCTAssertNil(FriendsTravel.overlap(other, with: [own]))
    }
    func testDirectConversationDoesNotReuseLargerGroup() {
        let owner = FriendsFixtures.owner, friend = FriendsFixtures.maya
        var group = FriendsFixtures.chat; group.members.append(.init(id: "third", handle: "third", name: "Third"))
        XCTAssertNil(FriendsTravel.directConversation(friend: friend.id, owner: owner.id, chats: [group]))
        XCTAssertNotNil(FriendsTravel.directConversation(friend: friend.id, owner: owner.id, chats: [group, FriendsFixtures.chat]))
    }
    func testAccountResetClearsPersonalSocialData() {
        let model = FriendsHomeModel(); model.friends = FriendsFixtures.friends; model.trips = [FriendsFixtures.remote]; model.chats = [FriendsFixtures.chat]; model.saved = [FriendsFixtures.remote.id]
        model.reset(); XCTAssertTrue(model.friends.isEmpty); XCTAssertTrue(model.trips.isEmpty); XCTAssertTrue(model.chats.isEmpty); XCTAssertTrue(model.saved.isEmpty)
    }
}
