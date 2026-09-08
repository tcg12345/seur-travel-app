import Foundation
import Observation

/// Public flight status only. Booking references and the local journey never enter this archive.
@MainActor @Observable final class TodayFlightStatusStore {
    static let shared = TodayFlightStatusStore()
    private(set) var feeds: [String: FlightFeed] = [:]
    private(set) var failed: Set<String> = []
    private var attempts: [String: Date] = [:]
    private var running: Set<String> = []
    private let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AurumTravel/today-flight-status.json")
        if let data = try? Data(contentsOf: self.url), let saved = try? JSONDecoder().decode([String: FlightFeed].self, from: data) { feeds = saved }
    }
    static func key(_ flight: FlightReservation, server: String) -> String {
        server + "|" + flight.flightNumber.uppercased().filter { !$0.isWhitespace } + "|" + flight.departureDay
    }
    static func match(_ feed: FlightFeed?, flight: FlightReservation) -> FlightSnapshot? {
        guard let feed else { return nil }
        func airportMatches(_ provider: String, _ saved: String) -> Bool {
            let a = provider.uppercased(), b = saved.uppercased()
            // FlightAware may return ICAO for US airports saved as IATA.
            return a == b || (a.count == 4 && a.hasPrefix("K") && String(a.dropFirst()) == b)
        }
        let matches = feed.flights.filter {
            guard airportMatches($0.origin, flight.departureAirport), airportMatches($0.destination, flight.arrivalAirport),
                  let departure = FlightSnapshot.date($0.scheduledOut ?? $0.actualOut ?? $0.estimatedOut),
                  let zone = TimeZone(identifier: $0.originZone) ?? TimeZone(identifier: flight.departureZone) else { return false }
            return TodayPlanner.key(departure, zone: zone) == flight.departureDay
        }
        // A multi-leg or ambiguous result must never update the wrong reservation.
        return matches.count == 1 ? matches[0] : nil
    }
    func snapshot(_ flight: FlightReservation, server: String) -> FlightSnapshot? { Self.match(feeds[Self.key(flight, server: server)], flight: flight) }
    func label(_ flight: FlightReservation, server: String, now: Date) -> String {
        let key = Self.key(flight, server: server)
        guard snapshot(flight, server: server) != nil, let feed = feeds[key] else { return failed.contains(key) ? "Live status unavailable · saved schedule" : "Saved schedule" }
        let age = max(0, now.timeIntervalSince1970 - feed.fetchedAt)
        let minutes = Int(age / 60)
        let text = minutes < 1 ? "just now" : minutes < 60 ? "\(minutes)m ago" : minutes < 1440 ? "\(minutes / 60)h ago" : "\(minutes / 1440)d ago"
        return (age >= 300 || failed.contains(key) ? "Last known status · " : "Updated ") + text
    }
    func refresh(_ flight: FlightReservation, server: String, now: Date = .now, fetch: () async throws -> FlightFeed) async {
        let key = Self.key(flight, server: server)
        guard !flight.flightNumber.isEmpty, !running.contains(key),
              attempts[key].map({ now.timeIntervalSince($0) >= 300 }) ?? true,
              feeds[key].map({ now.timeIntervalSince1970 - $0.fetchedAt >= 300 }) ?? true else { return }
        attempts[key] = now; running.insert(key)
        defer { running.remove(key) }
        do {
            let feed = try await fetch()
            guard feed.fetchedAt.isFinite, feed.fetchedAt <= now.timeIntervalSince1970 + 300,
                  Self.match(feed, flight: flight) != nil else { failed.insert(key); return }
            feeds[key] = feed; failed.remove(key)
            feeds = Dictionary(uniqueKeysWithValues: feeds.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(64).map { ($0.key, $0.value) })
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(feeds).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch { failed.insert(key) } // Keep the last successful status, including across relaunches.
    }
}
