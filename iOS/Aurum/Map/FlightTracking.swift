import SwiftUI
import MapKit
import Charts

struct FlightSnapshot: Codable, Identifiable, Hashable {
    var id: String
    var ident: String
    var status: String
    var cancelled: Bool
    var diverted: Bool
    var origin: String
    var destination: String
    var originName: String
    var destinationName: String
    var originZone: String
    var destinationZone: String
    var scheduledOut: String?
    var estimatedOut: String?
    var actualOut: String?
    var scheduledIn: String?
    var estimatedIn: String?
    var actualIn: String?
    var scheduledOff: String?
    var actualOff: String?
    var scheduledOn: String?
    var actualOn: String?
    var departureDelay: Double?
    var arrivalDelay: Double?
    var gateOrigin: String?
    var gateDestination: String?
    var terminalOrigin: String?
    var terminalDestination: String?
    var baggageClaim: String?
    var aircraft: String?
    var registration: String?
    var inboundID: String?
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds); return formatter.date(from: value)
    }
    static func time(_ value: String?, zone: String) -> String {
        guard let date = date(value) else { return "—" }
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0); formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }
    var delayMinutes: Int? { arrivalDelay.map { Int(($0 / 60).rounded()) } }
}
struct FlightFeed: Codable { var flights: [FlightSnapshot]; var fetchedAt: Double; var historyEnabled: Bool; var message: String }
struct FlightPosition: Codable {
    var latitude: Double; var longitude: Double; var timestamp: String?; var altitude: Double?; var groundspeed: Double?; var heading: Double?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var valid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}
struct MapFlight: Identifiable {
    var tripID: UUID?
    var tripTitle: String
    var flight: FlightReservation
    var id: String { (tripID?.uuidString ?? "standalone-") + flight.id.uuidString }
    var title: String { flight.flightNumber.isEmpty ? "Your flight" : flight.flightNumber.uppercased() }
    var departure: CLLocationCoordinate2D? { Self.coordinate(flight.departureLatitude, flight.departureLongitude) }
    var arrival: CLLocationCoordinate2D? { Self.coordinate(flight.arrivalLatitude, flight.arrivalLongitude) }
    static func coordinate(_ lat: Double?, _ lon: Double?) -> CLLocationCoordinate2D? {
        guard let lat, let lon, lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return .init(latitude: lat, longitude: lon)
    }
    var route: MKGeodesicPolyline? {
        guard let departure, let arrival else { return nil }
        let points = [departure, arrival]; return MKGeodesicPolyline(coordinates: points, count: 2)
    }
    var distance: Double? { guard let departure, let arrival else { return nil }; return CLLocation(latitude: departure.latitude, longitude: departure.longitude).distance(from: CLLocation(latitude: arrival.latitude, longitude: arrival.longitude)) / 1000 }
}

@MainActor @Observable final class FlightTracker {
    var feed: FlightFeed?
    var selectedID: String?
    var history: FlightFeed?
    var position: FlightPosition?
    var message: String?
    var loading = false
    var historyLoading = false
    var positionLoading = false
    private var generation = UUID()
    var selected: FlightSnapshot? { feed?.flights.first { $0.id == selectedID } }
    func load(_ flight: FlightReservation, api: TravelAPI) async {
        let token = UUID(); generation = token; loading = true; message = nil
        do {
            let result = try await api.flightStatus(flight.flightNumber, day: flight.departureDay)
            guard generation == token, !Task.isCancelled else { return }
            feed = result
            if !result.flights.contains(where: { $0.id == selectedID }) { selectedID = result.flights.count == 1 ? result.flights.first?.id : nil; position = nil; history = nil }
        } catch { guard generation == token else { return }; message = error.localizedDescription }
        if generation == token { loading = false }
    }
    func choose(_ id: String) { selectedID = id; position = nil; history = nil }
    func loadHistory(_ flight: FlightReservation, api: TravelAPI) async {
        historyLoading = true
        do { history = try await api.flightHistory(flight.flightNumber, day: flight.departureDay) } catch { message = error.localizedDescription }
        historyLoading = false
    }
    func locate(api: TravelAPI) async {
        guard let selectedID else { return }; positionLoading = true
        do { let value = try await api.flightPosition(selectedID); if self.selectedID == selectedID && value.valid { position = value } } catch { message = error.localizedDescription }
        positionLoading = false
    }
}

