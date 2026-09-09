import ActivityKit
import SwiftUI
import WidgetKit

@main struct SeurFlightWidgets: WidgetBundle {
    var body: some Widget { SeurFlightActivity() }
}
struct SeurFlightActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label(context.attributes.flightNumber, systemImage: "airplane").font(.headline); Spacer(); Text(context.isStale ? "Update pending" : context.state.status).font(.caption).lineLimit(1) }
                HStack {
                    endpoint(context.attributes.origin, time: context.state.departureTime)
                    Spacer()
                    Image(systemName: "airplane").foregroundStyle(.orange)
                    Spacer()
                    endpoint(context.attributes.destination, time: context.state.arrivalTime)
                }
                HStack {
                    Text(context.state.gate.isEmpty ? "Gate —" : "Gate " + context.state.gate)
                    if !context.state.terminal.isEmpty { Text("· Terminal " + context.state.terminal) }
                    Spacer()
                    if context.state.phase == "scheduled", context.state.departure > Date.now.timeIntervalSince1970 {
                        Text(timerInterval: Date.now...Date(timeIntervalSince1970: context.state.departure), countsDown: true).monospacedDigit().frame(maxWidth: 90)
                    } else { Text(context.state.delayMinutes > 0 ? "\(context.state.delayMinutes)m late" : "Airport local times") }
                }.font(.caption)
            }.padding(16).activityBackgroundTint(Color(red: 0.11, green: 0.12, blue: 0.13)).activitySystemActionForegroundColor(.white).foregroundStyle(.white)
                .widgetURL(URL(string: "seur://flights"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { endpoint(context.attributes.origin, time: context.state.departureTime) }
                DynamicIslandExpandedRegion(.trailing) { endpoint(context.attributes.destination, time: context.state.arrivalTime) }
                DynamicIslandExpandedRegion(.center) { Image(systemName: "airplane").foregroundStyle(.orange) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack { Text(context.attributes.flightNumber); Spacer(); Text(context.isStale ? "Update pending" : context.state.status).lineLimit(1); if !context.state.gate.isEmpty { Text("· Gate " + context.state.gate) } }.font(.caption)
                }
            } compactLeading: { Label(context.attributes.origin, systemImage: "airplane").font(.caption2) }
              compactTrailing: { Text(context.state.gate.isEmpty ? context.attributes.destination : context.state.gate).font(.caption2) }
              minimal: { Image(systemName: "airplane") }
                .widgetURL(URL(string: "seur://flights")).keylineTint(.orange)
        }
    }
    private func endpoint(_ code: String, time: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(code).font(.title3.weight(.semibold)); Text(time).font(.subheadline.monospacedDigit()) }
    }
}
