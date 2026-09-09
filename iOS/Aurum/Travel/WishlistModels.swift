import Foundation
import Observation

enum WishlistKind: String, Codable, CaseIterable, Identifiable {
    case destinations = "Destinations", stays = "Stays", dining = "Dining", experiences = "Things to do", ideas = "Other ideas"
    var id: String { rawValue }
    var symbol: String { switch self { case .destinations: "globe.europe.africa"; case .stays: "bed.double"; case .dining: "fork.knife"; case .experiences: "sparkles"; case .ideas: "lightbulb" } }
    var category: PlaceCategory { switch self { case .destinations, .ideas: .other; case .stays: .hotel; case .dining: .restaurant; case .experiences: .attraction } }
    static func forPlace(_ place: PlaceRecord) -> Self {
        switch place.category { case .hotel: .stays; case .restaurant, .bar, .cafe: .dining; case .other: .ideas; default: .experiences }
    }
}

struct WishlistIdea: Codable, Identifiable {
    var id = UUID().uuidString
    var name = ""
    var destination = ""
    var kind: WishlistKind = .experiences
    var website = ""
    var record: PlaceRecord { PlaceRecord(id: id, name: name, category: kind.category, city: kind == .destinations ? name : destination, website: website, source: "Wishlist idea") }
    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give your idea a name." }
        if !website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validatedURL(website.trimmingCharacters(in: .whitespacesAndNewlines)) == nil { return "Use a full website link starting with https:// or http://." }
        return nil
    }
}

struct WishlistDetails: Codable, Equatable {
    var notes = ""
    var collection = ""
    var topPick = false
    var addedAt = Date.now.timeIntervalSince1970
}

/// Extra wishlist information lives alongside existing bookmarks, never as another copy of them.
@MainActor @Observable final class WishlistLibrary {
    private(set) var ideas: [WishlistIdea] = []
    private(set) var details: [String: WishlistDetails] = [:]
    private let defaults: UserDefaults
    private var loadFailed = false
    var error: String?
    private struct Archive: Codable { var version = 1; var ideas: [WishlistIdea]; var details: [String: WishlistDetails] }
    init(defaults: UserDefaults) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: "seur.wishlist.v1") else { return }
        do {
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            guard archive.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            ideas = archive.ideas; details = archive.details
        } catch { loadFailed = true; self.error = "Your wishlist couldn’t be loaded. Its saved data has been kept. Restart the app to try again." }
    }
    func info(_ id: String) -> WishlistDetails { details[id] ?? WishlistDetails(addedAt: 0) }
    @discardableResult func update(_ value: WishlistDetails, for id: String) -> Bool {
        var next = details; var clean = value
        clean.collection = clean.collection.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = details.values.first(where: { $0.collection.localizedCaseInsensitiveCompare(clean.collection) == .orderedSame }) { clean.collection = existing.collection }
        next[id] = clean
        return persist(ideas: ideas, details: next)
    }
    func register(_ id: String) { var value = details[id] ?? WishlistDetails(); value.addedAt = Date.now.timeIntervalSince1970; _ = update(value, for: id) }
    @discardableResult func saveIdea(_ idea: WishlistIdea, details info: WishlistDetails) -> Bool {
        if let error = idea.validationError { self.error = error; return false }
        var clean = idea
        clean.name = clean.name.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.destination = clean.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.website = clean.website.trimmingCharacters(in: .whitespacesAndNewlines)
        if ideas.contains(where: { $0.id != clean.id && $0.name.foldedCityText == clean.name.foldedCityText && $0.destination.foldedCityText == clean.destination.foldedCityText && $0.kind == clean.kind }) {
            error = "That idea is already in your wishlist. Open it to add notes or change its collection."; return false
        }
        var next = ideas.filter { $0.id != clean.id }; next.append(clean)
        var metadata = details; var value = info; value.collection = value.collection.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = details.values.first(where: { $0.collection.localizedCaseInsensitiveCompare(value.collection) == .orderedSame }) { value.collection = existing.collection }
        metadata["idea:" + clean.id] = value
        return persist(ideas: next, details: metadata)
    }
    @discardableResult func remove(_ id: String) -> Bool {
        var next = details; next.removeValue(forKey: id)
        return persist(ideas: ideas.filter { "idea:" + $0.id != id }, details: next)
    }
    private func persist(ideas: [WishlistIdea], details: [String: WishlistDetails]) -> Bool {
        guard !loadFailed else { error = "Your saved wishlist couldn’t be loaded. Restart the app to try again; the original data has been kept."; return false }
        do {
            let data = try JSONEncoder().encode(Archive(ideas: ideas, details: details))
            defaults.set(data, forKey: "seur.wishlist.v1")
            self.ideas = ideas; self.details = details; error = nil; return true
        } catch { self.error = "Your wishlist changes couldn’t be saved. Please try again."; return false }
    }
}

