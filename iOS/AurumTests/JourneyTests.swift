import XCTest
import WidgetKit
import UserNotifications
import SwiftUI
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
    func testGuideFromTripExcludesPrivateBookingsAndNotes() throws {
        var trip = itinerary()
        trip.events[0].description = "Private dinner note"; trip.events[0].attendees = "Family"; trip.events[0].place.overview = "Provider description"
        trip.events[0].place.phone = "PRIVATE"; trip.events[0].place.rating = 4.5
        trip.description = "Private trip notes"
        let guide = TravelGuide.fromTrip(trip)
        XCTAssertNotEqual(guide.id, trip.id); XCTAssertEqual(guide.places.count, 1)
        XCTAssertTrue(guide.introduction.isEmpty); XCTAssertTrue(guide.places[0].note.isEmpty)
        let text = String(decoding: try JSONEncoder().encode(guide), as: UTF8.self)
        for secret in ["Private dinner note", "Family", "Provider description", "PRIVATE", "Private trip notes", "85.5"] { XCTAssertFalse(text.contains(secret)) }
    }
    func testGuideDraftPublicationAndEditsSurviveRelaunch() throws {
        let url = directory.appendingPathComponent("guides.json"), library = GuideLibrary(url: url)
        var guide = TravelGuide.fromTrip(itinerary()); guide.introduction = "A relaxed Paris weekend."
        XCTAssertNil(guide.publicationIssue); XCTAssertTrue(library.save(guide))
        let author = TravelAccount(id: UUID().uuidString, handle: "alice", name: "Alice")
        var remote = PublishedGuide(guide: guide, author: author, revision: 1, isPublished: true, isSummary: false, updatedAt: 1, placeCount: 1)
        XCTAssertTrue(library.accept(remote, server: "test")); XCTAssertFalse(library.drafts[0].hasChanges)
        guide.introduction = "A revised introduction, still private."
        XCTAssertTrue(library.save(guide)); XCTAssertTrue(library.drafts[0].hasChanges)
        let restored = GuideLibrary(url: url); XCTAssertEqual(restored.drafts[0].guide.introduction, guide.introduction); XCTAssertEqual(restored.drafts[0].revision, 1); XCTAssertEqual(restored.drafts[0].ownerID, author.id)
        remote.isPublished = false; remote.revision = 2
        XCTAssertTrue(restored.accept(remote, server: "test", replaceDraft: false)); XCTAssertEqual(restored.drafts[0].guide, guide); XCTAssertFalse(restored.drafts[0].isPublished)
        XCTAssertEqual(restored.drafts[0].revision, 2)
    }
    func testGuideBookmarksRequireFullContentAndBlockingPersists() throws {
        let url = directory.appendingPathComponent("guides.json"), library = GuideLibrary(url: url)
        let author = TravelAccount(id: UUID().uuidString, handle: "alice", name: "Alice")
        var remote = PublishedGuide(guide: TravelGuide.fromTrip(itinerary()), author: author, revision: 1, isPublished: true, isSummary: true, updatedAt: 1, placeCount: 1)
        XCTAssertFalse(library.bookmark(remote)); remote.isSummary = false; XCTAssertTrue(library.bookmark(remote))
        XCTAssertEqual(GuideLibrary(url: url).saved[0].guide.places.count, 1)
        XCTAssertTrue(library.block(author.id, blocked: true)); let restored = GuideLibrary(url: url)
        XCTAssertTrue(restored.saved.isEmpty); XCTAssertFalse(restored.visible(remote))
        XCTAssertTrue(restored.block(author.id, blocked: false)); XCTAssertTrue(restored.visible(remote))
        XCTAssertTrue(restored.hide(remote.id)); XCTAssertFalse(restored.visible(remote))
    }
    func testGuideCorruptArchiveCannotBeOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("guides.json"), bytes = Data("corrupt".utf8); try bytes.write(to: url)
        let library = GuideLibrary(url: url)
        XCTAssertFalse(library.save(TravelGuide(title: "Do not erase existing guides")))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testSuppliedDestinationCatalogIs16x9AndSkipsPhotoLookups() async throws {
        XCTAssertEqual(BundledDestinationCover.destinations.count, 300)
        let store = TripCoverStore(directory: directory)
        var calls = 0
        for city in BundledDestinationCover.destinations {
            let available = try autoreleasepool {
                let cover = try XCTUnwrap(BundledDestinationCover.cover(city: city), city)
                XCTAssertEqual(cover.image.size.width / cover.image.size.height, 16.0 / 9.0, accuracy: 0.001, city)
                XCTAssertEqual(cover.photo.provider, "bundled", city)
                XCTAssertNotNil(cover.photo.sourceURL); XCTAssertFalse(cover.photo.license.isEmpty)
                XCTAssertEqual(cover.photo.imageURL.scheme, "https", city)
                return true
            }
            _ = await store.cover(for: UUID(), allowLookup: !available) { calls += 1; return nil }
        }
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
    func testSuppliedDestinationNamesRespectCountriesAndUseRefreshedTokyo() throws {
        for city in ["Paris, France", "London, England", "New York, NY, United States", "NYC, USA", "Rome, IT",
                     "Washington, D.C., United States", "Xi’an, CN", "Cairo, Egypt", "Giza, EG", "Honolulu, US",
                     "Macao, MO", "Marrakech, Morocco", "Québec City, Canada", "Tokyo, Japan", "東京, 日本", "Tokyo Prefecture, JP"] {
            XCTAssertNotNil(BundledDestinationCover.cover(city: city), city)
        }
        for city in ["Paris, TX, US", "London, ON, Canada", "Athens, GA, US", "Rome, Georgia, US", "Burlington, Vermont, US", ""] {
            XCTAssertNil(BundledDestinationCover.cover(city: city), city)
        }
        let tokyo = try XCTUnwrap(BundledDestinationCover.cover(city: "Tokyo, Japan"))
        XCTAssertEqual(tokyo.photo.provider, "bundled")
        XCTAssertTrue(tokyo.photo.title.contains("Tokyo Tower"))
        XCTAssertEqual(tokyo.photo.sourceURL?.absoluteString, "https://bingwallpaper.anerg.com/detail/us/TokyoMetropolis")
        XCTAssertEqual(tokyo.photo.sourceName, "Bing")
        XCTAssertEqual(tokyo.photo.authors.first?.name, "Yukinori Hasumi/Getty Images")
        let paris = try XCTUnwrap(BundledDestinationCover.cover(city: "Paris"))
        XCTAssertEqual(paris.photo.sourceName, "Windows Spotlight")
        XCTAssertNil(paris.photo.licenseURL)
    }
    func testPexelsOnlyPhotoHostsAndTestGuard() async throws {
        XCTAssertTrue(CityPhotoImage.allowed(URL(string: "https://images.pexels.com/photos/123/a.jpeg")!))
        for url in ["https://upload.wikimedia.org/a", "https://lh3.googleusercontent.com/a", "http://images.pexels.com/a",
                    "https://images.pexels.com.evil.test/a", "https://key@images.pexels.com/a", "https://images.pexels.com:8443/a"] {
            XCTAssertFalse(CityPhotoImage.allowed(URL(string: url)!))
        }
        let response = try await TravelAPI().pexelsCityPhoto("Paris")
        XCTAssertNil(response.photo)
    }
    func testOldProvidersCannotEnterPexelsCoverStorage() async {
        for provider in ["google", "bundled", "supplied", "commons"] {
            var saved = savedCover(); saved.photo.provider = provider
            let result = await TripCoverStore(directory: directory).cover(for: UUID()) { saved }
            XCTAssertNil(result)
        }
    }
    func testRetainedPhotoIsAvailableBeforeAsyncCardTaskAndMemoized() async throws {
        let store = TripCoverStore(directory: directory), id = UUID()
        let saved = savedCover()
        _ = await store.cover(for: id) { saved }
        let reloaded = TripCoverStore(directory: directory)
        XCTAssertEqual(reloaded.cached(for: id)?.photo.title, saved.photo.title)
        try FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString + ".json"))
        XCTAssertNotNil(reloaded.cached(for: id))
    }
    private func savedCover() -> SavedTripCover {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 90)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        }
        return SavedTripCover(photo: CityPhoto(provider: "pexels", imageURL: URL(string: "https://images.pexels.com/photos/123/fixture.jpg")!,
            sourceURL: URL(string: "https://www.pexels.com/photo/fixture-123/"), authors: [.init(name: "Sample author")],
            license: "Pexels License", licenseURL: URL(string: "https://www.pexels.com/license/")!, title: "Fixture", attribution: "Photo by Sample author on Pexels"),
            data: image.jpegData(compressionQuality: 0.8)!)
    }
    func testTripCoverPersistsAcrossStoreRelaunchWithoutAnotherLookup() async throws {
        let store = TripCoverStore(directory: directory), id = UUID(), expected = savedCover()
        var calls = 0
        let first = await store.cover(for: id) { calls += 1; return expected }
        XCTAssertEqual(first?.data, expected.data)
        let reloaded = TripCoverStore(directory: directory)
        let restored = await reloaded.cover(for: id, allowLookup: false) { calls += 1; return nil }
        XCTAssertEqual(restored?.photo.authors.first?.name, "Sample author")
        XCTAssertEqual(restored?.photo.license, "Pexels License"); XCTAssertEqual(restored?.data, expected.data)
        _ = await reloaded.cover(for: id) { calls += 1; return nil }
        XCTAssertEqual(calls, 1)
        _ = await reloaded.cover(for: UUID()) { calls += 1; return nil }
        XCTAssertEqual(calls, 2) // A distinct trip gets its own attempt.
    }
    func testTripCoverFailureAndCorruptImageNeverRetryAfterRelaunch() async throws {
        for mode in 0..<3 {
            let id = UUID(), store = TripCoverStore(directory: directory)
            var calls = 0
            _ = await store.cover(for: id) {
                calls += 1
                if mode == 0 { throw URLError(.notConnectedToInternet) }
                return mode == 1 ? nil : self.savedCover()
            }
            if mode == 2 { try Data("broken".utf8).write(to: directory.appendingPathComponent(id.uuidString + ".json")) }
            let result = await TripCoverStore(directory: directory).cover(for: id) { calls += 1; return self.savedCover() }
            XCTAssertNil(result); XCTAssertEqual(calls, 1)
        }
    }
    func testTripCoverConcurrentViewsAndCancellationShareOneAttempt() async {
        let id = UUID(), store = TripCoverStore(directory: directory)
        var calls = 0
        var finish: CheckedContinuation<Void, Never>?
        let first = Task { await store.cover(for: id) {
            calls += 1
            await withCheckedContinuation { finish = $0 }
            return self.savedCover()
        } }
        while finish == nil { await Task.yield() }
        // Another instance must respect the claim even while the first request is running.
        let duplicate = await TripCoverStore(directory: directory).cover(for: id) { calls += 1; return nil }
        XCTAssertNil(duplicate)
        let second = Task { await store.cover(for: id) { calls += 1; return nil } }
        first.cancel() // Scrolling a card away must not abandon and restart the lookup.
        finish?.resume()
        let a = await first.value, b = await second.value
        XCTAssertEqual(calls, 1); XCTAssertEqual(a?.data, savedCover().data); XCTAssertEqual(b?.data, a?.data)
    }
    func testTripCoverUnavailableEndpointAndUnwritableStorageMakeNoRequest() async throws {
        let id = UUID(), store = TripCoverStore(directory: directory)
        var calls = 0
        _ = await store.cover(for: id, allowLookup: false) { calls += 1; return nil }
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        _ = await store.cover(for: id) { calls += 1; return nil }
        XCTAssertEqual(calls, 1)
        let blocked = directory.appendingPathComponent("file")
        try Data([1]).write(to: blocked)
        _ = await TripCoverStore(directory: blocked).cover(for: UUID()) { calls += 1; return nil }
        XCTAssertEqual(calls, 1)
    }
    func testWishlistItineraryPersistsAndMovesToDatedTripsWithoutLosingPlans() throws {
        let paris = JourneyStop(name: "Paris", arrival: "2000-01-01", nights: 3)
        let lyon = JourneyStop(name: "Lyon", arrival: "2000-01-04", nights: 2)
        var draft = JourneyDocument(title: "France someday", dateMode: .nights, stops: [paris, lyon])
        draft.events = [JourneyEvent(stopID: lyon.id, day: 1, place: PlaceRecord(name: "Dinner", city: "Lyon"), description: "Window table")]
        draft.hotels = [HotelReservation(place: PlaceRecord(name: "Lyon hotel", category: .hotel, city: "Lyon"), checkIn: "2000-01-04", checkOut: "2000-01-06", notes: "Suite idea")]
        let url = directory.appendingPathComponent("wishlist.json")
        let library = JourneyLibrary(url: url)
        XCTAssertTrue(library.save(draft)); XCTAssertTrue(library.trips.isEmpty)
        XCTAssertEqual(library.wishlistTrips.count, 1)
        let reloaded = JourneyLibrary(url: url)
        let restored = try XCTUnwrap(reloaded.wishlistTrips.first)
        XCTAssertTrue(restored.days.allSatisfy { $0.date == nil })
        let trip = try restored.scheduledWishlist(departure: "2027-03-10")
        XCTAssertEqual(trip.id, draft.id); XCTAssertEqual(trip.stops.map(\.arrival), ["2027-03-10", "2027-03-13"])
        XCTAssertEqual(trip.hotels[0].checkIn, "2027-03-13"); XCTAssertEqual(trip.hotels[0].checkOut, "2027-03-15")
        XCTAssertEqual(trip.hotels[0].notes, "Suite idea"); XCTAssertEqual(trip.events, draft.events)
        XCTAssertEqual(trip.date(for: trip.events[0]), "2027-03-14")
        XCTAssertTrue(reloaded.save(trip)); XCTAssertTrue(reloaded.wishlistTrips.isEmpty); XCTAssertEqual(reloaded.trips.count, 1)
        XCTAssertEqual(restored.dateMode, .nights)
    }
    func testWishlistReorderKeepsHotelDayOffsetsAndRejectsShortenedStay() throws {
        let paris = JourneyStop(name: "Paris", arrival: "2000-01-01", nights: 3)
        let lyon = JourneyStop(name: "Lyon", arrival: "2000-01-04", nights: 2)
        var draft = JourneyDocument(title: "Route", dateMode: .nights, stops: [lyon, paris])
        draft.hotels = [HotelReservation(place: PlaceRecord(name: "Paris hotel", category: .hotel, city: "Paris"), checkIn: "2000-01-02", checkOut: "2000-01-04")]
        try draft.scheduleWishlist(from: [paris, lyon], departure: "2000-01-01")
        XCTAssertEqual(draft.hotels[0].checkIn, "2000-01-04"); XCTAssertEqual(draft.hotels[0].checkOut, "2000-01-06")
        XCTAssertEqual(draft.stayLabel(draft.hotels[0]), "Day 4 – Day 6")
        let old = draft.stops; draft.stops[1].nights = 1
        let before = draft
        XCTAssertThrowsError(try draft.scheduleWishlist(from: old, departure: "2000-01-01"))
        XCTAssertEqual(draft, before)
    }
    private var statsNow: Date { ISO8601DateFormatter().date(from: "2026-09-07T16:00:00Z")! }
    func testStatisticsSeparatesPlannedStopsFromJournaledVisitsAndFlightConnections() {
        let paris = JourneyStop(name: "Paris", country: "France", arrival: "2026-09-06", nights: 3, countryCode: "FR")
        let tokyo = JourneyStop(name: "Tokyo", country: "Japan", arrival: "2026-09-10", nights: 3, countryCode: "JP")
        var d = JourneyDocument(title: "Two cities", startDate: "2026-09-06", endDate: "2026-09-13", stops: [paris,tokyo])
        d.places = [RatedPlace(place: .init(name: "Dinner", category: .restaurant, city: "Paris"), overall: 9, visitedOn: "2026-09-06", michelinStars: 3)]
        d.flights = [FlightReservation(departureAirport: "DOH", arrivalAirport: "NRT", departureDay: "2026-09-10", arrivalDay: "2026-09-10", departureLatitude: 25.2, departureLongitude: 51.6, arrivalLatitude: 35.7, arrivalLongitude: 140.3)]
        let values = TravelStatistics(documents:[d], now:statsNow, deviceZone:TimeZone(secondsFromGMT:0)!).summary()
        XCTAssertEqual(values.countries,["FR"]); XCTAssertEqual(values.cities,["paris"])
        XCTAssertEqual(values.planned.map(\.city),["Tokyo"]); XCTAssertEqual(values.upcomingTrips,1)
        XCTAssertEqual(values.kilometers,0); XCTAssertEqual(values.stars,3); XCTAssertNil(values.longest)
        var template = d; template.id = UUID(); template.isTemplate = true
        XCTAssertEqual(TravelStatistics(documents:[template],now:statsNow).summary().stars,0)
        var future = d; future.startDate = "2026-10-01"; future.endDate = "2026-10-06"; future.stops = [JourneyStop(name: "Tokyo",country:"Japan",arrival:"2026-10-01",nights:5)]
        XCTAssertTrue(TravelStatistics(documents:[future],now:statsNow).summary().countries.isEmpty)
    }
    func testStatisticsUsesHotelDestinationDayRatherThanFutureStopTimeZone() {
        let ny = JourneyStop(name:"New York",country:"US",arrival:"2026-09-06",nights:3,timeZone:"America/New_York")
        let tokyo = JourneyStop(name:"Tokyo",country:"JP",arrival:"2026-09-10",nights:3,timeZone:"Asia/Tokyo")
        var d = JourneyDocument(title:"Across the world",startDate:"2026-09-06",endDate:"2026-09-13",stops:[ny,tokyo])
        d.places = [RatedPlace(place:.init(name:"Lunch",city:"New York"),overall:8,visitedOn:"2026-09-06")]
        d.hotels = [HotelReservation(place:.init(name:"Stay",category:.hotel,city:"New York"),checkIn:"2026-09-06",checkOut:"2026-09-09")]
        let date = ISO8601DateFormatter().date(from:"2026-09-07T23:30:00Z")!
        XCTAssertEqual(TravelStatistics(documents:[d],now:date).summary().hotelNights,1)
    }
    func testStatisticsSplitsHotelNightsByYearAndKeepsCurrenciesSeparate() {
        let stop = JourneyStop(name:"Paris",country:"france",arrival:"2025-12-30",nights:3)
        var d = JourneyDocument(title:"New Year",startDate:"2025-12-30",endDate:"2026-01-02",stops:[stop])
        d.hotels = [HotelReservation(place:.init(name:"Paris stay",category:.hotel),checkIn:"2025-12-30",checkOut:"2026-01-02",cost:.init(amount:900,currency:"EUR"))]
        d.events = [JourneyEvent(stopID:stop.id,day:2,place:.init(name:"Lunch"),cost:.init(amount:100,currency:"USD"))]
        let stats = TravelStatistics(documents:[d,d],now:statsNow)
        XCTAssertEqual(stats.summary(year:2025).hotelNights,2); XCTAssertEqual(stats.summary(year:2026).hotelNights,1)
        XCTAssertEqual(stats.summary().trips,1); XCTAssertEqual(stats.summary().nightsAway,3)
        XCTAssertEqual(stats.summary().spend,["EUR":900,"USD":100]); XCTAssertEqual(stats.summary().longest?.nights,3)
        XCTAssertEqual(stats.summary(year:2025).countries,["FR"]); XCTAssertEqual(stats.summary(year:2026).countries,["FR"])
        d.hotels = []
        let fallback = TravelStatistics(documents:[d],now:statsNow).summary()
        XCTAssertEqual(fallback.hotelNights,0); XCTAssertEqual(fallback.otherNights,3); XCTAssertEqual(fallback.nightsLabel,"Nights away")
    }
    func testStatisticsCountryNormalizationStarredRestaurantsAndBrandThreshold() {
        XCTAssertEqual(TravelStatistics.countryCode("United Kingdom"),"GB"); XCTAssertEqual(TravelStatistics.countryCode("uk"),"GB")
        XCTAssertEqual(TravelStatistics.countryCode("france"),"FR"); XCTAssertNil(TravelStatistics.countryCode("Imaginary country"))
        var d = itinerary(); d.startDate = "2026-01-01"; d.endDate = "2026-01-04"; d.stops[0].arrival = "2026-01-01"
        let place = PlaceRecord(name:"A great table",category:.restaurant,city:"Paris")
        d.places = [RatedPlace(place:place,overall:9,visitedOn:"2026-01-01",michelinStars:3),RatedPlace(place:place,overall:8,visitedOn:"2026-01-02",michelinStars:3),RatedPlace(place:.init(name:"A hotel",category:.hotel),overall:0,michelinStars:3)]
        d.hotels = (1...3).map { i in HotelReservation(place:.init(name:"Stay \(i)",category:.hotel,brand:"Seur Hotels"),checkIn:"2026-01-0\(i)",checkOut:"2026-01-0\(i+1)") }
        let value = TravelStatistics(documents:[d],now:statsNow).summary()
        XCTAssertEqual(value.favoriteBrands,["Seur Hotels"]); XCTAssertEqual(value.stars,6); XCTAssertEqual(value.starredRestaurants,1)
        XCTAssertEqual(value.average,8.5)
        d.hotels.removeLast(); XCTAssertTrue(TravelStatistics(documents:[d],now:statsNow).summary().favoriteBrands.isEmpty)
    }
    func testStatisticsLegacyFieldsAndImageAreCompatible() throws {
        let old = try JSONDecoder().decode(JourneyDocument.self,from:JSONEncoder().encode(itinerary()))
        XCTAssertNil(old.stops[0].countryCode); XCTAssertNil(old.events[0].place.brand)
        var d = old; d.stops[0].countryCode = "FR"; d.events[0].place.brand = "A brand"
        let restored = try JSONDecoder().decode(JourneyDocument.self,from:JSONEncoder().encode(d))
        XCTAssertEqual(restored.stops[0].countryCode,"FR"); XCTAssertEqual(restored.events[0].place.brand,"A brand")
        let renderer = ImageRenderer(content:TravelStatsCard(summary:TravelStatistics(documents:[d],now:statsNow).summary(year:2026),year:2026).frame(width:360,height:640))
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        XCTAssertEqual(image.width,1080); XCTAssertEqual(image.height,1920)
    }
    func testStatisticsUndatedJournalOnlyAppearsInLifetimeAndDeduplicatesFlights() {
        var d = JourneyDocument(title:"Memories",dateMode:.nights,stops:[JourneyStop(name:"London",country:"UK",nights:2)])
        d.places = [RatedPlace(place:.init(name:"Lunch",city:"London"),overall:8,michelinStars:1)]
        let flight = FlightReservation(flightNumber:"BA1",departureAirport:"JFK",arrivalAirport:"LHR",departureDay:"2026-01-01",arrivalDay:"2026-01-02",departureLatitude:40.6413,departureLongitude:-73.7781,arrivalLatitude:51.47,arrivalLongitude:-0.4543)
        d.flights = [flight,flight]
        let stats = TravelStatistics(documents:[d],now:statsNow)
        XCTAssertEqual(stats.summary().countries,["GB"]); XCTAssertEqual(stats.summary().stars,1)
        XCTAssertEqual(stats.summary(year:2026).stars,0); XCTAssertEqual(stats.summary(year:2026).undatedEntries,1)
        XCTAssertEqual(stats.summary().miles,3451,accuracy:10)
        XCTAssertEqual(stats.summary().kilometers,stats.summary().miles/0.6213711922,accuracy:0.01)
    }
    func testRecapPosterRendersExactVerticalDimensionsWithoutNetwork() throws {
        let renderer = ImageRenderer(content: RecapPoster(recap: TripRecap(document: itinerary()), map: nil, photos: []).frame(width: 360, height: 640))
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        XCTAssertEqual(image.width, 1080); XCTAssertEqual(image.height, 1920)
    }
    func testRecapCombinesTransferDaysKeepsEmptyDaysAndUndatedMemories() {
        let paris = JourneyStop(name: "Paris", arrival: "2026-10-01", nights: 2)
        let lyon = JourneyStop(name: "Lyon", arrival: "2026-10-03", nights: 1)
        var d = JourneyDocument(title: "France", startDate: "2026-10-01", endDate: "2026-10-04", stops: [paris, lyon])
        d.places = [RatedPlace(place: .init(name: "A table"), overall: 9, visitedOn: "2026-10-03", michelinStars: 2), RatedPlace(place: .init(name: "Undated"))]
        d.hotels = [HotelReservation(place: .init(name: "Stay", category: .hotel), checkIn: "2026-10-01", checkOut: "2026-10-03")]
        let recap = TripRecap(document: d)
        XCTAssertEqual(recap.days.count, 5)
        XCTAssertEqual(recap.days[2].cities, ["Paris", "Lyon"])
        XCTAssertEqual(recap.days[2].places.count, 1)
        XCTAssertTrue(recap.days[1].places.isEmpty)
        XCTAssertEqual(recap.days[0].stays.count, 1)
        XCTAssertEqual(recap.days.last?.id, "undated")
        XCTAssertEqual(recap.ratedCount, 1); XCTAssertEqual(recap.stars, 2)
    }
    func testRecapPhotoSelectionStripsPrivateFieldsWithoutMutatingOriginal() throws {
        var d = itinerary()
        let first = JournalPhoto(jpeg: Data([1,2])), second = JournalPhoto(jpeg: Data([3,4]))
        d.places = [RatedPlace(place: .init(name: "Dinner", phone: "PRIVATE", website: "PRIVATE", overview: "PRIVATE"), overall: 8, notes: "PRIVATE", photos: [first, second])]
        d.hotels = [HotelReservation(confirmation: "PRIVATE", notes: "PRIVATE")]
        d.events[0].attendees = "PRIVATE"
        d.flights = [FlightReservation(bookingLink: "PRIVATE", notes: "PRIVATE")]
        d.description = "PRIVATE"
        let copy = TripRecap(document: d).shareDocument(photoIDs: [first.id])
        let json = String(data: try JSONEncoder().encode(copy), encoding: .utf8)!
        XCTAssertFalse(json.contains("PRIVATE")); XCTAssertEqual(copy.places[0].photos.map(\.id), [first.id])
        XCTAssertEqual(d.places[0].photos.count, 2); XCTAssertEqual(d.visibility, copy.visibility)
        XCTAssertTrue(copy.events.isEmpty)
    }
    func testRecapMilesSkipMissingCoordinatesAndMapFitsDateLine() {
        var d = itinerary()
        d.flights = [FlightReservation(departureLatitude: 40.6413, departureLongitude: -73.7781, arrivalLatitude: 51.47, arrivalLongitude: -0.4543), FlightReservation()]
        let recap = TripRecap(document: d)
        XCTAssertEqual(recap.flightMiles, 3451, accuracy: 10)
        let region = RecapMapGeometry.region([.init(id: "a", name: "a", latitude: 30, longitude: 179), .init(id: "b", name: "b", latitude: 32, longitude: -179)])
        XCTAssertLessThan(region.span.longitudeDelta, 4); XCTAssertEqual(abs(region.center.longitude), 180, accuracy: 0.01)
        var c = d; c.endDate = "2026-10-04"; c.stops[0].timeZone = "Pacific/Honolulu"
        let now = ISO8601DateFormatter().date(from: "2026-10-05T05:00:00Z")!
        XCTAssertFalse(TripRecap(document: c).hasEnded(now: now))
        XCTAssertTrue(TripRecap(document: c).hasEnded(now: now.addingTimeInterval(6*3600)))
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
    func testNotificationStepResumesAndExistingCompletionStaysComplete() {
        isolated { defaults in
            let store = OnboardingStore(defaults: defaults)
            store.move(to: 5)
            XCTAssertEqual(OnboardingStore(defaults: defaults).profile.step, 5)
            store.move(to: 6)
            let resumed = OnboardingStore(defaults: defaults)
            XCTAssertEqual(resumed.profile.step, 6)
            XCTAssertFalse(resumed.profile.completed)
            resumed.complete()
            XCTAssertTrue(OnboardingStore(defaults: defaults).profile.completed)
            let oldCompleted = TravelerProfile(completed: true, step: 5)
            defaults.set(try! JSONEncoder().encode(oldCompleted), forKey: OnboardingStore.key)
            XCTAssertTrue(OnboardingStore(defaults: defaults).profile.completed)
        }
    }
    func testNotificationPermissionAutomaticallyAsksOnceAndRegistersWhenAllowed() async {
        var status = UNAuthorizationStatus.notDetermined, requests = 0, registrations = 0
        let permission = OnboardingNotificationPermission(readStatus: { status }, request: {
            requests += 1; status = .authorized; return true
        }, register: { registrations += 1 })
        await permission.requestOnArrival()
        XCTAssertEqual(requests, 1); XCTAssertTrue(permission.isAllowed); XCTAssertEqual(registrations, 1)
        await permission.requestOnArrival()
        XCTAssertEqual(requests, 1)
    }
    func testNotificationDenialAndSettingsChangesNeverReprompt() async {
        var status = UNAuthorizationStatus.notDetermined, requests = 0, registrations = 0
        let permission = OnboardingNotificationPermission(readStatus: { status }, request: {
            requests += 1; status = .denied; return false
        }, register: { registrations += 1 })
        await permission.requestOnArrival()
        XCTAssertEqual(permission.status, .denied); XCTAssertFalse(permission.isAllowed)
        XCTAssertEqual(registrations, 0)
        await permission.requestOnArrival(); XCTAssertEqual(requests, 1)
        status = .authorized; await permission.refresh()
        XCTAssertTrue(permission.isAllowed); XCTAssertEqual(registrations, 1); XCTAssertEqual(requests, 1)
    }
    func testExistingNotificationPermissionAndErrorsRemainRecoverable() async {
        var requests = 0
        for status in [UNAuthorizationStatus.authorized, .provisional, .ephemeral, .denied] {
            let permission = OnboardingNotificationPermission(readStatus: { status }, request: { requests += 1; return true }, register: {})
            await permission.requestOnArrival()
            XCTAssertEqual(requests, 0)
        }
        var status = UNAuthorizationStatus.notDetermined
        let permission = OnboardingNotificationPermission(readStatus: { status }, request: {
            requests += 1
            if requests == 1 { throw URLError(.notConnectedToInternet) }
            status = .authorized; return true
        }, register: {})
        await permission.requestOnArrival(); XCTAssertNotNil(permission.error); XCTAssertFalse(permission.busy)
        await permission.requestOnArrival(); XCTAssertNil(permission.error); XCTAssertTrue(permission.isAllowed)
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
            XCTAssertEqual(store.profile.step, 6)
            XCTAssertTrue(store.profile.destination.isEmpty)
            XCTAssertTrue(store.profile.cuisines.isEmpty)
            store.toggleInterest("Exceptional stays"); store.toggleInterest("Exceptional stays")
            XCTAssertTrue(store.profile.interests.isEmpty)
        }
    }
}