/// Shared, airport-local presentation for saved cards and live departures.
enum FlightDisplay {
    static let teal = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.43, green: 0.80, blue: 0.76, alpha: 1) : UIColor(red: 0.10, green: 0.39, blue: 0.38, alpha: 1) })
    static let blue = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.56, green: 0.74, blue: 0.98, alpha: 1) : UIColor(red: 0.22, green: 0.36, blue: 0.58, alpha: 1) })
    static let caution = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.98, green: 0.73, blue: 0.38, alpha: 1) : UIColor(red: 0.58, green: 0.30, blue: 0.02, alpha: 1) })
    static func clock(_ value: String?, zone: String) -> String {
        guard let date = FlightSnapshot.date(value) else { return "—" }
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: zone) ?? .gmt
        formatter.dateFormat = "HH:mm"; return formatter.string(from: date)
    }
    static func localDate(day: String, time: String, zone: String) -> Date? {
        guard let zone = TimeZone(identifier: zone) else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.isLenient = false
        return formatter.date(from: day + " " + time)
    }
    static func duration(_ flight: FlightReservation) -> String? {
        guard let start = localDate(day: flight.departureDay, time: flight.departureTime, zone: flight.departureZone),
              let end = localDate(day: flight.arrivalDay, time: flight.arrivalTime, zone: flight.arrivalZone) else { return nil }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        guard minutes > 0 else { return nil }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
    static func countdown(_ flight: FlightReservation, now: Date) -> String {
        guard let date = localDate(day: flight.departureDay, time: flight.departureTime, zone: flight.departureZone) else { return "Departure time unavailable" }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "Scheduled time passed" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes >= 1440 { return "In \(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "In \(minutes / 60)h \(minutes % 60)m" }
        return "In \(minutes)m"
    }

}

/// Compact flight row that shares the map panel's surface.
struct FlightCard: View {
    let flight: FlightReservation
    var subtitle: String
    var status: String = "Saved schedule"
    var actionSymbol = "chevron.right"
    @Environment(\.dynamicTypeSize) private var typeSize
    private var accent: Color {
        let seed = flight.airline.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return [Color.bronze, FlightDisplay.teal, FlightDisplay.blue][seed % 3]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "airplane.departure").font(.caption.weight(.semibold)).foregroundStyle(accent)
                Text(flight.flightNumber.isEmpty ? "Your flight" : flight.flightNumber.uppercased()).font(.subheadline.weight(.semibold)).foregroundStyle(accent).fixedSize()
                Text(flight.airline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: actionSymbol).font(.caption.weight(.medium)).foregroundStyle(Color.bronze)
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                endpoint(flight.departureAirport, time: flight.departureTime)
                if !typeSize.isAccessibilitySize {
                    HStack(spacing: 4) { Circle().frame(width: 3, height: 3); Capsule().fill(accent.opacity(0.25)).frame(height: 1); Image(systemName: "airplane").font(.system(size: 11)); Capsule().fill(accent.opacity(0.25)).frame(height: 1) }.foregroundStyle(accent).frame(maxWidth: .infinity).accessibilityHidden(true)
                }
                endpoint(flight.arrivalAirport, time: flight.arrivalTime)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { schedule; Spacer(minLength: 12); countdown(at: context.date) }
                    VStack(alignment: .leading, spacing: 7) { schedule; countdown(at: context.date) }
                }
            }
            if flight.departureDay != flight.arrivalDay { Text("Arrives " + TravelDay.label(flight.arrivalDay) + " · airport local time").font(.caption).foregroundStyle(.secondary) }
            if status != "Saved schedule" { Text(status).font(.caption.weight(.medium)).foregroundStyle(Color.bronze) }
            if subtitle != "My flights" && subtitle != "Add to map" { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }.foregroundStyle(.primary).padding(.vertical, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 0.5) }
            .contentShape(Rectangle())
            .accessibilityHint("Times are local to each airport. Countdown is based on scheduled departure.")
    }
    private func endpoint(_ airport: String, time: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(airport.isEmpty ? "—" : airport).font(.title3.weight(.semibold))
            Text(time.isEmpty ? "—" : time).font(.subheadline.monospacedDigit())
        }.fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
    }
    private var schedule: some View {
        Text(TravelDay.label(flight.departureDay) + (FlightDisplay.duration(flight).map { " · " + $0 } ?? "")).font(.caption).foregroundStyle(.secondary)
    }
    private func countdown(at date: Date) -> some View {
        let text = FlightDisplay.countdown(flight, now: date)
        let upcoming = text.hasPrefix("In ")
        return Label(upcoming ? "Departs " + text.lowercased() : text, systemImage: upcoming ? "clock" : "clock.arrow.circlepath").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(upcoming ? accent : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 4).background(upcoming ? accent.opacity(0.10) : Color.primary.opacity(0.04), in: .capsule)
            .accessibilityLabel("Scheduled departure: " + FlightDisplay.countdown(flight, now: date))
    }
}

