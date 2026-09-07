import SwiftUI
import MapKit

struct WorldMapView: View {
    @Environment(TravelStore.self) private var store
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Namespace private var sectionSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .camera(MapCamera(centerCoordinate: .init(latitude: 22, longitude: 5), distance: 32_000_000))
    @State private var mapHeight: CGFloat = 800
    @State private var center = CLLocationCoordinate2D(latitude: 22, longitude: 5)
    @State private var mode = "Explore"
    @State private var panelVisible = true
    @State private var detent: PresentationDetent = .height(260)
    @State private var showSaved = false
    @State private var satellite = true
    @State private var selection: String?
    @State private var cityQuery = ""
    @State private var selectedCity: ExploreCity?
    @State private var interest: ExploreInterest = .attractions
    @State private var search = CityExploreModel()
    @State private var searchArea: ExploreCity?
    @State private var tripID: UUID?
    @State private var selectedFlightID: String?
    @State private var tracker = FlightTracker()
    @State private var adding: ExplorePlace?
    @State private var editingFlight = false
    @State private var newTrip = false
    @State private var flightInfo = false
    @State private var addingFlight = false
    private var flights: [MapFlight] {
        var values = api.savedFlights.map { MapFlight(tripID: nil, tripTitle: "My flights", flight: $0) }
        for trip in library.documents { for flight in trip.flights { values.append(MapFlight(tripID: trip.id, tripTitle: trip.title, flight: flight)) } }
        return values.sorted { a, b in
            if a.flight.departureDay == b.flight.departureDay { return a.flight.departureTime < b.flight.departureTime }
            return a.flight.departureDay > b.flight.departureDay
        }
    }

