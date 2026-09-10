import SwiftUI
import WidgetKit

struct WidgetHelpView: View {
    @Environment(WidgetDiscovery.self) private var discovery
    private let sample = JourneyWidgetSample.make()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("A little closer to your next journey").font(.system(.title2, design: .serif))
                Text("Touch and hold an empty area of your Home Screen, choose Edit → Add Widget, then search for Seur. Choose a widget and size, and tap Add Widget.").font(.subheadline)
                ForEach(JourneyWidgetKind.allCases, id: \.rawValue) { kind in
                    VStack(alignment: .leading, spacing: 8) {
                        JourneyWidgetContent(snapshot: sample, date: sample.savedAt, kind: kind, previewFamily: .systemMedium)
                            .padding(16).frame(height: 174)
                            .background { JourneyWidgetBackground(kind: kind) }.clipShape(.rect(cornerRadius: 24))
                        Text(kind == .today ? "Today follows your active trip and its saved itinerary." : kind == .nextTrip ? "Next Trip counts down to your earliest upcoming dated trip." : kind == .profile ? "Travel Profile shows your all-time logged history, with recent completed journeys in larger sizes." : "Budget shows completed activities and paid bookings for your active or next trip.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Illustrative previews").font(.caption2).foregroundStyle(.secondary)
                Text("Today and Next Trip also have Lock Screen sizes. Touch and hold the Lock Screen, choose Customize, then Add Widgets.").font(.subheadline)
                Text("Widgets refresh when you save plans or open Seur. iOS controls refresh timing. Flight times come from your saved itinerary; open the app for current flight status. Currency conversion uses saved rates and shows their date.").font(.caption).foregroundStyle(.secondary)
                Text("Tap Travel Profile to open your full travel statistics; other widgets open their trip. History uses completed trips and logged visits saved on this device, with an as-of date. Templates and unvisited future plans do not count toward your history.").font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }.background(Color.canvas).navigationTitle("Seur widgets").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("widget-guide").onAppear { discovery.markHandled() }
    }
}
struct WidgetTripDestination: View {
    let link: JourneyWidgetLink
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var addingBudget = false
    var body: some View {
        NavigationStack {
            Group {
                if let trip = library.trips.first(where: { $0.id == link.tripID }) {
                    if link.kind == .budget {
                        Group {
                            if TripBudget.isConfigured(trip) {
                                TripBudgetDashboard(initial: trip)
                            } else {
                                ContentUnavailableView {
                                    Label("Set up your trip budget", systemImage: "chart.pie")
                                } description: {
                                    Text("Choose a home currency and an optional spending target.")
                                } actions: {
                                    Button("Add budget") { addingBudget = true }.buttonStyle(.glassProminent)
                                }
                            }
                        }.sheet(isPresented: $addingBudget) { TripBudgetEditor(documentID: trip.id) }.background(Color.canvas)
                    } else { JourneyDetailView(id: trip.id, initialMode: link.kind == .today ? "Today" : nil) }
                } else { ContentUnavailableView("Trip no longer saved", systemImage: "suitcase", description: Text("This trip may have been removed from this device.")) }
            }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct WidgetProfileDestination: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            TravelStatsView().accessibilityIdentifier("widget-profile-destination")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}


/// A device-local, one-time invitation; viewing the guide also retires it.
@MainActor @Observable final class WidgetDiscovery {
    private static let key = "seur.widgets.invitationHandled.v1"
    private let defaults: UserDefaults
    private(set) var handled: Bool
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults; handled = defaults.bool(forKey: Self.key)
    }
    func shouldOffer(for documents: [JourneyDocument]) -> Bool {
        !handled && documents.contains { $0.isTemplate != true && !$0.isWishlistTrip }
    }
    func markHandled() { handled = true; defaults.set(true, forKey: Self.key) }
}

struct WidgetInvitationView: View {
    let documents: [JourneyDocument]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let date = Date.now
                    let snapshot = JourneyWidgetProjection.make(documents, now: date)
                    let kind: JourneyWidgetKind = snapshot.trips.isEmpty ? .profile : .nextTrip
                    JourneyWidgetContent(snapshot: snapshot, date: date, kind: kind, previewFamily: .systemMedium)
                        .padding(16).frame(height: 170)
                        .background { JourneyWidgetBackground(kind: kind) }.clipShape(.rect(cornerRadius: 24))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your trip, at a glance.").font(.system(.title2, design: .serif)).accessibilityAddTraits(.isHeader)
                        Text("Keep your plans, countdown and travel history on your Home Screen with Seur widgets.")
                            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    NavigationLink { WidgetHelpView() } label: {
                        Text("Show me how").frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.glassProminent).accessibilityIdentifier("widget-invitation-guide")
                    Button("Not now") { dismiss() }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("widget-invitation-dismiss")
                }.padding(24)
            }.background(Color.canvas).navigationTitle("Seur widgets").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(560), .large])
            .presentationDragIndicator(.visible)
    }
}