struct FlightDetailPanel: View {
    @Environment(TravelAPI.self) private var api
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    let flight: MapFlight
    @Bindable var tracker: FlightTracker
    var edit: () -> Void
    var track: (FlightPosition) -> Void
    @State private var setup = false
    private var live: FlightSnapshot? { tracker.selected }
    private var statusColor: Color { live?.cancelled == true ? .red : (live?.delayMinutes ?? 0) > 0 ? FlightDisplay.caution : FlightDisplay.teal }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "airplane").font(.title3).foregroundStyle(FlightDisplay.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(flight.title).font(.title2.weight(.semibold)).accessibilityIdentifier("map-flight-title")
                    Text(flight.flight.airline.isEmpty ? flight.tripTitle : flight.flight.airline).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: edit) { Image(systemName: "pencil").font(.subheadline).frame(width: 44, height: 44) }.buttonStyle(.plain).foregroundStyle(Color.bronze).accessibilityLabel("Edit saved flight")
            }.padding(.bottom, 14)
            ViewThatFits(in: .horizontal) {
                HStack { status; Spacer(minLength: 12); delay }
                VStack(alignment: .leading, spacing: 5) { status; delay }
            }.padding(.bottom, 8)
            if live?.actualOut == nil && live?.cancelled != true {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let countdown = FlightDisplay.countdown(flight.flight, now: context.date)
                    if countdown.hasPrefix("In ") { Text("Scheduled departure " + countdown.lowercased()).font(.caption).foregroundStyle(.secondary).padding(.bottom, 6) }
                }
            }
            Divider()
            endpoint(departure: true)
            HStack(spacing: 10) {
                Capsule().fill(Color.bronze.opacity(0.25)).frame(height: 1)
                Image(systemName: "airplane").font(.caption).foregroundStyle(Color.bronze)
                if let duration = FlightDisplay.duration(flight.flight) { Text(duration + " scheduled").font(.caption).foregroundStyle(.secondary).fixedSize() }
                Capsule().fill(FlightDisplay.teal.opacity(0.25)).frame(height: 1)
            }.padding(.vertical, 2).accessibilityHidden(true)
            endpoint(departure: false)
            Divider()
            updates
            FlightNotificationControls(flight: live, day: flight.flight.departureDay)
            Divider()
            if let feed = tracker.feed, feed.flights.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose your departure").font(.subheadline.weight(.semibold))
                    ForEach(feed.flights) { item in
                        Button { tracker.choose(item.id) } label: {
                            HStack { VStack(alignment: .leading, spacing: 4) { Text(item.origin + " → " + item.destination); Text(FlightSnapshot.time(item.scheduledOut, zone: item.originZone)).font(.caption) }; Spacer(); Image(systemName: item.id == tracker.selectedID ? "checkmark.circle.fill" : "circle") }.padding(.vertical, 8)
                        }.buttonStyle(.plain).foregroundStyle(Color.bronze)
                    }
                }.padding(.bottom, 12)
            }
            if let live {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 16) {
                        timeline("Departure · " + live.origin, scheduled: live.scheduledOut, estimated: live.estimatedOut, actual: live.actualOut, zone: live.originZone)
                        Divider()
                        timeline("Arrival · " + live.destination, scheduled: live.scheduledIn, estimated: live.estimatedIn, actual: live.actualIn, zone: live.destinationZone)
                    }.padding(.vertical, 12)
                } label: { Label("Full schedule", systemImage: "clock").font(.subheadline.weight(.medium)) }.padding(.vertical, 12)
                Divider()
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 14) {
                        fact("Aircraft", live.aircraft)
                        fact("Registration", live.registration)
                        Button { Task { await tracker.locate(api: api); if let position = tracker.position { track(position) } } } label: {
                            Label(tracker.positionLoading ? "Locating aircraft…" : "Show aircraft on map", systemImage: "location.north.line").font(.subheadline)
                        }.disabled(tracker.positionLoading)
                        if let position = tracker.position {
                            Text("Reported " + FlightSnapshot.time(position.timestamp, zone: "UTC") + " UTC").font(.caption).foregroundStyle(.secondary)
                            if let speed = position.groundspeed { Text("\(Int(speed)) knots ground speed").font(.caption) }
                            if let altitude = position.altitude { Text("\(Int(altitude * 100)) ft altitude").font(.caption) }
                        }
                    }.padding(.vertical, 12)
                } label: { Label("Aircraft & position", systemImage: "airplane").font(.subheadline.weight(.medium)) }.padding(.vertical, 12)
                Divider()
            }
            DisclosureGroup { historyPanel.padding(.vertical, 12) } label: {
                Label("Recent performance", systemImage: "chart.bar.xaxis").font(.subheadline.weight(.medium))
            }.padding(.vertical, 12).accessibilityIdentifier("flight-performance")
            Divider()
            if let link = validatedURL(flight.flight.bookingLink) { Link(destination: link) { Label("Open booking", systemImage: "arrow.up.right.square").font(.subheadline) }.padding(.vertical, 14); Divider() }
            if !flight.flight.notes.isEmpty { DisclosureGroup("Notes") { Text(flight.flight.notes).font(.body).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12) }.font(.subheadline).padding(.vertical, 12); Divider() }
            HStack(alignment: .top) {
                Text("Airport local times · Live updates by FlightAware").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("flight-detail-footer")
                Spacer(minLength: 12)
                Button { setup = true } label: { Image(systemName: "info.circle").frame(width: 32, height: 32) }.accessibilityLabel("About flight information")
            }.padding(.top, 14)
        }.task(id: "\(flight.flight.hashValue)-\(scenePhase)") {
            guard scenePhase == .active else { return }
            await tracker.load(flight.flight, api: api)
            while !Task.isCancelled && tracker.feed != nil {
                do { try await Task.sleep(for: .seconds(90)) } catch { break }
                guard !Task.isCancelled else { break }
                await tracker.load(flight.flight, api: api)
            }
        }.sheet(isPresented: $setup) { FlightDataInfoView() }
    }
    private var status: some View {
        Label(live?.status ?? "Saved schedule", systemImage: live?.cancelled == true ? "xmark.circle.fill" : "circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(statusColor)
    }
    @ViewBuilder private var delay: some View {
        if let minutes = live?.delayMinutes, minutes != 0 { Text(minutes > 0 ? "Arrival \(minutes)m late" : "Arrival \(-minutes)m early").font(.caption.weight(.medium)).foregroundStyle(statusColor) }
    }
    private var updates: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if tracker.loading { ProgressView().controlSize(.small); Text("Updating…").font(.caption).foregroundStyle(.secondary) }
                else if let feed = tracker.feed { Text("Updated " + Date(timeIntervalSince1970: feed.fetchedAt).formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { Task { await tracker.load(flight.flight, api: api) } } label: { Image(systemName: "arrow.clockwise").font(.subheadline).frame(width: 44, height: 36) }.disabled(tracker.loading).accessibilityLabel("Refresh flight status")
            }
            if let message = tracker.message { Label(message, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("flight-data-message") }
            if let message = tracker.feed?.message, !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 6)
    }
    private func endpoint(departure: Bool) -> some View {
        let saved = flight.flight
        let code = departure ? live?.origin ?? saved.departureAirport : live?.destination ?? saved.arrivalAirport
        let name = departure ? live?.originName : live?.destinationName
        let actual = departure ? live?.actualOut : live?.actualIn
        let estimated = departure ? live?.estimatedOut : live?.estimatedIn
        let scheduled = departure ? live?.scheduledOut ?? live?.scheduledOff : live?.scheduledIn ?? live?.scheduledOn
        let zone = departure ? live?.originZone ?? saved.departureZone : live?.destinationZone ?? saved.arrivalZone
        let clock = live == nil ? (departure ? saved.departureTime : saved.arrivalTime) : FlightDisplay.clock(actual ?? estimated ?? scheduled, zone: zone)
        let date = live == nil ? TravelDay.label(departure ? saved.departureDay : saved.arrivalDay) : String(FlightSnapshot.time(actual ?? estimated ?? scheduled, zone: zone).split(separator: ",").first ?? "—")
        let accent = departure ? Color.bronze : FlightDisplay.teal
        let gate = departure ? live?.gateOrigin : live?.gateDestination
        let terminal = departure ? live?.terminalOrigin : live?.terminalDestination
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text(departure ? "Departure" : "Arrival"); Spacer(); Text(date) }.font(.caption).foregroundStyle(.secondary)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(code.isEmpty ? "—" : code).font(.title2.weight(.semibold)).foregroundStyle(accent)
                    if let name { Text(name).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(clock.isEmpty ? "—" : clock).font(.title2.weight(.semibold).monospacedDigit()).fixedSize()
                    Text(live == nil ? "Scheduled" : actual != nil ? "Actual" : estimated != nil ? "Expected" : "Scheduled").font(.caption2).foregroundStyle(.secondary)
                    if let scheduled, let current = actual ?? estimated, FlightSnapshot.date(current) != FlightSnapshot.date(scheduled) {
                        Text(FlightDisplay.clock(scheduled, zone: zone) + " scheduled").font(.caption2).foregroundStyle(.secondary).strikethrough()
                    }
                }
            }
            if live != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { gateLabel(gate, accent: accent); if let terminal, !terminal.isEmpty { Text("Terminal " + terminal).font(.caption).foregroundStyle(.secondary) } }
                    VStack(alignment: .leading, spacing: 6) { gateLabel(gate, accent: accent); if let terminal, !terminal.isEmpty { Text("Terminal " + terminal).font(.caption).foregroundStyle(.secondary) } }
                }
                if !departure, let baggage = live?.baggageClaim, !baggage.isEmpty { Label("Baggage belt " + baggage, systemImage: "suitcase.rolling").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 14)
    }
    private func gateLabel(_ gate: String?, accent: Color) -> some View {
        Text(gate?.isEmpty == false ? "Gate " + gate! : "Gate not reported").font(.caption.weight(.semibold)).foregroundStyle(gate?.isEmpty == false ? accent : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 4).background(accent.opacity(0.09), in: .capsule)
    }
    private func fact(_ title: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(title).foregroundStyle(.secondary); Spacer(); Text(value?.isEmpty == false ? value! : "Not reported") }.font(.subheadline)
    }
    private func timeline(_ title: String, scheduled: String?, estimated: String?, actual: String?, zone: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach([("Scheduled", scheduled), ("Expected", estimated), ("Actual", actual)], id: \.0) { label, value in
                ViewThatFits(in: .horizontal) {
                    HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(FlightSnapshot.time(value, zone: zone)).monospacedDigit() }
                    VStack(alignment: .leading) { Text(label).foregroundStyle(.secondary); Text(FlightSnapshot.time(value, zone: zone)).monospacedDigit() }
                }.font(.caption)
            }
        }
    }
    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tracker.historyLoading { ProgressView("Loading recent arrivals…") }
            if let history = tracker.history {
                let rows = history.flights.filter { $0.origin == live?.origin && $0.destination == live?.destination && $0.delayMinutes != nil }.sorted { ($0.scheduledOut ?? "") < ($1.scheduledOut ?? "") }
                if rows.isEmpty { Text("No recent arrival data for this route.").font(.subheadline).foregroundStyle(.secondary) }
                else {
                    Chart(rows) { item in BarMark(x: .value("Departure", FlightSnapshot.date(item.scheduledOut) ?? .distantPast), y: .value("Arrival delay, minutes", item.delayMinutes ?? 0)).foregroundStyle((item.delayMinutes ?? 0) > 15 ? FlightDisplay.caution : FlightDisplay.teal) }.frame(height: 140).chartYAxisLabel("minutes").accessibilityLabel("Arrival delays for \(rows.count) sampled flights")
                    Text("\(rows.filter { ($0.delayMinutes ?? 0) <= 15 }.count) of \(rows.count) arrived within 15 minutes of schedule").font(.caption)
                }
                Text(history.message).font(.caption).foregroundStyle(.secondary)
            } else { Text("See how this route’s recent flights arrived.").font(.caption).foregroundStyle(.secondary) }
            Button("Load delay history") { Task { await tracker.loadHistory(flight.flight, api: api) } }.font(.subheadline).disabled(tracker.historyLoading || live == nil)
        }
    }
}