@MainActor final class LocationAutocompleteTests: XCTestCase {
    func testTravelCityPromotionPrecedesNearbyNamesAndDeduplicatesUK() {
        let raw = [LocationSuggestion(title: "London", subtitle: "ON, Canada"), LocationSuggestion(title: "London, KY", subtitle: "United States"), LocationSuggestion(title: "Londonderry, NH", subtitle: "United States"), LocationSuggestion(title: "London", subtitle: "England, United Kingdom")]
        let ranked = DestinationSuggestions.merge(raw, query: "London", kind: .destination)
        XCTAssertEqual(ranked.first?.subtitle, "England, United Kingdom")
        XCTAssertNotNil(ranked.first?.destination)
        XCTAssertEqual(ranked.filter { $0.subtitle.contains("United Kingdom") }.count, 1)
        XCTAssertEqual(ranked[1].subtitle, "ON, Canada")
        XCTAssertEqual(ranked.last?.title, "Londonderry, NH")
        XCTAssertEqual(DestinationSuggestions.preferred("Par", kind: .city).first?.title, "Paris")
        XCTAssertEqual(DestinationSuggestions.preferred("rome", kind: .destination).first?.subtitle, "Italy")
    }
    func testExplicitRegionsNeverPromoteTheWrongCity() {
        for query in ["London Ontario", "London, ON", "London Canada", "London, Kentucky", "London, OH", "Paris Texas", "Londonderry"] {
            XCTAssertTrue(DestinationSuggestions.preferred(query, kind: .destination).isEmpty, query)
        }
        for query in ["London", " LONDON ", "lon", "London, England", "London UK", "London, United Kingdom"] {
            XCTAssertEqual(DestinationSuggestions.preferred(query, kind: .destination).first?.destination?.country, "United Kingdom", query)
        }
        let ontario = LocationSuggestion(title: "London", subtitle: "Ontario, Canada")
        XCTAssertEqual(DestinationSuggestions.merge([ontario], query: "London Ontario", kind: .destination).first?.subtitle, ontario.subtitle)
        for kind in [LocationSearchKind.place, .airport, .address, .country, .timeZone] {
            XCTAssertTrue(DestinationSuggestions.preferred("London", kind: kind).isEmpty)
        }
    }
    func testDirectorySelectionHasCorrectOfflineGeography() {
        for city in DestinationSuggestions.cities {
            let selected = DestinationSuggestions.selection(city, kind: .destination)
            XCTAssertTrue(selected.place.hasCoordinate, city.name)
            XCTAssertNotNil(selected.countryCode, city.name)
            XCTAssertNotNil(TimeZone(identifier: selected.timeZone), city.name)
            XCTAssertEqual(selected.text, city.name + ", " + city.country)
        }
        let london = DestinationSuggestions.preferred("London", kind: .city)[0].destination!
        let selection = DestinationSuggestions.selection(london, kind: .city)
        XCTAssertEqual(selection.text, "London"); XCTAssertEqual(selection.countryCode, "GB")
        XCTAssertEqual(selection.timeZone, "Europe/London")
        XCTAssertEqual(selection.place.latitude!, 51.5074, accuracy: 0.001)
    }
    func testPreferredCitiesRemainStableAcrossAppleResponsesAndFailure() async throws {
        var calls = 0
        let model = LocationAutocompleteModel(appleSearch: { _, _ in
            calls += 1
            return [LocationSuggestion(title: "London", subtitle: "ON, Canada")]
        })
        model.update("London", kind: .destination)
        XCTAssertEqual(model.suggestions.first?.destination?.country, "United Kingdom", "Available before debounce/network")
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(model.suggestions.first?.destination?.country, "United Kingdom")
        XCTAssertEqual(model.suggestions.last?.subtitle, "ON, Canada")
        var selected: LocationSelection?
        model.select(model.suggestions[0], kind: .destination, category: .other) { selected = $0 }
        XCTAssertEqual(selected?.countryCode, "GB"); XCTAssertEqual(calls, 1, "Selection requires no additional lookup")
        let offline = LocationAutocompleteModel(appleSearch: { _, _ in throw JourneyError.message("Offline") })
        offline.update("London", kind: .destination)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(offline.suggestions.first?.destination?.country, "United Kingdom")
        offline.update("London Ontario", kind: .destination)
        XCTAssertTrue(offline.suggestions.isEmpty, "Old UK result clears immediately when the user qualifies the location")
        offline.stop()
    }
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
    func testGuideResultsSeedSeparateSearchWithoutExtraRequests() async {
        var calls = 0
        let model = CityExploreModel { [self] _, interest, _, _ in
            calls += 1
            return [sample("fresh", category: interest.category)]
        }
        model.seed(city: lisbon, sections: [
            ExploreSection(interest: .restaurants, places: [sample("cached", category: .restaurant)]),
            ExploreSection(interest: .museums, places: [], error: "Offline")
        ])
        await model.load(city: lisbon, interest: .restaurants, term: "", wider: false)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(model.places.first?.record.name, sample("cached").record.name)
        await model.load(city: lisbon, interest: .restaurants, term: "Italian", wider: false)
        XCTAssertEqual(calls, 1, "Changed filters must perform their own search")
        await model.load(city: lisbon, interest: .museums, term: "", wider: false)
        XCTAssertEqual(calls, 2, "A failed preview must not prevent retrying")
        await model.load(city: lisbon, interest: .restaurants, term: "", wider: true)
        XCTAssertEqual(calls, 3, "A wider area must not reuse the city-center preview")
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
    func testOverlapNormalizesCountriesAndAccentsWithoutGuessingUnknownCities() {
        var a = JourneyStop(name: "  Montréal ", country: "Canada", arrival: "2026-09-10", nights: 4)
        var b = JourneyStop(name: "Montreal", country: "CA", arrival: "2026-09-12", nights: 4)
        XCTAssertTrue(FriendOverlaps.sameCity(a,b))
        b.country = "France"; XCTAssertFalse(FriendOverlaps.sameCity(a,b))
        a.country = ""; b.country = ""; XCTAssertFalse(FriendOverlaps.sameCity(a,b))
        a.latitude = 45.5; a.longitude = -73.57; b.latitude = 45.51; b.longitude = -73.56
        XCTAssertTrue(FriendOverlaps.sameCity(a,b))
        b.latitude = 48.8; b.longitude = 2.3; XCTAssertFalse(FriendOverlaps.sameCity(a,b))
    }
    func testOverlapIncludesCheckoutDayAndKeepsDismissalIdentityAsTodayAdvances() {
        var remote = FriendsFixtures.remote
        remote.document.stops = [.init(name: "Paris", country: "France", arrival: "2026-09-10", nights: 4)]
        let own = JourneyDocument(title: "My Paris", stops: [.init(name: "Paris", country: "FR", arrival: "2026-09-12", nights: 4)])
        let first = FriendOverlaps.matches(remote: [remote], local: [own], friendIDs: [remote.owner.id], today: "2026-09-07")
        XCTAssertEqual(first.count,1); XCTAssertEqual(first.first?.start,"2026-09-12"); XCTAssertEqual(first.first?.end,"2026-09-14")
        let last = FriendOverlaps.matches(remote: [remote], local: [own], friendIDs: [remote.owner.id], today: "2026-09-14")
        XCTAssertEqual(last.first?.start,"2026-09-14"); XCTAssertEqual(first.first?.id,last.first?.id)
        XCTAssertTrue(FriendOverlaps.matches(remote: [remote], local: [own], friendIDs: [remote.owner.id], today: "2026-09-15").isEmpty)
        remote.document.stops[0].nights += 1
        XCTAssertNotEqual(first.first?.id,FriendOverlaps.matches(remote: [remote], local: [own], friendIDs: [remote.owner.id], today: "2026-09-07").first?.id)
    }
    func testOverlapRequiresAcceptedFriendAndExcludesTemplatesAndFlexibleDates() {
        var remote = FriendsFixtures.remote
        var own = remote.document; own.id = UUID()
        let today = remote.document.stops[0].arrival
        XCTAssertTrue(FriendOverlaps.matches(remote: [remote], local: [own], friendIDs: [], today: today).isEmpty)
        own.isTemplate = true
        XCTAssertTrue(FriendOverlaps.matches(remote: [remote], local: [own], friendIDs: [remote.owner.id], today: today).isEmpty)
        own.isTemplate = false; remote.document.isTemplate = true
        XCTAssertTrue(FriendOverlaps.matches(remote: [remote], local: [own], friendIDs: [remote.owner.id], today: today).isEmpty)
        remote.document.isTemplate = false; own.dateMode = .nights
        XCTAssertTrue(FriendOverlaps.matches(remote: [remote], local: [own], friendIDs: [remote.owner.id], today: today).isEmpty)
    }
    func testOverlapDeduplicatesEquivalentSharedAndLocalCopies() {
        let remote = FriendsFixtures.remote
        var own = remote.document; own.id = UUID()
        var another = own; another.id = UUID()
        XCTAssertEqual(FriendOverlaps.matches(remote: [remote,remote], local: [own,another], friendIDs: [remote.owner.id], today: remote.document.stops[0].arrival).count,1)
    }
    func testTripRequestAndReplyMetadataPreserveLegacyMessageDecoding() throws {
        let legacy = #"{"id":"message","sender":{"id":"person","handle":"maya","name":"Maya"},"text":"Hello","createdAt":0}"#.data(using: .utf8)!
        var message = try JSONDecoder().decode(TravelChatMessage.self,from:legacy)
        XCTAssertNil(message.tripRequest); XCTAssertNil(message.replyTo); XCTAssertNil(message.documentIsTemplate)
        message.tripRequest = .init(city:"Tokyo",month:"2027-03")
        let restored = try JSONDecoder().decode(TravelChatMessage.self,from:JSONEncoder().encode(message))
        XCTAssertEqual(restored.tripRequest?.city,"Tokyo"); XCTAssertTrue(restored.tripRequest?.prompt.contains("2027") == true)
        message.tripRequest = nil; message.replyTo = "request"; message.documentID = "trip"; message.documentIsTemplate = true
        let reply = try JSONDecoder().decode(TravelChatMessage.self,from:JSONEncoder().encode(message))
        XCTAssertEqual(reply.replyTo,"request"); XCTAssertEqual(reply.documentIsTemplate,true)
        let chat = try JSONDecoder().decode(TravelConversation.self,from:#"{"id":"chat","name":"Friends","members":[]}"#.data(using:.utf8)!)
        XCTAssertNil(chat.pendingRequests)
    }
    func testDirectConversationDoesNotReuseLargerGroup() {
        let owner = FriendsFixtures.owner, friend = FriendsFixtures.maya
        var group = FriendsFixtures.chat; group.members.append(.init(id: "third", handle: "third", name: "Third"))
        XCTAssertNil(FriendsTravel.directConversation(friend: friend.id, owner: owner.id, chats: [group]))
        XCTAssertNotNil(FriendsTravel.directConversation(friend: friend.id, owner: owner.id, chats: [group, FriendsFixtures.chat]))
    }
    func testAccountResetClearsPersonalSocialData() {
        let model = FriendsHomeModel(); model.friends = FriendsFixtures.friends; model.trips = [FriendsFixtures.remote]; model.chats = [FriendsFixtures.chat]; model.saved = [FriendsFixtures.remote.id]; model.dismissedOverlaps = ["private"]; model.overlapsEnabled = false
        model.reset(); XCTAssertTrue(model.friends.isEmpty); XCTAssertTrue(model.trips.isEmpty); XCTAssertTrue(model.chats.isEmpty); XCTAssertTrue(model.saved.isEmpty); XCTAssertTrue(model.dismissedOverlaps.isEmpty); XCTAssertTrue(model.overlapsEnabled)
    }
}

@MainActor final class TodayTests: XCTestCase {
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private func instant(_ value: String) -> Date { FlightSnapshot.date(value)! }
    func testActiveTripUsesDestinationDateAndIncludesLastDay() {
        var trip = TodayFixtures.trip
        let la = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertTrue(TodayPlanner.isActive(trip, now: instant("2026-09-05T23:00:00Z"), fallback: la))
        XCTAssertTrue(TodayPlanner.isActive(trip, now: instant("2026-09-09T21:59:00Z"), fallback: la))
        XCTAssertFalse(TodayPlanner.isActive(trip, now: instant("2026-09-09T22:01:00Z"), fallback: la))
        trip.dateMode = .nights
        XCTAssertFalse(TodayPlanner.isActive(trip, now: instant("2026-09-07T07:00:00Z")))
        XCTAssertTrue(TodayPlanner.items(trip, day: "2026-09-07", zone: paris).isEmpty)
    }
    func testCalendarDaysSurviveBothDaylightSavingChanges() {
        let ny = TimeZone(identifier: "America/New_York")!
        let spring = TodayPlanner.date("2026-03-08", minute: 0, zone: ny)!
        let next = TodayPlanner.date("2026-03-09", minute: 0, zone: ny)!
        XCTAssertEqual(next.timeIntervalSince(spring), 23 * 3600)
        let autumn = TodayPlanner.date("2026-11-01", minute: 0, zone: ny)!
        XCTAssertEqual(TodayPlanner.date("2026-11-02", minute: 0, zone: ny)!.timeIntervalSince(autumn), 25 * 3600)
    }
    func testTransferDayRetainsBothCitiesAndSortsReminders() {
        var trip = TodayFixtures.trip
        trip.stops[0].nights = 1
        let nextStop = JourneyStop(name: "Lyon", arrival: "2026-09-07", nights: 2, timeZone: "Europe/Paris")
        trip.stops.append(nextStop)
        trip.events.append(JourneyEvent(stopID: nextStop.id, day: 0, minute: 1200, place: PlaceRecord(name: "Lyon dinner")))
        trip.events.append(JourneyEvent(stopID: nextStop.id, day: 0, place: PlaceRecord(name: "Anytime walk"), allDay: true))
        trip.hotels[0].checkOut = "2026-09-07"
        trip.hotels.append(HotelReservation(place: PlaceRecord(name: "Lyon hotel"), checkIn: "2026-09-07", checkOut: "2026-09-09"))
        let context = TodayPlanner.context(trip, now: instant("2026-09-07T07:00:00Z"))
        XCTAssertEqual(context.stop?.id, nextStop.id)
        XCTAssertEqual(context.agendaDays.count, 2)
        let items = TodayPlanner.items(trip, day: context.day, zone: context.zone)
        XCTAssertEqual(items.map(\.sortMinute), [-1, 660, 780, 900, 1200])
        XCTAssertNil(items.first { $0.kind == .hotel }?.start)
        XCTAssertEqual(TodayPlanner.nextItem(items, now: instant("2026-09-07T07:00:00Z"))?.title, "Lunch by the river")
        XCTAssertEqual(TodayPlanner.nextItem(items, now: instant("2026-09-07T11:30:00Z"))?.title, "Lunch by the river")
        XCTAssertEqual(TodayPlanner.nextItem(items, now: instant("2026-09-07T12:31:00Z"))?.title, "Lyon dinner")
        XCTAssertNil(TodayPlanner.nextItem(items, now: instant("2026-09-07T21:00:00Z")))
    }
    func testOvernightFlightArrivalAndTimezoneFallback() {
        var trip = TodayFixtures.trip
        trip.stops[0].timeZone = nil
        var flight = FlightReservation(flightNumber: "AF1", departureAirport: "JFK", arrivalAirport: "CDG", departureDay: "2026-09-05", arrivalDay: "2026-09-06", departureTime: "22:00", arrivalTime: "11:00", arrivalLatitude: 49.0097, arrivalLongitude: 2.5479, departureZone: "America/New_York", arrivalZone: "Europe/Paris")
        trip.flights = [flight]
        XCTAssertEqual(TodayPlanner.zone(for: trip.stops[0], in: trip, fallback: .gmt).identifier, "Europe/Paris")
        let items = TodayPlanner.items(trip, day: "2026-09-06", zone: paris).filter { $0.kind == .flight }
        XCTAssertEqual(items.count, 2) // 22:00 JFK is 04:00 on the destination's next day.
        XCTAssertEqual(items.map(\.schedule), ["22:00", "11:00"])
        flight.arrivalLatitude = 35.6; flight.arrivalLongitude = 139.7; trip.flights = [flight]
        XCTAssertEqual(TodayPlanner.zone(for: trip.stops[0], in: trip, fallback: .gmt), .gmt)
    }
    func testDelayedFlightStaysAtEndOfOriginalDayAndCancelledIsNotNext() {
        var trip = TodayFixtures.trip
        var flight = FlightMapFixtures.trip.flights[0]
        flight.departureDay = "2026-09-07"; flight.departureTime = "23:30"; flight.departureZone = "Europe/Paris"
        flight.arrivalDay = "2026-09-08"; flight.arrivalTime = "02:00"; flight.arrivalZone = "Europe/Paris"
        trip.flights = [flight]
        var live = FlightMapFixtures.snapshot
        live.scheduledOut = "2026-09-07T21:30:00Z"; live.estimatedOut = "2026-09-07T22:30:00Z"
        live.estimatedIn = "2026-09-08T00:00:00Z"
        let items = TodayPlanner.items(trip, day: "2026-09-07", zone: paris, snapshots: [flight.id: live])
        XCTAssertEqual(items.last?.sortMinute, 1470)
        XCTAssertEqual(TodayPlanner.nextItem(items, now: instant("2026-09-07T21:00:00Z"))?.kind, .flight)
        live.cancelled = true
        XCTAssertNil(TodayPlanner.nextItem(TodayPlanner.items(trip, day: "2026-09-07", zone: paris, snapshots: [flight.id: live]), now: instant("2026-09-07T21:00:00Z")))
    }
    func testActiveChoiceIsStableAndEmptyDaysStillResolve() {
        let trip = TodayFixtures.trip
        var later = trip; later.id = UUID(); later.startDate = "2026-09-07"
        let now = instant("2026-09-07T07:00:00Z")
        XCTAssertEqual(TodayPlanner.activeTrip([trip, later], now: now)?.id, later.id)
        XCTAssertEqual(TodayPlanner.activeTrip([later, trip], now: now)?.id, later.id)
        XCTAssertTrue(TodayPlanner.items(trip, day: "2026-09-10", zone: paris).isEmpty)
        var noStops = trip; noStops.stops = []; noStops.events = []
        XCTAssertTrue(TodayPlanner.isActive(noStops, now: now, fallback: paris))
        XCTAssertNil(TodayPlanner.context(noStops, now: now).stop)
    }
    func testStopTimezoneArchiveCompatibilityAndSafeActions() throws {
        let legacy = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Paris\",\"code\":\"\",\"country\":\"France\",\"arrival\":\"2026-09-07\",\"nights\":3}".utf8)
        XCTAssertNil(try JSONDecoder().decode(JourneyStop.self, from: legacy).timeZone)
        let encoded = try JSONEncoder().encode(TodayFixtures.trip)
        XCTAssertEqual(try JSONDecoder().decode(JourneyDocument.self, from: encoded).stops[0].timeZone, paris.identifier)
        let place = PlaceRecord(name: "A & B", address: "1 Rue + Paris", latitude: 48.85, longitude: 2.35)
        let url = try XCTUnwrap(TravelPlaceActions.directions(place))
        XCTAssertEqual(url.scheme, "maps")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "48.85,2.35")
        XCTAssertEqual(TravelPlaceActions.phone("+33 (1) 23-45-67-89")?.absoluteString, "tel:+33123456789")
        XCTAssertNil(TravelPlaceActions.phone("Unavailable"))
        XCTAssertNil(TravelPlaceActions.booking("javascript:alert(1)"))
        XCTAssertNil(TravelPlaceActions.directions(PlaceRecord()))
    }
    func testFlightCachePersistsOfflineAndThrottlesRequests() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let now = Date.now
        var feed = FlightMapFixtures.feed
        var flight = FlightMapFixtures.trip.flights[0]
        let snapshot = feed.flights[0]
        flight.departureAirport = snapshot.origin; flight.arrivalAirport = snapshot.destination
        flight.departureDay = TodayPlanner.key(FlightSnapshot.date(snapshot.scheduledOut)!, zone: TimeZone(identifier: snapshot.originZone)!)
        feed.fetchedAt = now.timeIntervalSince1970
        let cache = TodayFlightStatusStore(url: url)
        var calls = 0
        await cache.refresh(flight, server: "test", now: now) { calls += 1; return feed }
        await cache.refresh(flight, server: "test", now: now.addingTimeInterval(60)) { calls += 1; return feed }
        XCTAssertEqual(calls, 1)
        let offline = TodayFlightStatusStore(url: url)
        XCTAssertNotNil(offline.snapshot(flight, server: "test"))
        XCTAssertNil(offline.snapshot(flight, server: "different-server"))
        await offline.refresh(flight, server: "test", now: now.addingTimeInterval(600)) { calls += 1; throw URLError(.notConnectedToInternet) }
        XCTAssertNotNil(offline.snapshot(flight, server: "test"))
        XCTAssertTrue(offline.label(flight, server: "test", now: now.addingTimeInterval(600)).contains("Last known status"))
        var ambiguous = feed; ambiguous.flights.append(snapshot)
        XCTAssertNil(TodayFlightStatusStore.match(ambiguous, flight: flight))
        var wrongRoute = flight; wrongRoute.arrivalAirport = "ZZZ"
        XCTAssertNil(TodayFlightStatusStore.match(feed, flight: wrongRoute))
    }
}

