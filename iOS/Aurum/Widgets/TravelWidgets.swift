import SwiftUI
import WidgetKit

struct JourneyWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: JourneyWidgetSnapshot?
}
struct JourneyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> JourneyWidgetEntry { JourneyWidgetEntry(date: .now, snapshot: JourneyWidgetSample.make()) }
    func getSnapshot(in context: Context, completion: @escaping (JourneyWidgetEntry) -> Void) {
        completion(JourneyWidgetEntry(date: .now, snapshot: context.isPreview ? JourneyWidgetSample.make() : JourneyWidgetStore.read(from: JourneyWidgetStore.sharedURL)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<JourneyWidgetEntry>) -> Void) {
        let now = Date(), snapshot = JourneyWidgetStore.read(from: JourneyWidgetStore.sharedURL)
        let dates = snapshot?.refreshDates(after: now) ?? [now, now.addingTimeInterval(3600)]
        let entries = dates.map { JourneyWidgetEntry(date: $0, snapshot: snapshot?.displaySnapshot(at: $0)) }
        completion(Timeline(entries: entries, policy: .after(dates.last ?? now.addingTimeInterval(3600))))
    }
}
struct SeurTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: JourneyWidgetKind.today.rawValue, provider: JourneyWidgetProvider()) { entry in
            JourneyWidgetContent(snapshot: entry.snapshot, date: entry.date, kind: .today).containerBackground(for: .widget) { JourneyWidgetBackground(kind: .today) }
        }.configurationDisplayName("Today in Seur").description("Your next saved plans, flights and hotel reminders in the destination’s time zone.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}
struct SeurNextTripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: JourneyWidgetKind.nextTrip.rawValue, provider: JourneyWidgetProvider()) { entry in
            JourneyWidgetContent(snapshot: entry.snapshot, date: entry.date, kind: .nextTrip).containerBackground(for: .widget) { JourneyWidgetBackground(kind: .nextTrip) }
        }.configurationDisplayName("Next Trip").description("Count down to your next journey, or keep your current trip close.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}
struct SeurBudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: JourneyWidgetKind.budget.rawValue, provider: JourneyWidgetProvider()) { entry in
            JourneyWidgetContent(snapshot: entry.snapshot, date: entry.date, kind: .budget).containerBackground(for: .widget) { JourneyWidgetBackground(kind: .budget) }
        }.configurationDisplayName("Trip Budget").description("Completed and paid spending against your target, plus your daily burn rate.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SeurTravelProfileWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: JourneyWidgetKind.profile.rawValue, provider: JourneyWidgetProvider()) { entry in
            JourneyWidgetContent(snapshot: entry.snapshot, date: entry.date, kind: .profile).containerBackground(for: .widget) { JourneyWidgetBackground(kind: .profile) }
        }.configurationDisplayName("Travel Profile").description("Your travel history: countries, cities, trips, nights away and recent completed journeys.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
