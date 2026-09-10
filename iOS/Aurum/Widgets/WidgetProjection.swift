import Foundation
import WidgetKit

enum JourneyWidgetProjection {
    static func make(_ documents: [JourneyDocument], now: Date = .now, rates: TripExchangeRates? = nil, fallback: TimeZone = .current) -> JourneyWidgetSnapshot {
        let expires = now.addingTimeInterval(30 * 86400)
        let candidates = documents.filter { document in
            guard document.isTemplate != true, document.dateMode == .dates,
                  let start = document.startDate, let end = document.endDate,
                  TravelDay.date(start) != nil, TravelDay.date(end) != nil, start <= end else { return false }
            return TodayPlanner.context(document, now: now, fallback: fallback).day <= end
        }.sorted {
            let a = TodayPlanner.isActive($0, now: now, fallback: fallback), b = TodayPlanner.isActive($1, now: now, fallback: fallback)
            if a != b { return a }
            if $0.startDate != $1.startDate { return a ? ($0.startDate ?? "") > ($1.startDate ?? "") : ($0.startDate ?? "") < ($1.startDate ?? "") }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }.prefix(12)
        let trips = candidates.compactMap { document -> JourneyWidgetTrip? in
            let startDay = document.startDate!, endDay = document.endDate!
            let stops = document.stops.map { stop in JourneyWidgetStop(name: String(stop.name.prefix(100)), arrival: stop.arrival, departure: stop.departure, zone: TodayPlanner.zone(for: stop, in: document, fallback: fallback).identifier) }
            guard let start = WidgetCalendar.date(startDay, zone: stops.first?.zone ?? fallback.identifier) else { return nil }
            let zones = Set(stops.map(\.zone) + [fallback.identifier])
            var days: [JourneyWidgetDay] = []
            for zoneID in zones.sorted() {
                let zone = TimeZone(identifier: zoneID) ?? fallback
                let from = max(startDay, TodayPlanner.key(now, zone: zone))
                let to = min(endDay, TodayPlanner.key(expires, zone: zone))
                guard from <= to else { continue }
                for offset in 0...min(32, TravelDay.distance(from, to)) {
                    let day = TravelDay.adding(offset, to: from)
                    let items = TodayPlanner.items(document, day: day, zone: zone).filter { !$0.completed }.map {
                        JourneyWidgetItem(id: $0.id, title: String($0.title.prefix(120)), symbol: $0.symbol, schedule: $0.schedule, zone: $0.zone.identifier, start: $0.start, end: $0.end)
                    }
                    if !items.isEmpty { days.append(JourneyWidgetDay(key: day, zone: zoneID, items: items)) }
                }
            }
            let currency = document.homeCurrency ?? "USD", spent = TripBudget.spent(document)
            let converted = TripBudget.converted(spent, home: currency, rates: rates)
            let usesRates = spent.keys.contains { $0 != currency } && converted != nil
            return JourneyWidgetTrip(id: document.id, title: String(document.title.prefix(120)), destination: String(document.routeLabel.prefix(140)), startDay: startDay, endDay: endDay, start: start, updatedAt: document.updatedAt, fallbackZone: fallback.identifier, stops: stops, days: days, currency: currency, target: document.budgetTarget, spent: converted, originalSpent: spent.keys.sorted().map { (spent[$0] ?? 0).formatted(.currency(code: $0)) }.joined(separator: " · "), rateDate: usesRates ? rates?.dates.values.sorted().first : nil)
        }
        // History uses the entire deduplicated library, independent of the itinerary cap.
        let statistics = TravelStatistics(documents: documents, now: now, deviceZone: fallback)
        let summary = statistics.summary()
        let recent = statistics.documents.filter { document in
            guard document.dateMode == .dates, let end = document.endDate, TravelDay.date(end) != nil else { return false }
            return end < WidgetCalendar.key(now, zone: document.stops.last?.timeZone ?? fallback.identifier)
        }.sorted {
            if $0.endDate != $1.endDate { return ($0.endDate ?? "") > ($1.endDate ?? "") }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }.prefix(3).map {
            JourneyWidgetHistoryTrip(title: String($0.title.prefix(120)), destination: String($0.routeLabel.prefix(140)), endDay: $0.endDate!)
        }
        let favorites = summary.favoriteCities.prefix(3).joined(separator: " · ")
        let profile = JourneyWidgetProfile(trips: summary.trips, countries: summary.countries.count, cities: summary.cities.count, nights: summary.nightsAway, nightsLabel: summary.nightsLabel, stars: summary.stars, favoriteCities: favorites.isEmpty ? nil : String(favorites.prefix(140)), recent: recent)
        return JourneyWidgetSnapshot(savedAt: now, expiresAt: expires, trips: trips, profile: profile)
    }
}
@MainActor enum JourneyWidgetPublisher {
    static func publish(_ documents: [JourneyDocument], rates: TripExchangeRates?) {
        // Test libraries must never replace a user's widget snapshot.
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing"), NSClassFromString("XCTestCase") == nil,
              let url = JourneyWidgetStore.sharedURL else { return }
        do {
            try JourneyWidgetStore.write(JourneyWidgetProjection.make(documents, rates: rates), to: url)
            JourneyWidgetKind.allCases.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0.rawValue) }
        } catch {
            // A prior snapshot must not keep advertising a removed trip if publication fails.
            try? FileManager.default.removeItem(at: url)
            JourneyWidgetKind.allCases.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0.rawValue) }
        }
    }
}

#if DEBUG
enum WidgetAppFixtures {
    static var trip: JourneyDocument {
        let day = TodayPlanner.key(.now, zone: .current)
        let stop = JourneyStop(name: "Paris", arrival: day, nights: 4, timeZone: TimeZone.current.identifier)
        var document = JourneyDocument(title: "Widget Paris trip", startDate: day, endDate: stop.departure, stops: [stop])
        document.id = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        document.events = [JourneyEvent(stopID: stop.id, place: PlaceRecord(name: "Walk by the river"), cost: TravelMoney(amount: 80, currency: "EUR"))]
        document.events[0].allDay = true
        document.budgetTarget = 500; document.homeCurrency = "EUR"
        return document
    }
}
#endif
