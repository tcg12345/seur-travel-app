import Foundation

struct TemplateMeta: Codable, Hashable {
    var tagline = ""
    var tags: [String] = []
    var suggestedSeason = ""
    var authorHandle = ""
    var cloneCount = 0
    var sourceTitle: String?
    var includesRatings: Bool?
    var includesCosts: Bool?
}
enum TemplateError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
extension JourneyDocument {
    func templated(meta: TemplateMeta, includeCosts: Bool = false, includeRatings: Bool = false) throws -> JourneyDocument {
        guard !stops.isEmpty else { throw TemplateError.invalid("Add at least one destination before making a template.") }
        var template = self
        template.id = UUID(); template.kind = .journey; template.isTemplate = true
        template.visibility = .private; template.description = ""; template.importedFrom = nil
        template.templateMeta = meta; template.templateMeta?.cloneCount = 0
        template.templateMeta?.includesCosts = includeCosts; template.templateMeta?.includesRatings = includeRatings
        template.templateMeta?.sourceTitle = title
        template.routePlan = nil
        template.budgetTarget = nil; template.homeCurrency = nil; template.companions = nil
        template.events = events.map { item in
            var event = item; event.attendees = nil; event.description = ""; event.links = []
            event.place.overview = ""; event.routeLegID = nil; event.routeMode = nil
            event.isDone = nil
            if let cost = event.cost { event.cost = TravelMoney(amount: cost.amount, currency: cost.currency) }
            if !includeCosts { event.cost = nil }; return event
        }
        template.hotels = hotels.map { hotel in
            var hotel = hotel; hotel.checkOutTime = nil; hotel.confirmation = ""; hotel.notes = ""; hotel.overview = ""; hotel.roomType = ""
            hotel.guests = 2; hotel.rooms = 1; hotel.place.overview = ""
            if let cost = hotel.cost { hotel.cost = TravelMoney(amount: cost.amount, currency: cost.currency) }
            if !includeCosts { hotel.cost = nil }; return hotel
        }
        // Air tickets are personal and date-specific. Their route remains represented by the stops.
        template.flights = []
        template.places = includeRatings ? places.map { rating in
            var rating = rating; rating.notes = ""; rating.photos = []; rating.visitedOn = nil; rating.place.overview = ""; return rating
        } : []
        if !includeRatings {
            template.events = template.events.map { var e = $0; e.place.rating = nil; return e }
            template.hotels = template.hotels.map { var h = $0; h.place.rating = nil; return h }
        }
        try template.shiftTemplateDates(to: "2000-01-01")
        template.dateMode = .nights; template.startDate = nil; template.endDate = nil
        template.updatedAt = Date.now.timeIntervalSince1970
        if let error = template.validationError() { throw TemplateError.invalid(error) }
        return template
    }
    func usingTemplate(departure: String) throws -> JourneyDocument {
        guard isTemplate == true, !stops.isEmpty, TravelDay.date(departure) != nil else { throw TemplateError.invalid("Choose a valid departure date for this template.") }
        // Re-sanitize on import too, including templates written by another client.
        var trip = try templated(meta: templateMeta ?? TemplateMeta(), includeCosts: templateMeta?.includesCosts == true, includeRatings: templateMeta?.includesRatings == true)
        try trip.shiftTemplateDates(to: departure)
        trip.isTemplate = false; trip.dateMode = .dates; trip.visibility = .private
        trip.startDate = departure; trip.endDate = trip.stops.last?.departure
        trip.importedFrom = id.uuidString; trip.templateMeta = templateMeta
        trip.templateMeta?.sourceTitle = title
        if let error = trip.validationError() { throw TemplateError.invalid(error) }
        return trip
    }
    private mutating func shiftTemplateDates(to departure: String) throws {
        let originals = stops
        var next = departure
        for index in stops.indices { stops[index].arrival = next; next = stops[index].departure }
        for index in hotels.indices {
            let hotel = hotels[index]
            let candidates = originals.filter { $0.arrival <= hotel.checkIn && hotel.checkIn < $0.departure && hotel.checkOut <= $0.departure }
            let named = candidates.filter { !$0.name.isEmpty && (hotel.place.city.localizedCaseInsensitiveContains($0.name) || $0.name.localizedCaseInsensitiveContains(hotel.place.city) && !hotel.place.city.isEmpty) }
            guard let stop = (named.count == 1 ? named.first : candidates.count == 1 ? candidates.first : nil),
                  let shifted = stops.first(where: { $0.id == stop.id }) else {
                throw TemplateError.invalid("Match the stay at \(hotel.place.name) to one destination's dates before saving this template.")
            }
            hotels[index].checkIn = TravelDay.adding(TravelDay.distance(stop.arrival, hotel.checkIn), to: shifted.arrival)
            hotels[index].checkOut = TravelDay.adding(TravelDay.distance(stop.arrival, hotel.checkOut), to: shifted.arrival)
        }
    }
}
enum TemplateCatalog {
    static let bundled: [JourneyDocument] = {
        guard let url = Bundle.main.url(forResource: "TripTemplates", withExtension: "json"),
              let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([JourneyDocument].self, from: data) else { return [] }
        return values
    }()
    static func matches(_ document: JourneyDocument, city: String, tag: String = "") -> Bool {
        document.isTemplate == true && (city.isEmpty || ([document.title, document.destination] + document.stops.map(\.name)).contains { $0.localizedCaseInsensitiveContains(city) }) && (tag.isEmpty || document.templateMeta?.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } == true)
    }
}
