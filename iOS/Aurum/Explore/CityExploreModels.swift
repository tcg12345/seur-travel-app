import Foundation
import MapKit
import Observation

struct ExploreCity: Codable, Hashable, Identifiable {
    var name: String
    var country: String
    var latitude: Double
    var longitude: Double
    var id: String { "\(name.foldedCityText)|\(Int((latitude * 100).rounded()))|\(Int((longitude * 100).rounded()))" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var region: MKCoordinateRegion { .init(center: coordinate, latitudinalMeters: 24_000, longitudinalMeters: 24_000) }
    init(name: String, country: String, latitude: Double, longitude: Double) { self.name = name; self.country = country; self.latitude = latitude; self.longitude = longitude }
    init?(_ selection: LocationSelection) {
        guard selection.place.hasCoordinate else { return nil }
        name = selection.place.city.isEmpty ? selection.text : selection.place.city
        country = selection.country
        latitude = selection.place.latitude!; longitude = selection.place.longitude!
    }
    func contains(_ place: ExplorePlace) -> Bool {
        place.city.id == id || (place.city.name.foldedCityText == name.foldedCityText && CLLocation(latitude: latitude, longitude: longitude).distance(from: CLLocation(latitude: place.city.latitude, longitude: place.city.longitude)) < 70_000)
    }
    func distance(to place: PlaceRecord) -> Double? {
        guard place.hasCoordinate else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude).distance(from: CLLocation(latitude: place.latitude!, longitude: place.longitude!))
    }
    static let collection: [ExploreCity] = [
        .init(name: "Paris", country: "France", latitude: 48.8566, longitude: 2.3522),
        .init(name: "London", country: "United Kingdom", latitude: 51.5074, longitude: -0.1278),
        .init(name: "Bangkok", country: "Thailand", latitude: 13.7563, longitude: 100.5018),
        .init(name: "Tokyo", country: "Japan", latitude: 35.6762, longitude: 139.6503),
        .init(name: "New York", country: "United States", latitude: 40.7128, longitude: -74.0060),
        .init(name: "Singapore", country: "Singapore", latitude: 1.3521, longitude: 103.8198),
        .init(name: "Hong Kong", country: "Hong Kong", latitude: 22.3193, longitude: 114.1694),
        .init(name: "Dubai", country: "United Arab Emirates", latitude: 25.2048, longitude: 55.2708),
        .init(name: "Shanghai", country: "China", latitude: 31.2304, longitude: 121.4737),
        .init(name: "Istanbul", country: "Türkiye", latitude: 41.0082, longitude: 28.9784),
        .init(name: "Macau", country: "Macau", latitude: 22.1987, longitude: 113.5439),
        .init(name: "Kuala Lumpur", country: "Malaysia", latitude: 3.1390, longitude: 101.6869)
    ]
    var collectionName: String? {
        Self.collection.first { reference in
            let a = name.foldedCityText, b = reference.name.foldedCityText
            let matches = a == b || (b == "new york" && ["new york city", "manhattan"].contains(a)) || (b == "macau" && a == "macao")
            return matches && CLLocation(latitude: latitude, longitude: longitude).distance(from: CLLocation(latitude: reference.latitude, longitude: reference.longitude)) < 70_000
        }?.name
    }
}

