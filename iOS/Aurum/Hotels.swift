import SwiftUI
import MapKit
import Observation

/// Provider identifiers stay separate from the bundled dining collection.
struct LodgingHotel: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var city: String
    var country: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var stars: Double?
    var rating: Double?
    var reviewCount: Int?
    var photo: String?
    var source = "LiteAPI / Nuitée"
    /// Provider aggregate, never an average of the currently loaded review page.
    var guestRating: Double? {
        guard let rating, rating.isFinite, (0...10).contains(rating), reviewCount != 0 else { return nil }
        return rating
    }
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }
    var place: PlaceRecord { .init(id: id, name: name, category: .hotel, city: city, address: address, latitude: latitude, longitude: longitude, source: source) }
    var idea: WishlistIdea { .init(id: id, name: name, destination: city, kind: .stays, selectedPlace: place) }
    var wishlistEntry: WishlistEntry { .init(id: "idea:" + id, source: .idea(idea), place: place, kind: .stays) }
    static let collectionLinks = ["lon-savoy": "liteapi:lp2a32f", "par-peninsula": "liteapi:lp7246c", "bkk-mandarin-oriental": "liteapi:lp1aae8"]
    static func bookmark(_ place: PlaceRecord) -> Self { .init(id: place.id, name: place.name, city: place.city, country: "", address: place.address, latitude: place.latitude, longitude: place.longitude) }
}
struct LodgingPhoto: Codable, Hashable, Identifiable { var url: String; var caption: String; var id: String { url } }
struct LodgingRoom: Codable, Identifiable { var id: String; var name: String; var description: String; var photos: [LodgingPhoto]; var maxOccupancy: Int?; var size: Double?; var sizeUnit: String }
struct LodgingDetail: Codable { var hotel: LodgingHotel; var description: String; var importantInformation: String; var photos: [LodgingPhoto]; var facilities: [String]; var rooms: [LodgingRoom]; var environment: String }
struct LodgingReview: Codable, Identifiable { var id: String; var name: String; var date: String; var rating: Double?; var headline: String; var pros: String; var cons: String; var source: String; var travelerType: String }
struct LodgingReviewPage: Codable { var reviews: [LodgingReview]; var nextOffset: Int?; var totalRecords: Int? }
struct LodgingPage: Codable { var hotels: [LodgingHotel]; var nextOffset: Int?; var environment: String }

struct HotelResultFilters: Equatable {
    var minimumPrice: Double? = nil
    var maximumPrice: Double? = nil
    var minimumStars = 0
    var minimumRating = 0
    var minimumReviews = 0
    var maximumDistanceKM = 0
    var breakfast = false
    var freeCancellation = false
    var availableOnly = false
    var photosOnly = false
    var needsRates: Bool { minimumPrice != nil || maximumPrice != nil || breakfast || freeCancellation || availableOnly }
    var active: Bool { self != Self() }
    func matches(_ hotel: LodgingHotel, destination: ExploreCity?) -> Bool {
        if minimumStars > 0 && (hotel.stars ?? -1) < Double(minimumStars) { return false }
        if minimumRating > 0 && (hotel.guestRating ?? -1) < Double(minimumRating) { return false }
        if minimumReviews > 0 && (hotel.reviewCount ?? 0) < minimumReviews { return false }
        if photosOnly && (hotel.photo?.isEmpty != false) { return false }
        if maximumDistanceKM > 0 {
            guard let destination, let coordinate = hotel.coordinate else { return false }
            let distance = CLLocation(latitude: destination.latitude, longitude: destination.longitude).distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if distance > Double(maximumDistanceKM) * 1000 { return false }
        }
        return true
    }
    func matches(_ offer: HotelRateOffer, currency: String) -> Bool {
        guard !offer.expired else { return false }
        if breakfast && !offer.breakfast { return false }
        if freeCancellation && !offer.freeCancellationAvailable { return false }
        if minimumPrice != nil || maximumPrice != nil {
            guard let total = offer.total, total.currency == currency, let amount = total.decimal else { return false }
            if let minimumPrice, amount < Decimal(minimumPrice) { return false }
            if let maximumPrice, amount > Decimal(maximumPrice) { return false }
        }
        return true
    }
}