@MainActor final class TripTemplateTests: XCTestCase {
    func testTemplateRemovesPersonalDetailsWithoutChangingSource() throws {
        var trip = TodayFixtures.trip
        trip.description = "Private journey note"
        trip.events[0].attendees = "Private guests"; trip.events[0].description = "Private event note"
        trip.events[0].links = ["https://example.com/private-booking"]
        trip.events[0].cost = TravelMoney(amount: 250, currency: "EUR")
        trip.hotels[0].notes = "Private room instructions"
        trip.flights = FlightMapFixtures.trip.flights
        trip.places = [RatedPlace(place: trip.events[0].place, overall: 4.5, notes: "Private journal", photos: [JournalPhoto(jpeg: Data([1,2,3]))])]
        let template = try trip.templated(meta: TemplateMeta(tagline: "A lovely weekend", tags: ["food"]))
        XCTAssertTrue(template.isTemplate == true); XCTAssertEqual(template.dateMode, .nights)
        XCTAssertNil(template.startDate); XCTAssertNil(template.endDate); XCTAssertEqual(template.stops[0].arrival, "2000-01-01")
        XCTAssertEqual(template.hotels[0].confirmation, ""); XCTAssertEqual(template.hotels[0].notes, "")
        XCTAssertNil(template.events[0].attendees); XCTAssertNil(template.events[0].cost); XCTAssertTrue(template.events[0].links.isEmpty)
        XCTAssertTrue(template.places.isEmpty); XCTAssertTrue(template.flights.isEmpty)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(template), as: UTF8.self).contains("Private"))
        XCTAssertEqual(trip.hotels[0].confirmation, "SEUR-DEMO-123")
        XCTAssertEqual(trip.places[0].photos.count, 1)
        let withRatings = try trip.templated(meta: TemplateMeta(), includeCosts: true, includeRatings: true)
        XCTAssertEqual(withRatings.places[0].overall, 4.5); XCTAssertTrue(withRatings.places[0].photos.isEmpty)
        XCTAssertEqual(withRatings.places[0].notes, ""); XCTAssertNotNil(withRatings.events[0].cost)
    }
    func testAllTenSeedsCloneAcrossLeapDayWithHotelsAndStableEventReferences() throws {
        XCTAssertEqual(TemplateCatalog.bundled.count, 10)
        for template in TemplateCatalog.bundled {
            XCTAssertNil(template.validationError(), template.title)
            let trip = try template.usingTemplate(departure: "2028-02-28")
            XCTAssertNil(trip.validationError(), template.title)
            XCTAssertEqual(trip.startDate, "2028-02-28"); XCTAssertEqual(trip.endDate, TravelDay.adding(template.nights, to: "2028-02-28"))
            XCTAssertEqual(trip.visibility, .private); XCTAssertFalse(trip.isTemplate == true)
            XCTAssertNotEqual(trip.id, template.id); XCTAssertEqual(trip.importedFrom, template.id.uuidString)
            XCTAssertEqual(trip.events.map(\.stopID), template.events.map(\.stopID)); XCTAssertEqual(trip.events.map(\.day), template.events.map(\.day))
            XCTAssertEqual(trip.templateMeta?.sourceTitle, template.title)
            for hotel in trip.hotels {
                XCTAssertTrue(trip.stops.contains { $0.arrival == hotel.checkIn && $0.departure == hotel.checkOut })
                XCTAssertTrue(hotel.confirmation.isEmpty)
            }
        }
    }
    func testGapDatesNormalizeAndPartialHotelStayKeepsItsNightOffsets() throws {
        var trip = TodayFixtures.trip
        trip.hotels[0].checkIn = "2026-09-07"; trip.hotels[0].checkOut = "2026-09-08"
        let stop = JourneyStop(name: "Lyon", arrival: "2026-09-12", nights: 2)
        trip.stops.append(stop); trip.endDate = stop.departure
        let template = try trip.templated(meta: TemplateMeta())
        XCTAssertEqual(template.stops[1].arrival, "2000-01-04")
        let clone = try template.usingTemplate(departure: "2027-12-30")
        XCTAssertEqual(clone.stops[1].arrival, "2028-01-02")
        XCTAssertEqual(clone.hotels[0].checkIn, "2027-12-31")
        XCTAssertEqual(clone.hotels[0].checkOut, "2028-01-01")
    }
    func testUnmatchedHotelRequiresCorrectionAndBadDateCannotClone() throws {
        var trip = TodayFixtures.trip; trip.hotels[0].checkIn = "2026-10-01"; trip.hotels[0].checkOut = "2026-10-03"
        XCTAssertThrowsError(try trip.templated(meta: TemplateMeta()))
        XCTAssertThrowsError(try TemplateCatalog.bundled[0].usingTemplate(departure: "2026-02-30"))
    }
    func testTemplatesRemainSeparateFromActiveTripsAndPersistOffline() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let library = JourneyLibrary(url: url)
        let template = try TodayFixtures.trip.templated(meta: TemplateMeta())
        XCTAssertTrue(library.save(template))
        XCTAssertTrue(library.trips.isEmpty)
        let restored = JourneyLibrary(url: url).documents[0]
        XCTAssertTrue(restored.isTemplate == true)
        XCTAssertFalse(TodayPlanner.isActive(restored, now: TodayClock.now()))
        XCTAssertTrue(TemplateCatalog.matches(TemplateCatalog.bundled[0], city: "Antibes", tag: "beach"))
        XCTAssertFalse(TemplateCatalog.matches(TemplateCatalog.bundled[0], city: "Paris", tag: "art"))
    }
}