/// Lightweight city centers for browsing. Venue searches only run after a city is opened;
/// worldwide autocomplete remains available beyond this directory.
struct CityBrowseRegion: Identifiable {
    let name: String
    let cities: [ExploreCity]
    var id: String { name }
    static let all: [Self] = [
        .init(name: "Europe", cities: [
            .init(name: "Paris", country: "France", latitude: 48.8566, longitude: 2.3522),
            .init(name: "London", country: "United Kingdom", latitude: 51.5074, longitude: -0.1278),
            .init(name: "Rome", country: "Italy", latitude: 41.9028, longitude: 12.4964),
            .init(name: "Barcelona", country: "Spain", latitude: 41.3874, longitude: 2.1686),
            .init(name: "Lisbon", country: "Portugal", latitude: 38.7223, longitude: -9.1393),
            .init(name: "Amsterdam", country: "Netherlands", latitude: 52.3676, longitude: 4.9041),
            .init(name: "Copenhagen", country: "Denmark", latitude: 55.6761, longitude: 12.5683),
            .init(name: "Stockholm", country: "Sweden", latitude: 59.3293, longitude: 18.0686),
            .init(name: "Oslo", country: "Norway", latitude: 59.9139, longitude: 10.7522),
            .init(name: "Athens", country: "Greece", latitude: 37.9838, longitude: 23.7275),
            .init(name: "Vienna", country: "Austria", latitude: 48.2082, longitude: 16.3738),
            .init(name: "Prague", country: "Czechia", latitude: 50.0755, longitude: 14.4378),
            .init(name: "Berlin", country: "Germany", latitude: 52.5200, longitude: 13.4050),
            .init(name: "Zurich", country: "Switzerland", latitude: 47.3769, longitude: 8.5417),
            .init(name: "Dublin", country: "Ireland", latitude: 53.3498, longitude: -6.2603),
            .init(name: "Istanbul", country: "Türkiye", latitude: 41.0082, longitude: 28.9784)
        ]),
        .init(name: "Asia", cities: [
            .init(name: "Tokyo", country: "Japan", latitude: 35.6762, longitude: 139.6503),
            .init(name: "Kyoto", country: "Japan", latitude: 35.0116, longitude: 135.7681),
            .init(name: "Seoul", country: "South Korea", latitude: 37.5665, longitude: 126.9780),
            .init(name: "Bangkok", country: "Thailand", latitude: 13.7563, longitude: 100.5018),
            .init(name: "Singapore", country: "Singapore", latitude: 1.3521, longitude: 103.8198),
            .init(name: "Hong Kong", country: "Hong Kong", latitude: 22.3193, longitude: 114.1694),
            .init(name: "Shanghai", country: "China", latitude: 31.2304, longitude: 121.4737),
            .init(name: "Macau", country: "Macau", latitude: 22.1987, longitude: 113.5439),
            .init(name: "Kuala Lumpur", country: "Malaysia", latitude: 3.1390, longitude: 101.6869),
            .init(name: "Hanoi", country: "Vietnam", latitude: 21.0278, longitude: 105.8342),
            .init(name: "Taipei", country: "Taiwan", latitude: 25.0330, longitude: 121.5654),
            .init(name: "Mumbai", country: "India", latitude: 19.0760, longitude: 72.8777)
        ]),
        .init(name: "Americas", cities: [
            .init(name: "New York", country: "United States", latitude: 40.7128, longitude: -74.0060),
            .init(name: "Los Angeles", country: "United States", latitude: 34.0522, longitude: -118.2437),
            .init(name: "San Francisco", country: "United States", latitude: 37.7749, longitude: -122.4194),
            .init(name: "Miami", country: "United States", latitude: 25.7617, longitude: -80.1918),
            .init(name: "Chicago", country: "United States", latitude: 41.8781, longitude: -87.6298),
            .init(name: "Toronto", country: "Canada", latitude: 43.6532, longitude: -79.3832),
            .init(name: "Vancouver", country: "Canada", latitude: 49.2827, longitude: -123.1207),
            .init(name: "Mexico City", country: "Mexico", latitude: 19.4326, longitude: -99.1332),
            .init(name: "Buenos Aires", country: "Argentina", latitude: -34.6037, longitude: -58.3816),
            .init(name: "Rio de Janeiro", country: "Brazil", latitude: -22.9068, longitude: -43.1729),
            .init(name: "Lima", country: "Peru", latitude: -12.0464, longitude: -77.0428),
            .init(name: "Cartagena", country: "Colombia", latitude: 10.3910, longitude: -75.4794)
        ]),
        .init(name: "Africa & Middle East", cities: [
            .init(name: "Marrakech", country: "Morocco", latitude: 31.6295, longitude: -7.9811),
            .init(name: "Cape Town", country: "South Africa", latitude: -33.9249, longitude: 18.4241),
            .init(name: "Cairo", country: "Egypt", latitude: 30.0444, longitude: 31.2357),
            .init(name: "Nairobi", country: "Kenya", latitude: -1.2921, longitude: 36.8219),
            .init(name: "Dubai", country: "United Arab Emirates", latitude: 25.2048, longitude: 55.2708),
            .init(name: "Abu Dhabi", country: "United Arab Emirates", latitude: 24.4539, longitude: 54.3773),
            .init(name: "Doha", country: "Qatar", latitude: 25.2854, longitude: 51.5310),
            .init(name: "Muscat", country: "Oman", latitude: 23.5880, longitude: 58.3829)
        ]),
        .init(name: "Oceania", cities: [
            .init(name: "Sydney", country: "Australia", latitude: -33.8688, longitude: 151.2093),
            .init(name: "Melbourne", country: "Australia", latitude: -37.8136, longitude: 144.9631),
            .init(name: "Brisbane", country: "Australia", latitude: -27.4698, longitude: 153.0251),
            .init(name: "Perth", country: "Australia", latitude: -31.9505, longitude: 115.8605),
            .init(name: "Auckland", country: "New Zealand", latitude: -36.8485, longitude: 174.7633),
            .init(name: "Queenstown", country: "New Zealand", latitude: -45.0312, longitude: 168.6626)
        ])
    ]
}

