import ActivityKit
import SwiftUI
import WidgetKit

@main struct SeurFlightWidgets: WidgetBundle {
    var body: some Widget { SeurTodayWidget(); SeurNextTripWidget(); SeurBudgetWidget(); SeurTravelProfileWidget(); SeurFlightActivity() }
}
struct SeurFlightActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            SeurFlightWidgetCard(attributes: context.attributes, state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color(uiColor: .secondarySystemBackground)).activitySystemActionForegroundColor(.primary)
                .widgetURL(URL(string: "seur://flights"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { endpoint(context.attributes.origin, time: context.state.departureTime) }
                DynamicIslandExpandedRegion(.trailing) { endpoint(context.attributes.destination, time: context.state.arrivalTime) }
                DynamicIslandExpandedRegion(.center) { Image(systemName: "airplane").foregroundStyle(Color(red: 0.78, green: 0.70, blue: 0.54)) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack { Text(context.attributes.flightNumber); Spacer(); Text(context.isStale ? "Update pending" : context.state.status).lineLimit(1); if !context.state.gate.isEmpty { Text("· Gate " + context.state.gate) } }.font(.caption)
                }
            } compactLeading: { Label(context.attributes.origin, systemImage: "airplane").font(.caption2) }
              compactTrailing: { Text(context.state.gate.isEmpty ? context.attributes.destination : context.state.gate).font(.caption2) }
              minimal: { Image(systemName: "airplane") }
                .widgetURL(URL(string: "seur://flights")).keylineTint(Color(red: 0.78, green: 0.70, blue: 0.54))
        }
    }
    private func endpoint(_ code: String, time: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(code).font(.system(.title2, design: .serif)); Text(time).font(.subheadline.monospacedDigit()) }
    }
}
