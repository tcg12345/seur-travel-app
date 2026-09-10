import Foundation

// Shared with the extension. Deliberately excludes photos, credentials, notes,
// booking references, companion identities and the full journey archive.
struct JourneyWidgetSnapshot: Codable {
    var version = 1
    var savedAt: Date
    var expiresAt: Date
    var trips: [JourneyWidgetTrip]
    // Optional so caches written before the history widget still decode.
    var profile: JourneyWidgetProfile? = nil
    func travelProfile(at date: Date) -> JourneyWidgetProfile? { version == 1 && date < expiresAt ? profile : nil }
    func available(at date: Date) -> [JourneyWidgetTrip] { version == 1 && date < expiresAt ? trips : [] }
    func active(at date: Date) -> JourneyWidgetTrip? {
        available(at: date).filter { $0.isActive(at: date) }.sorted {
            if $0.startDay != $1.startDay { return $0.startDay > $1.startDay }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }
    func upcoming(at date: Date) -> JourneyWidgetTrip? {
        available(at: date).filter { $0.localDay(at: date) < $0.startDay }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }
    /// Keep each rendered timeline entry small; the full cache stays in the provider.
    func displaySnapshot(at date: Date) -> Self {
        let ids = Set([active(at: date)?.id, upcoming(at: date)?.id].compactMap { $0 })
        var copy = self
        copy.trips = trips.filter { ids.contains($0.id) }.map { trip in
            var displayed = trip
            displayed.days = trip.days.filter { $0.key == trip.localDay(at: date) && $0.zone == trip.zone(at: date) }
            return displayed
        }
        return copy
    }
    /// Predictable hourly/day updates plus timed-item boundaries; no polling network.
    func refreshDates(after now: Date) -> [Date] {
        let horizon = now.addingTimeInterval(6 * 3600)
        var dates = Set((0...6).map { now.addingTimeInterval(Double($0) * 3600) })
        if expiresAt > now && expiresAt <= horizon { dates.insert(expiresAt) }
        for trip in available(at: now) {
            for zone in Set(trip.stops.map(\.zone) + [trip.fallbackZone]) {
                let calendar = WidgetCalendar.calendar(zone)
                if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)), midnight <= horizon { dates.insert(midnight) }
            }
            for item in trip.days.flatMap(\.items) {
                for boundary in [item.start, (item.end ?? item.start)?.addingTimeInterval(1)].compactMap({ $0 }) where boundary > now && boundary <= horizon { dates.insert(boundary) }
            }
        }
        // Request the next timeline at its final entry if a busy itinerary hits the cap.
        return Array(dates.sorted().prefix(48))
    }
}
struct JourneyWidgetProfile: Codable, Equatable {
    var trips: Int
    var countries: Int
    var cities: Int
    var nights: Int
    var nightsLabel: String
    var stars: Int
    var favoriteCities: String?
    var recent: [JourneyWidgetHistoryTrip]
    static let url = URL(string: "seur://profile")!
    static func matches(_ url: URL) -> Bool { url == Self.url }
}
struct JourneyWidgetHistoryTrip: Codable, Equatable {
    var title: String
    var destination: String
    var endDay: String
}
struct JourneyWidgetStop: Codable {
    var name: String
    var arrival: String
    var departure: String
    var zone: String
}
struct JourneyWidgetTrip: Codable, Identifiable {
    var id: UUID
    var title: String
    var destination: String
    var startDay: String
    var endDay: String
    var start: Date
    var updatedAt: Double
    var fallbackZone: String
    var stops: [JourneyWidgetStop]
    var days: [JourneyWidgetDay]
    var currency: String
    var target: Decimal?
    var spent: Decimal?
    var originalSpent: String
    var rateDate: String?
    func stop(at date: Date) -> JourneyWidgetStop? {
        let ordered = stops.sorted { $0.arrival < $1.arrival }
        return ordered.last { stop in
            let day = WidgetCalendar.key(date, zone: stop.zone)
            return stop.arrival <= day && day < stop.departure
        } ?? ordered.last { WidgetCalendar.key(date, zone: $0.zone) >= $0.arrival } ?? ordered.first
    }
    func zone(at date: Date) -> String { stop(at: date)?.zone ?? fallbackZone }
    func localDay(at date: Date) -> String { WidgetCalendar.key(date, zone: zone(at: date)) }
    func isActive(at date: Date) -> Bool { let day = localDay(at: date); return startDay <= day && day <= endDay }
    func items(at date: Date) -> [JourneyWidgetItem] {
        guard isActive(at: date) else { return [] }
        return days.first { $0.key == localDay(at: date) && $0.zone == zone(at: date) }?.items ?? []
    }
    func remaining(at date: Date) -> [JourneyWidgetItem] {
        let items = items(at: date).filter { ($0.end ?? $0.start).map { $0 >= date } ?? true }
        // Confirmed timed plans lead; date-only reminders never pretend to be "up next".
        return items.filter { $0.start != nil } + items.filter { $0.start == nil }
    }
    func daysUntil(_ date: Date) -> Int {
        let calendar = WidgetCalendar.calendar(stops.first?.zone ?? fallbackZone)
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: start)).day ?? 0)
    }
    func burnRate(at date: Date) -> Decimal? {
        guard let spent, localDay(at: date) >= startDay,
              let from = WidgetCalendar.date(startDay), let to = WidgetCalendar.date(min(endDay, localDay(at: date))) else { return nil }
        let days = WidgetCalendar.calendar("UTC").dateComponents([.day], from: from, to: to).day ?? 0
        return spent / Decimal(max(1, days + 1))
    }
}
struct JourneyWidgetDay: Codable {
    var key: String
    var zone: String
    var items: [JourneyWidgetItem]
}
struct JourneyWidgetItem: Codable, Identifiable {
    var id: String
    var title: String
    var symbol: String
    var schedule: String
    var zone: String
    var start: Date?
    var end: Date?
}
enum WidgetCalendar {
    static func calendar(_ zone: String) -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone) ?? .current; return c }
    static func key(_ date: Date, zone: String) -> String {
        let p = calendar(zone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }
    static func date(_ key: String, zone: String = "UTC") -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let value = calendar(zone).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), Self.key(value, zone: zone) == key else { return nil }
        return value
    }
}
enum JourneyWidgetKind: String, CaseIterable { case today = "SeurToday", nextTrip = "SeurNextTrip", budget = "SeurTripBudget", profile = "SeurTravelProfile" }
struct JourneyWidgetLink: Hashable, Identifiable {
    var tripID: UUID
    var kind: JourneyWidgetKind
    var id: String { tripID.uuidString + kind.rawValue }
    var url: URL { URL(string: "seur://trip/" + tripID.uuidString + "?widget=" + kind.rawValue)! }
    init(tripID: UUID, kind: JourneyWidgetKind) { self.tripID = tripID; self.kind = kind }
    init?(url: URL) {
        guard url.scheme == "seur", url.host == "trip", url.pathComponents.count == 2,
              let id = UUID(uuidString: url.lastPathComponent), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = parts.queryItems?.first(where: { $0.name == "widget" })?.value, let kind = JourneyWidgetKind(rawValue: raw), kind != .profile else { return nil }
        self.init(tripID: id, kind: kind)
    }
}
enum JourneyWidgetStore {
    static let group = "group.com.seurapp.travel"
    static var sharedURL: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("journey-widgets-v1.json") }
    static func read(from url: URL?) -> JourneyWidgetSnapshot? {
        guard let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 5_000_000,
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(JourneyWidgetSnapshot.self, from: data), value.version == 1 else { return nil }
        return value
    }
    static func write(_ snapshot: JourneyWidgetSnapshot, to url: URL) throws {
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 5_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
