import Foundation
import Observation

// Calendar days are stored as ISO local dates, independent of the device time zone.
enum TravelDay {
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    static func key(_ date: Date) -> String { let c = Calendar.current.dateComponents([.year, .month, .day], from: date); return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!) }
    static func date(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let date = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return c.year == p[0] && c.month == p[1] && c.day == p[2] ? date : nil
    }
    static func localDate(_ key: String) -> Date { guard let d = date(key) else { return .now }; return Calendar.current.date(from: calendar.dateComponents([.year, .month, .day], from: d)) ?? .now }
    static func adding(_ days: Int, to key: String) -> String {
        guard let d = date(key), let result = calendar.date(byAdding: .day, value: days, to: d) else { return key }
        let c = calendar.dateComponents([.year, .month, .day], from: result)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func distance(_ from: String, _ to: String) -> Int { guard let a = date(from), let b = date(to) else { return 0 }; return calendar.dateComponents([.day], from: a, to: b).day ?? 0 }
    static func label(_ key: String) -> String { localDate(key).formatted(.dateTime.month(.abbreviated).day()) }
}

enum JourneyKind: String, Codable, CaseIterable { case itinerary, trip, journey; var title: String { "Trips" } }
enum JourneyVisibility: String, Codable, CaseIterable { case `private`, friends, `public`; var title: String { rawValue.capitalized } }
enum JourneyDateMode: String, Codable, CaseIterable { case dates, nights; var title: String { self == .dates ? "Exact dates" : "Length of stay" } }
enum PlaceCategory: String, Codable, CaseIterable, Identifiable {
    case restaurant, attraction, hotel, museum, park, monument, shopping, entertainment, bar, cafe, beach, spa, landmark, other
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .restaurant: "fork.knife"; case .attraction, .landmark, .monument: "sparkles"; case .hotel: "bed.double"; case .museum: "building.columns"; case .park: "leaf"; case .shopping: "bag"; case .entertainment: "theatermasks"; case .bar: "wineglass"; case .cafe: "cup.and.saucer"; case .beach: "beach.umbrella"; case .spa: "water.waves"; case .other: "mappin" }
    }
    var scoreCategories: [String] {
        switch self { case .restaurant, .bar, .cafe: ["Food & drink", "Service", "Atmosphere", "Value"]
        case .hotel, .spa: ["Comfort", "Service", "Location", "Value"]
        default: ["Experience", "Atmosphere", "Accessibility", "Value"] }
    }
    var isImportablePlace: Bool { self == .restaurant || self == .attraction }
}
struct TravelMoney: Codable, Hashable {
    var amount: Decimal = 0
    var currency = "USD"
    var formatted: String { amount.formatted(.currency(code: currency)) }
    static let currencies = ["USD", "EUR", "GBP", "JPY", "THB", "SGD", "HKD", "AED", "CNY", "TRY", "MYR", "AUD", "CAD", "CHF"]
}
struct PlaceRecord: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var name = ""
    var category: PlaceCategory = .restaurant
    var city = ""
    var address = ""
    var phone = ""
    var website = ""
    var latitude: Double?
    var longitude: Double?
    var rating: Double?
    var ratingImageURL: String?
    var sourceURL: String?
    var source = "Manual entry"
    var overview = ""
    var hasCoordinate: Bool { if let latitude, let longitude { return latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }; return false }
}
struct JourneyStop: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = ""
    var code = ""
    var country = ""
    var arrival = TravelDay.key(.now)
    var nights = 3
    var latitude: Double?
    var longitude: Double?
    var departure: String { TravelDay.adding(nights, to: arrival) }
}
enum ItineraryItemKind: String, Codable, CaseIterable, Identifiable {
    case place, meeting, appointment, conference, celebration, concert, performance, sport, tour, transfer, train, ferry, shopping, wellness, freeTime, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .place: "Restaurant or activity"; case .meeting: "Meeting"; case .appointment: "Appointment"
        case .conference: "Conference"; case .celebration: "Celebration"; case .concert: "Concert"
        case .performance: "Theatre & performance"; case .sport: "Sporting event"; case .tour: "Tour & excursion"
        case .transfer: "Car & transfer"; case .train: "Train"; case .ferry: "Boat & ferry"
        case .shopping: "Shopping"; case .wellness: "Wellness"; case .freeTime: "Free time"; case .custom: "Custom event"
        }
    }
    var symbol: String {
        switch self {
        case .place: "fork.knife"; case .meeting: "person.2"; case .appointment: "calendar.badge.clock"
        case .conference: "person.3"; case .celebration: "party.popper"; case .concert: "music.mic"
        case .performance: "theatermasks"; case .sport: "sportscourt"; case .tour: "binoculars"
        case .transfer: "car"; case .train: "tram"; case .ferry: "ferry"
        case .shopping: "bag"; case .wellness: "leaf"; case .freeTime: "sun.horizon"; case .custom: "calendar.badge.plus"
        }
    }
    var titlePrompt: String {
        switch self {
        case .meeting: "Meeting title"; case .appointment: "Appointment with…"; case .conference: "Conference name"
        case .celebration: "What are you celebrating?"; case .concert: "Artist or concert"; case .performance: "Show or performance"
        case .sport: "Teams or sporting event"; case .tour: "Tour or excursion name"; case .transfer: "Transfer or driver"
        case .train: "Train service or route"; case .ferry: "Boat trip or sailing"; case .shopping: "Shopping plans"
        case .wellness: "Treatment or wellness session"; case .freeTime: "A little time for…"; default: "Event title"
        }
    }
    static let groups: [(title: String, items: [Self])] = [
        ("Discover & experience", [.place, .tour, .concert, .performance, .sport, .shopping, .wellness]),
        ("People & occasions", [.meeting, .appointment, .conference, .celebration]),
        ("Getting around", [.transfer, .train, .ferry]),
        ("Make it your own", [.freeTime, .custom])
    ]
}
struct JourneyEvent: Codable, Hashable, Identifiable {
    var id = UUID()
    var seriesID = UUID()
    var stopID: UUID
    var day = 0
    var minute = 19 * 60
    var place = PlaceRecord()
    var description = ""
    var links: [String] = []
    var cost: TravelMoney?
    // Optional fields keep previously saved itineraries compatible.
    var kind: ItineraryItemKind?
    var title: String?
    var allDay: Bool?
    var durationMinutes: Int?
    var attendees: String?
    var isPlaceVisit: Bool { kind == nil || kind == .place }
    var displayTitle: String { isPlaceVisit ? place.name : (title ?? "") }
    var categoryTitle: String { isPlaceVisit ? place.category.title : (kind?.title ?? "Event") }
    var symbol: String { isPlaceVisit ? place.category.symbol : (kind?.symbol ?? "calendar") }
    var sortMinute: Int { allDay == true ? -1 : minute }
    var endTimeLabel: String? {
        guard allDay != true, let durationMinutes else { return nil }
        let end = minute + durationMinutes
        return String(format: "%02d:%02d", (end / 60) % 24, end % 60) + (end >= 1440 ? " (+1 day)" : "")
    }
    var scheduleLabel: String { allDay == true ? "All day" : timeLabel + (endTimeLabel.map { " – " + $0 } ?? "") }
    var timeLabel: String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}