    private var selectedFlight: MapFlight? { flights.first { $0.id == selectedFlightID } }
    private var trip: JourneyDocument? { library.documents.first { $0.id == tripID } }
    private var cities: [ExploreCity] { var seen = Set<String>(); return (store.savedExploreCities + store.recentExploreCities + ExploreCity.collection).filter { seen.insert($0.id).inserted } }
    private var places: [ExplorePlace] {
        var seen = Set<String>()
        return (search.places + store.savedDiscoveries).filter { $0.record.hasCoordinate && seen.insert($0.id).inserted }
    }
    private var tripPlaces: [PlaceRecord] { var seen = Set<String>(); return (trip.map { [$0] } ?? library.documents).flatMap(\.mapPlaces).filter { $0.hasCoordinate && seen.insert($0.id).inserted } }
    private var routes: [MapFlight] { if let selectedFlight { return [selectedFlight] }; if mode == "Trips", let tripID { return flights.filter { $0.tripID == tripID } }; return flights }
    var body: some View {
        ZStack(alignment: .top) {
            map.ignoresSafeArea()
            topControls.padding(.horizontal, 18).padding(.top, 8)
            if panelVisible {
                PersistentMapPanel(detent: $detent, contentID: selectedFlightID ?? mode, header: { panelHeader }, content: { panelContent })

            }
        }
        .safeAreaInset(edge: .bottom) {
            if !panelVisible { Button { panelVisible = true } label: { Label("Explore your world", systemImage: "line.3.horizontal").frame(maxWidth: .infinity).padding(14) }.buttonStyle(.glassProminent).padding(.horizontal, 22).padding(.bottom, 8).accessibilityIdentifier("map-show-panel") }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mapHeight = $0 }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: store.selectedTab) { _, _ in
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { detent = .height(260); panelVisible = true }
        }
        .onChange(of: selection) { _, value in selected(value) }
        .onChange(of: mode) { selection = nil; if mode != "Flights" { selectedFlightID = nil; tracker = FlightTracker() } }
        .task(id: api.account?.id) { await api.loadSavedFlights() }
        .navigationDestination(isPresented: $showSaved) { SavedView().toolbar(.visible, for: .navigationBar) }
        .sheet(item: $adding) { ExploreAddToTripView(place: $0) }
        .sheet(isPresented: $editingFlight) { if let selectedFlight { FlightReservationEditor(documentID: selectedFlight.tripID, reservation: selectedFlight.flight) } }
        .sheet(isPresented: $newTrip) { TripCreationView() }
        .sheet(isPresented: $flightInfo) { FlightDataInfoView() }
        .sheet(isPresented: $addingFlight) { FlightAddView { flight in openFlight(MapFlight(tripID: nil, tripTitle: "My flights", flight: flight)) } }
    }
    private var map: some View {
        Map(position: $camera, selection: $selection) {
            if mode == "Explore" {
                ForEach(cities) { city in
                    Annotation(city.name, coordinate: city.coordinate) {
                        Image(systemName: store.isExploreCitySaved(city) ? "bookmark.fill" : "building.2.crop.circle").font(.system(size: 19, weight: .medium)).foregroundStyle(Color.bronze).padding(10).background(.regularMaterial, in: .circle).overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                    }.tag("city:" + city.id)
                }
                ForEach(places) { place in Marker(place.record.name, systemImage: place.record.category.symbol, coordinate: .init(latitude: place.record.latitude!, longitude: place.record.longitude!)).tint(Color.bronze).tag("place:" + place.id) }
            }
            if mode == "Trips" {
                ForEach(tripPlaces) { place in Marker(place.name, systemImage: place.category.symbol, coordinate: .init(latitude: place.latitude!, longitude: place.longitude!)).tint(Color.bronze).tag("tripplace:" + place.id) }
            }
            if mode != "Explore" {
                ForEach(routes) { value in
                    if let route = value.route {
                        MapPolyline(route).stroke(Color.bronze.opacity(selectedFlightID == nil ? 0.7 : 1), style: StrokeStyle(lineWidth: selectedFlightID == nil ? 2 : 3, lineCap: .round, dash: [8, 5]))
                    }
                    if let departure = value.departure { Marker(value.flight.departureAirport, systemImage: "airplane.departure", coordinate: departure).tint(Color.bronze).tag("flight:" + value.id) }
                    if let arrival = value.arrival { Marker(value.flight.arrivalAirport, systemImage: "airplane.arrival", coordinate: arrival).tint(Color.bronze).tag("flight:" + value.id) }
                }
            }
            if mode == "Flights", selectedFlight != nil, let position = tracker.position, position.valid {
                Annotation("Reported aircraft position", coordinate: position.coordinate) { Image(systemName: "location.north.fill").rotationEffect(.degrees(position.heading ?? 0)).font(.title2).foregroundStyle(.white).padding(12).background(Color.bronze, in: .circle) }
            }
        }.mapStyle(satellite ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll) : .standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .safeAreaPadding(.bottom, panelVisible && mode != "Explore" ? mapHeight * 0.59 : 0)
            .onMapCameraChange(frequency: .onEnd) { center = $0.region.center }
            .accessibilityIdentifier("world-map")
    }
    private var topControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) { Image(systemName: "globe.europe.africa"); Text("Your world").font(.system(.headline, design: .serif)) }.padding(.horizontal, 17).padding(.vertical, 13).glassEffect(.regular, in: .capsule)
            Spacer()
            Button { panelVisible = false; showSaved = true } label: { Image(systemName: "bookmark").frame(width: 44, height: 44) }.buttonStyle(.glass).accessibilityLabel("Saved places and collections").accessibilityIdentifier("map-saved")
            Menu {
                Button(satellite ? "Standard map" : "Satellite globe", systemImage: "map") { satellite.toggle() }
                Button("Show the globe", systemImage: "globe") { globe() }
                Button("Flight information", systemImage: "info.circle") { flightInfo = true }
            } label: { Image(systemName: "square.3.layers.3d").frame(width: 44, height: 44) }.buttonStyle(.glass).accessibilityLabel("Map display options")
        }
    }
    private var panelHeader: some View {
        HStack(spacing: 8) {
            if selectedFlight != nil {
                Button { selectedFlightID = nil; tracker = FlightTracker() } label: { Label("All flights", systemImage: "chevron.left") }.font(.subheadline.weight(.medium))
                Spacer()
            } else {
                HStack(spacing: 2) {
                    ForEach(["Explore", "Trips", "Flights"], id: \.self) { section in
                        Button {
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { mode = section }
                        } label: {
                            Text(section).font(.subheadline.weight(mode == section ? .semibold : .medium))
                                .foregroundStyle(mode == section ? Color.primary : Color.secondary)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background { if mode == section { Capsule().fill(Color.primary.opacity(0.07)).matchedGeometryEffect(id: "map-section", in: sectionSelection) } }
                        }.buttonStyle(.plain).accessibilityIdentifier("map-section-" + section)
                            .accessibilityAddTraits(mode == section ? .isSelected : [])
                    }
                }
                Spacer(minLength: 0)
            }
            Button { resizePanel(detent == .large ? .height(260) : .large) } label: {
                Image(systemName: detent == .large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").font(.caption.weight(.medium)).frame(width: 32, height: 44)
            }.accessibilityLabel(detent == .large ? "Collapse map panel" : "Expand map panel").accessibilityIdentifier("map-panel-expand")
            Menu {
                Button("Flight information", systemImage: "info.circle") { flightInfo = true }
                Button("Close map panel", systemImage: "xmark") { panelVisible = false }.accessibilityIdentifier("map-panel-close")
                Button("Show the globe", systemImage: "globe") { globe() }
            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 44) }.accessibilityLabel("Panel options").accessibilityIdentifier("map-panel-options")
        }.padding(.horizontal, 16).padding(.bottom, 12)
    }
    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let selectedFlight { FlightDetailPanel(flight: selectedFlight, tracker: tracker, edit: { editingFlight = true }, track: { position in move(.camera(MapCamera(centerCoordinate: position.coordinate, distance: 500_000))); resizePanel(.medium) }).id(selectedFlight.id) }
            else if mode == "Explore" { explorePanel }
            else if mode == "Trips" { tripsPanel }
            else { flightsPanel }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 24)
            .transition(.opacity).id(selectedFlightID ?? mode)
    }

    private var explorePanel: some View {
        VStack(alignment: .leading, spacing: 17) {
            LocationAutocompleteField("Search any city", text: $cityQuery, kind: .city, identifier: "world-city-search", onEdit: { if detent != .large { resizePanel(.large) } }, onSelect: { result in
                guard let city = ExploreCity(result) else { return }; selectedCity = city; store.rememberExploreCity(city); move(.region(city.region)); resizePanel(.medium); Task { await browse(city) }
            }).padding(15).background(Color.cardSurface, in: .rect(cornerRadius: 19))
            HStack {
                Menu {
                    ForEach([ExploreInterest.attractions, .restaurants, .museums, .parks, .cafes, .hotels]) { value in
                        Button(value.title, systemImage: value.symbol) { interest = value; if let searchArea { Task { await browse(searchArea) } } }
                    }
                } label: { Label(interest.title, systemImage: interest.symbol).font(.subheadline.weight(.medium)); Image(systemName: "chevron.down").font(.caption2) }
                Spacer()
                Button { let city = ExploreCity(name: selectedCity?.name ?? "Map area", country: selectedCity?.country ?? "", latitude: center.latitude, longitude: center.longitude); Task { await browse(city) }; resizePanel(.medium) } label: { Label("Search area", systemImage: "scope").font(.subheadline) }.accessibilityIdentifier("map-search-area")
            }.padding(.vertical, 4)
            if let selectedCity { NavigationLink { CityGuideView(city: selectedCity).toolbar(.visible, for: .navigationBar) } label: { HStack { VStack(alignment: .leading, spacing: 5) { Text(selectedCity.name).font(.system(.title2, design: .serif)); Text("City guide").font(.caption) }; Spacer(); Image(systemName: "arrow.up.right") }.padding(17).background(Color.cardSurface, in: .rect(cornerRadius: 21)) }.accessibilityIdentifier("map-city-guide") }
            if let selected = selectedPlace { ExplorePlaceRow(place: selected, add: { adding = selected }) }
            if search.loading { ProgressView("Finding places…") }
            if let error = search.sections.first(where: { $0.error != nil })?.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if searchArea != nil && !search.loading && search.places.isEmpty { Text("No places found. Try another area.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(search.places) { place in ExplorePlaceRow(place: place, add: { adding = place }) }
            if searchArea == nil { NavigationLink { CityExplorerView().toolbar(.visible, for: .navigationBar) } label: { HStack { Label("City guides", systemImage: "globe.europe.africa"); Spacer(); Image(systemName: "chevron.right").font(.caption) }.font(.subheadline).padding(.vertical, 8) } }
        }
    }
    private var selectedPlace: ExplorePlace? { guard let selection, selection.hasPrefix("place:") else { return nil }; return places.first { "place:" + $0.id == selection } }
    private var tripsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let trip {
                HStack { Text(trip.title).font(.system(.title2, design: .serif)); Spacer(); Button("All trips") { tripID = nil; globe() } }
                Text("\(trip.planCount) plans · \(trip.places.count) journal places · \(trip.flights.count) flights").font(.caption).foregroundStyle(.secondary)
                NavigationLink { JourneyDetailView(id: trip.id).toolbar(.visible, for: .navigationBar) } label: { Label("Open trip", systemImage: "suitcase.rolling") }.buttonStyle(.glass)
                if let selection, let place = tripPlaces.first(where: { "tripplace:" + $0.id == selection }) { Text(place.name).font(.headline); Text(place.address).font(.caption).foregroundStyle(.secondary) }
                ForEach(flights.filter { $0.tripID == trip.id }) { flight in flightRow(flight) }
            } else {
                ForEach(library.documents) { document in Button { tripID = document.id; focus(document); resizePanel(.medium) } label: { HStack { Image(systemName: "suitcase.rolling").font(.title2); VStack(alignment: .leading, spacing: 6) { Text(document.title).font(.system(.headline, design: .serif)); Text(document.routeLabel).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right") }.padding(17).background(Color.cardSurface, in: .rect(cornerRadius: 22)) }.buttonStyle(.plain).accessibilityIdentifier("map-trip-" + document.id.uuidString) }
                if library.documents.isEmpty { HStack { Label("No trips yet", systemImage: "suitcase.rolling").foregroundStyle(.secondary); Spacer(); Button { newTrip = true } label: { Label("Create trip", systemImage: "plus") }.buttonStyle(.glassProminent) }.font(.subheadline).padding(.vertical, 8) }
            }
        }
    }
    private var flightsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label(flights.isEmpty ? "No flights yet" : "\(flights.count) \(flights.count == 1 ? "flight" : "flights")", systemImage: "airplane").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button { addingFlight = true } label: { Label("Add flight", systemImage: "plus").font(.subheadline) }.buttonStyle(.glassProminent).accessibilityLabel("Add flight").accessibilityIdentifier("map-add-flight")
            }
            if let error = api.savedFlightsError { Text(error).font(.caption).foregroundStyle(.secondary); Button("Try again") { Task { await api.loadSavedFlights() } } }
            ForEach(flights) { flight in flightRow(flight) }
        }
    }
    private func flightRow(_ value: MapFlight) -> some View {
        Button { openFlight(value) } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack { Label(value.title, systemImage: "airplane").font(.headline); Spacer(); Text(TravelDay.label(value.flight.departureDay)).font(.caption) }
                HStack { Text(value.flight.departureAirport).lineLimit(2); Image(systemName: "arrow.right").foregroundStyle(Color.bronze); Text(value.flight.arrivalAirport).lineLimit(2) }.font(.system(.title3, design: .rounded, weight: .medium))
                HStack { Text(value.tripTitle).lineLimit(1); Spacer(); Text(value.route == nil ? "Locations needed" : "View flight") }.font(.caption).foregroundStyle(.secondary)
            }.padding(18).background(Color.cardSurface, in: .rect(cornerRadius: 23))
        }.buttonStyle(PressStyle()).accessibilityIdentifier("map-flight-" + value.id)
    }
    private func selected(_ value: String?) {
        guard let value else { return }
        if let city = cities.first(where: { value == "city:" + $0.id }) { selectedCity = city; cityQuery = city.name; resizePanel(.medium); move(.region(city.region)) }
        if value.hasPrefix("place:") { resizePanel(.medium) }
        if let flight = flights.first(where: { value == "flight:" + $0.id }) { openFlight(flight) }
        if value.hasPrefix("tripplace:") { resizePanel(.medium) }
    }
    private func browse(_ city: ExploreCity) async { searchArea = city; await search.load(city: city, interest: interest, term: "", wider: false) }
    private func openFlight(_ value: MapFlight) {
        mode = "Flights"; selectFlight(value)
    }

    private func selectFlight(_ value: MapFlight) {
        selectedFlightID = value.id; tracker = FlightTracker(); resizePanel(.medium)
        if let a = value.departure, let b = value.arrival {
            if abs(a.longitude - b.longitude) > 180 {
                let longitude = (a.longitude + b.longitude) / 2 + (a.longitude + b.longitude > 0 ? -180 : 180)
                move(.camera(MapCamera(centerCoordinate: .init(latitude: (a.latitude + b.latitude) / 2, longitude: longitude), distance: 32_000_000)))
            }
            else if let route = value.route {
                let rect = route.boundingMapRect
                move(.rect(rect.insetBy(dx: -max(rect.width * 0.25, 50_000), dy: -max(rect.height * 0.6, rect.width * 0.15))))
            }
        }
    }
    private func focus(_ trip: JourneyDocument) {
        let mapped = trip.mapPlaces.filter(\.hasCoordinate)
        guard !mapped.isEmpty else { globe(); return }
        let rect = mapped.reduce(MKMapRect.null) { partial, place in let p = MKMapPoint(CLLocationCoordinate2D(latitude: place.latitude!, longitude: place.longitude!)); return partial.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1)) }
        if rect.size.width > MKMapRect.world.size.width / 2 { globe() }
        else if mapped.count == 1 { move(.camera(MapCamera(centerCoordinate: .init(latitude: mapped[0].latitude!, longitude: mapped[0].longitude!), distance: 50_000))) }
        else { move(.rect(rect.insetBy(dx: -rect.size.width * 0.4, dy: -rect.size.height * 0.4))) }
    }
    private func resizePanel(_ value: PresentationDetent) { withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86)) { detent = value } }
    private func globe() { move(.camera(MapCamera(centerCoordinate: .init(latitude: 22, longitude: 5), distance: 32_000_000))) }
    private func move(_ position: MapCameraPosition) { withAnimation(reduceMotion ? nil : .smooth(duration: 0.8)) { camera = position } }

}

