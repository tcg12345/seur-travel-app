import Foundation

/// Fictional data used only by WidgetKit's gallery and explicitly labelled app previews.
enum JourneyWidgetSample {
    static func make(now: Date = .now) -> JourneyWidgetSnapshot {
        let zone = "Europe/Paris", key = WidgetCalendar.key(now, zone: zone), midnight = WidgetCalendar.date(key, zone: zone)!
        let end = WidgetCalendar.key(midnight.addingTimeInterval(4 * 86400), zone: zone)
        let item = JourneyWidgetItem(id: "sample-dinner", title: "Dinner by the Seine", symbol: "fork.knife", schedule: "19:30", zone: zone, start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200))
        let trip = JourneyWidgetTrip(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, title: "A few days in Paris", destination: "Paris, France", startDay: key, endDay: end, start: midnight, updatedAt: 0, fallbackZone: zone, stops: [.init(name: "Paris", arrival: key, departure: end, zone: zone)], days: [.init(key: key, zone: zone, items: [item])], currency: "EUR", target: 1800, spent: 460, originalSpent: "€460", rateDate: nil)
        var next = trip; next.id = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!; next.title = "Kyoto & Tokyo"; next.destination = "Japan"; next.start = midnight.addingTimeInterval(12 * 86400); next.startDay = WidgetCalendar.key(next.start, zone: zone); next.endDay = WidgetCalendar.key(next.start.addingTimeInterval(6 * 86400), zone: zone); next.stops = []; next.days = []
        return JourneyWidgetSnapshot(savedAt: now, expiresAt: now.addingTimeInterval(30 * 86400), trips: [trip, next], profile: JourneyWidgetProfile(trips: 18, countries: 12, cities: 26, nights: 94, nightsLabel: "Nights away", stars: 8, favoriteCities: "Paris", recent: [
            .init(title: "A summer in Italy", destination: "Rome · Florence", endDay: "2026-08-20"),
            .init(title: "A week in Copenhagen", destination: "Copenhagen, Denmark", endDay: "2026-06-14"),
            .init(title: "Spring in Japan", destination: "Tokyo · Kyoto", endDay: "2026-04-18")
        ]))
    }
}
