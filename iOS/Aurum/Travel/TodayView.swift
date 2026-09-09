import SwiftUI
import UIKit

/// Only used with documents from JourneyLibrary, never a shared-document preview.
struct TodayHubView: View {
    @Environment(JourneyLibrary.self) private var library
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            if let trip = TodayPlanner.activeTrip(library.documents, now: TodayClock.now(timeline.date)) {
                TodayView(document: trip)
            }
        }
    }
}
struct TodayView: View {
    let document: JourneyDocument
    @Environment(TravelAPI.self) private var api
    @Environment(TravelStore.self) private var travel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset = 0
    @State private var selectedItem: TodayItem?
    @State private var statuses = TodayFlightStatusStore.shared
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = TodayClock.now(timeline.date)
            let context = TodayPlanner.context(document, now: now)
            let base = max(document.startDate ?? context.day, min(document.endDate ?? context.day, context.day))
            let day = TravelDay.adding(offset, to: base)
            let snapshots = Dictionary(uniqueKeysWithValues: document.flights.compactMap { flight in statuses.snapshot(flight, server: api.baseURL).map { (flight.id, $0) } })
            let items = TodayPlanner.items(document, day: day, zone: context.zone, snapshots: snapshots)
            let next = day == context.day ? TodayPlanner.nextItem(items, now: now) : nil
            VStack(alignment: .leading, spacing: 4) {
                heading(day: day, context: context, base: base, empty: items.isEmpty)
                if document.dateMode != .dates {
                    Text("Set trip dates to see your daily plan here.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        TodayItemRow(item: item, isNext: item.id == next?.id, happening: item.start.map { $0 <= now } ?? false) { selectedItem = item }
                    }
                    let staying = document.hotels.filter { $0.checkIn < day && day < $0.checkOut }
                    ForEach(staying) { hotel in
                        let item = TodayItem(id: "stay-\(hotel.id)", kind: .hotel, title: hotel.place.name, detail: hotel.roomType,
                            symbol: "bed.double", schedule: "Staying", sortMinute: 0, place: hotel.place, confirmation: hotel.confirmation, zone: context.zone)
                        TodayItemRow(item: item, isNext: false) { selectedItem = item }
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("today-view")
                .sheet(item: $selectedItem) { item in
                    TodayItemActions(item: item, day: day, statusLabel: item.flightID.flatMap { id in document.flights.first { $0.id == id } }.map { statuses.label($0, server: api.baseURL, now: now) })
                }
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { value in
                    guard abs(value.translation.width) > 65, abs(value.translation.width) > abs(value.translation.height) * 1.8 else { return }
                    move(value.translation.width < 0 ? 1 : -1)
                })
                .task(id: refreshID(day)) {
                    guard scenePhase == .active, travel.selectedTab == 2, api.status?.flightTracking == true, api.isSignedIn,
                          !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
                    while !Task.isCancelled {
                        let ids = Set(items.compactMap(\.flightID))
                        for flight in document.flights where ids.contains(flight.id) {
                            let originZone = TimeZone(identifier: flight.departureZone) ?? context.zone
                            let distance = TravelDay.distance(TodayPlanner.key(.now, zone: originZone), flight.departureDay)
                            guard (-7...1).contains(distance), !Task.isCancelled else { continue }
                            await statuses.refresh(flight, server: api.baseURL) { try await api.flightStatus(flight.flightNumber, day: flight.departureDay) }
                        }
                        do { try await Task.sleep(for: .seconds(300)) } catch { return }
                    }
                }
        }
    }
    private func refreshID(_ day: String) -> String {
        day + "|\(scenePhase)|\(travel.selectedTab)|\(api.isSignedIn)|\(api.status?.flightTracking == true)|" + api.baseURL + "|" + document.flights.map { "\($0.id)-\($0.flightNumber)-\($0.departureDay)" }.joined()
    }
    private func move(_ amount: Int) { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { offset += amount } }
    private func heading(day: String, context: TodayPlanner.Context, base: String, empty: Bool) -> some View {
        let difference = TravelDay.distance(context.day, day)
        let title = difference == 0 ? "Today" : difference == -1 ? "Yesterday" : difference == 1 ? "Tomorrow" : TravelDay.label(day)
        return HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text(empty ? "No activities " + (abs(difference) <= 1 ? title.lowercased() : "on " + title) : title)
                    .font(.headline).accessibilityIdentifier("today-day-title")
                if !empty { Text(TravelDay.label(day)).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if day != context.day {
                Button("Today") { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { offset = TravelDay.distance(base, context.day) } }.font(.caption.weight(.medium)).frame(minHeight: 44)
            }
            Button { move(-1) } label: { Image(systemName: "chevron.left").font(.caption.weight(.semibold)).frame(width: 36, height: 44) }.accessibilityLabel("Previous day").accessibilityIdentifier("today-previous")
            Button { move(1) } label: { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).frame(width: 36, height: 44) }.accessibilityLabel("Next day").accessibilityIdentifier("today-next-day")
        }.tint(Color.bronze)
    }
}
private struct TodayItemRow: View {
    let item: TodayItem
    let isNext: Bool
    var happening = false
    var action: () -> Void
    private var accent: Color { item.kind == .flight ? .blue : item.kind == .hotel ? .teal : .bronze }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(accent)
                    .frame(width: 34, height: 34).background(accent.opacity(0.09), in: .rect(cornerRadius: 10)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    if isNext { Text(happening ? "Happening now" : "Up next").font(.caption2.weight(.medium)).foregroundStyle(accent).accessibilityIdentifier("today-next") }
                    Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    if let timing = item.timing { Label(timing.label, systemImage: timing.symbol).font(.caption2).foregroundStyle(timing.color) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(item.schedule).font(.subheadline.weight(.medium).monospacedDigit()).foregroundStyle(accent).fixedSize(horizontal: true, vertical: false)
            }.padding(.horizontal, 12).padding(.vertical, 12)
                .background(isNext ? accent.opacity(0.055) : .clear, in: .rect(cornerRadius: 16))
                .contentShape(.rect(cornerRadius: 16))
        }.buttonStyle(PressStyle()).accessibilityIdentifier(item.id)
            .accessibilityHint("Show plan details and actions")
    }
}
private struct TodayItemActions: View {
    @Environment(\.dismiss) private var dismiss
    let item: TodayItem
    let day: String
    var statusLabel: String?
    @State private var copyCount = 0
    @State private var copied = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(item.schedule + " · " + TravelDay.label(item.start.map { TodayPlanner.key($0, zone: item.zone) } ?? day) + " · " + (item.zone.abbreviation(for: item.start ?? .now) ?? item.zone.identifier))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !item.detail.isEmpty { Text(item.detail).font(.subheadline).foregroundStyle(.secondary) }
                    if let timing = item.timing { Label(timing.label, systemImage: timing.symbol).font(.subheadline.weight(.medium)).foregroundStyle(timing.color) }
                    if let saved = item.scheduled, let live = item.start, abs(saved.timeIntervalSince(live)) >= 60 {
                        Text("Scheduled " + TodayPlanner.clock(saved, zone: item.zone)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let statusLabel { Text(statusLabel).font(.caption).foregroundStyle(.secondary) }
                    if !item.note.isEmpty { Text(item.note).font(.subheadline).textSelection(.enabled) }
                    VStack(spacing: 0) {
                        if let url = TravelPlaceActions.directions(item.place) {
                            Link(destination: url) { actionRow("Directions", detail: item.place.address, symbol: "arrow.triangle.turn.up.right.diamond") }.accessibilityIdentifier("today-directions")
                        }
                        if let url = TravelPlaceActions.phone(item.place.phone) {
                            Link(destination: url) { actionRow("Call", detail: item.place.phone, symbol: "phone") }.accessibilityIdentifier("today-call")
                        }
                        if let url = TravelPlaceActions.booking(item.place.website) {
                            Link(destination: url) { actionRow("Website", detail: url.host ?? "", symbol: "safari") }.accessibilityIdentifier("today-website")
                        }
                        if !item.confirmation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button { UIPasteboard.general.string = item.confirmation; copyCount += 1; copied = true } label: {
                                actionRow(copied ? "Copied" : "Copy confirmation", detail: item.confirmation, symbol: copied ? "checkmark" : "doc.on.doc")
                            }.accessibilityLabel(copied ? "Confirmation copied" : "Copy confirmation " + item.confirmation).accessibilityIdentifier("today-confirmation-" + item.id)
                        }
                        if let url = TravelPlaceActions.booking(item.bookingLink) {
                            Link(destination: url) { actionRow("Booking", detail: "", symbol: "ticket") }
                        }
                    }.tint(Color.bronze).buttonStyle(.plain)
                }.padding(.horizontal, 22).padding(.bottom, 22)
            }.background(Color.canvas).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("today-actions-done") } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .sensoryFeedback(.selection, trigger: copyCount)
            .task(id: copyCount) { guard copyCount > 0 else { return }; do { try await Task.sleep(for: .seconds(2)); copied = false } catch {} }
    }
    private func actionRow(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.body).frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.vertical, 7).contentShape(Rectangle())
        }
    }
}

