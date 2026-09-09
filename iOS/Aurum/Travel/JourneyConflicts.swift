import Foundation

/// Advisory checks over saved plans only. No network, guessed durations or airport buffers.
enum JourneyConflicts {
    struct Warning: Identifiable, Equatable {
        enum Kind: String { case overlappingEvents, beforeArrival, checkoutAfterFlight }
        let kind: Kind
        let eventIDs: [UUID]
        var hotelID: UUID? = nil
        var flightID: UUID? = nil
        let title: String
        let detail: String
        var id: String { ([kind.rawValue] + eventIDs.map(\.uuidString).sorted() + [hotelID?.uuidString ?? "", flightID?.uuidString ?? ""]).joined(separator: "|") }
    }
    private struct TimedEvent {
        let event: JourneyEvent
        let stop: JourneyStop
        let day: String
        let start: Date
        let end: Date?
        let zone: TimeZone?
    }
    static func minute(_ time: String?) -> Int? {
        guard let time, (4...5).contains(time.count) else { return nil }
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }
    private static let utc = TimeZone(secondsFromGMT: 0)!
    /// Reject invalid clock times, including local times skipped by daylight-saving changes.
    private static func date(_ day: String, minute: Int, zone: TimeZone) -> Date? {
        guard (0..<1440).contains(minute), let result = TodayPlanner.date(day, minute: minute, zone: zone), TodayPlanner.key(result, zone: zone) == day else { return nil }
        let parts = TodayPlanner.calendar(zone).dateComponents([.hour, .minute], from: result)
        return parts.hour == minute / 60 && parts.minute == minute % 60 ? result : nil
    }
    private static func zone(_ stop: JourneyStop, in d: JourneyDocument) -> TimeZone? {
        if let id = stop.timeZone, let z = TimeZone(identifier: id) { return z }
        for f in d.flights {
            if near(stop, flight: f, arrival: true), let z = TimeZone(identifier: f.arrivalZone) { return z }
            if near(stop, flight: f, arrival: false), let z = TimeZone(identifier: f.departureZone) { return z }
        }
        return nil
    }
    private static func near(_ stop: JourneyStop, flight: FlightReservation, arrival: Bool) -> Bool {
        let lat = arrival ? flight.arrivalLatitude : flight.departureLatitude
        let lon = arrival ? flight.arrivalLongitude : flight.departureLongitude
        if let point = RoutePoint(stop), let lat, let lon {
            let airport = RoutePoint(id: "", name: "", latitude: lat, longitude: lon)
            return airport.valid && point.distance(to: airport) <= 150
        }
        let code = stop.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return (3...4).contains(code.count) && code == (arrival ? flight.arrivalAirport : flight.departureAirport).uppercased()
    }
    private static func hotelStop(_ hotel: HotelReservation, in d: JourneyDocument) -> JourneyStop? {
        let candidates = d.stops.filter { $0.arrival <= hotel.checkIn && hotel.checkIn < $0.departure }
        if hotel.place.hasCoordinate {
            let point = RoutePoint(id: "", name: "", latitude: hotel.place.latitude!, longitude: hotel.place.longitude!)
            return candidates.filter { RoutePoint($0).map { point.distance(to: $0) <= 60 } == true }
                .min { point.distance(to: RoutePoint($0)!) < point.distance(to: RoutePoint($1)!) }
                ?? JourneyStop(name: hotel.place.city, arrival: hotel.checkIn, nights: TravelDay.distance(hotel.checkIn, hotel.checkOut), latitude: hotel.place.latitude, longitude: hotel.place.longitude)
        }
        let city = TravelStatistics.normalized(hotel.place.city)
        let matches = candidates.filter { !city.isEmpty && TravelStatistics.normalized($0.name) == city }
        return matches.count == 1 ? matches[0] : nil
    }
    static func detect(_ d: JourneyDocument) -> [Warning] {
        let stops = Dictionary(d.stops.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let events: [TimedEvent] = d.events.compactMap { event in
            guard event.allDay != true, let stop = stops[event.stopID], (0...max(0, stop.nights)).contains(event.day) else { return nil }
            let zone = d.dateMode == .dates ? zone(stop, in: d) : nil
            let day = TravelDay.adding(event.day, to: d.dateMode == .dates ? stop.arrival : "2000-01-01")
            guard let start = date(day, minute: event.minute, zone: zone ?? utc) else { return nil }
            let end = event.durationMinutes.flatMap { (1...1440).contains($0) ? start.addingTimeInterval(Double($0 * 60)) : nil }
            return TimedEvent(event: event, stop: stop, day: day, start: start, end: end, zone: zone)
        }.sorted { $0.start == $1.start ? $0.event.id.uuidString < $1.event.id.uuidString : $0.start < $1.start }
        var warnings: [Warning] = []
        for (i, a) in events.enumerated() {
            for b in events.dropFirst(i + 1) {
                if b.start > a.start, a.end.map({ b.start >= $0 }) ?? true { break }
                // Comparing different destinations requires real zones and calendar dates.
                guard a.event.stopID == b.event.stopID || (d.dateMode == .dates && a.zone != nil && b.zone != nil) else { continue }
                let overlaps = a.start == b.start || (a.start < b.start && a.end.map { $0 > b.start } == true)
                guard overlaps else { continue }
                let aContext = a.stop.id != b.stop.id ? " · " + a.stop.name : (a.day != b.day && d.dateMode == .dates ? " · " + TravelDay.label(a.day) : "")
                let bContext = a.stop.id != b.stop.id ? " · " + b.stop.name : (a.day != b.day && d.dateMode == .dates ? " · " + TravelDay.label(b.day) : "")
                warnings.append(.init(kind: .overlappingEvents, eventIDs: [a.event.id,b.event.id], title: a.start == b.start ? "Two plans start together" : "Plans overlap",
                    detail: "\(a.event.displayTitle) (\(a.event.scheduleLabel)\(aContext)) and \(b.event.displayTitle) (\(b.event.scheduleLabel)\(bContext)) overlap. Review their times or durations."))
            }
        }
        // Flexible-date plans can have relative event conflicts, but not booked-date conflicts.
        guard d.dateMode == .dates, d.isTemplate != true else { return warnings }
        for item in events {
            let incoming: [(FlightReservation, Date, TimeZone)] = d.flights.compactMap { flight in
                guard near(item.stop, flight: flight, arrival: true), let minutes = minute(flight.arrivalTime) else { return nil }
                let arrivalZone = TimeZone(identifier: flight.arrivalZone) ?? item.zone ?? utc
                let eventZone = item.zone ?? arrivalZone
                guard let arrival = date(flight.arrivalDay, minute: minutes, zone: arrivalZone) else { return nil }
                let localDay = TodayPlanner.key(arrival, zone: eventZone)
                guard localDay >= TravelDay.adding(-1, to: item.stop.arrival), localDay <= item.stop.departure else { return nil }
                return (flight, arrival, eventZone)
            }
            // A subsequent return to this city must not invalidate plans after the first arrival.
            guard let (flight, arrival, eventZone) = incoming.min(by: { $0.1 < $1.1 }),
                  let start = date(item.day, minute: item.event.minute, zone: eventZone), start < arrival else { continue }
            let arrivalDay = TodayPlanner.key(arrival, zone: eventZone)
            let label = TodayPlanner.clock(arrival, zone: eventZone) + (arrivalDay != item.day ? " on " + TravelDay.label(arrivalDay) : "")
            warnings.append(.init(kind: .beforeArrival, eventIDs: [item.event.id], flightID: flight.id, title: "Plan starts before your flight arrives",
                detail: "\(item.event.displayTitle) starts at \(item.event.timeLabel). \(flight.flightNumber.isEmpty ? "Your flight" : flight.flightNumber) is scheduled to arrive at \(label) in \(item.stop.name)."))
        }
        for hotel in d.hotels {
            guard TravelDay.date(hotel.checkIn) != nil, TravelDay.date(hotel.checkOut) != nil, hotel.checkOut > hotel.checkIn,
                  let stop = hotelStop(hotel, in: d) else { continue }
            for flight in d.flights {
                guard near(stop, flight: flight, arrival: false), let minutes = minute(flight.departureTime) else { continue }
                let hotelZone = zone(stop, in: d) ?? TimeZone(identifier: flight.departureZone) ?? utc
                let flightZone = TimeZone(identifier: flight.departureZone) ?? hotelZone
                guard let departure = date(flight.departureDay, minute: minutes, zone: flightZone) else { continue }
                let departureDay = TodayPlanner.key(departure, zone: hotelZone)
                guard hotel.checkIn <= departureDay, departureDay <= hotel.checkOut else { continue }
                let laterDate = hotel.checkOut > departureDay
                let checkout = minute(hotel.checkOutTime).flatMap { date(hotel.checkOut, minute: $0, zone: hotelZone) }
                guard laterDate || checkout.map({ $0 > departure }) == true else { continue }
                let timing = TravelDay.label(departureDay) + " at " + TodayPlanner.clock(departure, zone: hotelZone)
                warnings.append(.init(kind: .checkoutAfterFlight, eventIDs: [], hotelID: hotel.id, flightID: flight.id,
                    title: laterDate ? "Hotel stay continues after your flight" : "Checkout is after your flight departs",
                    detail: "\(hotel.place.name) checkout: \(TravelDay.label(hotel.checkOut))\(hotel.checkOutTime.map { " at " + $0 } ?? ""). \(flight.flightNumber.isEmpty ? "Your flight" : flight.flightNumber) departs \(timing). Check your stay dates or plan an earlier checkout."))
            }
        }
        return warnings.sorted { $0.id < $1.id }
    }
}
