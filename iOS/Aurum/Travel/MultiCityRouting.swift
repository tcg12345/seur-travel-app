import Foundation

struct RoutePoint: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var valid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
    init(id: String, name: String, latitude: Double, longitude: Double) { self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude }
    init?(_ stop: JourneyStop) {
        guard let lat = stop.latitude, let lon = stop.longitude else { return nil }
        self.init(id: stop.id.uuidString, name: stop.name, latitude: lat, longitude: lon)
        if !valid { return nil }
    }
    func distance(to other: Self) -> Double {
        let r = Double.pi / 180, a = latitude * r, b = other.latitude * r
        let h = pow(sin((b - a) / 2), 2) + cos(a) * cos(b) * pow(sin((other.longitude - longitude) * r / 2), 2)
        return 6371 * 2 * asin(sqrt(min(1, max(0, h))))
    }
}
enum RouteMode: String, Codable, CaseIterable, Identifiable {
    case train, flight, transfer
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .train ? "tram" : self == .flight ? "airplane" : "car" }
}
enum RouteObjective: String, Codable, CaseIterable, Identifiable {
    case distance, time
    var id: String { rawValue }
    var title: String { self == .distance ? "Less backtracking" : "Less travel time" }
}
struct RouteLegChoice: Codable, Hashable {
    var key: String
    var mode: RouteMode
    var minutes: Int
    var extraDays: Int = 0
}
struct JourneyRoutePlan: Codable, Hashable {
    var home: RoutePoint?
    var returnHome = true
    var keepFirst = true
    var keepLast = false
    var preferTrain = true
    var objective: RouteObjective = .distance
    var choices: [RouteLegChoice] = []
    var reserveTransfers = true
    var valid: Bool {
        home?.valid != false && (home?.name.count ?? 0) <= 500 && choices.count <= 82 && Set(choices.map(\.key)).count == choices.count &&
        choices.allSatisfy { $0.key.count <= 200 && (15...4320).contains($0.minutes) && (max(0, $0.minutes / 1440)...3).contains($0.extraDays) }
    }
    func choice(_ key: String) -> RouteLegChoice? { choices.first { $0.key == key } }
}
struct RouteEstimate: Hashable {
    var mode: RouteMode
    var rideMinutes: Int
    var bufferMinutes: Int
    var explanation: String
    var source: String?
    var total: Int { rideMinutes + bufferMinutes }
    static func duration(_ minutes: Int) -> String { minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h" + (minutes % 60 == 0 ? "" : " \(minutes % 60)m") }
}
struct JourneyRouteLeg: Identifiable {
    var from: RoutePoint
    var to: RoutePoint
    var options: [RouteEstimate]
    var selected: RouteEstimate
    var extraDays: Int
    var customized: Bool
    var id: String { from.id + ">" + to.id }
    var distance: Double { from.distance(to: to) }
    var isTravelDay: Bool { selected.total >= 360 || extraDays > 0 }
    var mapsURL: URL {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name: "saddr", value: "\(from.latitude),\(from.longitude)"), URLQueryItem(name: "daddr", value: "\(to.latitude),\(to.longitude)"), URLQueryItem(name: "dirflg", value: "r")]
        return c.url!
    }
}

