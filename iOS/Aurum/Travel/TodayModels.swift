import Foundation

/// Local itinerary projection. No network, storage, or UI dependencies: also usable by a future widget.
enum TodayPlanner {
    struct Context {
        var day: String
        var zone: TimeZone
        var stop: JourneyStop?
        var agendaDays: [JourneyAgendaDay]
    }
    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone; return calendar
    }
    static func key(_ date: Date, zone: TimeZone) -> String {
        let parts = calendar(zone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    static func date(_ day: String, minute: Int, zone: TimeZone) -> Date? {
        guard let date = TravelDay.date(day) else { return nil }
        var parts = TravelDay.calendar.dateComponents([.year, .month, .day], from: date)
        parts.hour = minute / 60; parts.minute = minute % 60
        return calendar(zone).date(from: parts)
    }
    static func zone(for stop: JourneyStop?, in document: JourneyDocument, fallback: TimeZone = .current) -> TimeZone {
        guard let stop else { return fallback }
        if let id = stop.timeZone, let zone = TimeZone(identifier: id) { return zone }
        // Older trips can recover their destination zone from a nearby arrival airport.
        if let point = RoutePoint(stop) {
            for flight in document.flights.sorted(by: { $0.arrivalDay > $1.arrivalDay }) {
                guard flight.arrivalDay <= stop.departure, flight.arrivalDay >= TravelDay.adding(-1, to: stop.arrival),
                      let lat = flight.arrivalLatitude, let lon = flight.arrivalLongitude,
                      let zone = TimeZone(identifier: flight.arrivalZone) else { continue }
                let airport = RoutePoint(id: "", name: "", latitude: lat, longitude: lon)
                if airport.valid && point.distance(to: airport) < 150 { return zone }
            }
        }
        return fallback
    }
    static func context(_ document: JourneyDocument, now: Date, fallback: TimeZone = .current) -> Context {
        let stops = document.stops.sorted { $0.arrival < $1.arrival }
        // Half-open stays give a transfer day to the incoming city; checkout plans still render.
        let stop = stops.last { stop in
            let day = key(now, zone: Self.zone(for: stop, in: document, fallback: fallback))
            return stop.arrival <= day && day < stop.departure
        } ?? stops.last { key(now, zone: Self.zone(for: $0, in: document, fallback: fallback)) >= $0.arrival } ?? stops.first
        let zone = Self.zone(for: stop, in: document, fallback: fallback)
        let day = key(now, zone: zone)
        return Context(day: day, zone: zone, stop: stop, agendaDays: document.days.filter { $0.date == day })
    }
    static func isActive(_ document: JourneyDocument, now: Date, fallback: TimeZone = .current) -> Bool {
        guard document.isTemplate != true, document.dateMode == .dates, let start = document.startDate, let end = document.endDate,
              TravelDay.date(start) != nil, TravelDay.date(end) != nil else { return false }
        let day = context(document, now: now, fallback: fallback).day
        return start <= day && day <= end
    }
    static func activeTrip(_ documents: [JourneyDocument], now: Date, fallback: TimeZone = .current) -> JourneyDocument? {
        documents.filter { isActive($0, now: now, fallback: fallback) }.sorted {
            if $0.startDate != $1.startDate { return ($0.startDate ?? "") > ($1.startDate ?? "") }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }
    static func items(_ document: JourneyDocument, day: String, zone: TimeZone, snapshots: [UUID: FlightSnapshot] = [:]) -> [TodayItem] {
        guard document.dateMode == .dates else { return [] }
        var result: [TodayItem] = []
        for event in document.events {
            guard let stop = document.stops.first(where: { $0.id == event.stopID }),
                  let eventDay = document.days.first(where: { $0.stopID == event.stopID && $0.localDay == event.day })?.date else { continue }
            let eventZone = self.zone(for: stop, in: document, fallback: zone)
            let start = date(eventDay, minute: event.minute, zone: eventZone)
            let allDay = event.allDay == true
            guard allDay ? eventDay == day : start.map({ key($0, zone: zone) == day }) ?? (eventDay == day) else { continue }
            let end = start.flatMap { start in event.durationMinutes.map { start.addingTimeInterval(Double($0) * 60) } }
            result.append(TodayItem(id: "event-\(event.id)", kind: .event, title: event.displayTitle, detail: event.categoryTitle,
                symbol: event.symbol, schedule: event.scheduleLabel, start: allDay ? nil : start, end: end,
                sortMinute: allDay ? -1 : minute(start, zone: zone, fallback: event.sortMinute), place: event.place,
                note: event.description, zone: eventZone, completed: event.isDone == true))
        }
        for hotel in document.hotels {
            for checkout in [true, false] where (checkout ? hotel.checkOut : hotel.checkIn) == day {
                // Reservations have dates, not check-in hours. These are ordering groups, never claimed times.
                result.append(TodayItem(id: "hotel-\(hotel.id)-\(checkout)", kind: .hotel,
                    title: (checkout ? "Check out · " : "Check in · ") + hotel.place.name,
                    detail: hotel.roomType, symbol: checkout ? "door.left.hand.open" : "bed.double",
                    schedule: checkout ? "Morning" : "Afternoon", sortMinute: checkout ? 660 : 900,
                    place: hotel.place, confirmation: hotel.confirmation,
                    note: "Confirm " + (checkout ? "checkout" : "check-in") + " time with the hotel.", zone: zone))
            }
        }
        for flight in document.flights {
            let snapshot = snapshots[flight.id]
            for departure in [true, false] {
                let flightDay = departure ? flight.departureDay : flight.arrivalDay
                let flightZone = TimeZone(identifier: departure ? flight.departureZone : flight.arrivalZone) ?? zone
                let saved = FlightDisplay.localDate(day: flightDay, time: departure ? flight.departureTime : flight.arrivalTime, zone: flightZone.identifier)
                let live = FlightSnapshot.date(departure ? snapshot?.actualOut ?? snapshot?.estimatedOut : snapshot?.actualIn ?? snapshot?.estimatedIn)
                let start = live ?? saved
                // Keep a delayed flight on its booked day as well as its new day so it cannot disappear.
                guard (saved.map({ key($0, zone: zone) == day }) ?? (flightDay == day)) || start.map({ key($0, zone: zone) == day }) == true else { continue }
                let airport = departure ? flight.departureAirport : flight.arrivalAirport
                let place = PlaceRecord(name: airport, category: .other,
                    latitude: departure ? flight.departureLatitude : flight.arrivalLatitude,
                    longitude: departure ? flight.departureLongitude : flight.arrivalLongitude)
                let timing = snapshot?.timing(departure: departure)
                let gate = departure ? snapshot?.gateOrigin : snapshot?.gateDestination
                let terminal = departure ? snapshot?.terminalOrigin : snapshot?.terminalDestination
                let location = [gate.flatMap { $0.isEmpty ? nil : "Gate " + $0 }, terminal.flatMap { $0.isEmpty ? nil : "Terminal " + $0 }].compactMap { $0 }.joined(separator: " · ")
                result.append(TodayItem(id: "flight-\(flight.id)-\(departure)", kind: .flight,
                    title: (departure ? "Depart " : "Arrive ") + airport,
                    detail: [flight.flightNumber, flight.airline, location].filter { !$0.isEmpty }.joined(separator: " · "),
                    symbol: departure ? "airplane.departure" : "airplane.arrival",
                    schedule: start.map { clock($0, zone: flightZone) } ?? (departure ? flight.departureTime : flight.arrivalTime),
                    start: start, sortMinute: minute(start, zone: zone, fallback: 0) + (start.map { TravelDay.distance(day, key($0, zone: zone)) * 1440 } ?? 0), place: place,
                    bookingLink: flight.bookingLink, zone: flightZone, flightID: flight.id, timing: timing,
                    completed: (departure ? snapshot?.actualOut : snapshot?.actualIn) != nil || snapshot?.cancelled == true,
                    scheduled: saved))
            }
        }
        return result.sorted { $0.sortMinute == $1.sortMinute ? $0.id < $1.id : $0.sortMinute < $1.sortMinute }
    }
    /// Only confirmed timed items can be "next"; date-only hotel reminders are still in the timeline.
    static func nextItem(_ items: [TodayItem], now: Date) -> TodayItem? {
        items.filter { !$0.completed && $0.start != nil && (($0.end ?? $0.start!) >= now) }
            .sorted { $0.start! == $1.start! ? $0.id < $1.id : $0.start! < $1.start! }.first
    }
    static func clock(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter(); formatter.timeZone = zone; formatter.dateFormat = "HH:mm"; return formatter.string(from: date)
    }
    private static func minute(_ date: Date?, zone: TimeZone, fallback: Int) -> Int {
        guard let date else { return fallback }
        let parts = calendar(zone).dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
struct TodayItem: Identifiable {
    enum Kind { case event, hotel, flight }
    var id: String
    var kind: Kind
    var title: String
    var detail: String
    var symbol: String
    var schedule: String
    var start: Date?
    var end: Date?
    var sortMinute: Int
    var place: PlaceRecord
    var confirmation = ""
    var bookingLink = ""
    var note = ""
    var zone: TimeZone
    var flightID: UUID?
    var timing: FlightTiming?
    var completed = false
    var scheduled: Date?
}
enum TravelPlaceActions {
    static func directions(_ place: PlaceRecord) -> URL? {
        var url = URLComponents(); url.scheme = "maps"; url.host = ""
        if place.hasCoordinate {
            url.queryItems = [URLQueryItem(name: "daddr", value: "\(place.latitude!),\(place.longitude!)")]
        } else {
            let query = [place.name, place.address, place.city].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: ", ")
            guard !query.isEmpty else { return nil }
            url.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        return url.url
    }
    static func phone(_ value: String) -> URL? {
        let number = value.filter { "0123456789+".contains($0) }
        guard number.filter({ "0123456789".contains($0) }).count >= 3 else { return nil }
        return URL(string: "tel:" + number)
    }
    static func booking(_ value: String) -> URL? {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }; return url
    }
}