enum TodayClock {
    static func now(_ date: Date = .now) -> Date {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--today-testing") { return FlightSnapshot.date("2026-09-07T07:00:00Z")! }
        #endif
        return date
    }
}
#if DEBUG
enum TodayFixtures {
    static var trip: JourneyDocument {
        let stop = JourneyStop(name: "Paris", arrival: "2026-09-06", nights: 3, latitude: 48.8566, longitude: 2.3522, timeZone: "Europe/Paris")
        let restaurant = PlaceRecord(name: "Lunch by the river", category: .restaurant, city: "Paris", address: "1 Rue du Pont Louis-Philippe, Paris", phone: "+33 1 42 78 31 64", website: "https://example.com/restaurant", latitude: 48.8549, longitude: 2.354)
        var trip = JourneyDocument(title: "Paris with family", startDate: stop.arrival, endDate: stop.departure, stops: [stop])
        trip.events = [JourneyEvent(stopID: stop.id, day: 1, minute: 780, place: restaurant, durationMinutes: 90), JourneyEvent(stopID: stop.id, day: 2, minute: 600, place: PlaceRecord(name: "Museum morning", category: .museum))]
        trip.hotels = [HotelReservation(place: PlaceRecord(name: "Your Paris hotel", category: .hotel, address: "10 Place de la Concorde, Paris", phone: "+33 1 44 71 15 00"), checkIn: "2026-09-06", checkOut: "2026-09-09", roomType: "Deluxe double", confirmation: "SEUR-DEMO-123")]
        return trip
    }
}
#endif