struct HotelReservation: Codable, Hashable, Identifiable {
    var id = UUID()
    var place = PlaceRecord(category: .hotel)
    var checkIn = TravelDay.key(.now)
    var checkOut = TravelDay.adding(3, to: TravelDay.key(.now))
    var guests = 2
    var rooms = 1
    var roomType = ""
    var confirmation = ""
    var cost: TravelMoney?
    var notes = ""
    var overview = ""
}
struct FlightReservation: Codable, Hashable, Identifiable {
    var id = UUID()
    var airline = ""
    var flightNumber = ""
    var departureAirport = ""
    var arrivalAirport = ""
    var departureDay = TravelDay.key(.now)
    var arrivalDay = TravelDay.key(.now)
    var departureTime = "09:00"
    var arrivalTime = "12:00"
    var departureLatitude: Double?
    var departureLongitude: Double?
    var arrivalLatitude: Double?
    var arrivalLongitude: Double?
    var departureZone = ""
    var arrivalZone = ""
    var cost: TravelMoney?
    var bookingLink = ""
    var notes = ""
}
struct JournalPhoto: Codable, Hashable, Identifiable { var id = UUID(); var jpeg: Data }
struct RatedPlace: Codable, Hashable, Identifiable {
    var id = UUID()
    var place = PlaceRecord()
    var overall: Double = 0
    var scores: [String: Double] = [:]
    var notes = ""
    var visitedOn: String?
    var priceRange = ""
    var michelinStars: Int?
    var photos: [JournalPhoto] = []
}
struct JourneyDocument: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: JourneyKind = .journey
    var title = ""
    var destination = ""
    var description = ""
    var dateMode: JourneyDateMode = .dates
    var startDate: String?
    var endDate: String?
    var visibility: JourneyVisibility = .private
    var stops: [JourneyStop] = []
    var events: [JourneyEvent] = []
    var hotels: [HotelReservation] = []
    var flights: [FlightReservation] = []
    var places: [RatedPlace] = []
    var updatedAt: Double = Date.now.timeIntervalSince1970
    var importedFrom: String?
    /// Older trips stored a destination and dates without a route. Reuse those choices.
    @discardableResult mutating func preparePlanningRoute() -> Bool {
        guard stops.isEmpty, !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let startDate, let endDate, TravelDay.date(startDate) != nil, TravelDay.date(endDate) != nil,
              (1...365).contains(TravelDay.distance(startDate, endDate)) else { return false }
        stops = [JourneyStop(name: destination.trimmingCharacters(in: .whitespacesAndNewlines), arrival: startDate, nights: TravelDay.distance(startDate, endDate))]
        dateMode = .dates
        return true
    }
    var routeLabel: String { stops.isEmpty ? destination : stops.map(\.name).joined(separator: " → ") }
    var nights: Int { stops.reduce(0) { $0 + $1.nights } }
    var planCount: Int { events.count + hotels.count + flights.count }
    var eventTotals: [String: Decimal] { Self.totals(events.compactMap(\.cost)) }
    var totals: [String: Decimal] { Self.totals(events.compactMap(\.cost) + hotels.compactMap(\.cost) + flights.compactMap(\.cost)) }
    static func totals(_ costs: [TravelMoney]) -> [String: Decimal] { costs.reduce(into: [:]) { $0[$1.currency, default: 0] += $1.amount } }
    var mapPlaces: [PlaceRecord] {
        let destinations = stops.map { PlaceRecord(id: "stop-" + $0.id.uuidString, name: $0.name, category: .other, city: $0.name, latitude: $0.latitude, longitude: $0.longitude, source: "Destination") }
        let airports = flights.flatMap { flight in [
            PlaceRecord(id: "departure-" + flight.id.uuidString, name: flight.departureAirport, category: .other, latitude: flight.departureLatitude, longitude: flight.departureLongitude, source: "Flight departure"),
            PlaceRecord(id: "arrival-" + flight.id.uuidString, name: flight.arrivalAirport, category: .other, latitude: flight.arrivalLatitude, longitude: flight.arrivalLongitude, source: "Flight arrival")
        ] }
        let eventLocations = events.map { event in
            var location = event.place
            if !event.isPlaceVisit { location.id = event.id.uuidString; location.name = event.displayTitle + (location.name.isEmpty ? "" : " · " + location.name) }
            return location
        }
        return destinations + eventLocations + hotels.map(\.place) + airports + places.map(\.place)
    }
    var averageScore: Double? { let ratings = places.map(\.overall).filter { $0 > 0 }; return ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count) }
    var days: [JourneyAgendaDay] {
        var offset = 0
        return stops.flatMap { stop -> [JourneyAgendaDay] in
            defer { offset += stop.nights }
            return (0...max(0, stop.nights)).map { day in JourneyAgendaDay(stopID: stop.id, localDay: day, index: offset + day, city: stop.name, date: dateMode == .dates ? TravelDay.adding(day, to: stop.arrival) : nil) }
        }
    }
    func date(for event: JourneyEvent) -> String? { guard dateMode == .dates, let stop = stops.first(where: { $0.id == event.stopID }) else { return nil }; return TravelDay.adding(event.day, to: stop.arrival) }
    mutating func putEvent(_ event: JourneyEvent, on days: Set<Int>) {
        guard !days.isEmpty else { return }
        events.removeAll { $0.id == event.id }
        for (index, day) in days.sorted().enumerated() {
            var copy = event; copy.day = day
            if let existing = events.first(where: { $0.seriesID == event.seriesID && $0.stopID == event.stopID && $0.day == day }) {
                copy.id = existing.id; events.removeAll { $0.id == existing.id }
            } else if index > 0 { copy.id = UUID() }
            events.append(copy)
        }
    }
    var plannedPlacesToRate: [RatedPlace] {
        var seen = Set<String>()
        return events.filter { $0.isPlaceVisit && $0.place.category.isImportablePlace }.compactMap { event in
            guard seen.insert(event.place.source + "::" + event.place.id).inserted else { return nil }
            return RatedPlace(place: event.place)
        }
    }
    @discardableResult mutating func addPlannedPlacesToJournal(from source: JourneyDocument? = nil) -> Int {
        var existing = Set(places.map { $0.place.source + "::" + $0.place.id })
        let additions = (source ?? self).plannedPlacesToRate.filter { existing.insert($0.place.source + "::" + $0.place.id).inserted }
        places += additions
        return additions.count
    }
    func copyAsTrip() -> JourneyDocument {
        var trip = JourneyDocument(kind: .trip, title: title, destination: routeLabel, description: description, startDate: startDate, endDate: endDate)
        var seen = Set<String>()
        trip.places = events.filter { $0.isPlaceVisit && $0.place.category.isImportablePlace }.compactMap { event in
            let key = event.place.source + "::" + event.place.id
            guard seen.insert(key).inserted else { return nil }
            return RatedPlace(place: event.place)
        }
        trip.importedFrom = title
        return trip
    }
    func validationError() -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give your journey a title." }
        if title.count > 200 || description.count > 20000 { return "Shorten the title or description." }
        if stops.count > 40 || events.count > 2000 || places.count > 500 { return "This journey exceeds the supported size." }
        if let startDate, TravelDay.date(startDate) == nil { return "Choose a valid start date." }
        if let endDate, TravelDay.date(endDate) == nil { return "Choose a valid end date." }
        if let startDate, let endDate, endDate < startDate { return "End date must be on or after start date." }
        if Set(stops.map(\.id)).count != stops.count { return "Duplicate destination identifiers." }
        for (index, stop) in stops.enumerated() {
            if stop.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(1...365).contains(stop.nights) { return "Each destination needs a name and 1–365 nights." }
            if dateMode == .dates {
                if TravelDay.date(stop.arrival) == nil { return "Choose a valid arrival date." }
                if index > 0 && stop.arrival < stops[index - 1].departure { return "Destination dates overlap. The next stop must start on or after the previous checkout." }
            }
        }
        for e in events {
            guard let stop = stops.first(where: { $0.id == e.stopID }), (0...stop.nights).contains(e.day), (0..<1440).contains(e.minute), !e.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "An event needs a valid destination, day, time and name." }
            if e.displayTitle.count > 500 || (e.attendees?.count ?? 0) > 2000 { return "Shorten the event title or guest list." }
            if let duration = e.durationMinutes, !(1...1440).contains(duration) { return "Event duration must be between one minute and 24 hours." }
            if e.links.contains(where: { validatedURL($0) == nil }) { return "Event links must start with https:// or http://." }
        }
        for h in hotels {
            if h.place.name.isEmpty || TravelDay.date(h.checkIn) == nil || TravelDay.date(h.checkOut) == nil || h.checkOut <= h.checkIn || !(1...99).contains(h.guests) || !(1...50).contains(h.rooms) { return "Check hotel names, dates, guests and rooms." }
        }
        for f in flights {
            if f.airline.isEmpty || f.departureAirport.isEmpty || f.arrivalAirport.isEmpty || TravelDay.date(f.departureDay) == nil || TravelDay.date(f.arrivalDay) == nil || !Self.validTime(f.departureTime) || !Self.validTime(f.arrivalTime) { return "Check the flight airline, airports, dates and local times." }
            if !f.bookingLink.isEmpty && validatedURL(f.bookingLink) == nil { return "Enter a valid flight booking URL." }
        }
        for p in places {
            if p.place.name.isEmpty || !p.overall.isFinite || !(0...10).contains(p.overall) || p.scores.values.contains(where: { !$0.isFinite || !(0...10).contains($0) }) { return "Place ratings must be between 0 and 10." }
            if let day = p.visitedOn, TravelDay.date(day) == nil { return "Choose a valid visit date." }
            if let stars = p.michelinStars, !(0...3).contains(stars) { return "Michelin stars must be between 0 and 3." }
            if p.photos.count > 6 || p.photos.contains(where: { $0.jpeg.count > 1_500_000 }) { return "Use up to six photos, each smaller than 1.5 MB." }
        }
        let allPlaces = events.map(\.place) + hotels.map(\.place) + places.map(\.place)
        if allPlaces.contains(where: { ($0.latitude != nil || $0.longitude != nil) && !$0.hasCoordinate }) { return "Enter valid latitude and longitude together." }
        for money in events.compactMap(\.cost) + hotels.compactMap(\.cost) + flights.compactMap(\.cost) {
            if money.amount.isNaN || money.amount < 0 || money.amount > 1_000_000_000 || money.currency.count != 3 { return "Enter a valid nonnegative price and three-letter currency." }
        }
        return nil
    }
    static func validTime(_ value: String) -> Bool { let p = value.split(separator: ":").compactMap { Int($0) }; return p.count == 2 && (0...23).contains(p[0]) && (0...59).contains(p[1]) }
}
struct JourneyAgendaDay: Identifiable, Hashable {
    var stopID: UUID
    var localDay: Int
    var index: Int
    var city: String
    var date: String?
    var id: String { stopID.uuidString + ":" + String(localDay) }
    var label: String { date.map(TravelDay.label) ?? "Day \(index + 1)" }
}
struct JourneyArchive: Codable { var version = 1; var document: JourneyDocument }
struct JourneyLibraryArchive: Codable { var version = 1; var documents: [JourneyDocument] }