/// Operator-published typical corridors, checked September 7, 2026. These are
/// planning baselines, never dated schedules or a claim of available tickets.
private enum RailCorridors {
    struct City { var name: String; var lat: Double; var lon: Double }
    static let cities: [City] = [
        .init(name: "Copenhagen", lat: 55.6761, lon: 12.5683), .init(name: "Stockholm", lat: 59.3293, lon: 18.0686),
        .init(name: "Oslo", lat: 59.9139, lon: 10.7522), .init(name: "Hamburg", lat: 53.5511, lon: 9.9937),
        .init(name: "London", lat: 51.5074, lon: -0.1278), .init(name: "Paris", lat: 48.8566, lon: 2.3522),
        .init(name: "Brussels", lat: 50.8503, lon: 4.3517),
        .init(name: "Amsterdam", lat: 52.3676, lon: 4.9041), .init(name: "Gothenburg", lat: 57.7089, lon: 11.9746)
    ]
    static let links: [(Int, Int, Int, Int, String)] = [
        (0, 1, 375, 45, "https://www.dsb.dk/find-produkter-og-services/dsb-udland/sverige/stockholm/"),
        (1, 2, 330, 45, "https://www.sj.no/en/highspeed/"),
        (0, 3, 275, 45, "https://www.dsb.dk/find-produkter-og-services/dsb-udland/tyskland/hamborg/"),
        (4, 5, 136, 90, "https://www.eurostar.com/uk-en/train/london-to-paris"),
        (5, 6, 82, 45, "https://www.eurostar.com/be-en/train/paris-to-brussels"),
        (6, 7, 112, 45, "https://www.eurostar.com/fr-fr/train/bruxelles-amsterdam"),
        (4, 6, 113, 90, "https://www.eurostar.com/be-en/train/london-to-brussels"),
        (0, 8, 193, 45, "https://www.dsb.dk/find-produkter-og-services/dsb-udland/sverige/goteborg/"),
        (8, 2, 210, 45, "https://www.vy.no/en/train/oslo-gothenburg")
    ]
    static func estimate(_ a: RoutePoint, _ b: RoutePoint) -> RouteEstimate? {
        func city(_ point: RoutePoint) -> Int? { cities.indices.first { point.distance(to: .init(id: "", name: "", latitude: cities[$0].lat, longitude: cities[$0].lon)) < 30 } }
        guard let from = city(a), let to = city(b), from != to else { return nil }
        var times = Array(repeating: Int.max / 2, count: cities.count)
        var paths = Array(repeating: [Int](), count: cities.count)
        var visited = Set<Int>(); times[from] = 0; paths[from] = [from]
        for _ in cities.indices {
            guard let current = cities.indices.filter({ !visited.contains($0) }).min(by: { times[$0] < times[$1] }), times[current] < Int.max / 2 else { break }
            visited.insert(current)
            for link in links where link.0 == current || link.1 == current {
                let next = link.0 == current ? link.1 : link.0
                let score = times[current] + link.2 + (current == from ? 0 : 45)
                if score < times[next] { times[next] = score; paths[next] = paths[current] + [next] }
            }
        }
        let path = paths[to]
        guard path.count >= 2 else { return nil }
        let pairs = zip(path, path.dropFirst()).compactMap { a, b in links.first { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) } }
        let stationBuffer = pairs.map { $0.3 }.max() ?? 45
        let connections = max(0, path.count - 2)
        let ride = pairs.reduce(0) { $0 + $1.2 }
        let via = path.dropFirst().dropLast().map { cities[$0].name }.joined(separator: ", ")
        return .init(mode: .train, rideMinutes: ride, bufferMinutes: stationBuffer + connections * 45,
            explanation: (via.isEmpty ? "Typical rail journey" : "Rail estimate via " + via + "; 45m per connection") + " + station time. Check operators for your dates and service changes.", source: pairs.first?.4)
    }
}