struct FlightDataInfoView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Live status") {
                    Text("Arrival times, delays, gates and aircraft details update when provided by the airline or tracking service.")
                }
                Section("On the map") {
                    Label("Dashed route · planned flight", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    Label("Aircraft marker · reported position", systemImage: "airplane")
                }
                Section("Delay history") {
                    Text("Recent departures can show a delay sample. Coverage depends on the airline and available flight data.")
                }
                Section { Link("FlightAware", destination: URL(string: "https://www.flightaware.com/commercial/aeroapi/")!) }
            }.scrollContentBackground(.hidden).background(Color.canvas)
                .navigationTitle("Flight information").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }
    }
}

#if DEBUG
@MainActor enum FlightMapFixtures {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--map-testing") }
    static var snapshot: FlightSnapshot {
        FlightSnapshot(id: "BAW178-ui-test", ident: "BA178", status: "UI test · Delayed", cancelled: false, diverted: false, origin: "JFK", destination: "LHR", originName: "John F. Kennedy International", destinationName: "London Heathrow", originZone: "America/New_York", destinationZone: "Europe/London", scheduledOut: "2026-09-06T22:00:00Z", estimatedOut: "2026-09-06T22:30:00Z", scheduledIn: "2026-09-07T05:00:00Z", estimatedIn: "2026-09-07T05:35:00Z", departureDelay: 1800, arrivalDelay: 2100, gateOrigin: "8", gateDestination: "B32", terminalOrigin: "8", terminalDestination: "5", aircraft: "B77W", registration: "TEST ONLY")
    }
    static var feed: FlightFeed { .init(flights: [snapshot], fetchedAt: Date.now.timeIntervalSince1970, historyEnabled: true, message: "UI test fixture") }
    static var history: FlightFeed {
        let rows = (1...5).map { day in var row = snapshot; row.id += "-\(day)"; row.scheduledOut = "2026-09-0\(day)T22:00:00Z"; row.arrivalDelay = Double([0, 1200, -300, 2100, 600][day - 1]); return row }
        return .init(flights: rows, fetchedAt: Date.now.timeIntervalSince1970, historyEnabled: true, message: "UI test sample only")
    }
    static var trip: JourneyDocument {
        let stop = JourneyStop(name: "London", country: "United Kingdom", arrival: "2026-09-07", nights: 4, latitude: 51.5074, longitude: -0.1278)
        var trip = JourneyDocument(title: "Map QA journey", stops: [stop])
        trip.flights = [FlightReservation(airline: "British Airways", flightNumber: "BA178", departureAirport: "JFK", arrivalAirport: "LHR", departureDay: "2026-09-06", arrivalDay: "2026-09-07", departureTime: "18:00", arrivalTime: "06:00", departureLatitude: 40.6413, departureLongitude: -73.7781, arrivalLatitude: 51.4700, arrivalLongitude: -0.4543, departureZone: "America/New_York", arrivalZone: "Europe/London")]
        trip.events = [JourneyEvent(stopID: stop.id, place: PlaceRecord(name: "A London museum", category: .museum, city: "London", latitude: 51.5194, longitude: -0.1270), kind: .place)]
        return trip
    }
}
#endif