@MainActor @Observable final class JourneyLibrary {
    private(set) var documents: [JourneyDocument] = []
    var error: String?
    private let url: URL
    private var loadFailed = false
    init(url: URL? = nil) {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(testing ? "AurumUITestTravel/library.json" : "AurumTravel/library.json")
        if url == nil && testing && !ProcessInfo.processInfo.arguments.contains("--preserve-state") { try? FileManager.default.removeItem(at: self.url) }
        #if DEBUG
        if url == nil && FlightMapFixtures.enabled && !ProcessInfo.processInfo.arguments.contains("--preserve-state") { documents = [FlightMapFixtures.trip]; return }
        #endif
        guard FileManager.default.fileExists(atPath: self.url.path) else { return }
        do {
            let archive = try JSONDecoder().decode(JourneyLibraryArchive.self, from: Data(contentsOf: self.url))
            guard archive.version == 1 else { throw JourneyError.message("This library was made with a newer Aurum version.") }
            documents = archive.documents
        } catch { loadFailed = true; self.error = "Your travel library couldn’t be loaded. Your original file has been kept: \(error.localizedDescription)" }
    }
    @discardableResult func save(_ input: JourneyDocument) -> Bool {
        if let validation = input.validationError() { error = validation; return false }
        var document = input; document.kind = .journey; document.updatedAt = Date.now.timeIntervalSince1970
        var next = documents
        if let i = next.firstIndex(where: { $0.id == document.id }) { next[i] = document } else { next.insert(document, at: 0) }
        return persist(next)
    }
    @discardableResult func remove(_ id: UUID) -> Bool { persist(documents.filter { $0.id != id }) }
    private func persist(_ next: [JourneyDocument]) -> Bool {
        guard !loadFailed else { error = "Your unreadable library has been preserved. Restore a valid backup before saving new journeys."; return false }
        do {
            let data = try JSONEncoder().encode(JourneyLibraryArchive(documents: next))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            documents = next; error = nil; return true
        } catch { self.error = "Couldn’t save this journey: \(error.localizedDescription)"; return false }
    }
    func importData(_ data: Data) throws -> UUID {
        guard data.count <= 40_000_000 else { throw JourneyError.message("This file is too large (40 MB maximum).") }
        let archive = try JSONDecoder().decode(JourneyArchive.self, from: data)
        guard archive.version == 1 else { throw JourneyError.message("Unsupported Aurum file version.") }
        var copy = archive.document
        if let reason = copy.validationError() { throw JourneyError.message(reason) }
        copy.id = UUID(); copy.visibility = .private; copy.importedFrom = copy.title
        guard save(copy) else { throw JourneyError.message(error ?? "Import failed.") }
        return copy.id
    }
}
enum JourneyError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let text) = self { return text }; return nil } }