struct WishlistEntry: Identifiable {
    enum Source { case hotel(Hotel), restaurant(RestaurantPlace), discovery(ExplorePlace), city(ExploreCity), idea(WishlistIdea) }
    let id: String
    let source: Source
    let place: PlaceRecord
    let kind: WishlistKind
    var title: String { place.name }
    var subtitle: String {
        if kind == .destinations { return city?.country ?? (customIdea?.destination.isEmpty == false ? customIdea!.destination : "Destination idea") }
        return place.city.isEmpty ? kind.rawValue : place.city
    }
    var tripDestination: String {
        if kind == .destinations { return customIdea?.destination.isEmpty == false ? title + ", " + customIdea!.destination : title }
        return place.city
    }
    var city: ExploreCity? { if case .city(let city) = source { city } else { nil } }
    func isPlanned(in document: JourneyDocument) -> Bool {
        if kind == .destinations { return document.stops.contains { $0.name.foldedCityText == tripDestination.foldedCityText } }
        return document.events.contains { $0.place.id == place.id && $0.place.source == place.source } || document.hotels.contains { $0.place.id == place.id && $0.place.source == place.source }
    }
    var customIdea: WishlistIdea? { if case .idea(let idea) = source { idea } else { nil } }
}

enum WishlistSort: String, CaseIterable { case newest = "Recently saved", name = "Name A–Z", destination = "Destination" }