extension String {
    var foldedCityText: String { folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).trimmingCharacters(in: .whitespacesAndNewlines) }
    var usefulCollectionText: String { ["", "n/a", "unknown", "not available", "not specified", "none"].contains(foldedCityText) ? "" : self }
}

enum ExploreInterest: String, CaseIterable, Identifiable, Codable {
    case highlights, restaurants, attractions, museums, parks, cafes, bars, shopping, entertainment, spas, beaches, landmarks, hotels
    var id: String { rawValue }
    var title: String {
        switch self { case .highlights: "Highlights"; case .restaurants: "Restaurants"; case .attractions: "Things to do"; case .museums: "Art & museums"; case .parks: "Parks & gardens"; case .cafes: "Cafés"; case .bars: "Bars & nightlife"; case .shopping: "Shopping"; case .entertainment: "Shows & culture"; case .spas: "Spas & wellness"; case .beaches: "Beaches"; case .landmarks: "Landmarks"; case .hotels: "Hotels" }
    }
    var category: PlaceCategory {
        switch self { case .highlights, .attractions: .attraction; case .restaurants: .restaurant; case .museums: .museum; case .parks: .park; case .cafes: .cafe; case .bars: .bar; case .shopping: .shopping; case .entertainment: .entertainment; case .spas: .spa; case .beaches: .beach; case .landmarks: .landmark; case .hotels: .hotel }
    }
    var symbol: String { self == .highlights ? "sparkles" : category.symbol }
    var query: String {
        switch self { case .highlights, .attractions: "attractions"; case .museums: "museums"; case .parks: "parks"; case .entertainment: "theaters"; case .spas: "spas"; case .landmarks: "landmarks"; default: rawValue }
    }
    var subtitle: String {
        switch self { case .restaurants: "A table worth making time for"; case .attractions: "Find your next little detour"; case .museums: "An afternoon of discovery"; case .parks: "A slower side of the city"; default: "Find something that feels like you" }
    }
    static let overview: [Self] = [.restaurants, .attractions, .museums, .parks]
}

struct ExplorePlace: Codable, Hashable, Identifiable {
    var record: PlaceRecord
    var city: ExploreCity
    var hotelID: String?
    var venueID: String?
    var hotelName = ""
    var cuisine = ""
    var priceBand = ""
    var venueLocation = ""
    var id: String { record.source + "|" + record.id }
    var isCollection: Bool { hotelID != nil }
    var subtitle: String { isCollection ? "At " + hotelName : record.address.isEmpty ? city.name : record.address }
    @MainActor static func collection(_ hotels: [Hotel], city: ExploreCity) -> [Self] {
        guard let name = city.collectionName else { return [] }
        let sorted = hotels.filter { $0.city == name }.sorted {
            let a = TravelStore.featuredIDs.firstIndex(of: $0.id) ?? 100, b = TravelStore.featuredIDs.firstIndex(of: $1.id) ?? 100
            return a == b ? $0.name < $1.name : a < b
        }
        return sorted.flatMap { hotel in hotel.venues.map { venue in
            let category: PlaceCategory = venue.type.foldedCityText.contains("bar") ? .bar : venue.type.foldedCityText.contains("cafe") ? .cafe : .restaurant
            return Self(record: PlaceRecord(id: RestaurantPlace(hotel: hotel, venue: venue).id, name: venue.name, category: category, city: city.name, address: hotel.address.usefulCollectionText, website: hotel.website, source: "Seur hotel collection", overview: venue.description.usefulCollectionText), city: city, hotelID: hotel.id, venueID: venue.id, hotelName: hotel.name, cuisine: venue.cuisine.usefulCollectionText, priceBand: venue.price.usefulCollectionText, venueLocation: venue.location.usefulCollectionText)
        } }
    }
}

struct ExploreSection: Identifiable {
    var interest: ExploreInterest
    var places: [ExplorePlace]
    var error: String?
    var id: String { interest.id }
}