struct FlightAirport: Decodable {
    var code: String
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZone: String
}

struct FlightAirline: Identifiable, Hashable {
    var name: String
    var code: String
    var id: String { code }
    static let collection: [FlightAirline] = [
        ("Aer Lingus", "EI"), ("Aeromexico", "AM"), ("Air Canada", "AC"), ("Air China", "CA"),
        ("Air France", "AF"), ("Air India", "AI"), ("Air New Zealand", "NZ"), ("Air Portugal · TAP", "TP"),
        ("Air Transat", "TS"), ("Alaska Airlines", "AS"), ("All Nippon Airways · ANA", "NH"),
        ("American Airlines", "AA"), ("Asiana Airlines", "OZ"), ("Austrian Airlines", "OS"),
        ("Avianca", "AV"), ("British Airways", "BA"), ("Brussels Airlines", "SN"),
        ("Cathay Pacific", "CX"), ("China Airlines", "CI"), ("China Eastern", "MU"), ("China Southern", "CZ"),
        ("Copa Airlines", "CM"), ("Delta Air Lines", "DL"), ("easyJet", "U2"), ("Egyptair", "MS"),
        ("Emirates", "EK"), ("Ethiopian Airlines", "ET"), ("Etihad Airways", "EY"), ("EVA Air", "BR"),
        ("Fiji Airways", "FJ"), ("Finnair", "AY"), ("Frontier Airlines", "F9"), ("Gulf Air", "GF"),
        ("Hawaiian Airlines", "HA"), ("Iberia", "IB"), ("Icelandair", "FI"), ("IndiGo", "6E"),
        ("ITA Airways", "AZ"), ("Japan Airlines", "JL"), ("JetBlue", "B6"), ("Jetstar", "JQ"),
        ("Kenya Airways", "KQ"), ("KLM", "KL"), ("Korean Air", "KE"), ("LATAM", "LA"),
        ("LOT Polish Airlines", "LO"), ("Lufthansa", "LH"), ("Malaysia Airlines", "MH"),
        ("Norwegian", "DY"), ("Oman Air", "WY"), ("Philippine Airlines", "PR"), ("Qantas", "QF"),
        ("Qatar Airways", "QR"), ("Royal Air Maroc", "AT"), ("Royal Jordanian", "RJ"), ("Ryanair", "FR"),
        ("Saudia", "SV"), ("Scandinavian Airlines · SAS", "SK"), ("Singapore Airlines", "SQ"),
        ("South African Airways", "SA"), ("Southwest Airlines", "WN"), ("Spirit Airlines", "NK"),
        ("SriLankan Airlines", "UL"), ("Swiss", "LX"), ("Thai Airways", "TG"), ("Turkish Airlines", "TK"),
        ("United Airlines", "UA"), ("Vietnam Airlines", "VN"), ("Virgin Atlantic", "VS"),
        ("Virgin Australia", "VA"), ("Vueling", "VY"), ("WestJet", "WS"), ("Wizz Air", "W6")
    ].map { FlightAirline(name: $0.0, code: $0.1) }
    static func matches(_ query: String) -> [FlightAirline] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = collection.filter { term.isEmpty || $0.name.localizedCaseInsensitiveContains(term) || $0.code.localizedCaseInsensitiveContains(term) }
        if results.isEmpty && term.range(of: "^[A-Za-z0-9]{2,3}$", options: .regularExpression) != nil {
            return [.init(name: "Airline code " + term.uppercased(), code: term.uppercased())]
        }
        return Array(results.prefix(8))
    }
    static func identified(by ident: String) -> FlightAirline? {
        collection.first { ident.uppercased().hasPrefix($0.code) && ident.dropFirst($0.code.count).first?.isNumber == true }
    }
}