@MainActor final class JourneyConflictTests: XCTestCase {
    private func trip() -> JourneyDocument {
        JourneyDocument(title: "Paris", startDate: "2026-09-10", endDate: "2026-09-14", stops: [.init(name: "Paris", country: "France", arrival: "2026-09-10", nights: 4, latitude: 48.85, longitude: 2.35, timeZone: "Europe/Paris")])
    }
    private func event(_ d: JourneyDocument, _ minute: Int, duration: Int? = nil, day: Int = 0) -> JourneyEvent {
        .init(stopID: d.stops[0].id, day: day, minute: minute, place: .init(name: "Dinner"), durationMinutes: duration)
    }
    private func arrival() -> FlightReservation {
        .init(flightNumber: "AF1", departureAirport: "JFK", arrivalAirport: "CDG", departureDay: "2026-09-10", arrivalDay: "2026-09-10", departureTime: "09:00", arrivalTime: "20:00", departureLatitude: 40.64, departureLongitude: -73.78, arrivalLatitude: 49.0, arrivalLongitude: 2.55, departureZone: "America/New_York", arrivalZone: "Europe/Paris")
    }
    private func departure(_ day: String = "2026-09-14", time: String = "10:00") -> FlightReservation {
        .init(flightNumber: "AF2", departureAirport: "CDG", arrivalAirport: "JFK", departureDay: day, arrivalDay: day, departureTime: time, arrivalTime: "12:00", departureLatitude: 49.0, departureLongitude: 2.55, arrivalLatitude: 40.64, arrivalLongitude: -73.78, departureZone: "Europe/Paris", arrivalZone: "America/New_York")
    }
    private func hotel() -> HotelReservation {
        .init(place: .init(name: "Paris hotel", category: .hotel, city: "Paris"), checkIn: "2026-09-10", checkOut: "2026-09-14")
    }
    func testOverlapUsesKnownDurationsAndAllowsBackToBackPlans() {
        var d = trip(); d.events = [event(d,600,duration:60),event(d,630)]
        XCTAssertEqual(JourneyConflicts.detect(d).filter { $0.kind == .overlappingEvents }.count,1)
        d.events[1].minute=660; XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
        d.events[0].durationMinutes=nil; d.events[1].minute=610; XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
        d.events[1].minute=600; XCTAssertEqual(JourneyConflicts.detect(d).count,1)
        d.events[0].allDay=true; XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
    }
    func testOvernightOverlapAndResolutionAfterEdit() {
        var d = trip(); d.events=[event(d,1410,duration:90),event(d,30,day:1)]
        XCTAssertEqual(JourneyConflicts.detect(d).count,1)
        let warning = JourneyConflicts.detect(d)[0]; d.events.reverse()
        XCTAssertEqual(JourneyConflicts.detect(d)[0].id,warning.id)
        d.events[0].minute=60; XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
        d.events.removeAll(); XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
    }
    func testEventsInDifferentDestinationsCompareInstantsNotClockLabels() {
        var d=trip(); d.stops.append(.init(name:"New York",arrival:"2026-09-10",nights:2,timeZone:"America/New_York"))
        d.events=[event(d,15*60,duration:60),.init(stopID:d.stops[1].id,minute:9*60,kind:.meeting,title:"New York meeting",durationMinutes:60)]
        XCTAssertEqual(JourneyConflicts.detect(d).count,1)
        d.events[1].minute=15*60; XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
        d.stops[1].timeZone=nil; d.events[1].minute=9*60; XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
    }
    func testDinnerBeforeArrivalAndDifferentAirportExclusion() {
        var d=trip(); d.flights=[arrival()]; d.events=[event(d,19*60)]
        XCTAssertEqual(JourneyConflicts.detect(d).first?.kind,.beforeArrival)
        d.events[0].minute=20*60; XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
        d.events[0].minute=19*60; d.flights[0].arrivalLatitude=35.55; d.flights[0].arrivalLongitude=139.78
        XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
    }
    func testArrivalConversionAcrossMidnightAndMissingZones() {
        var d=trip(); d.flights=[arrival()]; d.flights[0].arrivalZone="UTC"; d.flights[0].arrivalTime="23:30"
        d.events=[event(d,60,day:1)]
        XCTAssertEqual(JourneyConflicts.detect(d).first?.kind,.beforeArrival)
        d.events[0].minute=90; XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
        d.stops[0].timeZone=nil; d.flights[0].arrivalZone=""; d.flights[0].arrivalTime="20:00"; d.events=[event(d,19*60)]
        XCTAssertEqual(JourneyConflicts.detect(d).first?.kind,.beforeArrival)
    }
    func testArrivalAfterMidnightFlagsPreviousEveningPlan() {
        var d=trip(); d.flights=[arrival()]; d.flights[0].arrivalDay="2026-09-11"; d.flights[0].arrivalTime="01:00"
        d.events=[event(d,19*60)]
        XCTAssertEqual(JourneyConflicts.detect(d).first?.kind,.beforeArrival)
    }
    func testLaterReturnFlightDoesNotInvalidatePlansAfterFirstArrival() {
        var d=trip(); var first=arrival(); first.arrivalTime="10:00"; d.flights=[first,arrival()]
        d.events=[event(d,19*60)]
        XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
    }
    func testHotelCheckoutDateAndExplicitTimeWithoutAssumedDeadline() {
        var d=trip(); d.hotels=[hotel()]; d.flights=[departure()]
        XCTAssertTrue(JourneyConflicts.detect(d).isEmpty) // No checkout hour has been recorded.
        d.hotels[0].checkOutTime="11:00"; XCTAssertEqual(JourneyConflicts.detect(d).first?.kind,.checkoutAfterFlight)
        d.hotels[0].checkOutTime="10:00"; XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
        d.hotels[0].checkOutTime=nil; d.flights=[departure("2026-09-13")]
        XCTAssertEqual(JourneyConflicts.detect(d).first?.kind,.checkoutAfterFlight)
        d.flights=[departure("2026-09-09")]; XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
        d.flights=[departure()]; d.hotels[0].checkOutTime="11:00"; d.flights[0].departureLatitude=40.64; d.flights[0].departureLongitude = -73.78
        XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
    }
    func testLocatedHotelDoesNotRequireAnAgendaStop() {
        var d=trip(); d.stops=[]; d.hotels=[hotel()]; d.hotels[0].place.latitude=48.85; d.hotels[0].place.longitude=2.35
        d.flights=[departure("2026-09-13")]
        XCTAssertEqual(JourneyConflicts.detect(d).first?.kind,.checkoutAfterFlight)
    }
    func testUnknownHotelLocationDoesNotAttachItToWrongFlight() {
        var d=trip(); d.hotels=[hotel()]; d.hotels[0].place.city="London"; d.hotels[0].checkOutTime="11:00"; d.flights=[departure()]
        XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
    }
    func testFlexiblePlansOnlyCompareRelativeEventsWithinOneStop() {
        var d=trip(); d.dateMode = .nights; d.flights=[arrival()]; d.hotels=[hotel()]; d.events=[event(d,600,duration:60),event(d,630)]
        XCTAssertEqual(JourneyConflicts.detect(d).map(\.kind),[.overlappingEvents])
        d.events[1].day=1; XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
    }
    func testInvalidClockAndDSTGapDoNotCreateWarnings() {
        XCTAssertNil(JourneyConflicts.minute("24:00")); XCTAssertNil(JourneyConflicts.minute("12:60")); XCTAssertEqual(JourneyConflicts.minute("9:30"),570)
        var d=trip(); d.stops[0].arrival="2026-03-29"; d.events=[event(d,150,duration:60),event(d,180)]
        XCTAssertTrue(JourneyConflicts.detect(d).isEmpty) // 02:30 does not exist in Paris that day.
        d.events[0].minute = -1; XCTAssertTrue(JourneyConflicts.detect(d).isEmpty)
    }
    func testCheckoutTimeLegacyRoundTripAndTemplatePrivacy() throws {
        var d=trip(); d.hotels=[hotel()]
        let old=try JSONDecoder().decode(JourneyDocument.self,from:JSONEncoder().encode(d)); XCTAssertNil(old.hotels[0].checkOutTime)
        d.hotels[0].checkOutTime="11:30"
        let restored=try JSONDecoder().decode(JourneyDocument.self,from:JSONEncoder().encode(d)); XCTAssertEqual(restored.hotels[0].checkOutTime,"11:30")
        XCTAssertNil(try d.templated(meta:.init()).hotels[0].checkOutTime)
        d.hotels[0].checkOutTime="25:00"; XCTAssertNotNil(d.validationError())
    }
}

