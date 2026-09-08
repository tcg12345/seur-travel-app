import Foundation

/// All statistics are derived locally. Flights contribute distance, never visits.
struct TravelStatistics {
    struct Visit: Identifiable {
        var id: String
        var city: String
        var countryCode: String?
        var point: RoutePoint?
        var start: String?
        var end: String?
    }
    struct Summary {
        var trips = 0
        var countries: Set<String> = []
        var cities: Set<String> = []
        var visits: [Visit] = []
        var planned: [Visit] = []
        var upcomingTrips = 0
        var hotelNights = 0
        var otherNights = 0
        var kilometers = 0.0
        var stars = 0
        var starredRestaurants = 0
        var scores: [Double] = []
        var brandStays: [String: Int] = [:]
        var cityVisits: [String: Int] = [:]
        var longest: (title: String, nights: Int)?
        var spend: [String: Decimal] = [:]
        var undatedEntries = 0
        var unknownCountries = 0
        var nightsAway: Int { hotelNights + otherNights }
        var nightsLabel: String { otherNights > 0 ? "Nights away" : "Hotel nights" }
        var miles: Double { kilometers * 0.6213711922 }
        var average: Double? { scores.isEmpty ? nil : scores.reduce(0,+) / Double(scores.count) }
        var favoriteBrands: [String] {
            guard brandStays.values.reduce(0,+) >= 3, let high = brandStays.values.max() else { return [] }
            return brandStays.filter { $0.value == high }.keys.sorted()
        }
        var favoriteCities: [String] {
            guard let high = cityVisits.values.max() else { return [] }
            return cityVisits.filter { $0.value == high }.keys.sorted()
        }
    }
    let documents: [JourneyDocument]
    let catalog: [Hotel]
    let now: Date
    let deviceZone: TimeZone
    private let brandsByID: [String: String]
    private let brandsByName: [String: String]
    init(documents: [JourneyDocument], catalog: [Hotel] = [], now: Date = .now, deviceZone: TimeZone = .current) {
        // Cloud restores with the same ID must not double the travel history.
        var unique: [UUID: JourneyDocument] = [:]
        for d in documents where d.isTemplate != true {
            if unique[d.id] == nil || unique[d.id]!.updatedAt < d.updatedAt { unique[d.id] = d }
        }
        self.documents = unique.values.sorted { $0.id.uuidString < $1.id.uuidString }
        self.catalog = catalog; self.now = now; self.deviceZone = deviceZone
        var ids: [String:String] = [:], names: [String:String] = [:], duplicates = Set<String>()
        for hotel in catalog {
            let key = Self.normalized(hotel.name) + "|" + Self.normalized(hotel.city)
            if names[key] != nil { duplicates.insert(key) }
            let value = hotel.brand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && !["independent","n/a","unknown","—","-"].contains(Self.normalized(value)) { ids[hotel.id] = value; names[key] = value }
        }
        for key in duplicates { names.removeValue(forKey:key) }
        brandsByID = ids; brandsByName = names
    }
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static let countryNames: [String: String] = {
        var result: [String: String] = ["uk":"GB", "united kingdom":"GB", "usa":"US", "u.s.a.":"US", "u.s.":"US", "united states of america":"US", "south korea":"KR", "czech republic":"CZ", "uae":"AE"]
        for region in Locale.Region.isoRegions where region.identifier.count == 2 {
            let code = region.identifier
            result[normalized(code)] = code
            for locale in [Locale(identifier: "en_US"), Locale.current] {
                if let name = locale.localizedString(forRegionCode: code) { result[normalized(name)] = code }
            }
        }
        return result
    }()
    static func countryCode(_ value: String?) -> String? { value.flatMap { countryNames[normalized($0)] } }
    static func brand(for place: PlaceRecord, catalog: [Hotel]) -> String? {
        let explicit = place.brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if place.brand != nil { return explicit.isEmpty || ["independent", "n/a", "unknown", "none", "—", "-"].contains(normalized(explicit)) ? nil : explicit }
        let matches = catalog.filter { $0.id == place.id || (normalized($0.name) == normalized(place.name) && normalized($0.city) == normalized(place.city)) }
        guard matches.count == 1 else { return nil }
        let brand = matches[0].brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return brand.isEmpty || ["independent", "n/a", "unknown", "—", "-"].contains(normalized(brand)) ? nil : brand
    }
    private func today(_ zone: String?) -> String {
        var c = Calendar(identifier: .gregorian); c.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? deviceZone
        let v = c.dateComponents([.year,.month,.day], from: now)
        return String(format: "%04d-%02d-%02d", v.year!, v.month!, v.day!)
    }
    private func includes(_ start: String?, _ end: String? = nil, year: Int?) -> Bool {
        guard let year else { return true }
        guard let start, TravelDay.date(start) != nil else { return false }
        return start <= "\(year)-12-31" && (end ?? start) >= "\(year)-01-01"
    }
    private func nights(_ start: String, _ end: String, before: String, year: Int?) -> Int {
        guard TravelDay.date(start) != nil, TravelDay.date(end) != nil else { return 0 }
        let a = max(start, year.map { "\($0)-01-01" } ?? start)
        let b = min(end, before, year.map { "\($0+1)-01-01" } ?? end)
        return max(0, TravelDay.distance(a,b))
    }
    private func matched(_ p: RatedPlace, _ stop: JourneyStop) -> Bool {
        let city = Self.normalized(p.place.city), name = Self.normalized(stop.name)
        if !city.isEmpty && (city == name || name.hasPrefix(city + ",") || city.hasPrefix(name + ",")) { return true }
        if let point = RoutePoint(stop), p.place.hasCoordinate {
            return point.distance(to: .init(id: "", name: "", latitude: p.place.latitude!, longitude: p.place.longitude!)) < 35
        }
        return false
    }
    private func date(for p: RatedPlace, in d: JourneyDocument, today: String) -> String? {
        if let day = p.visitedOn, TravelDay.date(day) != nil { return day }
        // An undated entry inherits a finished trip's end, never a future booking.
        return d.dateMode == .dates && (d.endDate ?? "9999") < today ? d.endDate : nil
    }
    var years: [Int] {
        var years = Set<Int>()
        for d in documents {
            let dates = d.places.compactMap(\.visitedOn) + (d.dateMode == .dates ? d.stops.flatMap { [$0.arrival,$0.departure] } + [d.startDate,d.endDate].compactMap { $0 } : [])
            for date in dates where TravelDay.date(date) != nil { if let year = Int(date.prefix(4)), (1900...2200).contains(year) { years.insert(year) } }
        }
        years.insert(Int(today(nil).prefix(4))!)
        return years.sorted(by: >)
    }
    func summary(year: Int? = nil) -> Summary {
        var result = Summary(), seenStays = Set<String>(), seenFlights = Set<String>(), seenPlaces = Set<String>(), seenVisits = Set<String>()
        var brandLabels: [String: String] = [:], cityLabels: [String: String] = [:], starred = Set<String>()
        for d in documents {
            let day = today(d.stops.last?.timeZone)
            let ended = d.dateMode == .dates && d.endDate.flatMap(TravelDay.date) != nil && d.endDate! < day
            let begun = d.dateMode != .dates || (d.startDate ?? d.stops.first?.arrival ?? day) <= day
            let logged = ended || (!d.places.isEmpty && begun)
            let actualPlaces = d.places.filter { p in
                let placeDay = today(d.stops.first(where: { matched(p,$0) })?.timeZone)
                return logged && (p.visitedOn == nil || (TravelDay.date(p.visitedOn!) != nil && p.visitedOn! <= placeDay))
            }
            let tripDay = ended ? d.endDate : actualPlaces.compactMap(\.visitedOn).filter { $0 <= day }.sorted().last
            if logged && includes(tripDay, year: year) {
                result.trips += 1
                // A partly journaled future itinerary is not a longest completed trip.
                if ended && (result.longest == nil || d.nights > result.longest!.nights) { result.longest = (d.title,d.nights) }
            }
            var hasUpcoming = false
            var visitedStopIDs = Set<UUID>()
            for s in d.stops {
                let localDay = today(s.timeZone), proof = actualPlaces.filter { p in
                    matched(p,s) && (d.dateMode != .dates || p.visitedOn == nil || (p.visitedOn! >= s.arrival && p.visitedOn! <= s.departure))
                }
                let visited = logged && (d.dateMode != .dates || s.arrival <= localDay) && (ended || !proof.isEmpty)
                let start = d.dateMode == .dates ? s.arrival : proof.compactMap(\.visitedOn).min()
                let end = d.dateMode == .dates ? min(s.departure,localDay) : proof.compactMap(\.visitedOn).max()
                let visit = Visit(id: d.id.uuidString + "|" + s.id.uuidString, city: s.name, countryCode: Self.countryCode(s.countryCode) ?? Self.countryCode(s.country), point: RoutePoint(s), start: start, end: end)
                if visited {
                    visitedStopIDs.insert(s.id)
                    let key = Self.normalized(s.name), identity = key + "|" + (start ?? s.id.uuidString)
                    if includes(start,end,year:year) && seenVisits.insert(identity).inserted {
                        result.visits.append(visit); result.cities.insert(key)
                        if let code = visit.countryCode { result.countries.insert(code) } else { result.unknownCountries += 1 }
                        let label = cityLabels[key] ?? s.name; cityLabels[key] = label; result.cityVisits[label,default:0] += 1
                    }
                } else if d.dateMode == .dates && s.arrival >= localDay && includes(s.arrival,s.departure,year:year) {
                    result.planned.append(visit); hasUpcoming = true
                }
            }
            if d.dateMode == .dates, let start = d.startDate, start >= day, includes(start,d.endDate,year:year) { hasUpcoming = true }
            if hasUpcoming { result.upcomingTrips += 1 }
            guard logged else { continue }
            if d.hotels.isEmpty {
                for s in d.stops where visitedStopIDs.contains(s.id) {
                    if d.dateMode == .dates { result.otherNights += nights(s.arrival,s.departure,before:today(s.timeZone),year:year) }
                    else if year == nil { result.otherNights += s.nights }
                }
            }
            for h in d.hotels where TravelDay.date(h.checkIn) != nil {
                let hotelDay = today(d.stops.first(where: { matched(RatedPlace(place:h.place),$0) && h.checkIn >= $0.arrival && h.checkIn < $0.departure })?.timeZone)
                guard h.checkIn < hotelDay else { continue }
                let identity = Self.normalized(h.place.name) + "|" + Self.normalized(h.place.city) + "|" + h.checkIn + "|" + h.checkOut
                guard seenStays.insert(identity).inserted else { continue }
                let count = nights(h.checkIn,h.checkOut,before:hotelDay,year:year)
                result.hotelNights += count
                if count > 0, let brand = (h.place.brand != nil ? Self.brand(for:h.place,catalog:[]) : brandsByID[h.place.id] ?? brandsByName[Self.normalized(h.place.name) + "|" + Self.normalized(h.place.city)]) {
                    let key = Self.normalized(brand), label = brandLabels[key] ?? brand; brandLabels[key] = label
                    result.brandStays[label,default:0] += 1
                }
                if includes(h.checkIn,year:year), let money = h.cost { result.spend[money.currency,default:0] += money.amount }
            }
            for f in d.flights {
                // Only a finished arrival day is treated as flown without live status.
                guard TravelDay.date(f.arrivalDay) != nil, f.arrivalDay < today(f.arrivalZone), includes(f.departureDay,year:year) else { continue }
                let identity = f.flightNumber.isEmpty ? f.id.uuidString : [f.airline,f.flightNumber,f.departureAirport,f.arrivalAirport,f.departureDay,f.departureTime].map(Self.normalized).joined(separator:"|")
                guard seenFlights.insert(identity).inserted else { continue }
                let copy = JourneyDocument(flights:[f])
                result.kilometers += TripRecap(document:copy).legs.filter(\.flight).reduce(0) { $0 + $1.from.distance(to:$1.to) }
                if let money = f.cost { result.spend[money.currency,default:0] += money.amount }
            }
            for p in actualPlaces {
                let date = date(for:p,in:d,today:day)
                if date == nil { result.undatedEntries += 1 }
                guard includes(date,year:year) else { continue }
                let placeKey = Self.normalized(p.place.name) + "|" + Self.normalized(p.place.city)
                let identity = placeKey + "|" + (p.visitedOn ?? p.id.uuidString)
                guard seenPlaces.insert(identity).inserted else { continue }
                if p.overall > 0 { result.scores.append(p.overall) }
                if p.place.category == .restaurant, let stars = p.michelinStars, stars > 0 {
                    result.stars += min(3,stars); starred.insert(placeKey)
                }
            }
            for e in d.events {
                if let date = d.date(for:e), date < today(d.stops.first(where: { $0.id == e.stopID })?.timeZone), includes(date,year:year), let money = e.cost { result.spend[money.currency,default:0] += money.amount }
            }
        }
        result.starredRestaurants = starred.count
        return result
    }
}