/// This panel belongs to the map, so the original system tab bar never moves or changes owners.
/// Drag state stays here, keeping continuous gesture updates out of the map renderer.
// Content stops at the tab-bar safe area, while the same sheet material continues
// behind the root's native tab bar to the physical bottom edge of the screen.
private struct PersistentMapPanel<Header: View, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var detent: PresentationDetent
    var contentID: String
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @State private var translation: CGFloat = 0
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88) }
    var body: some View {
        GeometryReader { geo in
            let maximum = max(300, geo.size.height - 8)
            let compact = min(260.0, maximum * 0.48)
            let medium = max(compact, maximum * 0.60)
            let resting = detent == .large ? maximum : detent == .medium ? medium : compact
            let height = min(maximum, max(compact, resting - translation))
            let progress = min(1, max(0, (height - compact) / max(1, maximum - compact)))
            let shape = UnevenRoundedRectangle(topLeadingRadius: 30 - progress * 6, bottomLeadingRadius: 30 * (1 - progress), bottomTrailingRadius: 30 * (1 - progress), topTrailingRadius: 30 - progress * 6)
            let change: (CGFloat) -> Void = { translation = $0 }
            let end: (CGFloat, CGFloat) -> Void = { distance, velocity in
                let projected = resting - distance - velocity * 0.18
                let target = [compact, medium, maximum].min(by: { abs($0 - projected) < abs($1 - projected) }) ?? compact
                withAnimation(spring) { translation = 0; detent = target == maximum ? .large : target == medium ? .medium : .height(260) }
            }
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Capsule().fill(.secondary.opacity(0.25)).frame(width: 32, height: 4).padding(.top, 10).padding(.bottom, 7)
                        .accessibilityLabel("Map panel height").accessibilityAdjustableAction { direction in withAnimation(spring) { detent = direction == .increment ? .large : .height(260) } }
                    header()
                }.contentShape(Rectangle()).simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in if abs(value.translation.height) > abs(value.translation.width) { change(value.translation.height) } }
                    .onEnded { value in end(value.translation.height, value.velocity.height) })
                ScrollView {
                    content().background(MapScrollBridge(expanded: detent == .large, onDrag: change, onEnd: end).frame(width: 0, height: 0))
                }.id(contentID).scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.always)
                    .accessibilityIdentifier("map-panel-scroll")
            }
            .frame(height: height, alignment: .top)
            .clipShape(.rect(topLeadingRadius: 30 - progress * 6, topTrailingRadius: 30 - progress * 6))
            .background(alignment: .top) {
                shape.fill(Color.canvas.opacity(0.3 + progress * 0.7))
                    .frame(height: height + geo.safeAreaInsets.bottom)
                    .glassEffect(.regular, in: shape)
                    .shadow(color: .black.opacity(0.12), radius: 16, y: -2)
                    .accessibilityIdentifier("map-panel-surface")
            }
            .padding(.horizontal, 12 * (1 - progress))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(spring, value: detent)
        }
    }
}