extension FlightSnapshot {
    func reservation(airline: String) -> FlightReservation {
        func local(_ text: String?, zone: String, format: String) -> String {
            guard let date = Self.date(text) else { return "" }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0); formatter.dateFormat = format
            return formatter.string(from: date)
        }
        return FlightReservation(airline: airline, flightNumber: ident, departureAirport: origin, arrivalAirport: destination,
            departureDay: local(scheduledOut ?? scheduledOff, zone: originZone, format: "yyyy-MM-dd"),
            arrivalDay: local(scheduledIn ?? scheduledOn, zone: destinationZone, format: "yyyy-MM-dd"),
            departureTime: local(scheduledOut ?? scheduledOff, zone: originZone, format: "HH:mm"),
            arrivalTime: local(scheduledIn ?? scheduledOn, zone: destinationZone, format: "HH:mm"),
            departureZone: originZone, arrivalZone: destinationZone)
    }
}

struct FlightAddView: View {
    private enum Step: Hashable { case number, destination, date, results }
    @Environment(TravelAPI.self) private var api
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let documentID: UUID?
    var onAdded: (FlightReservation) -> Void
    @State private var path: [Step] = []
    @State private var method = "Flight number"
    @State private var airlineText = ""
    @State private var airline: FlightAirline?
    @State private var number = ""
    @State private var day = Date.now
    @State private var origin = ""
    @State private var destination = ""
    @State private var feed: FlightFeed?
    @State private var error: String?
    @State private var loading = false
    @State private var preparing: String?
    @State private var prepared: [String: FlightReservation] = [:]
    @State private var draft: FlightReservation?
    @State private var accountSheet = false
    @FocusState private var focused: Step?
    init(documentID: UUID? = nil, departureDay: String? = nil, onAdded: @escaping (FlightReservation) -> Void) {
        self.documentID = documentID
        self.onAdded = onAdded
        _day = State(initialValue: departureDay.map(TravelDay.localDate) ?? .now)
    }
    private func savedFlight(_ id: UUID) -> FlightReservation? {
        if let documentID { return library.documents.first(where: { $0.id == documentID })?.flights.first(where: { $0.id == id }) }
        return api.savedFlights.first(where: { $0.id == id })
    }
    private var needsAccount: Bool {
        #if DEBUG
        if FlightMapFixtures.enabled { return false }
        #endif
        return !api.isSignedIn
    }
    private var validNumber: Bool { number.range(of: "^[0-9]{1,4}[A-Za-z]?$", options: .regularExpression) != nil }
    private var validRoute: Bool { Self.airportCode(origin) != nil && Self.airportCode(destination) != nil && Self.airportCode(origin) != Self.airportCode(destination) }
    static func airportCode(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return value.range(of: "^[A-Z0-9]{3,4}$", options: .regularExpression) == nil ? nil : value
    }
    var body: some View {
        NavigationStack(path: $path) {
            page(title: method == "Flight number" ? "Which airline?" : "Where from?", subtitle: method == "Flight number" ? "Search by airline name or code." : "Choose your departure airport.", progress: 1) {
                Picker("Find by", selection: $method) { Text("Flight number").tag("Flight number"); Text("Route").tag("Route") }.pickerStyle(.segmented).accessibilityIdentifier("flight-search-method")
                if method == "Flight number" { airlinePage }
                else {
                    airportField(departure: true)
                    nextButton("Continue", enabled: Self.airportCode(origin) != nil) { advance(.destination) }
                }
                manualButton
            }
            .navigationDestination(for: Step.self) { step in
                Group {
                    switch step {
                    case .number:
                        page(title: "Flight number?", subtitle: airline?.name ?? "Your airline", progress: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(airline?.code ?? "").font(.largeTitle.weight(.semibold)).foregroundStyle(Color.bronze)
                                TextField("178", text: $number).font(.largeTitle.weight(.semibold).monospacedDigit()).textInputAutocapitalization(.characters).autocorrectionDisabled().keyboardType(.asciiCapable).focused($focused, equals: .number).submitLabel(.continue).onSubmit { if validNumber { advance(.date) } }.accessibilityIdentifier("flight-number-query")
                            }.padding(22).cardSurface(cornerRadius: 24)
                            Text("The digits after your airline code, as shown on your booking.").font(.subheadline).foregroundStyle(.secondary)
                            nextButton("Continue", enabled: validNumber) { advance(.date) }
                        }
                    case .destination:
                        page(title: "Where to?", subtitle: "Departing from \(Self.airportCode(origin) ?? origin)", progress: 2) {
                            airportField(departure: false)
                            nextButton("Continue", enabled: validRoute) { advance(.date) }
                            if Self.airportCode(origin) == Self.airportCode(destination), !destination.isEmpty { Text("Choose a different arrival airport.").font(.subheadline).foregroundStyle(.secondary) }
                        }
                    case .date:
                        page(title: "When do you fly?", subtitle: searchLabel, progress: 3) {
                            DatePicker("Departure date", selection: $day, displayedComponents: .date).datePickerStyle(.graphical).accessibilityIdentifier("flight-search-date")
                                .padding(12).cardSurface(cornerRadius: 24)
                                .onChange(of: day) { advance(.results) }
                            Text("Use the departure airport’s local date.").font(.subheadline).foregroundStyle(.secondary)
                            nextButton("Find flight", enabled: true, identifier: "flight-find") { advance(.results) }
                        }
                    case .results:
                        page(title: "Choose your flight", subtitle: searchLabel + " · " + TravelDay.label(TravelDay.key(day)), progress: 4) { resultsPage }
                            .task(id: api.isSignedIn) { await search() }
                    }
                }.navigationBarBackButtonHidden(preparing != nil)
            }

        }
        .tint(Color.bronze).presentationDetents([.large]).presentationDragIndicator(.visible).interactiveDismissDisabled(preparing != nil)
        .sheet(item: $draft) { value in
            FlightReservationEditor(documentID: documentID, reservation: value, onSaved: {
                if let saved = savedFlight(value.id) { onAdded(saved); dismiss() }
            }).environment(\.tripEditorEmbedded, false)
        }
        .fullScreenCover(isPresented: $accountSheet) { TravelAccountView() }
        .onChange(of: api.isSignedIn) { if api.isSignedIn { accountSheet = false } }
        .onChange(of: method) { error = nil; feed = nil }
        .sensoryFeedback(.success, trigger: preparing == nil && !api.savedFlights.isEmpty)
    }
    private var searchLabel: String { method == "Flight number" ? (airline?.code ?? "") + " " + number.uppercased() : (Self.airportCode(origin) ?? origin) + " → " + (Self.airportCode(destination) ?? destination) }
    private func page<Content: View>(title: String, subtitle: String, progress: Int, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 6) { ForEach(1...4, id: \.self) { index in Capsule().fill(index <= progress ? Color.bronze : Color.bronze.opacity(0.14)).frame(height: 3) } }.accessibilityLabel("Step \(progress) of 4")
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.largeTitle.weight(.semibold)).tracking(-0.8).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                content()
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(Color.canvas).navigationTitle("Add flight").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).disabled(preparing != nil).accessibilityIdentifier("flight-add-cancel") } }
    }
    private var airlinePage: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.bronze)
                TextField("Airline name or code", text: $airlineText).autocorrectionDisabled().submitLabel(.continue).accessibilityIdentifier("flight-airline-query")
                    .onSubmit { let matches = FlightAirline.matches(airlineText); if matches.count == 1, let first = matches.first { selectAirline(first) } }
            }.padding(18).cardSurface(cornerRadius: 20)
            VStack(spacing: 0) {
                ForEach(FlightAirline.matches(airlineText)) { value in
                    Button { selectAirline(value) } label: {
                        HStack(spacing: 14) {
                            Text(value.code).font(.subheadline.weight(.semibold)).foregroundStyle(Color.bronze).frame(width: 46, height: 46).background(Color.bronze.opacity(0.08), in: .rect(cornerRadius: 14))
                            Text(value.name).font(.body.weight(.medium)).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }.padding(.vertical, 11).contentShape(Rectangle())
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("flight-airline-" + value.code)
                    if value.id != FlightAirline.matches(airlineText).last?.id { Divider().padding(.leading, 60) }
                }
                if FlightAirline.matches(airlineText).isEmpty { Text("Try the airline’s two- or three-character code.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 16) }
            }
        }
    }
    private func selectAirline(_ value: FlightAirline) { airline = value; advance(.number) }
    private func advance(_ step: Step) {
        guard path.last != step, preparing == nil else { return }
        focused = nil; error = nil
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.26)) { path.append(step) }
    }
    private func nextButton(_ title: String, enabled: Bool, identifier: String = "flight-step-continue", action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(title); Spacer(); Image(systemName: "arrow.right") }.font(.headline).padding(.vertical, 13).padding(.horizontal, 8).frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).disabled(!enabled).accessibilityIdentifier(identifier)
    }
    private func airportField(departure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LocationAutocompleteField(departure ? "Departure airport or code" : "Arrival airport or code", text: departure ? $origin : $destination, kind: .airport, identifier: departure ? "flight-route-origin" : "flight-route-destination", onSelect: { result in resolveAirport(result, departure: departure) })
                .padding(18).cardSurface(cornerRadius: 20)
                .onSubmit { if departure && Self.airportCode(origin) != nil { advance(.destination) }; if !departure && validRoute { advance(.date) } }
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.secondary) }
        }
    }
    private var manualButton: some View {
        Button {
            draft = FlightReservation(airline: airline?.name ?? "", flightNumber: (airline?.code ?? "") + number.uppercased(), departureAirport: Self.airportCode(origin) ?? "", arrivalAirport: Self.airportCode(destination) ?? "", departureDay: TravelDay.key(day), arrivalDay: TravelDay.key(day))
        } label: { Label("Enter flight manually", systemImage: "square.and.pencil").font(.subheadline) }.disabled(preparing != nil).accessibilityIdentifier("flight-manual")
    }
    @ViewBuilder private var resultsPage: some View {
        if needsAccount {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sign in to find and save your flights.").font(.body)
                nextButton("Sign in", enabled: true) { accountSheet = true }
                Button("Search again") { Task { await search() } }.font(.subheadline)
            }
        } else if loading {
            ProgressView("Finding your departure…").frame(maxWidth: .infinity).padding(.vertical, 40)
        }
        if let error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("flight-search-error") }
        if let feed {
            Text(documentID == nil ? "Tap a flight to add it to your map." : "Tap a flight to add it to your trip.").font(.subheadline).foregroundStyle(.secondary)
            ForEach(feed.flights) { flight in
                Button { Task { await choose(flight) } } label: {
                    FlightCard(flight: flight.reservation(airline: FlightAirline.identified(by: flight.ident)?.name ?? airline?.name ?? flight.ident), subtitle: preparing == flight.id ? "Adding…" : (documentID == nil ? "Add to map" : "Add to trip"), status: flight.status, actionSymbol: "plus")
                        .overlay { if preparing == flight.id { ProgressView().padding(16).background(.regularMaterial, in: .circle) } }
                }.buttonStyle(PressStyle()).disabled(preparing != nil).accessibilityIdentifier("flight-result-" + flight.id)
            }
            if feed.flights.isEmpty {
                ContentUnavailableView("No flights found", systemImage: "airplane", description: Text("Try another date or flight number, or add your booked schedule manually."))
            }
            if !feed.message.isEmpty { Text(feed.message).font(.caption).foregroundStyle(.secondary) }
        }
        if !loading && !needsAccount { Button("Search again") { Task { await search() } }.disabled(preparing != nil) }
        manualButton
    }
    private func resolveAirport(_ selection: LocationSelection, departure: Bool) {
        guard let lat = selection.place.latitude, let lon = selection.place.longitude else { return }
        let selectedText = selection.text
        let startingPath = path
        Task {
            do {
                let airport = try await api.nearbyFlightAirport(latitude: lat, longitude: lon)
                guard path == startingPath, method == "Route" else { return }
                if departure && origin == selectedText { origin = airport.code; advance(.destination) }
                if !departure && destination == selectedText { destination = airport.code; if validRoute { advance(.date) } }
            } catch { if path == startingPath { self.error = error.localizedDescription } }
        }
    }
    private func search() async {
        guard !needsAccount, !loading else { return }
        loading = true; error = nil; feed = nil
        let searchMethod = method, searchDay = TravelDay.key(day), searchNumber = number, searchOrigin = origin, searchDestination = destination, searchAirline = airline
        defer { loading = false }
        do {
            let result: FlightFeed
            if searchMethod == "Flight number" { result = try await api.flightStatus((searchAirline?.code ?? "") + searchNumber.uppercased(), day: searchDay) }
            else { result = try await api.flightRoute(origin: Self.airportCode(searchOrigin) ?? "", destination: Self.airportCode(searchDestination) ?? "", day: searchDay) }
            guard !Task.isCancelled, path.last == .results, method == searchMethod, TravelDay.key(day) == searchDay, number == searchNumber, origin == searchOrigin, destination == searchDestination, airline == searchAirline else { return }
            feed = result
        } catch { if !Task.isCancelled && path.last == .results { self.error = error.localizedDescription } }
    }
    private func choose(_ flight: FlightSnapshot) async {
        guard preparing == nil else { return }
        preparing = flight.id; error = nil; defer { preparing = nil }
        var value = prepared[flight.id] ?? flight.reservation(airline: FlightAirline.identified(by: flight.ident)?.name ?? airline?.name ?? flight.ident)
        // Reuse the reservation ID on retries so an interrupted response cannot create duplicates.
        prepared[flight.id] = value
        do {
            async let departure = api.flightAirport(flight.origin)
            async let arrival = api.flightAirport(flight.destination)
            let (a, b) = try await (departure, arrival)
            value.departureLatitude = a.latitude; value.departureLongitude = a.longitude
            value.arrivalLatitude = b.latitude; value.arrivalLongitude = b.longitude
            var validation = JourneyDocument(title: "Flight"); validation.flights = [value]
            if let problem = validation.validationError() { error = problem; return }
            if let documentID {
                guard var document = library.documents.first(where: { $0.id == documentID }) else { error = "This trip is no longer available."; return }
                document.flights.removeAll { $0.id == value.id }
                document.flights.append(value)
                guard library.save(document) else { error = library.error ?? "Couldn’t save this flight to your trip. Try again."; return }
            } else {
                try await api.saveFlight(value)
            }
            guard let saved = savedFlight(value.id) else { error = "Your flight could not be found after saving. Please try again."; return }
            onAdded(saved); dismiss()
        } catch { self.error = "Couldn’t add this flight. " + error.localizedDescription }
    }
}
