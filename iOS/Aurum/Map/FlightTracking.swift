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

struct FlightDetailPanel: View {
    @Environment(TravelAPI.self) private var api
    @Environment(\.scenePhase) private var scenePhase
    let flight: MapFlight
    @Bindable var tracker: FlightTracker
    var edit: () -> Void
    var track: (FlightPosition) -> Void
    @State private var setup = false
    private var live: FlightSnapshot? { tracker.selected }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) { Eyebrow(text: flight.flight.airline.isEmpty ? "Your flight" : flight.flight.airline); Editorial(flight.title, size: 34).accessibilityIdentifier("map-flight-title"); Text(flight.tripTitle).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button(action: edit) { Image(systemName: "pencil").frame(width: 40, height: 40) }.buttonStyle(.glass).accessibilityLabel("Edit saved flight")
            }
            Label(live?.status ?? "Saved schedule", systemImage: live?.cancelled == true ? "xmark.circle" : "airplane").font(.subheadline.weight(.medium)).foregroundStyle(live?.cancelled == true ? Color.red : Color.bronze)
            HStack(alignment: .top, spacing: 12) {
                airport(live?.origin ?? flight.flight.departureAirport, name: live?.originName, time: live.map { FlightSnapshot.time($0.actualOut ?? $0.estimatedOut ?? $0.scheduledOut, zone: $0.originZone) } ?? "\(flight.flight.departureDay)\n\(flight.flight.departureTime)", caption: live == nil ? "Saved departure" : live?.actualOut != nil ? "Departed gate" : "Expected departure")
                Image(systemName: "airplane").foregroundStyle(Color.bronze).padding(.top, 18)
                airport(live?.destination ?? flight.flight.arrivalAirport, name: live?.destinationName, time: live.map { FlightSnapshot.time($0.actualIn ?? $0.estimatedIn ?? $0.scheduledIn, zone: $0.destinationZone) } ?? "\(flight.flight.arrivalDay)\n\(flight.flight.arrivalTime)", caption: live == nil ? "Saved arrival" : live?.actualIn != nil ? "Arrived at gate" : "Expected arrival")
            }.padding(18).background(Color.cardSurface, in: .rect(cornerRadius: 23))
            Text("Times are local to each airport. Route lines show the direct airport-to-airport route, not the aircraft’s flown track.").font(.caption).foregroundStyle(.secondary)
            if let distance = flight.distance { Label("\(Int(distance)) km direct distance", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.caption).foregroundStyle(.secondary) }
            if tracker.loading { ProgressView("Checking flight status…") }
            if let message = tracker.message { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("flight-data-message") }
            if let feed = tracker.feed {
                if !feed.message.isEmpty { Text(feed.message).font(.subheadline).foregroundStyle(.secondary) }
                Text("Last checked " + Date(timeIntervalSince1970: feed.fetchedAt).formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                if feed.flights.count > 1 {
                    Text("Choose your departure").font(.headline)
                    ForEach(feed.flights) { item in Button { tracker.choose(item.id) } label: { HStack { VStack(alignment: .leading) { Text(item.origin + " → " + item.destination); Text(FlightSnapshot.time(item.scheduledOut, zone: item.originZone)).font(.caption) }; Spacer(); if item.id == tracker.selectedID { Image(systemName: "checkmark.circle.fill") } }.padding(12) }.buttonStyle(.glass) }
                }
            }
            HStack { Button { Task { await tracker.load(flight.flight, api: api) } } label: { Label("Refresh status", systemImage: "arrow.clockwise") }.disabled(tracker.loading); Spacer(); Button { setup = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About live flight data") }.font(.subheadline)
            if let live {
                VStack(alignment: .leading, spacing: 15) {
                    SectionHeading(title: "Every minute, considered")
                    timeline("Departure · " + live.origin, scheduled: live.scheduledOut, estimated: live.estimatedOut, actual: live.actualOut, zone: live.originZone)
                    Divider()
                    timeline("Arrival · " + live.destination, scheduled: live.scheduledIn, estimated: live.estimatedIn, actual: live.actualIn, zone: live.destinationZone)
                }.padding(18).background(Color.cardSurface, in: .rect(cornerRadius: 23))
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 18) {
                    fact("Departure gate", live.gateOrigin); fact("Arrival gate", live.gateDestination); fact("Departure terminal", live.terminalOrigin); fact("Arrival terminal", live.terminalDestination); fact("Baggage belt", live.baggageClaim); fact("Aircraft", live.aircraft); fact("Registration", live.registration); fact("Arrival delay", live.delayMinutes.map { $0 > 0 ? "\($0) min late" : $0 < 0 ? "\(-$0) min early" : "On schedule" })
                }.padding(18).background(Color.cardSurface, in: .rect(cornerRadius: 23))
                Button { Task { await tracker.locate(api: api); if let position = tracker.position { track(position) } } } label: { Label(tracker.positionLoading ? "Locating aircraft…" : "Show reported position", systemImage: "location.north.line") }.buttonStyle(.glass).disabled(tracker.positionLoading)
                if let position = tracker.position {
                    VStack(alignment: .leading, spacing: 8) { Text("Position reported " + FlightSnapshot.time(position.timestamp, zone: "UTC") + " UTC").font(.caption); if let speed = position.groundspeed { Text("\(Int(speed)) knots ground speed").font(.caption) }; if let altitude = position.altitude { Text("\(Int(altitude * 100)) ft reported altitude").font(.caption) } }.foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 13) {
                HStack { SectionHeading(title: "Delay history", subtitle: "Recent completed departures"); Spacer(); if tracker.historyLoading { ProgressView() } }
                if let history = tracker.history {
                    let rows = history.flights.filter { $0.origin == live?.origin && $0.destination == live?.destination && $0.delayMinutes != nil }.sorted { ($0.scheduledOut ?? "") < ($1.scheduledOut ?? "") }
                    if rows.isEmpty { Text("No completed flights with arrival-delay data were returned for this route.").font(.subheadline).foregroundStyle(.secondary) }
                    else {
                        Chart(rows) { item in BarMark(x: .value("Departure", FlightSnapshot.date(item.scheduledOut) ?? .distantPast), y: .value("Arrival delay, minutes", item.delayMinutes ?? 0)).foregroundStyle((item.delayMinutes ?? 0) > 15 ? Color.orange : Color.bronze) }.frame(height: 150).chartYAxisLabel("minutes").accessibilityLabel("Arrival delays for \(rows.count) sampled flights")
                        Text("\(rows.count) flights sampled · \(rows.filter { ($0.delayMinutes ?? 0) <= 15 }.count) arrived within 15 minutes of schedule").font(.caption)
                    }
                    Text(history.message).font(.caption2).foregroundStyle(.secondary)
                } else { Text("See recent arrival delays for this flight and route when historical data is connected.").font(.subheadline).foregroundStyle(.secondary) }
                Button("Load delay history") { Task { await tracker.loadHistory(flight.flight, api: api) } }.disabled(tracker.historyLoading || live == nil)
            }.padding(18).background(Color.cardSurface, in: .rect(cornerRadius: 23))
            if let link = validatedURL(flight.flight.bookingLink) { Link(destination: link) { Label("Open booking", systemImage: "arrow.up.right.square") } }
            if !flight.flight.notes.isEmpty { Text(flight.flight.notes).font(.subheadline) }
            Text("FlightAware supplies connected flight information. Missing fields remain unreported; saved times are never presented as live predictions.").font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("flight-detail-footer")
        }.task(id: "\(flight.flight.hashValue)-\(scenePhase)") {
            guard scenePhase == .active else { return }
            await tracker.load(flight.flight, api: api)
            while !Task.isCancelled && tracker.feed != nil {
                do { try await Task.sleep(for: .seconds(90)) } catch { break }
                guard !Task.isCancelled else { break }
                await tracker.load(flight.flight, api: api)
            }
        }
            .sheet(isPresented: $setup) { FlightDataInfoView() }
    }
    private func airport(_ code: String, name: String?, time: String, caption: String) -> some View { VStack(alignment: .leading, spacing: 8) { Text(code).font(.system(.title2, design: .rounded, weight: .semibold)).lineLimit(2); if let name { Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Text(time).font(.subheadline.monospacedDigit()); Text(caption).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
    private func fact(_ title: String, _ value: String?) -> some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value?.isEmpty == false ? value! : "Not reported").font(.subheadline.weight(.medium)) } }
    private func timeline(_ title: String, scheduled: String?, estimated: String?, actual: String?, zone: String) -> some View { VStack(alignment: .leading, spacing: 9) { Text(title).font(.subheadline.weight(.semibold)); ForEach([("Scheduled", scheduled), ("Estimated", estimated), ("Actual", actual)], id: \.0) { label, value in HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(FlightSnapshot.time(value, zone: zone)).monospacedDigit() }.font(.caption) } } }
}
struct FlightDataInfoView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 24) {
            Eyebrow(text: "Flight intelligence"); Editorial("A clearer picture\nof your journey.", size: 35)
            Text("Your saved flights and routes work immediately. Connected flight data adds updated departure and arrival times, delays, gates, terminals, aircraft details and reported positions when available.")
            Text("Historical access adds a recent delay sample. Availability varies by airline, airport and subscription. Seur does not reproduce Flighty’s proprietary predictions.").foregroundStyle(.secondary)
            Link("Explore FlightAware AeroAPI", destination: URL(string: "https://www.flightaware.com/commercial/aeroapi/")!).buttonStyle(.glass)
            Text("The app’s operator connects the provider securely through Seur’s backend. No flight API secret belongs in the iPhone app. Background alerts and Live Activities require an additional notification service.").font(.subheadline).foregroundStyle(.secondary)
        }.padding(24) }.background(Color.canvas).navigationTitle("Live flight data").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } } }
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
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    var onAdded: (FlightReservation) -> Void
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
    @State private var draft: FlightReservation?
    @State private var accountSheet = false
    private var needsAccount: Bool {
        #if DEBUG
        if FlightMapFixtures.enabled { return false }
        #endif
        return !api.isSignedIn
    }
    @FocusState private var editingAirline: Bool
    private var canSearch: Bool {
        if method == "Flight number" { return airline != nil && number.range(of: "^[0-9]{1,4}[A-Za-z]?$", options: .regularExpression) != nil }
        return Self.airportCode(origin) != nil && Self.airportCode(destination) != nil && origin != destination
    }
    static func airportCode(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return value.range(of: "^[A-Z0-9]{3,4}$", options: .regularExpression) == nil ? nil : value
    }
    var body: some View {
        Group {
            if let draft {
                FlightReservationEditor(documentID: nil, reservation: draft, onCancel: { self.draft = nil }, onSaved: {
                    if let saved = api.savedFlights.first(where: { $0.id == draft.id }) { onAdded(saved) }
                    dismiss()
                })
            } else {
                NavigationStack {
                    Form {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: "airplane.circle").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Color.bronze)
                                Text("Every flight.\nOne beautiful view.").font(.system(size: 30, weight: .regular, design: .serif))
                                Text("Find your departure and save it to your map. No trip needed.").font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 8)
                        }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                        Section {
                            Picker("Find by", selection: $method) { Text("Flight number").tag("Flight number"); Text("Route").tag("Route") }.pickerStyle(.segmented).accessibilityIdentifier("flight-search-method")
                        }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                        if needsAccount { Section { Button { accountSheet = true } label: { Label("Sign in to find and save flights", systemImage: "person.crop.circle") } } }
                        if method == "Flight number" { airlineSection } else { routeSection }
                        Section { DatePicker("Departure date", selection: $day, displayedComponents: .date).accessibilityIdentifier("flight-search-date") } footer: { Text("Use the local date at your departure airport.") }
                        Section {
                            Button { Task { await search() } } label: { HStack { Spacer(); if loading { ProgressView() }; Text(loading ? "Finding flights…" : "Find flight").fontWeight(.semibold); Spacer() } }.disabled(!canSearch || loading || preparing != nil).accessibilityIdentifier("flight-find")
                        }
                        if let error { Section { Label(error, systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("flight-search-error") } }
                        resultsSection
                        Section {
                            Button { draft = FlightReservation(airline: airline?.name ?? "", flightNumber: (airline?.code ?? "") + number.uppercased(), departureAirport: origin, arrivalAirport: destination, departureDay: TravelDay.key(day), arrivalDay: TravelDay.key(day)) } label: { Label("Enter flight manually", systemImage: "square.and.pencil") }.disabled(preparing != nil).accessibilityIdentifier("flight-manual")
                        } footer: { Text("Have a booking for a later date? Add its confirmed schedule now. Live details appear when the provider reports them.") }
                    }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Color.canvas)
                        .navigationTitle("Add a flight").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                }
            }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
            .sheet(isPresented: $accountSheet) { TravelAccountView() }
            .onChange(of: api.isSignedIn) { if api.isSignedIn { accountSheet = false } }
            .onChange(of: airlineText) { if airlineText != airline?.name { airline = nil }; feed = nil }
            .onChange(of: method) { feed = nil; error = nil; editingAirline = false }
            .onChange(of: day) { feed = nil }
            .onChange(of: origin) { feed = nil }
            .onChange(of: destination) { feed = nil }
    }
    private var airlineSection: some View {
        Section("Your airline") {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Airline name or code", text: $airlineText).focused($editingAirline).autocorrectionDisabled().accessibilityIdentifier("flight-airline-query")
                if let airline { Text(airline.code).font(.caption.weight(.semibold)).foregroundStyle(Color.bronze) }
            }
            if editingAirline {
                ForEach(FlightAirline.matches(airlineText)) { value in
                    Button { airline = value; airlineText = value.name; editingAirline = false } label: {
                        HStack { Text(value.name).foregroundStyle(.primary); Spacer(); Text(value.code).foregroundStyle(.secondary) }
                    }.accessibilityIdentifier("flight-airline-" + value.code)
                }
                if FlightAirline.matches(airlineText).isEmpty { Text("Try the airline’s two- or three-character code.").font(.caption).foregroundStyle(.secondary) }
            }
            HStack { Text("Flight number"); Spacer(); TextField("178", text: $number).multilineTextAlignment(.trailing).textInputAutocapitalization(.characters).autocorrectionDisabled().keyboardType(.asciiCapable).accessibilityIdentifier("flight-number-query") }.onChange(of: number) { feed = nil }
        }
    }
    private var routeSection: some View {
        Section("Your route") {
            LocationAutocompleteField("Departure airport or code", text: $origin, kind: .airport, identifier: "flight-route-origin") { result in resolveAirport(result, departure: true) }
            LocationAutocompleteField("Arrival airport or code", text: $destination, kind: .airport, identifier: "flight-route-destination") { result in resolveAirport(result, departure: false) }
        }
    }
    @ViewBuilder private var resultsSection: some View {
    if let feed {
        Section("Departures") {
            ForEach(feed.flights) { flight in
                Button { Task { await choose(flight) } } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(flight.ident).font(.headline); Spacer(); if preparing == flight.id { ProgressView() } else { Image(systemName: "chevron.right").font(.caption) } }
                        HStack { Text(flight.origin); Image(systemName: "arrow.right").foregroundStyle(Color.bronze); Text(flight.destination) }.font(.system(.title3, design: .rounded, weight: .medium))
                        Text(FlightSnapshot.time(flight.scheduledOut ?? flight.scheduledOff, zone: flight.originZone) + " · " + flight.status).font(.caption).foregroundStyle(.secondary)
                    }.foregroundStyle(.primary).padding(.vertical, 8)
                }.disabled(preparing != nil).accessibilityIdentifier("flight-result-" + flight.id)
            }
            if !feed.message.isEmpty { Text(feed.message).font(.caption).foregroundStyle(.secondary) }
        }
    }
    }
    private func resolveAirport(_ selection: LocationSelection, departure: Bool) {
        guard let lat = selection.place.latitude, let lon = selection.place.longitude else { return }
        let selectedText = selection.text
        Task {
            do {
                let airport = try await api.nearbyFlightAirport(latitude: lat, longitude: lon)
                if departure && origin == selectedText { origin = airport.code }
                if !departure && destination == selectedText { destination = airport.code }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func search() async {
        editingAirline = false; loading = true; error = nil; feed = nil
        let searchMethod = method, searchDay = TravelDay.key(day), searchNumber = number, searchOrigin = origin, searchDestination = destination, searchAirline = airline
        defer { loading = false }
        do {
            let result: FlightFeed
            if searchMethod == "Flight number" { result = try await api.flightStatus((searchAirline?.code ?? "") + searchNumber.uppercased(), day: searchDay) }
            else { result = try await api.flightRoute(origin: Self.airportCode(searchOrigin) ?? "", destination: Self.airportCode(searchDestination) ?? "", day: searchDay) }
            guard method == searchMethod, TravelDay.key(day) == searchDay, number == searchNumber, origin == searchOrigin, destination == searchDestination, airline == searchAirline else { return }
            feed = result
        } catch { self.error = error.localizedDescription }
    }
    private func choose(_ flight: FlightSnapshot) async {
        preparing = flight.id; error = nil; defer { preparing = nil }
        var value = flight.reservation(airline: FlightAirline.identified(by: flight.ident)?.name ?? airline?.name ?? flight.ident)
        do {
            async let departure = api.flightAirport(flight.origin)
            async let arrival = api.flightAirport(flight.destination)
            let (a, b) = try await (departure, arrival)
            value.departureLatitude = a.latitude; value.departureLongitude = a.longitude
            value.arrivalLatitude = b.latitude; value.arrivalLongitude = b.longitude
            draft = value
        } catch { self.error = "Couldn’t load this flight’s airport locations. Try again, or enter the flight manually to select its airports." }
    }
}