enum ExploreSort: String, CaseIterable { case suggested = "Suggested", distance = "Distance from center", name = "Name A–Z" }

enum DiningPricePreference: String, CaseIterable, Identifiable {
    case any = "Any price", budget = "Budget", moderate = "Moderate", upscale = "Upscale", fineDining = "Fine dining"
    var id: String { rawValue }
    var query: String {
        switch self {
        case .any: ""
        case .budget: "inexpensive"
        case .moderate: "moderately priced"
        case .upscale: "upscale"
        case .fineDining: "fine dining"
        }
    }
}

struct DiningSearchPreferences: Equatable {
    var cuisine = "Any cuisine"
    var price: DiningPricePreference = .any
    static let cuisines = ["Any cuisine", "French", "Italian", "Japanese", "Chinese", "Indian", "Thai", "Mexican", "Mediterranean", "Middle Eastern", "Korean", "Vietnamese", "Spanish", "Greek", "American", "Vegetarian", "Vegan", "Seafood"]
    var active: Bool { cuisine != "Any cuisine" || price != .any }
    var summary: String { [cuisine == "Any cuisine" ? nil : cuisine, price == .any ? nil : price.rawValue].compactMap { $0 }.joined(separator: " · ") }
    func searchTerm(_ text: String = "", interest: ExploreInterest) -> String {
        guard interest == .restaurants, active else { return text }
        return [price.query, cuisine == "Any cuisine" ? "" : cuisine, "restaurants", text.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct CityMapRequest: Identifiable {
    let id = UUID()
    var city: ExploreCity
    var interest: ExploreInterest
    var term: String
    var dining: DiningSearchPreferences
    var sort: ExploreSort
    var wider: Bool
    var savedOnly: Bool
    var websiteOnly: Bool
    var places: [ExplorePlace]
}

@MainActor @Observable final class CityExploreModel {
    typealias Search = @MainActor (ExploreCity, ExploreInterest, String, Bool) async throws -> [ExplorePlace]
    private(set) var sections: [ExploreSection] = []
    private(set) var loading = false
    private var revision = UUID()
    private var cache: [String: [ExploreSection]] = [:]
    private let search: Search
    init(search: Search? = nil) { self.search = search ?? CityExploreSearch.search }
    var places: [ExplorePlace] {
        var seen = Set<String>()
        return sections.flatMap(\.places).filter { seen.insert($0.id).inserted }
    }
    /// Transfer the guide's unfiltered previews into a separate results page without
    /// repeating network requests. Failed sections remain retryable.
    func seed(city: ExploreCity, sections: [ExploreSection]) {
        let successful = sections.filter { $0.error == nil }
        for section in successful {
            cache[city.id + "|" + section.interest.id + "||false"] = [section]
        }
        if ExploreInterest.overview.allSatisfy({ interest in successful.contains { $0.interest == interest } }) {
            cache[city.id + "|highlights||false"] = ExploreInterest.overview.compactMap { interest in successful.first { $0.interest == interest } }
        }
    }
    func present(_ places: [ExplorePlace], interest: ExploreInterest) {
        revision = UUID()
        sections = [ExploreSection(interest: interest, places: places)]
        loading = false
    }
    func load(city: ExploreCity, interest: ExploreInterest, term: String, wider: Bool, refresh: Bool = false) async {
        let stamp = UUID(); revision = stamp
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = city.id + "|" + interest.id + "|" + query.foldedCityText + "|\(wider)"
        if !refresh, let existing = cache[key] { sections = existing; loading = false; return }
        sections = []; loading = true
        if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
        guard !Task.isCancelled, revision == stamp else { return }
        let interests = interest == .highlights && query.isEmpty ? ExploreInterest.overview : [interest == .highlights ? .attractions : interest]
        var fetched: [ExploreSection] = []
        await withTaskGroup(of: ExploreSection.self) { group in
            for category in interests {
                group.addTask { [search] in
                    do { return try await ExploreSection(interest: category, places: search(city, category, query, wider)) }
                    catch { return ExploreSection(interest: category, places: [], error: "This part of the city couldn’t load. Please try again.") }
                }
            }
            for await section in group { fetched.append(section) }
        }
        guard !Task.isCancelled, revision == stamp else { return }
        sections = interests.compactMap { interest in fetched.first { $0.interest == interest } }
        loading = false
        if sections.allSatisfy({ $0.error == nil }) { if cache.count >= 40 { cache.removeAll() }; cache[key] = sections }
    }
    func visible(sort: ExploreSort, savedOnly: Bool, websiteOnly: Bool, savedIDs: Set<String>) -> [ExplorePlace] {
        let filtered = places.filter { (!savedOnly || savedIDs.contains($0.id)) && (!websiteOnly || validatedURL($0.record.website) != nil) }
        switch sort {
        case .suggested: return filtered
        case .distance: return filtered.sorted { ($0.city.distance(to: $0.record) ?? .infinity) < ($1.city.distance(to: $1.record) ?? .infinity) }
        case .name: return filtered.sorted { $0.record.name.localizedStandardCompare($1.record.name) == .orderedAscending }
        }
    }
}

@MainActor enum CityExploreSearch {
    static func search(city: ExploreCity, interest: ExploreInterest, term: String, wider: Bool) async throws -> [ExplorePlace] {
        #if DEBUG
        if PlaceSearchTestPolicy.usesFixtures || (ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--city-testing")) {
            try await Task.sleep(for: .milliseconds(120))
            if term.foldedCityText.contains("noresults") { return [] }
            return (0..<6).map { index in
                ExplorePlace(record: PlaceRecord(id: "city-fixture-\(city.id)-\(interest.id)-\(index)", name: "\(city.name) \(interest.category.title) \(index + 1)", category: interest.category, city: city.name, address: "\(index + 1) Example Street, \(city.name)", website: "https://example.com", latitude: city.latitude + Double(index) * 0.003, longitude: city.longitude + Double(index) * 0.003, source: "UI test fixture"), city: city)
            }
        }
        #endif
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term.isEmpty ? interest.query : term
        request.region = MKCoordinateRegion(center: city.coordinate, latitudinalMeters: wider ? 70_000 : 24_000, longitudinalMeters: wider ? 70_000 : 24_000)
        request.regionPriority = .required
        request.resultTypes = .pointOfInterest
        let response: MKLocalSearch.Response
        do { response = try await MKLocalSearch(request: request).start() }
        catch let error as MKError where error.code == .placemarkNotFound { return [] }
        var seen = Set<String>()
        return response.mapItems.compactMap { item in
            var record = ApplePlaceSearch.record(item, fallbackName: request.naturalLanguageQuery ?? "Place", category: category(item.pointOfInterestCategory, fallback: interest.category))
            if item.identifier == nil {
                record.id = record.name.foldedCityText + "|" + String(format: "%.5f,%.5f", item.location.coordinate.latitude, item.location.coordinate.longitude)
            }
            if record.city.isEmpty { record.city = city.name }
            guard record.hasCoordinate, seen.insert(record.id).inserted else { return nil }
            return ExplorePlace(record: record, city: city)
        }
    }
    static func category(_ value: MKPointOfInterestCategory?, fallback: PlaceCategory) -> PlaceCategory {
        switch value { case .restaurant: .restaurant; case .cafe, .bakery: .cafe; case .nightlife, .brewery, .winery: .bar; case .hotel: .hotel; case .museum: .museum; case .park, .nationalPark: .park; case .beach: .beach; case .store: .shopping; case .theater, .movieTheater: .entertainment; default: fallback }
    }
    static func locateCollection(_ value: ExplorePlace) async -> ExplorePlace {
        guard value.isCollection, !value.record.hasCoordinate else { return value }
        #if DEBUG
        if PlaceSearchTestPolicy.usesFixtures || (ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--city-testing")) {
            var result = value; result.record.latitude = value.city.latitude; result.record.longitude = value.city.longitude; return result
        }
        #endif
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = value.hotelName + " " + value.record.address + " " + value.city.name
        request.region = value.city.region; request.regionPriority = .required; request.resultTypes = .pointOfInterest
        guard let response = try? await MKLocalSearch(request: request).start() else { return value }
        func normalized(_ text: String) -> String { text.foldedCityText.replacingOccurrences(of: "the ", with: "").filter { $0.isLetter || $0.isNumber } }
        let hotelName = normalized(value.hotelName)
        guard let item = response.mapItems.first(where: { normalized($0.name ?? "") == hotelName }), (value.city.distance(to: ApplePlaceSearch.record(item, fallbackName: value.hotelName)) ?? .infinity) < 70_000 else { return value }
        var result = value; result.record.latitude = item.location.coordinate.latitude; result.record.longitude = item.location.coordinate.longitude
        return result
    }
}
