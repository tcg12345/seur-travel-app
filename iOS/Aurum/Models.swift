import Foundation
import Observation

struct DiningVenue: Codable, Hashable, Identifiable {
    let name, type, cuisine, location, description, price: String
    var id: String { name + "|" + cuisine + "|" + location }
}

struct Hotel: Codable, Hashable, Identifiable {
    let id, name, city, country, brand, stars, district, neighborhood: String
    let address, transit, rating, price, description, website: String
    let sources: [String]
    let venues: [DiningVenue]
    var image: String? {
        switch id {
        case "bkk-mandarin-oriental": "bangkok"
        case "par-peninsula": "paris"
        case "lon-savoy": "london"
        default: nil
        }
    }
    var shortName: String {
        switch id {
        case "bkk-mandarin-oriental": "Mandarin Oriental"
        case "par-peninsula": "The Peninsula"
        default: name
        }
    }
    var officialURL: URL? { validatedURL(website) }
    var searchText: String {
        ([name, city, country, brand, district] + venues.flatMap { [$0.name, $0.cuisine, $0.type] }).joined(separator: " ")
    }
}

func validatedURL(_ string: String) -> URL? {
    guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
          ["https", "http"].contains(scheme), url.host != nil else { return nil }
    return url
}

enum TravelCategory: String, CaseIterable, Identifiable {
    case hotels = "Stays", dining = "Dining", flights = "Flights", experiences = "Experiences"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .hotels: "bed.double"; case .dining: "fork.knife"; case .flights: "airplane"; case .experiences: "sparkles" }
    }
}

enum HotelSort: String, CaseIterable, Identifiable {
    case featured = "Featured", dining = "Most dining options", name = "Name A–Z"
    var id: String { rawValue }
}

struct TripPlan: Codable, Identifiable, Hashable {
    var id = UUID()
    let name: String
    let city: String
    let kind: String
    let hotelID: String?
    var start: Date
    var end: Date
    var guests: Int
    var symbol: String { kind == "Stay" ? "bed.double" : kind == "Dining" ? "fork.knife" : "sparkles" }
}

struct BookingDates {
    var start = Calendar.current.date(byAdding: .day, value: 14, to: .now)!
    var end = Calendar.current.date(byAdding: .day, value: 18, to: .now)!
    var guests = 2
    var nights: Int { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: end)).day ?? 0 }
    var isValid: Bool { Calendar.current.startOfDay(for: start) >= Calendar.current.startOfDay(for: .now) && nights > 0 && (1...9).contains(guests) }
}

struct FlightSearch {
    var origin = "New York"
    var destination = "Paris"
    var cabin = "Business"
    var oneWay = false
    var dates = BookingDates()
    var error: String? {
        let from = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty && !to.isEmpty && from.lowercased() != to.lowercased() else { return "Choose different departure and arrival cities." }
        guard Calendar.current.startOfDay(for: dates.start) >= Calendar.current.startOfDay(for: .now) else { return "Choose a departure date today or later." }
        guard oneWay || dates.isValid else { return "Return must be after departure." }
        return nil
    }
    var url: URL? {
        guard error == nil else { return nil }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        let query = "\(oneWay ? "one way" : "round trip") flights from \(origin) to \(destination) on \(formatter.string(from: dates.start))" + (oneWay ? "" : " returning \(formatter.string(from: dates.end))") + " \(dates.guests) adults \(cabin)"
        var parts = URLComponents(string: "https://www.google.com/travel/flights")!
        parts.queryItems = [URLQueryItem(name: "q", value: query)]
        return parts.url
    }
}