extension TravelStore {
    var wishlistEntries: [WishlistEntry] {
        var entries = savedHotels.map { hotel in
            WishlistEntry(id: "hotel:" + hotel.id, source: .hotel(hotel), place: PlaceRecord(id: hotel.id, name: hotel.name, category: .hotel, city: hotel.city, address: hotel.address.usefulCollectionText, website: hotel.website, source: "Seur hotel collection", brand: hotel.brand), kind: .stays)
        }
        entries += savedDiscoveries.map { place in
            WishlistEntry(id: place.isCollection ? "restaurant:" + place.record.id : "place:" + place.id, source: .discovery(place), place: place.record, kind: .forPlace(place.record))
        }
        let known = Set(entries.map(\.id))
        entries += savedDiningPlaces.filter { !known.contains("restaurant:" + $0.id) }.map { restaurant in
            WishlistEntry(id: "restaurant:" + restaurant.id, source: .restaurant(restaurant), place: PlaceRecord(id: restaurant.id, name: restaurant.venue.name, category: .restaurant, city: restaurant.hotel.city, address: restaurant.hotel.address.usefulCollectionText, website: restaurant.hotel.website, source: "Seur hotel collection"), kind: .dining)
        }
        entries += savedExploreCities.map { city in
            WishlistEntry(id: "city:" + city.id, source: .city(city), place: PlaceRecord(id: city.id, name: city.name, category: .other, city: city.name, latitude: city.latitude, longitude: city.longitude, source: "Saved city"), kind: .destinations)
        }
        entries += wishlist.ideas.map { WishlistEntry(id: "idea:" + $0.id, source: .idea($0), place: $0.record, kind: $0.kind) }
        return entries
    }
    func wishlistMatches(query: String, kind: WishlistKind? = nil, collection: String? = nil, topPicks: Bool = false, sort: WishlistSort = .newest) -> [WishlistEntry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return wishlistEntries.filter { entry in
            let info = wishlist.info(entry.id)
            return (kind == nil || entry.kind == kind) && (collection == nil || info.collection == collection) && (!topPicks || info.topPick) && (term.isEmpty || [entry.title, entry.subtitle, info.notes, info.collection, entry.kind.rawValue].joined(separator: " ").localizedCaseInsensitiveContains(term))
        }.sorted { a, b in
            switch sort {
            case .newest:
                let x = wishlist.info(a.id).addedAt, y = wishlist.info(b.id).addedAt
                if x != y { return x > y }
            case .destination: if a.subtitle != b.subtitle { return a.subtitle.localizedStandardCompare(b.subtitle) == .orderedAscending }
            case .name: break
            }
            let order = a.title.localizedStandardCompare(b.title)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }
    var wishlistCollections: [String] { Array(Set(wishlistEntries.map { wishlist.info($0.id).collection }.filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    @discardableResult func removeFromWishlist(_ entry: WishlistEntry) -> Bool {
        guard wishlist.remove(entry.id) else { return false }
        switch entry.source {
        case .hotel(let hotel): if saved.contains(hotel.id) { toggleSave(hotel) }
        case .restaurant(let restaurant): if savedRestaurants.contains(restaurant.id) { toggleRestaurantSave(restaurant) }
        case .discovery(let place): if isDiscoverySaved(place) { toggleDiscovery(place) }
        case .city(let city): if isExploreCitySaved(city) { toggleExploreCity(city) }
        case .idea: break
        }
        return true
    }
}

extension JourneyDocument {
    /// Relative plans use internal day anchors; the UI never presents those as travel dates.
    mutating func scheduleWishlist(from previous: [JourneyStop], departure: String) throws {
        var scheduled = self
        try scheduled.applyWishlistSchedule(from: previous, departure: departure)
        self = scheduled
    }
    private mutating func applyWishlistSchedule(from previous: [JourneyStop], departure: String) throws {
        guard TravelDay.date(departure) != nil, !stops.isEmpty else { throw JourneyError.message("Add a destination and choose a valid departure date.") }
        var next = departure
        for i in stops.indices {
            if i > 0, let plan = routePlan {
                let key = stops[i - 1].id.uuidString + ">" + stops[i].id.uuidString
                next = TravelDay.adding(plan.choices.first { $0.key == key }?.extraDays ?? 0, to: next)
            }
            stops[i].arrival = next; next = stops[i].departure
        }
        for i in hotels.indices {
            let stay = hotels[i]
            let candidates = previous.filter { $0.arrival <= stay.checkIn && stay.checkIn < $0.departure && stay.checkOut <= $0.departure }
            let named = candidates.filter { !stay.place.city.isEmpty && ($0.name.localizedCaseInsensitiveContains(stay.place.city) || stay.place.city.localizedCaseInsensitiveContains($0.name)) }
            guard let old = named.count == 1 ? named.first : candidates.count == 1 ? candidates.first : nil,
                  let stop = stops.first(where: { $0.id == old.id }) else { throw JourneyError.message("Choose a destination and days for the stay at \(stay.place.name) before changing this route.") }
            let first = TravelDay.distance(old.arrival, stay.checkIn), last = TravelDay.distance(old.arrival, stay.checkOut)
            guard last <= stop.nights else { throw JourneyError.message("The stay at \(stay.place.name) is longer than your new stop. Shorten the stay first.") }
            hotels[i].checkIn = TravelDay.adding(first, to: stop.arrival)
            hotels[i].checkOut = TravelDay.adding(last, to: stop.arrival)
        }
        if dateMode == .dates { startDate = departure; endDate = stops.last?.departure }
        else { startDate = nil; endDate = nil }
    }
    func scheduledWishlist(departure: String) throws -> JourneyDocument {
        guard isWishlistTrip else { throw JourneyError.message("This plan already has travel dates.") }
        var trip = self
        trip.dateMode = .dates
        try trip.scheduleWishlist(from: stops, departure: departure)
        if let error = trip.validationError() { throw JourneyError.message(error) }
        return trip
    }
    func stayLabel(_ hotel: HotelReservation) -> String {
        guard isWishlistTrip, let start = stops.first?.arrival else { return "\(TravelDay.label(hotel.checkIn)) – \(TravelDay.label(hotel.checkOut))" }
        return "Day \(TravelDay.distance(start, hotel.checkIn) + 1) – Day \(TravelDay.distance(start, hotel.checkOut) + 1)"
    }
}
