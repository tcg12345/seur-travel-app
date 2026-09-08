import SwiftUI
import UIKit

/// Only used with documents from JourneyLibrary, never a shared-document preview.
struct TodayHubView: View {
    @Environment(JourneyLibrary.self) private var library
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            if let trip = TodayPlanner.activeTrip(library.documents, now: TodayClock.now(timeline.date)) {
                VStack(alignment: .leading, spacing: 18) {
                    TodayView(document: trip)
                    NavigationLink { JourneyDetailView(id: trip.id) } label: {
                        Label("Open trip", systemImage: "arrow.up.right").font(.subheadline.weight(.semibold))
                    }.accessibilityIdentifier("today-open-trip")
                    Divider().padding(.vertical, 6)
                    Text("Your travel library").font(.title3.weight(.semibold))
                }
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
            VStack(alignment: .leading, spacing: 18) {
                heading(day: day, context: context, base: base)
                if document.dateMode != .dates {
                    Text("Set trip dates to see your daily plan here.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    if let next {
                        HStack(spacing: 10) {
                            Image(systemName: next.symbol).foregroundStyle(Color.bronze)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(next.start! <= now ? "HAPPENING NOW" : "UP NEXT").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(Color.bronze)
                                Text(next.title).font(.headline)
                                Text(next.schedule + " · " + next.zone.identifier.split(separator: "/").last!.replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 12).accessibilityElement(children: .combine).accessibilityIdentifier("today-next")
                    }
                    if items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("A little room to explore", systemImage: "sun.horizon").font(.headline)
                            Text("No plans saved for this day. Your trip library and full plan are still below.").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 20).accessibilityIdentifier("today-empty")
                    }
                    ForEach(items) { item in
                        TodayItemRow(item: item, day: day, displayZone: context.zone, isNext: item.id == next?.id,
                            statusLabel: item.flightID.flatMap { id in document.flights.first { $0.id == id } }.map { statuses.label($0, server: api.baseURL, now: now) })
                    }
                    let staying = document.hotels.filter { $0.checkIn < day && day < $0.checkOut }
                    if !staying.isEmpty {
                        Text("YOUR HOTEL").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary).padding(.top, 8)
                        ForEach(staying) { hotel in
                            TodayItemRow(item: TodayItem(id: "stay-\(hotel.id)", kind: .hotel, title: hotel.place.name, detail: hotel.roomType,
                                symbol: "bed.double", schedule: "Staying", sortMinute: 0, place: hotel.place, confirmation: hotel.confirmation, zone: context.zone),
                                day: day, displayZone: context.zone, isNext: false)
                        }
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("today-view")
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
    private func heading(day: String, context: TodayPlanner.Context, base: String) -> some View {
        let difference = TravelDay.distance(context.day, day)
        let title = difference == 0 ? "Today" : difference == -1 ? "Yesterday" : difference == 1 ? "Tomorrow" : TravelDay.label(day)
        let cities = Array(NSOrderedSet(array: document.days.filter { $0.date == day }.map(\.city))) as? [String] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            Text(document.title).font(.caption.weight(.medium)).foregroundStyle(Color.bronze)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(.largeTitle, design: .serif).weight(.medium)).accessibilityIdentifier("today-day-title")
                    Text(TravelDay.label(day) + (cities.isEmpty ? "" : " · " + cities.joined(separator: " → "))).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous day").accessibilityIdentifier("today-previous")
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next day").accessibilityIdentifier("today-next-day")
            }
            HStack {
                Text("Times local to each place").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if day != context.day { Button("Back to today") { withAnimation { offset = TravelDay.distance(base, context.day) } }.font(.caption.weight(.semibold)) }
            }
        }
    }
}
private struct TodayItemRow: View {
    let item: TodayItem
    let day: String
    let displayZone: TimeZone
    let isNext: Bool
    var statusLabel: String?
    @State private var copyCount = 0
    @State private var copied = false
    private var accent: Color { item.kind == .flight ? .blue : item.kind == .hotel ? .teal : .bronze }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Divider()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.symbol).font(.title3).foregroundStyle(accent).frame(width: 26).padding(.top, 2)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.schedule).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(accent)
                        if let start = item.start, TodayPlanner.key(start, zone: item.zone) != day {
                            Text(TravelDay.label(TodayPlanner.key(start, zone: item.zone))).font(.caption).foregroundStyle(.secondary)
                        }
                        if item.zone != displayZone { Text(item.zone.abbreviation(for: item.start ?? .now) ?? item.zone.identifier).font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(item.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    if !item.detail.isEmpty { Text(item.detail).font(.caption).foregroundStyle(.secondary) }
                    if let timing = item.timing { Label(timing.label, systemImage: timing.symbol).font(.caption.weight(.semibold)).foregroundStyle(timing.color) }
                    if let saved = item.scheduled, let live = item.start, abs(saved.timeIntervalSince(live)) >= 60 {
                        Text("Scheduled " + TodayPlanner.clock(saved, zone: item.zone)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let statusLabel { Text(statusLabel).font(.caption2).foregroundStyle(.secondary) }
                    if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    actions
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.vertical, 5)
        }.accessibilityElement(children: .contain).accessibilityIdentifier(item.id)
            .sensoryFeedback(.selection, trigger: copyCount)
            .task(id: copyCount) { guard copyCount > 0 else { return }; do { try await Task.sleep(for: .seconds(2)); copied = false } catch {} }
    }
    private var actions: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let url = TravelPlaceActions.directions(item.place) {
                Link(destination: url) {
                    Label(item.place.address.isEmpty ? "Directions" : item.place.address, systemImage: "arrow.triangle.turn.up.right.diamond")
                        .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .leading)
                }.accessibilityLabel("Directions to " + item.place.name)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { contactActions }
                VStack(alignment: .leading, spacing: 4) { contactActions }
            }
        }.font(.caption.weight(.medium)).tint(accent)
    }
    @ViewBuilder private var contactActions: some View {
        if !item.confirmation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button { UIPasteboard.general.string = item.confirmation; copyCount += 1; copied = true } label: {
                Label(copied ? "Copied" : item.confirmation, systemImage: copied ? "checkmark" : "doc.on.doc").frame(minHeight: 44)
            }.accessibilityLabel(copied ? "Confirmation copied" : "Copy confirmation " + item.confirmation).accessibilityIdentifier("today-confirmation-" + item.id)
        }
        if let url = TravelPlaceActions.phone(item.place.phone) { Link(destination: url) { Label(item.place.phone, systemImage: "phone").frame(minHeight: 44) }.accessibilityLabel("Call " + item.place.name) }
        if let url = TravelPlaceActions.booking(item.bookingLink) { Link(destination: url) { Label("Booking", systemImage: "ticket").frame(minHeight: 44) } }
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
        let restaurant = PlaceRecord(name: "Lunch by the river", category: .restaurant, city: "Paris", address: "1 Rue du Pont Louis-Philippe, Paris", phone: "+33 1 42 78 31 64", latitude: 48.8549, longitude: 2.354)
        var trip = JourneyDocument(title: "Paris with family", startDate: stop.arrival, endDate: stop.departure, stops: [stop])
        trip.events = [JourneyEvent(stopID: stop.id, day: 1, minute: 780, place: restaurant, durationMinutes: 90), JourneyEvent(stopID: stop.id, day: 2, minute: 600, place: PlaceRecord(name: "Museum morning", category: .museum))]
        trip.hotels = [HotelReservation(place: PlaceRecord(name: "Your Paris hotel", category: .hotel, address: "10 Place de la Concorde, Paris", phone: "+33 1 44 71 15 00"), checkIn: "2026-09-06", checkOut: "2026-09-09", roomType: "Deluxe double", confirmation: "SEUR-DEMO-123")]
        return trip
    }
}
#endif