@MainActor final class AccountSignInTests: XCTestCase {
    func testPKCEVerifierEntropyAndStandardChallengeVector() throws {
        let a=try AccountSignIn.randomToken(),b=try AccountSignIn.randomToken()
        XCTAssertEqual(a.count,43);XCTAssertNotEqual(a,b)
        XCTAssertNil(a.range(of:"[^A-Za-z0-9_-]",options:.regularExpression))
        XCTAssertEqual(AccountSignIn.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(AccountSignIn.nonceHash("abc"),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testCallbackRequiresExactRegisteredAppRouteAndSuccessfulCode() throws {
        XCTAssertEqual(try AccountSignIn.code(from:URL(string:"seur://auth/callback?code=hello")!),"hello")
        for value in ["https://auth/callback?code=hello","seur://evil/callback?code=hello","seur://auth/other?code=hello","seur://auth/callback?error=denied&code=hello","seur://auth/callback"] { XCTAssertThrowsError(try AccountSignIn.code(from:URL(string:value)!)) }
    }
    func testEmailAndProviderConfigurationDecoding() throws {
        XCTAssertTrue(AccountSignIn.validEmail("me@example.com"));XCTAssertFalse(AccountSignIn.validEmail("me@"));XCTAssertFalse(AccountSignIn.validEmail("me @example.com"))
        let options=try JSONDecoder().decode(AccountAuthOptions.self,from:Data(#"{"apple":true,"google":false,"email":true,"minimumPasswordLength":8}"#.utf8))
        XCTAssertEqual(options.minimumPasswordLength,8);XCTAssertFalse(options.google)
    }
}

private final class CutoverURLProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var reply: ((URLRequest) async throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in
            do {
                guard let reply = Self.reply else { throw URLError(.unsupportedURL) }
                let (status, data) = try await reply(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { }
}

@MainActor final class SupabaseCutoverTests: XCTestCase {
    private func client() -> (TravelAPI, URLSession, UserDefaults, String) {
        let suite = "seur-cutover-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("https://" + suite + ".invalid/functions/v1/travel-api", forKey: "aurum.backendURL")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CutoverURLProtocol.self]
        let session = URLSession(configuration: config)
        return (TravelAPI(session: session, defaults: defaults), session, defaults, suite)
    }
    func testSummaryListsCannotBeImportedThroughDetailEndpoint() async throws {
        let (api, session, defaults, suite) = client()
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite); CutoverURLProtocol.reply = nil }
        let remote = FriendsFixtures.remote
        CutoverURLProtocol.reply = { request in
            XCTAssertTrue(request.url!.path.hasPrefix("/functions/v1/travel-api/v1/"))
            return (200, try request.url!.path.hasSuffix("/documents") ? JSONEncoder().encode([remote]) : JSONEncoder().encode(remote))
        }
        let summaries = try await api.documents()
        XCTAssertEqual(summaries.first?.isSummary, true)
        do { _ = try await api.document(remote.id); XCTFail("A summary cannot stand in for a complete journey") }
        catch { XCTAssertTrue(error.localizedDescription.contains("full journey")) }
    }
    func testFullJourneyKeepsPhotoBytesAndImportsAsPrivateCopy() async throws {
        let (api, session, defaults, suite) = client()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite); CutoverURLProtocol.reply = nil; try? FileManager.default.removeItem(at: directory) }
        var remote = FriendsFixtures.remote
        remote.isSummary = nil // Deployed full responses omit the optional marker.
        remote.document.visibility = .friends
        let bytes = try XCTUnwrap(UIImage(systemName: "airplane")?.jpegData(compressionQuality: 0.8))
        let photo = JournalPhoto(jpeg: bytes)
        remote.document.places = [RatedPlace(place: PlaceRecord(name: "Paris dinner", category: .restaurant), photos: [photo])]
        let payload = try JSONEncoder().encode(remote)
        CutoverURLProtocol.reply = { _ in (200, payload) }
        let full = try await api.document(remote.id)
        XCTAssertEqual(full.document.places[0].photos[0], photo)
        let library = JourneyLibrary(url: directory.appendingPathComponent("journeys.json"))
        _ = try library.importData(JSONEncoder().encode(JourneyArchive(document: full.document)))
        let copy = try XCTUnwrap(library.documents.first)
        XCTAssertEqual(copy.visibility, .private); XCTAssertNotEqual(copy.id, remote.document.id)
        XCTAssertEqual(copy.places[0].photos[0].jpeg, bytes)
    }
    func testAccountDeletionFailureRetainsSessionAndSuccessClearsKeychainWithoutDeletingLocalTrips() async throws {
        let (api, session, defaults, suite) = client()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite); CutoverURLProtocol.reply = nil; try? FileManager.default.removeItem(at: directory) }
        let library = JourneyLibrary(url: directory.appendingPathComponent("journeys.json"))
        XCTAssertTrue(library.save(FriendsFixtures.trip))
        var failDeletion = true
        let auth = TravelAuthResponse(token: String(repeating: "a", count: 80), user: FriendsFixtures.owner)
        CutoverURLProtocol.reply = { request in
            if request.url!.path.hasSuffix("/auth/login") { return (200, try JSONEncoder().encode(auth)) }
            if request.url!.path.hasSuffix("/account") {
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + auth.token)
                return failDeletion ? (502, Data(#"{"error":"Photo cleanup failed. Retry."}"#.utf8)) : (200, Data(#"{"ok":true}"#.utf8))
            }
            if request.url!.path.hasSuffix("/status") { return (200, Data(#"{"tripadvisor":false,"ai":false,"publicSharing":true}"#.utf8)) }
            XCTFail("Deleted Keychain session must not request /me")
            return (401, Data(#"{"error":"Deleted account"}"#.utf8))
        }
        try await api.authenticate(handle: "tester", name: "Test", password: "eight888", register: false)
        do { try await api.deleteAccount(); XCTFail("Storage failure must be surfaced") } catch { }
        XCTAssertTrue(api.isSignedIn)
        failDeletion = false
        try await api.deleteAccount()
        XCTAssertFalse(api.isSignedIn); XCTAssertNil(api.account)
        let reopened = TravelAPI(session: session, defaults: defaults)
        try await reopened.refresh()
        XCTAssertFalse(reopened.isSignedIn)
        XCTAssertEqual(JourneyLibrary(url: directory.appendingPathComponent("journeys.json")).documents.count, 1)
    }
    func testResponseFromPreviousServerIsDiscarded() async throws {
        let (api, session, defaults, suite) = client()
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite); CutoverURLProtocol.reply = nil }
        var remote = FriendsFixtures.remote; remote.isSummary = nil
        let payload = try JSONEncoder().encode(remote)
        CutoverURLProtocol.reply = { _ in
            api.baseURL = "https://another-test-server.invalid"
            return (200, payload)
        }
        do { _ = try await api.document(remote.id); XCTFail("Old-server response must be discarded") }
        catch { XCTAssertTrue(error.localizedDescription.contains("account changed")) }
    }
    func testDelayedDeletionCannotSignOutAReplacementSession() async throws {
        let (api, session, defaults, suite) = client()
        defer { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite); CutoverURLProtocol.reply = nil }
        var loginCount = 0
        CutoverURLProtocol.reply = { request in
            if request.url!.path.hasSuffix("/auth/login") {
                loginCount += 1
                return (200, try JSONEncoder().encode(TravelAuthResponse(token: String(repeating: loginCount == 1 ? "a" : "b", count: 80), user: FriendsFixtures.owner)))
            }
            if request.url!.path.hasSuffix("/account") {
                // A different login finishes while the old DELETE is in flight.
                try await api.authenticate(handle: "tester", name: "Test", password: "eight888", register: false)
            }
            return (200, Data(#"{"ok":true}"#.utf8))
        }
        try await api.authenticate(handle: "tester", name: "Test", password: "eight888", register: false)
        do { try await api.deleteAccount(); XCTFail("Old DELETE must not clear a replacement session") }
        catch { XCTAssertTrue(error.localizedDescription.contains("account changed")) }
        XCTAssertTrue(api.isSignedIn)
        try await api.logout()
    }
}

@MainActor final class TripBudgetTests: XCTestCase {
    private let a = "00000000-0000-4000-8000-000000000001"
    private let b = "00000000-0000-4000-8000-000000000002"
    private let c = "00000000-0000-4000-8000-000000000003"
    private func trip() -> JourneyDocument {
        var trip = TodayFixtures.trip
        trip.companions = [.init(id: a, name: "Alex"), .init(id: b, name: "Blair"), .init(id: c, name: "Casey")]
        trip.homeCurrency = "USD"; trip.budgetTarget = 1000
        return trip
    }
    func testBudgetOptInSurvivesStorageAndIgnoresPricesAlone() throws {
        var document = TodayFixtures.trip
        document.homeCurrency = nil; document.budgetTarget = nil; document.companions = nil
        document.events[0].cost = .init(amount: 100, currency: "USD")
        document.events[0].isDone = true
        XCTAssertFalse(TripBudget.isConfigured(document))
        document.homeCurrency = "USD"
        let restored = try JSONDecoder().decode(JourneyDocument.self, from: JSONEncoder().encode(document))
        XCTAssertTrue(TripBudget.isConfigured(restored))
        document.homeCurrency = nil; document.budgetTarget = 500
        XCTAssertTrue(TripBudget.isConfigured(document), "Preserve older targets without a home currency")
        document.budgetTarget = nil; document.companions = [.init(id: a, name: "Alex")]
        XCTAssertTrue(TripBudget.isConfigured(document), "Existing companion settlements remain reachable")
    }
    func testDashboardLedgerMatchesTripTotalsAndPreservesActualRules() {
        var trip = trip()
        trip.events[0].cost = .init(amount: 40, currency: "EUR", isPaid: true)
        trip.events[0].isDone = false
        trip.events[1].cost = .init(amount: 25, currency: "USD", isPaid: false)
        trip.events[1].isDone = true; trip.events[1].kind = .shopping
        trip.hotels[0].cost = .init(amount: 300, currency: "USD", isPaid: true)
        trip.flights = [FlightReservation(cost: .init(amount: 80, currency: "EUR", isPaid: false))]
        let entries = BudgetLedger.entries(trip)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(Set(entries.map(\.id)).count, 4)
        XCTAssertEqual(BudgetLedger.totals(entries), trip.totals)
        XCTAssertEqual(BudgetLedger.totals(entries.filter(\.spent)), ["USD": 325])
        XCTAssertEqual(BudgetLedger.totals(entries.filter(\.spent)), TripBudget.spent(trip))
        XCTAssertEqual(entries.first { $0.source == .event(trip.events[1].id) }?.category, .shopping)
        XCTAssertEqual(entries.first { $0.source == .hotel(trip.hotels[0].id) }?.category, .stays)
        XCTAssertNil(TripBudget.converted(BudgetLedger.totals(entries), home: "USD", rates: nil))
        trip.dateMode = .nights
        XCTAssertTrue(BudgetLedger.entries(trip).allSatisfy { $0.date == nil })
    }
    func testDashboardCompanionBalancesConserveEachOriginalCurrency() {
        var trip = trip()
        trip.events[0].isDone = true; trip.events[1].isDone = true
        trip.events[0].cost = .init(amount: 10, currency: "EUR", paidBy: a, splitBetween: [a, b, c])
        trip.events[1].cost = .init(amount: 101, currency: "JPY", paidBy: b, splitBetween: [a, b, c])
        let balances = [a, b, c].map { BudgetLedger.balance($0, in: trip) }
        for currency in ["EUR", "JPY"] { XCTAssertEqual(balances.reduce(Decimal.zero) { $0 + ($1[currency] ?? 0) }, 0) }
        XCTAssertEqual(balances[0]["EUR"], Decimal(string: "6.66"))
        XCTAssertEqual(balances[1]["JPY"], 67)
        XCTAssertTrue(BudgetLedger.balance(UUID().uuidString, in: trip).isEmpty)
    }
    func testOnlyDoneEventsAndPaidBookingsCountAsSpent() {
        var trip = trip()
        trip.events[0].cost = .init(amount: 100, currency: "EUR")
        trip.events[1].cost = .init(amount: 50, currency: "EUR")
        trip.hotels[0].cost = .init(amount: 300, currency: "USD")
        XCTAssertTrue(TripBudget.spent(trip).isEmpty)
        trip.events[0].isDone = true; trip.hotels[0].cost?.isPaid = true
        XCTAssertEqual(TripBudget.spent(trip), ["EUR": 100, "USD": 300])
        XCTAssertEqual(trip.totals, ["EUR": 150, "USD": 300])
        let now = ISO8601DateFormatter().date(from: "2026-09-07T07:00:00Z")!
        let today = TodayPlanner.items(trip, day: "2026-09-07", zone: TimeZone(identifier: "Europe/Paris")!)
        XCTAssertTrue(today.first { $0.kind == .event }?.completed == true)
        XCTAssertNil(TodayPlanner.nextItem(today, now: now))
        trip.events[0].isDone = false
        XCTAssertEqual(TripBudget.spent(trip), ["USD": 300])
    }
    func testEqualSplitsConserveCentsAndDoNotConvertSettlements() {
        var trip = trip()
        trip.events[0].isDone = true; trip.events[1].isDone = true
        trip.events[0].cost = .init(amount: 10, currency: "EUR", paidBy: a, splitBetween: [c, b, a])
        trip.events[1].cost = .init(amount: 101, currency: "JPY", paidBy: a, splitBetween: [a, b, c])
        let transfers = TripBudget.settlements(trip)
        XCTAssertEqual(transfers.filter { $0.money.currency == "EUR" }.map(\.money.amount), [Decimal(string: "3.33")!, Decimal(string: "3.33")!])
        XCTAssertEqual(transfers.filter { $0.money.currency == "JPY" }.map(\.money.amount), [34, 33])
        XCTAssertTrue(transfers.allSatisfy { $0.to == a })
        trip.events[0].cost?.splitBetween = [a, b, c]
        XCTAssertEqual(TripBudget.settlements(trip), transfers)
    }
    func testPayerCanCoverOthersAndBalancesNetMultipleExpenses() {
        var trip = trip()
        trip.events[0].isDone = true; trip.events[1].isDone = true
        trip.events[0].cost = .init(amount: 10, currency: "USD", paidBy: a, splitBetween: [b, c])
        trip.events[1].cost = .init(amount: 6, currency: "USD", paidBy: b, splitBetween: [a, b, c])
        let transfers = TripBudget.settlements(trip)
        XCTAssertEqual(transfers, [.init(from: b, to: a, money: .init(amount: 1, currency: "USD")), .init(from: c, to: a, money: .init(amount: 7, currency: "USD"))])
        trip.events[1].isDone = false
        XCTAssertEqual(TripBudget.settlements(trip).map(\.money.amount), [5, 5])
    }
    func testConversionUsesCrossRatesAndNeverSilentlyDropsMissingCurrencies() {
        let rates = TripExchangeRates(base: "USD", rates: ["USD": 1, "EUR": Decimal(string: "0.8")!, "JPY": 100], dates: [:], fetchedAt: 0, stale: true)
        XCTAssertEqual(TripBudget.converted(["EUR": 80, "JPY": 10000], home: "USD", rates: rates), 200)
        XCTAssertEqual(TripBudget.converted(["USD": 100], home: "EUR", rates: rates), 80)
        XCTAssertNil(TripBudget.converted(["GBP": 100, "USD": 5], home: "USD", rates: rates))
        XCTAssertEqual(TripBudget.converted(["USD": 100], home: "USD", rates: nil), 100)
        XCTAssertEqual(TripBudget.converted([:], home: "USD", rates: nil), 0)
    }
    func testBurnDaysIncludeTodayAndCapAtTripEnd() {
        var trip = trip()
        let date = { (day: String) in ISO8601DateFormatter().date(from: day + "T12:00:00Z")! }
        XCTAssertNil(TripBudget.elapsedDays(trip, now: date("2026-09-05")))
        XCTAssertEqual(TripBudget.elapsedDays(trip, now: date("2026-09-06")), 1)
        XCTAssertEqual(TripBudget.elapsedDays(trip, now: date("2026-09-07")), 2)
        XCTAssertEqual(TripBudget.elapsedDays(trip, now: date("2026-10-01")), 4)
        trip.dateMode = .nights
        XCTAssertNil(TripBudget.elapsedDays(trip, now: date("2026-10-01")))
    }
    func testLedgerRoundTripRejectsDanglingSplitsAndLegacyTripsStillDecode() throws {
        var trip = trip(); trip.events[0].isDone = true
        trip.events[0].cost = .init(amount: 25, currency: "USD", paidBy: a, splitBetween: [a, b])
        XCTAssertNil(trip.validationError())
        let restored = try JSONDecoder().decode(JourneyDocument.self, from: JSONEncoder().encode(trip))
        XCTAssertEqual(restored, trip)
        trip.companions?.removeAll { $0.id == b }
        XCTAssertNotNil(trip.validationError())
        trip = self.trip(); trip.budgetTarget = -1
        XCTAssertNotNil(trip.validationError())
        let old = TodayFixtures.trip
        let legacy = try JSONDecoder().decode(JourneyDocument.self, from: JSONEncoder().encode(old))
        XCTAssertNil(legacy.budgetTarget); XCTAssertNil(legacy.companions); XCTAssertNil(legacy.events[0].isDone)
    }
    func testTemplatesDiscardLedgerAndRepeatedEventsDoNotCopyCompletion() throws {
        var trip = trip(); trip.events[0].isDone = true
        trip.events[0].cost = .init(amount: 25, currency: "USD", paidBy: a, splitBetween: [a, b])
        trip.hotels[0].cost = .init(amount: 100, currency: "USD", paidBy: a, splitBetween: [a, b], isPaid: true)
        let template = try trip.templated(meta: .init(), includeCosts: true)
        XCTAssertNil(template.companions); XCTAssertNil(template.budgetTarget)
        XCTAssertNil(template.events[0].isDone); XCTAssertNil(template.events[0].cost?.paidBy)
        XCTAssertNil(template.hotels[0].cost?.isPaid); XCTAssertEqual(template.events[0].cost?.amount, 25)
        let original = trip.events[0]
        trip.putEvent(original, on: [original.day, original.day + 1])
        XCTAssertEqual(trip.events.filter { $0.seriesID == original.seriesID && $0.isDone == true }.count, 1)
    }
}

@MainActor final class SeasonalityTests: XCTestCase {
    func city(_ name: String) throws -> CitySeasonality { try XCTUnwrap(SeasonalityCatalog.shared?.city(named: name)) }
    func assessment(_ name: String, _ from: String, _ to: String) throws -> SeasonalityAssessment {
        try XCTUnwrap(try city(name).assessment(arrival: from, departure: to))
    }
    func testBundledCatalogCoversEveryCatalogCityAndTwelveMonths() throws {
        let catalog = try XCTUnwrap(SeasonalityCatalog.shared)
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertNotNil(SeasonalityRange.date(catalog.reviewedOn))
        XCTAssertEqual(Set(catalog.cities.map(\.name)), Set(TravelStore.cities))
        XCTAssertEqual(catalog.cities.count, 12)
        XCTAssertEqual(Set(catalog.cities.map(\.id)).count, 12)
        for city in catalog.cities {
            XCTAssertEqual(city.months.map(\.month), Array(1...12), city.name)
            XCTAssertTrue(city.months.contains { $0.season == .peak })
            XCTAssertTrue(city.months.contains { $0.season == .shoulder })
            XCTAssertTrue(city.months.allSatisfy { !$0.weather.isEmpty && !$0.rain.isEmpty })
            XCTAssertFalse(city.notices.isEmpty); XCTAssertFalse(city.sources.isEmpty)
            XCTAssertEqual(Set(city.notices.map(\.id)).count, city.notices.count)
            for source in city.sources { XCTAssertEqual(source.url.scheme, "https"); XCTAssertNotNil(source.url.host) }
            for notice in city.notices {
                XCTAssertEqual(notice.source.scheme, "https")
                switch notice.timing {
                case .annual:
                    XCTAssertNotNil(SeasonalityRange.date("2000-" + (notice.start ?? "")))
                    XCTAssertNotNil(SeasonalityRange.date("2000-" + (notice.end ?? "")))
                case .dated:
                    XCTAssertFalse((notice.occurrences ?? []).isEmpty)
                    for range in notice.occurrences ?? [] {
                        let start = try XCTUnwrap(SeasonalityRange.date(range.start)), end = try XCTUnwrap(SeasonalityRange.date(range.end))
                        XCTAssertLessThanOrEqual(start, end)
                    }
                case .checkCalendar: XCTAssertNil(notice.start); XCTAssertNil(notice.end)
                }
            }
        }
    }
    func testCityMatchingHandlesAutocompleteAliasesWithoutSubstringFalsePositives() throws {
        let catalog = try XCTUnwrap(SeasonalityCatalog.shared)
        XCTAssertEqual(catalog.city(named: "  PARIS,   FRANCE  ", countryCode: "fr")?.id, "paris")
        XCTAssertEqual(catalog.city(named: "İstanbul")?.id, "istanbul")
        XCTAssertEqual(catalog.city(named: "Macao")?.id, "macau")
        XCTAssertEqual(catalog.city(named: "Paris, Île-de-France, France", countryCode: "FR")?.id, "paris")
        XCTAssertNil(catalog.city(named: "Paris Hotel, Île-de-France, France", countryCode: "FR"))
        XCTAssertEqual(catalog.city(named: "New York, NY")?.id, "new-york")
        XCTAssertNil(catalog.city(named: "Paris", countryCode: "US"))
        for name in ["Paris, Texas", "Paris Hotel Las Vegas", "France", "", "Amsterdam", "London, Ontario"] { XCTAssertNil(catalog.city(named: name), name) }
    }
    func testAugustClosureIncludesArrivalAndDepartureBoundaries() throws {
        for dates in [("2026-07-30", "2026-08-01"), ("2026-08-31", "2026-09-02"), ("2026-08-15", "2026-08-15")] {
            XCTAssertTrue(try assessment("Paris", dates.0, dates.1).advisories.contains { $0.id == "paris-august" })
        }
        XCTAssertFalse(try assessment("Paris", "2026-09-01", "2026-09-04").advisories.contains { $0.id == "paris-august" })
    }
    func testAllTouchedMonthsIncludingYearBoundaryAppearInTravelOrder() throws {
        XCTAssertEqual(try assessment("Paris", "2026-07-30", "2026-09-01").months.map(\.month), [7, 8, 9])
        XCTAssertEqual(try assessment("Tokyo", "2026-12-30", "2027-01-04").months.map(\.month), [12, 1])
        XCTAssertEqual(try assessment("Paris", "2026-01-01", "2027-01-01").months.count, 12)
    }
    func testAnnualNewYearWindowMatchesJanuaryAndDecemberOnly() throws {
        for dates in [("2026-12-30", "2027-01-02"), ("2027-01-01", "2027-01-03")] {
            XCTAssertTrue(try assessment("Tokyo", dates.0, dates.1).advisories.contains { $0.id == "tokyo-new-year" })
        }
        XCTAssertFalse(try assessment("Tokyo", "2027-06-01", "2027-06-05").advisories.contains { $0.id == "tokyo-new-year" })
    }
    func testGoldenWeekMatchesAcrossMonthBoundary() throws {
        XCTAssertTrue(try assessment("Tokyo", "2027-04-28", "2027-05-02").advisories.contains { $0.id == "tokyo-golden-week" })
        XCTAssertFalse(try assessment("Tokyo", "2027-05-10", "2027-05-15").advisories.contains { $0.id == "tokyo-golden-week" })
    }
    func testLunarHolidayUsesPublishedYearAndObservedDays() throws {
        let match = try assessment("Hong Kong", "2027-02-09", "2027-02-10").advisories.first { $0.id == "hong-kong-lunar-new-year" }
        XCTAssertNotNil(match); XCTAssertNil(match?.calendarPrompt)
        XCTAssertFalse(try assessment("Hong Kong", "2027-02-17", "2027-02-19").advisories.contains { $0.id == "hong-kong-lunar-new-year" })
        let unknown = try assessment("Hong Kong", "2028-02-17", "2028-02-19").advisories.first { $0.id == "hong-kong-lunar-new-year" }
        XCTAssertEqual(unknown?.unverifiedYears, [2028])
    }
    func testRamadanNeverReusesPriorGregorianDates() throws {
        let known = try assessment("Istanbul", "2026-03-01", "2026-03-04").advisories.first { $0.id == "istanbul-ramadan" }
        XCTAssertNotNil(known); XCTAssertNil(known?.calendarPrompt)
        XCTAssertFalse(try assessment("Istanbul", "2026-06-01", "2026-06-04").advisories.contains { $0.id == "istanbul-ramadan" })
        let unknown = try assessment("Istanbul", "2027-03-01", "2027-03-04").advisories.first { $0.id == "istanbul-ramadan" }
        XCTAssertEqual(unknown?.unverifiedYears, [2027])
        let crossing = try assessment("Istanbul", "2026-12-30", "2027-01-02").advisories.first { $0.id == "istanbul-ramadan" }
        XCTAssertEqual(crossing?.unverifiedYears, [2027])
        XCTAssertEqual(try assessment("Dubai", "2027-01-01", "2027-01-04").advisories.first { $0.id == "dubai-ramadan" }?.unverifiedYears, [2027])
    }
    func testFlexibleAndInvalidDatesDoNotInventSelectedMonth() throws {
        let paris = try city("Paris")
        XCTAssertNil(paris.assessment(arrival: nil, departure: nil))
        for dates in [("2026-02-30", "2026-03-02"), ("2026-09-02", "2026-09-01"), ("2026-9-01", "2026-09-03"), ("2026-01-01", "9999-01-01")] { XCTAssertNil(paris.assessment(arrival: dates.0, departure: dates.1)) }
    }
    func testRouteReorderReassessesProjectedDatesWithoutMutatingOriginal() throws {
        let paris = JourneyStop(name: "Paris", arrival: "2026-08-28", nights: 2, latitude: 48.8566, longitude: 2.3522)
        let london = JourneyStop(name: "London", arrival: "2026-08-30", nights: 5, latitude: 51.5074, longitude: -0.1278)
        let trip = JourneyDocument(title: "Seasons", startDate: paris.arrival, endDate: london.departure, stops: [paris, london])
        let preview = try MultiCityRouting.applying([london, paris], plan: JourneyRoutePlan(), to: trip)
        let projected = try XCTUnwrap(preview.stops.first { $0.id == paris.id })
        XCTAssertEqual(projected.arrival, "2026-09-02")
        XCTAssertTrue(try assessment("Paris", paris.arrival, paris.departure).advisories.contains { $0.id == "paris-august" })
        XCTAssertFalse(try assessment("Paris", projected.arrival, projected.departure).advisories.contains { $0.id == "paris-august" })
        XCTAssertEqual(trip.stops.first?.arrival, "2026-08-28")
    }
}

@MainActor final class JourneyWidgetTests: XCTestCase {
    func testWidgetInvitationWaitsForATripAndPersistsDismissal() {
        let suite = "WidgetDiscoveryTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let discovery = WidgetDiscovery(defaults: defaults)
        XCTAssertFalse(discovery.shouldOffer(for: []))
        var trip = TodayFixtures.trip
        trip.isTemplate = true
        XCTAssertFalse(discovery.shouldOffer(for: [trip]))
        trip.isTemplate = nil; trip.dateMode = .nights
        XCTAssertFalse(discovery.shouldOffer(for: [trip]))
        trip.dateMode = .dates
        XCTAssertTrue(discovery.shouldOffer(for: [trip]))
        discovery.markHandled()
        XCTAssertFalse(discovery.shouldOffer(for: [trip]))
        XCTAssertFalse(WidgetDiscovery(defaults: defaults).shouldOffer(for: [trip, TodayFixtures.trip]))
        XCTAssertTrue(WidgetDiscovery(defaults: defaults).handled)
    }

    func instant(_ day: String, _ hour: Int = 12, zone: String = "UTC") -> Date { WidgetCalendar.calendar(zone).date(byAdding: .hour, value: hour, to: WidgetCalendar.date(day, zone: zone)!)! }
    func trip(_ start: String = "2026-09-08", zone: String = "Europe/Paris") -> JourneyDocument {
        let stop = JourneyStop(name: "Paris", arrival: start, nights: 3, timeZone: zone)
        return JourneyDocument(title: "Paris plans", startDate: start, endDate: stop.departure, stops: [stop])
    }
    func testProjectionExcludesUndatedTemplatesAndPastTrips() {
        let current = trip(), future = trip("2026-10-01"), past = trip("2026-08-01")
        var flexible = trip(); flexible.dateMode = .nights
        var template = trip(); template.isTemplate = true
        let snapshot = JourneyWidgetProjection.make([past, template, flexible, future, current], now: instant("2026-09-08"))
        XCTAssertEqual(Set(snapshot.trips.map(\.id)), Set([current.id, future.id]))
        XCTAssertEqual(snapshot.active(at: instant("2026-09-08"))?.id, current.id)
        XCTAssertEqual(snapshot.upcoming(at: instant("2026-09-08"))?.id, future.id)
    }
    func testActiveSelectionAgreesWithTodayAcrossTimeZones() throws {
        let current = trip("2026-09-09", zone: "Asia/Tokyo"), date = instant("2026-09-08", 16)
        let snapshot = JourneyWidgetProjection.make([current], now: date, fallback: TimeZone(identifier: "America/New_York")!)
        XCTAssertTrue(TodayPlanner.isActive(current, now: date))
        let widget = try XCTUnwrap(snapshot.active(at: date))
        XCTAssertEqual(widget.localDay(at: date), "2026-09-09")
        XCTAssertEqual(widget.zone(at: date), "Asia/Tokyo")
        XCTAssertEqual(widget.daysUntil(date), 0)
    }
    func testItemsAdvanceAtTheirEndAndSkipDonePlansWithoutLeakingNotes() throws {
        var document = trip(zone: "UTC")
        var done = JourneyEvent(stopID: document.stops[0].id, place: PlaceRecord(name: "Already done")); done.minute = 900; done.isDone = true
        var next = JourneyEvent(stopID: document.stops[0].id, place: PlaceRecord(name: "Museum"), description: "PRIVATE NOTE"); next.minute = 780; next.durationMinutes = 60
        document.events = [done, next]
        document.hotels = [HotelReservation(place: PlaceRecord(name: "Hotel", category: .hotel), checkIn: "2026-09-08", checkOut: "2026-09-11", confirmation: "SECRET-BOOKING", notes: "PRIVATE HOTEL NOTE")]
        let snapshot = JourneyWidgetProjection.make([document], now: instant("2026-09-08")), widget = try XCTUnwrap(snapshot.trips.first)
        XCTAssertEqual(widget.remaining(at: instant("2026-09-08")).first?.title, "Museum")
        XCTAssertFalse(widget.items(at: instant("2026-09-08")).contains { $0.title == "Already done" })
        XCTAssertFalse(widget.remaining(at: instant("2026-09-08", 15)).contains { $0.title == "Museum" })
        XCTAssertTrue(widget.remaining(at: instant("2026-09-08", 15)).contains { $0.title == "Check in · Hotel" && $0.start == nil })
        let json = String(data: try JSONEncoder().encode(snapshot), encoding: .utf8)!
        for value in ["PRIVATE NOTE", "SECRET-BOOKING", "PRIVATE HOTEL NOTE", "jpeg", "password", "splitBetween"] { XCTAssertFalse(json.contains(value)) }
    }
    func testBudgetUsesDoneAndPaidCostsAndSavedFX() throws {
        var document = trip(); document.homeCurrency = "EUR"; document.budgetTarget = 600
        var event = JourneyEvent(stopID: document.stops[0].id, place: PlaceRecord(name: "Lunch"), cost: TravelMoney(amount: 100, currency: "USD")); event.isDone = true
        document.events = [event, JourneyEvent(stopID: document.stops[0].id, cost: TravelMoney(amount: 200, currency: "EUR"))]
        let date = instant("2026-09-09"), rates = TripExchangeRates(base: "USD", rates: ["USD": 1, "EUR": Decimal(string: "0.9")!], dates: ["EUR": "2026-09-07"], fetchedAt: date.timeIntervalSince1970, stale: true)
        let widget = try XCTUnwrap(JourneyWidgetProjection.make([document], now: date, rates: rates).trips.first)
        XCTAssertEqual(widget.spent, 90); XCTAssertEqual(widget.target, 600); XCTAssertEqual(widget.burnRate(at: date), 45)
        XCTAssertEqual(widget.rateDate, "2026-09-07")
        XCTAssertNil(JourneyWidgetProjection.make([document], now: date).trips.first?.spent)
    }
    func testCountdownAndBurnRateUseCalendarDaysAcrossDST() throws {
        let zone = "America/New_York", date = instant("2026-03-07", 23, zone: zone)
        let document = trip("2026-03-09", zone: zone)
        let widget = try XCTUnwrap(JourneyWidgetProjection.make([document], now: date).trips.first)
        XCTAssertEqual(widget.daysUntil(date), 2)
        var active = try XCTUnwrap(JourneyWidgetProjection.make([trip("2026-03-07", zone: zone)], now: date).trips.first)
        active.spent = 300
        XCTAssertEqual(active.burnRate(at: instant("2026-03-09", 1, zone: zone)), 100)
    }
    func testTimelineContainsEventBoundaryMidnightAndExpiryWithBoundedSize() throws {
        let date = instant("2026-09-08", 22), end = date.addingTimeInterval(600)
        var snapshot = JourneyWidgetSample.make(now: date)
        snapshot.trips[0].days[0].items[0].end = end
        snapshot.expiresAt = date.addingTimeInterval(1200)
        let dates = snapshot.refreshDates(after: date)
        XCTAssertEqual(dates.first, date); XCTAssertTrue(dates.contains(end.addingTimeInterval(1))); XCTAssertTrue(dates.contains(snapshot.expiresAt))
        XCTAssertEqual(Set(dates).count, dates.count); XCTAssertLessThanOrEqual(dates.count, 48)
        XCTAssertNil(snapshot.active(at: snapshot.expiresAt)); XCTAssertNil(snapshot.upcoming(at: snapshot.expiresAt))
        var utc = JourneyWidgetProjection.make([trip(zone: "UTC")], now: date)
        utc.expiresAt = date.addingTimeInterval(86400)
        XCTAssertTrue(utc.refreshDates(after: date).contains(instant("2026-09-09", 0)))
    }
    func testAtomicSnapshotReplacementRemovalAndCorruptData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), url = directory.appendingPathComponent("widget.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = instant("2026-09-08")
        try JourneyWidgetStore.write(JourneyWidgetProjection.make([trip()], now: date), to: url)
        XCTAssertEqual(JourneyWidgetStore.read(from: url)?.trips.count, 1)
        try JourneyWidgetStore.write(JourneyWidgetProjection.make([], now: date), to: url)
        XCTAssertTrue(try XCTUnwrap(JourneyWidgetStore.read(from: url)).trips.isEmpty)
        try Data("corrupt".utf8).write(to: url); XCTAssertNil(JourneyWidgetStore.read(from: url))
        var incompatible = JourneyWidgetProjection.make([], now: date); incompatible.version = 2
        try JourneyWidgetStore.write(incompatible, to: url); XCTAssertNil(JourneyWidgetStore.read(from: url))
    }
    func testDeepLinksAreExactAndRoundTripAllWidgetKinds() {
        let id = UUID()
        for kind in JourneyWidgetKind.allCases where kind != .profile { let link = JourneyWidgetLink(tripID: id, kind: kind); XCTAssertEqual(JourneyWidgetLink(url: link.url), link) }
        for value in ["https://trip/\(id)?widget=SeurToday", "seur://trip/no-id?widget=SeurToday", "seur://trip/\(id)?widget=other", "seur://trip/\(id)/extra?widget=SeurToday", "seur://flights"] { XCTAssertNil(JourneyWidgetLink(url: URL(string: value)!)) }
    }
    func testDisplayEntriesRetainOnlySelectedTripsAndCurrentDay() throws {
        let date = instant("2026-09-08")
        var snapshot = JourneyWidgetProjection.make([trip(), trip("2026-09-20"), trip("2026-10-01")], now: date)
        snapshot.trips[0].days = [.init(key: "2026-09-08", zone: "Europe/Paris", items: []), .init(key: "2026-09-09", zone: "Europe/Paris", items: [])]
        let displayed = snapshot.displaySnapshot(at: date)
        XCTAssertEqual(displayed.trips.count, 2)
        XCTAssertEqual(displayed.active(at: date)?.days.map(\.key), ["2026-09-08"])
        XCTAssertEqual(displayed.upcoming(at: date)?.startDay, "2026-09-20")
        XCTAssertTrue(snapshot.displaySnapshot(at: snapshot.expiresAt).trips.isEmpty)
    }
    func testProfileUsesWholeHistoryAndMatchesStatistics() throws {
        let date = instant("2026-09-08")
        var past = trip("2026-08-01"); past.stops[0].countryCode = "FR"; past.title = "Summer in Paris"
        var duplicate = past; duplicate.updatedAt = past.updatedAt - 1; duplicate.title = "Old title"
        var template = trip("2026-07-01"); template.isTemplate = true
        var flexible = trip(); flexible.dateMode = .nights
        let future = (0..<15).map { trip(TravelDay.adding($0 * 4, to: "2026-10-01")) }
        let documents = future + [past, duplicate, template, flexible]
        let snapshot = JourneyWidgetProjection.make(documents, now: date)
        let profile = try XCTUnwrap(snapshot.travelProfile(at: date))
        let stats = TravelStatistics(documents: documents, now: date).summary()
        XCTAssertEqual(snapshot.trips.count, 12)
        XCTAssertEqual(profile.trips, 1); XCTAssertEqual(profile.countries, 1); XCTAssertEqual(profile.cities, 1)
        XCTAssertEqual(profile.trips, stats.trips); XCTAssertEqual(profile.nights, stats.nightsAway)
        XCTAssertEqual(profile.nightsLabel, stats.nightsLabel); XCTAssertEqual(profile.stars, stats.stars)
        XCTAssertEqual(profile.recent.map(\.title), ["Summer in Paris"])
        XCTAssertEqual(profile.recent.first?.endDay, "2026-08-04")
        XCTAssertEqual(snapshot.displaySnapshot(at: date).profile, profile)
        let historyOnly = JourneyWidgetProjection.make([past], now: date)
        XCTAssertTrue(historyOnly.trips.isEmpty)
        XCTAssertEqual(historyOnly.displaySnapshot(at: date).travelProfile(at: date)?.trips, 1)
        XCTAssertEqual(JourneyWidgetProjection.make([], now: date).profile?.trips, 0)
    }
    func testProfileRecentTripsRespectDestinationDateAndStayBounded() throws {
        let date = instant("2026-09-08", 16)
        let paris = trip("2026-09-05", zone: "Europe/Paris")
        let tokyo = trip("2026-09-05", zone: "Asia/Tokyo")
        let past = (1...5).map { trip("2026-08-0\($0)") }
        let profile = try XCTUnwrap(JourneyWidgetProjection.make(past + [paris, tokyo], now: date).profile)
        XCTAssertEqual(profile.recent.count, 3)
        XCTAssertEqual(profile.recent.map(\.endDay), ["2026-09-08", "2026-08-08", "2026-08-07"])
    }
    func testProfileLegacyCacheExpiryAndDedicatedLink() throws {
        let date = instant("2026-09-08"), snapshot = JourneyWidgetSample.make(now: date)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        json.removeValue(forKey: "profile")
        let legacy = try JSONDecoder().decode(JourneyWidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.profile); XCTAssertEqual(legacy.trips.count, 2)
        XCTAssertNil(snapshot.travelProfile(at: snapshot.expiresAt))
        var incompatible = snapshot; incompatible.version = 2
        XCTAssertNil(incompatible.travelProfile(at: date))
        XCTAssertEqual(JourneyWidgetContent(snapshot: snapshot, date: date, kind: .profile).link, JourneyWidgetProfile.url)
        XCTAssertEqual(JourneyWidgetContent(snapshot: nil, date: date, kind: .profile).link, JourneyWidgetProfile.url)
        XCTAssertTrue(JourneyWidgetProfile.matches(URL(string: "seur://profile")!))
        for value in ["https://profile", "seur://profile/extra", "seur://profile?trip=abc", "seur://trip/\(UUID())?widget=SeurTravelProfile"] {
            XCTAssertFalse(JourneyWidgetProfile.matches(URL(string: value)!))
            XCTAssertNil(JourneyWidgetLink(url: URL(string: value)!))
        }
    }
    func testWidgetAlternateAppearancesRender() throws {
        let date = instant("2026-09-08"), sample = JourneyWidgetSample.make(now: date)
        var busy = sample
        busy.trips[0].title = "A long weekend discovering the French Riviera"
        busy.trips[0].stops[0].name = "Aix-en-Provence"
        let item = busy.trips[0].days[0].items[0]
        busy.trips[0].days[0].items = (0..<6).map { index in
            var next = item; next.id = "event-\(index)"; next.title = "Private tour of the gardens and historic art collection"; return next
        }
        var over = sample; over.trips[0].spent = 2400
        var missing = sample; missing.trips[0].spent = nil; missing.trips[0].originalSpent = "€460 · ¥12,500"
        var expired = sample; expired.expiresAt = date
        let variants: [(String, JourneyWidgetSnapshot, ColorScheme, WidgetRenderingMode)] = [
            ("Dark", sample, .dark, .fullColor), ("Empty", JourneyWidgetProjection.make([], now: date), .light, .fullColor),
            ("Tinted", sample, .light, .accented), ("Long itinerary", busy, .light, .fullColor),
            ("Expired", expired, .dark, .fullColor)
        ]
        for (label, snapshot, scheme, mode) in variants {
            for kind in JourneyWidgetKind.allCases {
                let large = label == "Long itinerary" && kind == .today
                let family: WidgetFamily = large ? .systemLarge : label == "Dark" || label == "Tinted" ? .systemMedium : .systemSmall
                let width: CGFloat = family == .systemSmall ? 170 : 360, height: CGFloat = large ? 390 : 170
                let view = JourneyWidgetContent(snapshot: snapshot, date: date, kind: kind, previewFamily: family)
                    .padding(16).frame(width: width, height: height).background { JourneyWidgetBackground(kind: kind) }
                    .background(Color(uiColor: .systemBackground)).environment(\.colorScheme, scheme).environment(\.widgetRenderingMode, mode)
                let renderer = ImageRenderer(content: view); renderer.scale = 2
                let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage)); attachment.name = "\(label) \(kind.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        for (label, snapshot) in [("Over target", over), ("Missing FX", missing)] {
            let view = JourneyWidgetContent(snapshot: snapshot, date: date, kind: .budget, previewFamily: .systemSmall)
                .padding(16).frame(width: 170, height: 170).background { JourneyWidgetBackground(kind: .budget) }.environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage)); attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
        }
        let attributes = FlightActivityAttributes(watchID: "preview", flightNumber: "BA178", origin: "JFK", destination: "LHR")
        let state = FlightActivityAttributes.ContentState(status: "En route", departure: date.addingTimeInterval(-3600).timeIntervalSince1970, arrival: date.addingTimeInterval(3600).timeIntervalSince1970, departureTime: "08:10 EDT", arrivalTime: "20:05 BST", gate: "B32", terminal: "5", delayMinutes: 15, phase: "airborne", updatedAt: date.timeIntervalSince1970)
        let view = SeurFlightWidgetCard(attributes: attributes, state: state, stale: false, date: date).frame(width: 360)
        let renderer = ImageRenderer(content: view); renderer.scale = 2
        let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage)); attachment.name = "Flight Live Activity"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testWidgetLayoutsRenderAllSupportedShapes() throws {
        let date = instant("2026-09-08"), snapshot = JourneyWidgetSample.make(now: date)
        let shapes: [(JourneyWidgetKind, WidgetFamily, CGFloat, CGFloat)] = [(.profile, .systemSmall, 170, 170), (.profile, .systemMedium, 360, 170), (.profile, .systemLarge, 360, 390), (.today, .systemSmall, 170, 170), (.today, .systemMedium, 360, 170), (.today, .systemLarge, 360, 390), (.nextTrip, .systemSmall, 170, 170), (.nextTrip, .systemMedium, 360, 170), (.budget, .systemSmall, 170, 170), (.budget, .systemMedium, 360, 170), (.today, .accessoryRectangular, 160, 80), (.nextTrip, .accessoryCircular, 76, 76)]
        for (kind, family, width, height) in shapes {
            let padding: CGFloat = family == .accessoryRectangular || family == .accessoryCircular ? 0 : 16
            let content = JourneyWidgetContent(snapshot: snapshot, date: date, kind: kind, previewFamily: family).padding(padding).frame(width: width, height: height).background {
                if padding == 0 { Color(uiColor: .systemBackground) } else { JourneyWidgetBackground(kind: kind) }
            }.environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content); renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width); XCTAssertEqual(image.size.height, height)
            let attachment = XCTAttachment(image: image); attachment.name = "Widget \(kind.rawValue) \(family)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