// Observe the native scroll pan instead of adding a competing full-surface gesture.
// A collapsed sheet consumes vertical movement; an expanded sheet scrolls normally
// until a downward pull reaches the top. Buttons retain native cancellation behavior.
private struct MapScrollBridge: UIViewRepresentable {
    var expanded: Bool
    var onDrag: (CGFloat) -> Void
    var onEnd: (CGFloat, CGFloat) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> Probe {
        let probe = Probe(); probe.attach = { [weak coordinator = context.coordinator] view in coordinator?.attach(from: view) }; return probe
    }
    func updateUIView(_ view: Probe, context: Context) { context.coordinator.parent = self }
    static func dismantleUIView(_ view: Probe, coordinator: Coordinator) { coordinator.detach() }
    final class Probe: UIView {
        var attach: ((UIView) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { attach?(self) } }
    }
    final class Coordinator: NSObject {
        var parent: MapScrollBridge
        weak var scroll: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var movingSheet = false
        private var finishedSheetPan = false
        private var origin: CGFloat = 0
        init(parent: MapScrollBridge) { self.parent = parent }
        func attach(from view: UIView) {
            var ancestor = view.superview
            while let current = ancestor {
                if let candidate = current as? UIScrollView {
                    guard scroll !== candidate else { return }; detach(); scroll = candidate
                    candidate.alwaysBounceVertical = true
                    candidate.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
                    observation = candidate.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                        guard let self, scroll.isDragging || scroll.isDecelerating else { return }
                        if self.movingSheet || self.finishedSheetPan || !self.parent.expanded {
                            let top = -scroll.adjustedContentInset.top
                            if abs(scroll.contentOffset.y - top) > 0.1 { scroll.contentOffset.y = top }
                        }
                    }
                    return
                }
                ancestor = current.superview
            }
        }
        func detach() { observation = nil; scroll?.panGestureRecognizer.removeTarget(self, action: #selector(pan(_:))); scroll = nil }
        @objc private func pan(_ gesture: UIPanGestureRecognizer) {
            guard let scroll else { return }
            let dy = gesture.translation(in: scroll.window).y
            let velocity = gesture.velocity(in: scroll.window)
            let top = -scroll.adjustedContentInset.top
            switch gesture.state {
            case .began:
                finishedSheetPan = false; origin = 0; movingSheet = !parent.expanded || (scroll.contentOffset.y <= top + 1 && velocity.y > 0)
            case .changed:
                if !movingSheet && scroll.contentOffset.y <= top + 1 && velocity.y > 0 { movingSheet = true; origin = dy }
                if movingSheet { scroll.contentOffset.y = top; parent.onDrag(dy - origin) }
            case .ended, .cancelled:
                if movingSheet { finishedSheetPan = true; scroll.setContentOffset(CGPoint(x: 0, y: top), animated: false); parent.onEnd(dy - origin, gesture.state == .cancelled ? 0 : velocity.y) }
                movingSheet = false
            default: break
            }
        }
    }
}
