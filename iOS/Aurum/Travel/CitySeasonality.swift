import Foundation

/// Offline editorial guidance. Moving holidays are never projected onto another year.
struct SeasonalityCatalog: Decodable {
    let schemaVersion: Int
    let reviewedOn: String
    let cities: [CitySeasonality]
    static let shared: SeasonalityCatalog? = {
        guard let url = Bundle.main.url(forResource: "CitySeasonality", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(Self.self, from: data),
              catalog.schemaVersion == 1 else { return nil }
        return catalog
    }()
    func city(named name: String, countryCode: String? = nil) -> CitySeasonality? {
        let normalized = Self.normalize(name)
        let code = countryCode.flatMap { $0.isEmpty ? nil : $0.uppercased() }
        return cities.first { city in
            guard code == nil || code == city.countryCode else { return false }
            let names = ([city.name] + city.aliases).map(Self.normalize)
            if names.contains(normalized) { return true }
            // Maps may return “Paris, Île-de-France, France”. A known country lets us
            // match the complete city component without guessing from arbitrary text.
            guard code != nil, let component = normalized.split(separator: ",").first else { return false }
            return names.contains(Self.normalize(String(component)))
        }
    }
    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
struct CitySeasonality: Decodable, Identifiable {
    let id: String
    let name: String
    let countryCode: String
    let aliases: [String]
    let months: [SeasonalityMonth]
    let notices: [SeasonalityNotice]
    let sources: [SeasonalitySource]
    func assessment(arrival: String?, departure: String?) -> SeasonalityAssessment? {
        guard let arrival, let departure, let start = SeasonalityRange.date(arrival), let end = SeasonalityRange.date(departure),
              start <= end, TravelDay.distance(arrival, departure) <= 3660 else { return nil }
        let calendar = TravelDay.calendar
        let firstYear = calendar.component(.year, from: start), lastYear = calendar.component(.year, from: end)
        var selectedMonths: [Int] = []
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: start))!
        while cursor <= end {
            let month = calendar.component(.month, from: cursor)
            if !selectedMonths.contains(month) { selectedMonths.append(month) }
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor)!
        }
        let relevant = notices.compactMap { notice -> SeasonalityAdvisory? in
            switch notice.timing {
            case .annual:
                guard let from = notice.start, let to = notice.end else { return nil }
                let overlaps = ((firstYear - 1)...lastYear).contains { year in
                    SeasonalityRange(start: String(format: "%04d-", year) + from, end: String(format: "%04d-", year + (to < from ? 1 : 0)) + to).overlaps(start, end)
                }
                return overlaps ? SeasonalityAdvisory(notice: notice, unverifiedYears: []) : nil
            case .dated:
                let ranges = notice.occurrences ?? []
                let knownYears = Set(ranges.flatMap { range -> [Int] in
                    guard let a = SeasonalityRange.date(range.start), let b = SeasonalityRange.date(range.end), a <= b else { return [] }
                    return Array(calendar.component(.year, from: a)...calendar.component(.year, from: b))
                })
                let missing = Array(firstYear...lastYear).filter { !knownYears.contains($0) }
                if ranges.contains(where: { $0.overlaps(start, end) }) || !missing.isEmpty { return SeasonalityAdvisory(notice: notice, unverifiedYears: missing) }
                return nil
            case .checkCalendar:
                return SeasonalityAdvisory(notice: notice, unverifiedYears: Array(firstYear...lastYear))
            }
        }
        return SeasonalityAssessment(months: selectedMonths.compactMap { selected in months.first { $0.month == selected } }, advisories: relevant)
    }
}
struct SeasonalityMonth: Decodable, Identifiable {
    enum Season: String, Decodable { case peak, shoulder, quieter; var title: String { rawValue.capitalized } }
    let month: Int
    let season: Season
    /// Broad daytime feel and rainfall pattern, not a forecast or measured normal.
    let weather: String
    let rain: String
    var id: Int { month }
    var name: String { DateFormatter().monthSymbols[month - 1] }
}
struct SeasonalitySource: Decodable, Identifiable {
    let title: String
    let url: URL
    var id: String { url.absoluteString }
}
struct SeasonalityRange: Decodable {
    let start: String
    let end: String
    static func date(_ key: String) -> Date? {
        guard key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return TravelDay.date(key)
    }
    func overlaps(_ from: Date, _ to: Date) -> Bool {
        guard let a = Self.date(start), let b = Self.date(end), a <= b else { return false }
        return a <= to && b >= from
    }
}
struct SeasonalityNotice: Decodable, Identifiable {
    enum Timing: String, Decodable { case annual, dated, checkCalendar }
    let id: String
    let title: String
    let detail: String
    let timing: Timing
    let start: String?
    let end: String?
    let occurrences: [SeasonalityRange]?
    let source: URL
    var schedule: String {
        switch timing {
        case .annual:
            guard let start, let end else { return "Check dates" }
            return TravelDay.label("2000-" + start) + " – " + TravelDay.label("2000-" + end) + " · recurring guidance"
        case .dated:
            return (occurrences ?? []).map { $0.start + " – " + $0.end }.joined(separator: "; ")
        case .checkCalendar: return "Dates vary by year; check the local calendar"
        }
    }
}
struct SeasonalityAdvisory: Identifiable {
    let notice: SeasonalityNotice
    let unverifiedYears: [Int]
    var id: String { notice.id }
    var calendarPrompt: String? {
        unverifiedYears.isEmpty ? nil : "Dates not verified for " + unverifiedYears.map(String.init).joined(separator: ", ") + ". Check the local calendar before choosing dates."
    }
}
struct SeasonalityAssessment {
    let months: [SeasonalityMonth]
    let advisories: [SeasonalityAdvisory]
}

#if DEBUG
enum SeasonalityFixtures {
    static var trip: JourneyDocument {
        let paris = JourneyStop(name: "Paris", arrival: "2026-08-28", nights: 2, latitude: 48.8566, longitude: 2.3522, countryCode: "FR")
        let london = JourneyStop(name: "London", arrival: "2026-08-30", nights: 5, latitude: 51.5074, longitude: -0.1278, countryCode: "GB")
        var trip = JourneyDocument(title: "Seasons in Europe", startDate: paris.arrival, endDate: london.departure, stops: [paris, london])
        trip.routePlan = JourneyRoutePlan()
        return trip
    }
}
#endif
