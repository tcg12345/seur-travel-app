import Foundation

/// Local, deterministic recap assembly; does not fetch or publish a journey.
struct TripRecap {
    struct Day: Identifiable {
        var id: String
        var label: String
        var cities: [String]
        var places: [RatedPlace]
        var stays: [HotelReservation]
    }
    struct Leg: Identifiable {
        var id: String
        var from: RoutePoint
        var to: RoutePoint
        var flight: Bool
        var step: Int
    }
    let document: JourneyDocument
    var stops: [RoutePoint] { document.stops.compactMap(RoutePoint.init) }
    var ratedCount: Int { document.places.filter { $0.overall > 0 }.count }
    var stars: Int { document.places.filter { $0.place.category == .restaurant }.reduce(0) { $0 + max(0, min(3, $1.michelinStars ?? 0)) } }
    var flightMiles: Int { Int(legs.filter(\.flight).reduce(0) { $0 + $1.from.distance(to: $1.to) } * 0.621371) }
    func hasEnded(now: Date = .now, fallbackZone: TimeZone = .current) -> Bool {
        guard document.dateMode == .dates, document.isTemplate != true, let end = document.endDate, TravelDay.date(end) != nil else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = document.stops.last?.timeZone.flatMap(TimeZone.init(identifier:)) ?? fallbackZone
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return end < String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    var legs: [Leg] {
        var result: [Leg] = []
        // Never bridge a missing city coordinate: doing so would invent a route.
        for i in document.stops.indices.dropFirst() {
            if let a = RoutePoint(document.stops[i-1]), let b = RoutePoint(document.stops[i]) {
                result.append(.init(id: "ground-\(i)", from: a, to: b, flight: false, step: stops.firstIndex(where: { $0.id == b.id }) ?? 0))
            }
        }
        for f in document.flights {
            guard let a = point(f.departureAirport, f.departureLatitude, f.departureLongitude), let b = point(f.arrivalAirport, f.arrivalLatitude, f.arrivalLongitude) else { continue }
            let nearest = stops.indices.min(by: { stops[$0].distance(to: b) < stops[$1].distance(to: b) }) ?? 0
            let dateStep = document.dateMode == .dates ? (document.stops.last(where: { $0.arrival <= f.departureDay }).flatMap { s in stops.firstIndex(where: { $0.id == s.id.uuidString }) } ?? 0) : 0
            let step = max(nearest, dateStep)
            // A booked flight replaces the city-to-city ground stroke for that leg.
            result.removeAll { !$0.flight && $0.from.distance(to: a) < 100 && $0.to.distance(to: b) < 100 }
            result.append(.init(id: f.id.uuidString, from: a, to: b, flight: true, step: step))
        }
        return result
    }
    var mapPoints: [RoutePoint] { stops + legs.filter(\.flight).flatMap { [$0.from, $0.to] } }
    private func point(_ name: String, _ lat: Double?, _ lon: Double?) -> RoutePoint? {
        guard let lat, let lon, lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return .init(id: name, name: name, latitude: lat, longitude: lon)
    }
    var days: [Day] {
        var result: [Day] = []
        for day in document.days {
            let key = day.date ?? String(format: "day-%03d", day.index)
            if let i = result.firstIndex(where: { $0.id == key }) {
                if !result[i].cities.contains(day.city) { result[i].cities.append(day.city) }
            } else { result.append(.init(id: key, label: day.date.map(TravelDay.label) ?? "Day \(day.index + 1)", cities: [day.city], places: [], stays: [])) }
        }
        // Legacy single-destination trips may not yet have stops.
        if result.isEmpty, document.dateMode == .dates, let start = document.startDate, let end = document.endDate,
           TravelDay.date(start) != nil, TravelDay.date(end) != nil, (0...365).contains(TravelDay.distance(start, end)) {
            result = (0...TravelDay.distance(start, end)).map { offset in
                let key = TravelDay.adding(offset, to: start)
                return .init(id: key, label: TravelDay.label(key), cities: [document.destination], places: [], stays: [])
            }
        }
        for place in document.places {
            let key = place.visitedOn.flatMap { TravelDay.date($0) != nil ? $0 : nil } ?? "undated"
            if let i = result.firstIndex(where: { $0.id == key }) { result[i].places.append(place) }
            else { result.append(.init(id: key, label: key == "undated" ? "Memories without a date" : TravelDay.label(key), cities: [place.place.city].filter { !$0.isEmpty }, places: [place], stays: [])) }
        }
        for hotel in document.hotels {
            if let i = result.firstIndex(where: { $0.id == hotel.checkIn }) { result[i].stays.append(hotel) }
            else {
                let key = TravelDay.date(hotel.checkIn) != nil ? hotel.checkIn : "undated"
                if let i = result.firstIndex(where: { $0.id == key }) { result[i].stays.append(hotel) }
                else { result.append(.init(id: key, label: key == "undated" ? "Memories without a date" : TravelDay.label(key), cities: [hotel.place.city].filter { !$0.isEmpty }, places: [], stays: [hotel])) }
            }
        }
        return result.sorted { $0.id < $1.id }
    }
    func rating(for hotel: HotelReservation) -> Double? {
        document.places.first { p in
            p.place.category == .hotel && p.overall > 0 &&
            ((p.place.id == hotel.place.id && p.place.source == hotel.place.source) ||
             (p.place.name.localizedCaseInsensitiveCompare(hotel.place.name) == .orderedSame && p.place.city.localizedCaseInsensitiveCompare(hotel.place.city) == .orderedSame)) &&
            (p.visitedOn == nil || (p.visitedOn! >= hotel.checkIn && p.visitedOn! <= hotel.checkOut))
        }?.overall
    }
    /// Strip personal fields before even constructing the upload. The server independently
    /// projects an allowlist, so a modified client cannot leak booking fields into a recap.
    func shareDocument(photoIDs: Set<UUID>) -> JourneyDocument {
        var copy = document
        copy.description = ""; copy.events = []; copy.routePlan = nil; copy.importedFrom = nil; copy.templateMeta = nil
        copy.hotels = copy.hotels.map { h in
            HotelReservation(id: h.id, place: safePlace(h.place), checkIn: h.checkIn, checkOut: h.checkOut)
        }
        copy.flights = copy.flights.map { f in var f = f; f.notes = ""; f.bookingLink = ""; f.cost = nil; return f }
        copy.places = copy.places.map { p in
            var p = p; p.notes = ""; p.scores = [:]; p.priceRange = ""; p.place = safePlace(p.place)
            p.photos = p.photos.filter { photoIDs.contains($0.id) }; return p
        }
        return copy
    }
    private func safePlace(_ p: PlaceRecord) -> PlaceRecord {
        PlaceRecord(id: p.id, name: p.name, category: p.category, city: p.city, latitude: p.latitude, longitude: p.longitude, source: p.source)
    }
}