enum MultiCityRouting {
    static func options(_ a: RoutePoint, _ b: RoutePoint) -> [RouteEstimate] {
        let km = a.distance(to: b)
        if km < 80 {
            return [.init(mode: .transfer, rideMinutes: max(15, Int(ceil(km / 40 * 60 / 5)) * 5), bufferMinutes: 20, explanation: "Local transfer allowance based on distance. Traffic, terrain and services are not checked.")]
        }
        let flight = RouteEstimate(mode: .flight, rideMinutes: max(50, Int(ceil((km / 750 * 60 + 40) / 5)) * 5), bufferMinutes: 180,
            explanation: "Distance-based flight estimate + 3h for airports and ground transfers. Direct service, connections and date-line changes are not verified.")
        return RailCorridors.estimate(a, b).map { [$0, flight] } ?? [flight]
    }
    static func leg(_ a: RoutePoint, _ b: RoutePoint, plan: JourneyRoutePlan) -> JourneyRouteLeg {
        let options = options(a, b), key = a.id + ">" + b.id
        let fastest = options.min { $0.total < $1.total }!
        let preferred = plan.preferTrain ? options.first { $0.mode == .train && $0.total <= fastest.total + 90 } ?? fastest : fastest
        let choice = plan.choice(key)
        let selected = choice.map { RouteEstimate(mode: $0.mode, rideMinutes: $0.minutes, bufferMinutes: 0, explanation: "Your total transfer allowance, including connections and time at the airport or station.") } ?? preferred
        return .init(from: a, to: b, options: options, selected: selected, extraDays: choice?.extraDays ?? max(0, selected.total / 1440), customized: choice != nil)
    }
    static func legs(_ stops: [JourneyStop], plan: JourneyRoutePlan) -> [JourneyRouteLeg] {
        let points = stops.compactMap(RoutePoint.init)
        guard points.count == stops.count, !points.isEmpty else { return [] }
        var route = points
        if let home = plan.home, home.valid { route.insert(home, at: 0); if plan.returnHome { route.append(home) } }
        return zip(route, route.dropFirst()).map { leg($0, $1, plan: plan) }
    }
    static func score(_ leg: JourneyRouteLeg, objective: RouteObjective) -> Double {
        objective == .distance ? leg.distance : Double(max(leg.selected.total, leg.extraDays * 1440))
    }
    static func cost(_ stops: [JourneyStop], plan: JourneyRoutePlan) -> Double { legs(stops, plan: plan).reduce(0) { $0 + score($1, objective: plan.objective) } }
    /// Exact dynamic programming for up to eleven stops. Larger routes use a
    /// bounded multi-start nearest-neighbor + reversal search; never claim optimality.
    static func suggest(_ stops: [JourneyStop], plan: JourneyRoutePlan) -> [JourneyStop]? {
        let points = stops.compactMap(RoutePoint.init), n = stops.count
        guard n >= 2, n <= 40, points.count == n, plan.valid else { return nil }
        let matrix = points.map { a in points.map { b in score(leg(a, b, plan: plan), objective: plan.objective) } }
        func start(_ i: Int) -> Double { plan.home.map { score(leg($0, points[i], plan: plan), objective: plan.objective) } ?? 0 }
        func end(_ i: Int) -> Double { plan.returnHome ? plan.home.map { score(leg(points[i], $0, plan: plan), objective: plan.objective) } ?? 0 : 0 }
        func value(_ order: [Int]) -> Double { start(order[0]) + end(order.last!) + zip(order, order.dropFirst()).reduce(0) { $0 + matrix[$1.0][$1.1] } }
        var best = Array(0..<n)
        if n <= 11 {
            let size = 1 << n
            var scores = Array(repeating: Array(repeating: Double.infinity, count: n), count: size)
            var previous = Array(repeating: Array(repeating: -1, count: n), count: size)
            for i in 0..<n where (!plan.keepFirst || i == 0) && (!plan.keepLast || i != n - 1) { scores[1 << i][i] = start(i) }
            for mask in 1..<size {
                for last in 0..<n where scores[mask][last].isFinite {
                    for next in 0..<n where mask & (1 << next) == 0 {
                        let nextMask = mask | (1 << next)
                        if plan.keepLast && next == n - 1 && nextMask != size - 1 { continue }
                        let candidate = scores[mask][last] + matrix[last][next]
                        if candidate < scores[nextMask][next] - 0.0001 { scores[nextMask][next] = candidate; previous[nextMask][next] = last }
                    }
                }
            }
            if let last = (0..<n).filter({ !plan.keepLast || $0 == n - 1 }).min(by: { scores[size - 1][$0] + end($0) < scores[size - 1][$1] + end($1) }), scores[size - 1][last].isFinite {
                var path: [Int] = [], mask = size - 1, current = last
                while current >= 0 { path.append(current); let prior = previous[mask][current]; mask ^= 1 << current; current = prior }
                if path.count == n { best = path.reversed() }
            }
        } else {
            for seed in (plan.keepFirst ? [0] : Array(0..<n)) where !plan.keepLast || seed != n - 1 {
                var path = [seed], remaining = Set(0..<n).subtracting([seed])
                while !remaining.isEmpty {
                    let allowed = remaining.filter { !plan.keepLast || $0 != n - 1 || remaining.count == 1 }.sorted()
                    let next = allowed.min { matrix[path.last!][$0] < matrix[path.last!][$1] }!
                    path.append(next); remaining.remove(next)
                }
                for _ in 0..<4 {
                    var improved = false
                    for a in (plan.keepFirst ? 1 : 0)..<(n - 1) {
                        for b in (a + 1)..<(plan.keepLast ? n - 1 : n) {
                            var next = path; next.replaceSubrange(a...b, with: path[a...b].reversed())
                            if value(next) < value(path) - 0.01 { path = next; improved = true }
                        }
                    }
                    if !improved { break }
                }
                if value(path) < value(best) - 0.01 { best = path }
            }
        }
        // Preserve the user's ordering on a tie; a suggestion must improve it.
        return value(best) < value(Array(0..<n)) - 0.01 ? best.map { stops[$0] } : stops
    }
    static func transferDates(_ leg: JourneyRouteLeg, stops: [JourneyStop]) -> (departure: String, arrival: String)? {
        guard let first = stops.first else { return nil }
        if let source = stops.first(where: { $0.id.uuidString == leg.from.id }) {
            return (source.departure, TravelDay.adding(leg.extraDays, to: source.departure))
        }
        return (TravelDay.adding(-leg.extraDays, to: first.arrival), first.arrival)
    }
    static func applying(_ stops: [JourneyStop], plan: JourneyRoutePlan, to original: JourneyDocument) throws -> JourneyDocument {
        guard stops.count >= 2, Set(stops.map(\.id)) == Set(original.stops.map(\.id)), stops.count == original.stops.count,
              stops.allSatisfy({ RoutePoint($0) != nil }), plan.valid,
              plan.choices.allSatisfy({ (15...4320).contains($0.minutes) && (max(0, $0.minutes / 1440)...3).contains($0.extraDays) }) else { throw JourneyError.message("Check the destinations and transfer allowances before applying this route.") }
        var d = original; d.stops = stops
        let legs = legs(stops, plan: plan)
        if d.dateMode == .dates {
            guard let start = original.stops.first?.arrival, TravelDay.date(start) != nil else { throw JourneyError.message("Choose a valid trip start date first.") }
            d.stops[0].arrival = start
            for i in d.stops.indices.dropFirst() {
                let key = d.stops[i - 1].id.uuidString + ">" + d.stops[i].id.uuidString
                d.stops[i].arrival = TravelDay.adding(legs.first { $0.id == key }?.extraDays ?? 0, to: d.stops[i - 1].departure)
            }
            d.startDate = start; d.endDate = d.stops.last?.departure
            if let home = plan.home {
                if let outbound = legs.first, outbound.from.id == home.id { d.startDate = transferDates(outbound, stops: d.stops)?.departure }
                if plan.returnHome, let inbound = legs.last, inbound.to.id == home.id { d.endDate = transferDates(inbound, stops: d.stops)?.arrival }
            }
        }
        d.destination = d.routeLabel
        var savedPlan = plan; savedPlan.choices.removeAll { choice in !legs.contains { $0.id == choice.key } }
        d.routePlan = savedPlan
        let existing = Dictionary(d.events.filter { $0.routeLegID != nil }.map { ($0.routeLegID!, $0) }, uniquingKeysWith: { first, _ in first })
        d.events.removeAll { $0.routeLegID != nil }
        if plan.reserveTransfers {
            for leg in legs {
                let source = d.stops.first { $0.id.uuidString == leg.from.id }
                guard let stop = source ?? d.stops.first else { continue }
                var event = JourneyEvent(stopID: stop.id, day: source == nil ? 0 : stop.nights, minute: 9 * 60,
                    place: PlaceRecord(id: "route:" + leg.id, name: leg.from.name + " → " + leg.to.name, category: .other, city: leg.from.name, latitude: leg.from.latitude, longitude: leg.from.longitude, source: "Route planner"),
                    description: "Planning allowance: " + RouteEstimate.duration(leg.selected.total) + ". " + leg.selected.explanation + (leg.extraDays > 0 ? " Allow \(leg.extraDays) additional travel day(s)." : "") + " Departure time is a placeholder; update it after booking.",
                    kind: leg.selected.mode == .train ? .train : .transfer, title: "Travel to " + leg.to.name,
                    allDay: leg.isTravelDay, durationMinutes: min(1440, leg.selected.total))
                event.routeLegID = leg.id; event.routeMode = leg.selected.mode
                if let existing = existing[leg.id] { event.id = existing.id; event.seriesID = existing.seriesID }
                if source == nil { event.title = "Arrive in " + leg.to.name }
                if d.dateMode == .dates, let dates = transferDates(leg, stops: d.stops) {
                    event.description += " Transfer dates: " + dates.departure + " to " + dates.arrival + "."
                }
                d.events.append(event)
            }
        }
        if let error = d.validationError() { throw JourneyError.message(error) }
        return d
    }
}

#if DEBUG
enum MultiCityRouteFixtures {
    static var trip: JourneyDocument {
        let paris = JourneyStop(name: "Paris", arrival: "2026-10-01", nights: 3, latitude: 48.8566, longitude: 2.3522)
        let amsterdam = JourneyStop(name: "Amsterdam", arrival: "2026-10-04", nights: 2, latitude: 52.3676, longitude: 4.9041)
        let brussels = JourneyStop(name: "Brussels", arrival: "2026-10-06", nights: 2, latitude: 50.8503, longitude: 4.3517)
        var trip = JourneyDocument(title: "European route", startDate: paris.arrival, endDate: brussels.departure, stops: [paris, amsterdam, brussels])
        trip.events = [JourneyEvent(stopID: amsterdam.id, day: 1, place: PlaceRecord(name: "Museum afternoon", category: .museum))]
        return trip
    }
}
#endif