@MainActor @Observable final class HotelSearchModel {
    var stay = HotelStayPreferences() { didSet { if oldValue != stay { rates.clear() }; if oldValue.currency != stay.currency { filters.minimumPrice = nil; filters.maximumPrice = nil }; if !stay.ratesReady { filters.minimumPrice = nil; filters.maximumPrice = nil; filters.breakfast = false; filters.freeCancellation = false; filters.availableOnly = false } } }
    var filters = HotelResultFilters()
    var rates = HotelRateModel()
    var rateSearchEnabled = false
    var sortByPrice = false
    // The current provider integration is sandbox-only. This is a test guest,
    // not an inference about the traveler. Production must use saved nationality.
    init() { stay.guestNationality = "US" }
    var destination: ExploreCity?
    var query = ""
    var hotelName = ""
    var stars = ""
    var score = ""
    var sortByName = false
    var hotels: [LodgingHotel] = []
    var nextOffset: Int?
    var loading = false
    var searched = false
    var error: String?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    func matchingRate(for hotel: LodgingHotel) -> HotelRateResult? {
        guard rates.criteria == HotelRateCriteria(stay), !rates.expired, let result = rates.results[hotel.id] else { return nil }
        return HotelRateResult(hotelId: hotel.id, offers: result.offers.filter { filters.matches($0, currency: stay.currency) }, status: result.status)
    }
    var results: [LodgingHotel] {
        let values = hotels.filter { hotel in
            filters.matches(hotel, destination: destination) && (!filters.needsRates || matchingRate(for: hotel)?.offers.isEmpty == false)
        }
        if sortByPrice {
            return values.sorted { a, b in
                let av = matchingRate(for: a)?.offers.first?.total?.decimal, bv = matchingRate(for: b)?.offers.first?.total?.decimal
                if let av, let bv, av != bv { return av < bv }
                if (av != nil) != (bv != nil) { return av != nil }
                return a.id < b.id
            }
        }
        return sortByName ? values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : values
    }
    func clear() {
        rates.clear(); rateSearchEnabled = false; task?.cancel(); generation = UUID(); hotels = []; nextOffset = nil; searched = false; loading = false; error = nil
    }
    func select(_ city: ExploreCity, api: TravelAPI) { rateSearchEnabled = false; destination = city; query = city.name; search(api: api) }
    func search(api: TravelAPI, more: Bool = false) {
        guard let destination, !more || (!loading && nextOffset != nil) else { return }
        task?.cancel(); let requestID = UUID(); generation = requestID
        let skip = more ? nextOffset! : 0, name = hotelName, stars = stars, score = score
        if !more { hotels = []; nextOffset = nil; rates.clear() }
        loading = true; error = nil; searched = true
        task = Task {
            defer { if generation == requestID { loading = false } }
            do {
                let page = try await api.hotelSearch(city: destination, name: name, stars: stars, score: score, offset: skip)
                try Task.checkCancellation(); guard generation == requestID else { return }
                var seen = Set(hotels.map(\.id)); hotels += page.hotels.filter { seen.insert($0.id).inserted }
                nextOffset = page.nextOffset
                if rateSearchEnabled { rates.load(hotelIDs: page.hotels.map(\.id), stay: stay, api: api, more: more) }
            } catch { if generation == requestID && !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func refreshRates(api: TravelAPI) {
        rateSearchEnabled = true
        rates.load(hotelIDs: Array(hotels.prefix(20)).map(\.id), stay: stay, api: api)
    }
}

extension TravelStore {
    func isHotelSaved(_ hotel: LodgingHotel) -> Bool {
        if let legacyID = LodgingHotel.collectionLinks.first(where: { $0.value == hotel.id })?.key, saved.contains(legacyID) { return true }
        return wishlist.ideas.contains { $0.id == hotel.id }
    }
    func toggleHotelSave(_ hotel: LodgingHotel) {
        if let legacyID = LodgingHotel.collectionLinks.first(where: { $0.value == hotel.id })?.key, let legacy = hotels.first(where: { $0.id == legacyID }) { toggleSave(legacy); return }
        if isHotelSaved(hotel) { _ = wishlist.remove("idea:" + hotel.id) }
        else if !wishlist.saveIdea(hotel.idea, details: WishlistDetails()) { showMessage(wishlist.error ?? "Couldn’t save this hotel.") }
    }
}

/// Hotel tests never contact the provider; content is deliberately identifiable as a fixture.
@MainActor enum HotelFixtures {
    static var enabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--hotel-testing") && PlaceSearchTestPolicy.blocksPaidRequests
        #else
        false
        #endif
    }
    static func hotel(_ index: Int = 0) -> LodgingHotel {
        .init(id: "liteapi:lpfixture\(index)", name: index == 0 ? "Palazzo Testa · Test hotel" : "Roman Retreat \(index + 1)", city: "Rome", country: "IT", address: "Via Nazionale, Rome", latitude: 41.9008 + Double(index / 5) * 0.004, longitude: 12.4936 + Double(index % 5) * 0.004, stars: 5, rating: 9.4, reviewCount: 826, photo: "fixture:london")
    }
    static var trip: JourneyDocument {
        let start = TravelDay.adding(2, to: TravelDay.key(.now))
        return JourneyDocument(id: UUID(uuidString: "EEEE0000-0000-4000-8000-000000000099")!, title: "Rome escape", destination: "Rome", startDate: start, endDate: TravelDay.adding(3, to: start), stops: [JourneyStop(name: "Rome", country: "Italy", arrival: start, nights: 3)])
    }
    static var detail: LodgingDetail {
        .init(hotel: hotel(), description: "A quiet base in the heart of Rome, with generous rooms, a roof terrace and a welcoming sense of place. This is test content.", importantInformation: "Check-in from 15:00. Confirm policies with the hotel before travel.", photos: (0..<12).map { .init(url: "fixture:photo-\($0)", caption: "Test photograph \($0 + 1)") }, facilities: ["Restaurant", "Spa", "Fitness centre", "Terrace"], rooms: [.init(id: "room1", name: "Deluxe double room", description: "Room content is for discovery. Availability has not been checked.", photos: (0..<4).map { .init(url: "fixture:room-\($0)", caption: "Room photograph \($0 + 1)") }, maxOccupancy: 2, size: 32, sizeUnit: "m²")], environment: "sandbox")
    }
}

/// Editable search preferences. Only a matching, unexpired rate response supplies a price.
struct HotelStayPreferences: Equatable {
    var checkIn: Date?
    var checkOut: Date?
    var adults = 2
    var rooms = 1
    var roomGuests: [HotelOccupancy] = []
    var travelerID: String?
    var guestNationality = ""
    var currency = "USD"
    var occupancies: [HotelOccupancy] {
        if roomGuests.count == rooms && roomGuests.reduce(0, { $0 + $1.adults }) == adults { return roomGuests }
        guard rooms > 0 else { return [] }
        return (0..<rooms).map { HotelOccupancy(adults: adults / rooms + ($0 < adults % rooms ? 1 : 0)) }
    }
    var childCount: Int { occupancies.reduce(0) { $0 + $1.children.count } }
    var ratesReady: Bool { datesValid && (1...30).contains(nights) && !guestNationality.isEmpty && (1...8).contains(rooms) && occupancies.allSatisfy(\.valid) && adults + childCount <= 24 }
    var nights: Int {
        guard let checkIn, let checkOut else { return 0 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: checkIn), to: Calendar.current.startOfDay(for: checkOut)).day ?? 0
    }
    var datesValid: Bool { (checkIn == nil && checkOut == nil) || (checkIn != nil && checkOut != nil && (1...30).contains(nights) && Calendar.current.startOfDay(for: checkIn!) >= Calendar.current.startOfDay(for: .now)) }
    var dateLabel: String {
        guard let checkIn, let checkOut else { return "Add dates" }
        return checkIn.formatted(.dateTime.month(.abbreviated).day()) + " – " + checkOut.formatted(.dateTime.month(.abbreviated).day())
    }
    var guestLabel: String { "\(adults + childCount) \(childCount > 0 ? "guests" : adults == 1 ? "adult" : "adults") · \(rooms) \(rooms == 1 ? "room" : "rooms")" }
    mutating func select(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        if checkIn == nil || checkOut != nil || day <= checkIn! { checkIn = day; checkOut = nil }
        else { checkOut = day }
    }
}