@MainActor @Observable final class TravelStore {
    static let cities = ["Bangkok", "Paris", "London", "Tokyo", "New York", "Singapore", "Hong Kong", "Dubai", "Shanghai", "Istanbul", "Macau", "Kuala Lumpur"]
    static let featuredIDs = ["bkk-mandarin-oriental", "par-peninsula", "lon-savoy"]
    private(set) var hotels: [Hotel] = []
    private(set) var saved: Set<String> = []
    private(set) var plans: [TripPlan] = []
    private(set) var savedRestaurants: Set<String> = []
    private(set) var savedDiscoveries: [ExplorePlace] = []
    private(set) var savedExploreCities: [ExploreCity] = []
    private(set) var recentExploreCities: [ExploreCity] = []
    private(set) var restaurantVisits: [String: RestaurantVisit] = [:]
    let concierge = ConciergeConversation()
    var selectedTab = 0
    var cityMapRequest: CityMapRequest?
    var category: TravelCategory = .hotels
    var query = ""
    var city = "Everywhere"
    var cuisine = "Any cuisine"
    var sort: HotelSort = .featured
    var dates = BookingDates()
    var message: String?
    var loadError: String?
    var compared: Set<String> = []
    private var toastTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private var index: [String: String] = [:]

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? .standard
        if let saved = self.defaults.stringArray(forKey: "aurum.saved") { self.saved = Set(saved) }
        if let data = self.defaults.data(forKey: "aurum.plans"), let plans = try? JSONDecoder().decode([TripPlan].self, from: data) { self.plans = plans }
        savedRestaurants = Set(self.defaults.stringArray(forKey: "aurum.savedRestaurants") ?? [])
        if let data = self.defaults.data(forKey: "aurum.restaurantVisits"), let visits = try? JSONDecoder().decode([String: RestaurantVisit].self, from: data) { restaurantVisits = visits }
        if let data = self.defaults.data(forKey: "aurum.savedDiscoveries"), let values = try? JSONDecoder().decode([ExplorePlace].self, from: data) { savedDiscoveries = values }
        if let data = self.defaults.data(forKey: "aurum.savedExploreCities"), let values = try? JSONDecoder().decode([ExploreCity].self, from: data) { savedExploreCities = values }
        if let data = self.defaults.data(forKey: "aurum.recentExploreCities"), let values = try? JSONDecoder().decode([ExploreCity].self, from: data) { recentExploreCities = values }
        do {
            guard let url = Bundle.main.url(forResource: "hotels", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            hotels = try JSONDecoder().decode([Hotel].self, from: Data(contentsOf: url))
            index = Dictionary(uniqueKeysWithValues: hotels.map { ($0.id, $0.searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)) })
        } catch { loadError = "The hotel collection couldn’t be opened. Please reinstall the app and try again." }
    }
    var featured: [Hotel] { Self.featuredIDs.compactMap { id in hotels.first { $0.id == id } } }
    var savedHotels: [Hotel] { hotels.filter { saved.contains($0.id) }.sorted { $0.name < $1.name } }
    var results: [Hotel] { search(query: query, city: city, cuisine: cuisine, sort: sort) }
    func search(query: String, city: String = "Everywhere", cuisine: String = "Any cuisine", sort: HotelSort = .featured) -> [Hotel] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let matches = hotels.filter { hotel in
            (city == "Everywhere" || hotel.city == city) && (q.isEmpty || index[hotel.id, default: ""].contains(q)) && (cuisine == "Any cuisine" || hotel.venues.contains { $0.cuisine.localizedCaseInsensitiveContains(cuisine) })
        }
        return matches.sorted { a, b in
            switch sort {
            case .featured:
                let x = Self.featuredIDs.firstIndex(of: a.id) ?? 100, y = Self.featuredIDs.firstIndex(of: b.id) ?? 100
                return x == y ? a.name < b.name : x < y
            case .dining: return a.venues.count == b.venues.count ? a.name < b.name : a.venues.count > b.venues.count
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }
    func isDiscoverySaved(_ place: ExplorePlace) -> Bool { savedDiscoveries.contains { $0.id == place.id } || (place.isCollection && savedRestaurants.contains(place.record.id)) }
    func toggleDiscovery(_ place: ExplorePlace) {
        let removing = isDiscoverySaved(place)
        savedDiscoveries.removeAll { $0.id == place.id }
        if !removing { savedDiscoveries.insert(place, at: 0) }
        if place.isCollection {
            if removing { savedRestaurants.remove(place.record.id) } else { savedRestaurants.insert(place.record.id) }
            defaults.set(Array(savedRestaurants), forKey: "aurum.savedRestaurants")
        }
        if let data = try? JSONEncoder().encode(savedDiscoveries) { defaults.set(data, forKey: "aurum.savedDiscoveries") }
    }
    func refreshSavedDiscovery(_ place: ExplorePlace) {
        guard let index = savedDiscoveries.firstIndex(where: { $0.id == place.id }) else { return }
        savedDiscoveries[index] = place
        if let data = try? JSONEncoder().encode(savedDiscoveries) { defaults.set(data, forKey: "aurum.savedDiscoveries") }
    }
    func isExploreCitySaved(_ city: ExploreCity) -> Bool { savedExploreCities.contains { $0.id == city.id } }
    func toggleExploreCity(_ city: ExploreCity) {
        if isExploreCitySaved(city) { savedExploreCities.removeAll { $0.id == city.id } } else { savedExploreCities.insert(city, at: 0) }
        if let data = try? JSONEncoder().encode(savedExploreCities) { defaults.set(data, forKey: "aurum.savedExploreCities") }
    }
    func rememberExploreCity(_ city: ExploreCity) {
        if recentExploreCities.first?.id == city.id { return }
        recentExploreCities.removeAll { $0.id == city.id }; recentExploreCities.insert(city, at: 0); recentExploreCities = Array(recentExploreCities.prefix(12))
        if let data = try? JSONEncoder().encode(recentExploreCities) { defaults.set(data, forKey: "aurum.recentExploreCities") }
    }
    func toggleSave(_ hotel: Hotel) {
        if saved.contains(hotel.id) { saved.remove(hotel.id) } else { saved.insert(hotel.id) }
        defaults.set(Array(saved), forKey: "aurum.saved")
    }
    var savedDiningPlaces: [RestaurantPlace] {
        hotels.flatMap { hotel in hotel.venues.map { RestaurantPlace(hotel: hotel, venue: $0) } }
            .filter { savedRestaurants.contains($0.id) }.sorted { $0.venue.name < $1.venue.name }
    }
    func toggleRestaurantSave(_ place: RestaurantPlace) {
        if let city = ExploreCity.collection.first(where: { $0.name == place.hotel.city }), let discovery = ExplorePlace.collection([place.hotel], city: city).first(where: { $0.record.id == place.id }) { toggleDiscovery(discovery); return }
        if savedRestaurants.contains(place.id) { savedRestaurants.remove(place.id) } else { savedRestaurants.insert(place.id) }
        defaults.set(Array(savedRestaurants), forKey: "aurum.savedRestaurants")
    }
    func saveRestaurantVisit(_ visit: RestaurantVisit, for place: RestaurantPlace) {
        var clean = visit
        clean.rating = min(5, max(0, clean.rating))
        clean.note = clean.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.rating == 0 && clean.note.isEmpty { restaurantVisits.removeValue(forKey: place.id) }
        else { restaurantVisits[place.id] = clean }
        if let data = try? JSONEncoder().encode(restaurantVisits) { defaults.set(data, forKey: "aurum.restaurantVisits") }
    }
    func toggleCompare(_ hotel: Hotel) {
        if compared.contains(hotel.id) { compared.remove(hotel.id) }
        else if compared.count < 3 { compared.insert(hotel.id) }
        else { showMessage("Compare up to three hotels at a time.") }
    }
    @discardableResult func addPlan(name: String, city: String, kind: String, hotelID: String?, dates: BookingDates) -> Bool {
        guard dates.isValid else { showMessage("Choose valid travel dates first."); return false }
        guard !plans.contains(where: { $0.name == name && $0.hotelID == hotelID && Calendar.current.isDate($0.start, inSameDayAs: dates.start) }) else { showMessage("Already in your itinerary for these dates."); return false }
        plans.append(TripPlan(name: name, city: city, kind: kind, hotelID: hotelID, start: dates.start, end: dates.end, guests: dates.guests))
        persistPlans(); showMessage("Added to your trip. Reservation still required."); return true
    }
    func removePlan(_ plan: TripPlan) { plans.removeAll { $0.id == plan.id }; persistPlans() }
    func updatePlan(_ plan: TripPlan) { if let i = plans.firstIndex(where: { $0.id == plan.id }) { plans[i] = plan; persistPlans() } }
    private func persistPlans() { if let data = try? JSONEncoder().encode(plans) { defaults.set(data, forKey: "aurum.plans") } }
    func showMessage(_ text: String) {
        toastTask?.cancel(); message = text
        toastTask = Task { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { message = nil } }
    }
    var exportText: String {
        "SEUR — MY ITINERARY\nDraft plans. Confirm reservations with providers.\n\n" + plans.sorted { $0.start < $1.start }.map { "\($0.start.formatted(date: .abbreviated, time: .omitted)) · \($0.kind)\n\($0.name) — \($0.city)\n\($0.guests) adults\n" }.joined(separator: "\n")
    }
}
