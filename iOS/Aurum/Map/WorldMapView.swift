import SwiftUI
import MapKit

struct WorldMapView: View {
    @Environment(TravelStore.self) private var store
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Namespace private var sectionSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .camera(MapCamera(centerCoordinate: .init(latitude: 22, longitude: 5), distance: 32_000_000))
    #if DEBUG
    @State private var cameraProbe = ""
    #endif
    @State private var mapHeight: CGFloat = 800
    @State private var mapBottomInset: CGFloat = 0
    @State private var center = CLLocationCoordinate2D(latitude: 22, longitude: 5)
    @State private var mode = "Explore"
    @State private var detent: PresentationDetent = .height(260)
    @State private var showSaved = false
    @State private var satellite = true
    @State private var selection: String?
    @State private var cityQuery = ""
    @State private var placeQuery = ""
    @State private var widerSearch = false
    @State private var selectedCity: ExploreCity?
    @State private var interest: ExploreInterest = .attractions
    @State private var diningFilters = DiningSearchPreferences()
    @State private var showExploreFilters = false
    @State private var exploreSort: ExploreSort = .suggested
    @State private var websiteOnly = false
    @State private var savedOnly = false
    private var visiblePlaces: [ExplorePlace] {
        search.visible(sort: exploreSort, savedOnly: savedOnly, websiteOnly: websiteOnly, savedIDs: Set(store.savedDiscoveries.map(\.id)))
    }
    private var exploreFiltersActive: Bool { (interest == .restaurants && diningFilters.active) || websiteOnly || savedOnly || exploreSort != .suggested }
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
    @State private var addedFlightNumber: String?
    init(request: CityMapRequest? = nil) {
        guard let request else { return }
        _camera = State(initialValue: .region(request.city.region))
        _center = State(initialValue: request.city.coordinate)
        _selectedCity = State(initialValue: request.city)
        _cityQuery = State(initialValue: request.city.name)
        _placeQuery = State(initialValue: request.term)
        _searchArea = State(initialValue: request.city)
        _interest = State(initialValue: request.interest)
        _diningFilters = State(initialValue: request.dining)
        _exploreSort = State(initialValue: request.sort)
        _websiteOnly = State(initialValue: request.websiteOnly)
        _savedOnly = State(initialValue: request.savedOnly)
        _widerSearch = State(initialValue: request.wider)
        _detent = State(initialValue: .medium)
        let results = CityExploreModel()
        results.present(request.places, interest: request.interest)
        _search = State(initialValue: results)
    }
    private var flights: [MapFlight] {
        var values = api.savedFlights.map { MapFlight(tripID: nil, tripTitle: "My flights", flight: $0) }
        for trip in library.trips { for flight in trip.flights { values.append(MapFlight(tripID: trip.id, tripTitle: trip.title, flight: flight)) } }
        return values.sorted { a, b in
            if a.flight.departureDay == b.flight.departureDay { return a.flight.departureTime < b.flight.departureTime }
            return a.flight.departureDay > b.flight.departureDay
        }
    }

    private var selectedFlight: MapFlight? { flights.first { $0.id == selectedFlightID } }
    private var trip: JourneyDocument? { library.trips.first { $0.id == tripID } }
    private var cities: [ExploreCity] { var seen = Set<String>(); return (store.savedExploreCities + store.recentExploreCities + ExploreCity.collection).filter { seen.insert($0.id).inserted } }
    private var places: [ExplorePlace] {
        var seen = Set<String>()
        return (searchArea == nil ? store.savedDiscoveries : visiblePlaces).filter { $0.record.hasCoordinate && seen.insert($0.id).inserted }
    }
    private var tripPlaces: [PlaceRecord] { var seen = Set<String>(); return (trip.map { [$0] } ?? library.trips).flatMap(\.mapPlaces).filter { $0.hasCoordinate && seen.insert($0.id).inserted } }
    private var routes: [MapFlight] { if let selectedFlight { return [selectedFlight] }; if mode == "Trips", let tripID { return flights.filter { $0.tripID == tripID } }; return flights }
    private var mapBottomPadding: CGFloat {
        // Sheet movement must never change MapKit's viewport: changing its safe
        // area makes it refit the camera during the panel's spring animation.
        // Reserve only the compact panel, regardless of section or detail state.
        let layout = MapPanelLayout(availableHeight: mapHeight, flightDetail: false)
        return layout.compact + mapBottomInset + 8
    }
    var body: some View {
        ZStack(alignment: .top) {
            map.ignoresSafeArea()
            topControls.padding(.horizontal, 18).padding(.top, 8)
            #if DEBUG
            if FlightMapFixtures.enabled {
                Text(cameraProbe).font(.system(size: 1)).foregroundStyle(.clear).frame(width: 1, height: 1)
                    .accessibilityIdentifier("map-camera-probe").accessibilityLabel(cameraProbe).allowsHitTesting(false)
            }
            #endif
            PersistentMapPanel(detent: $detent, contentID: selectedFlightID ?? (mode + (addedFlightNumber ?? "")), flightDetail: selectedFlightID != nil, header: { panelHeader }, content: { panelContent })
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mapHeight = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { mapBottomInset = $0 }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: store.selectedTab) { _, _ in
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { detent = .height(260) }
        }
        .onChange(of: selection) { _, value in selected(value) }
        .onChange(of: tracker.position?.timestamp) { old, _ in
            if old == nil, store.selectedTab == 1, mode == "Flights", let position = tracker.position, position.valid {
                move(.camera(MapCamera(centerCoordinate: position.coordinate, distance: 800_000)))
            }
        }
        .onChange(of: FlightNotifications.shared.openFlights, initial: true) {
            if FlightNotifications.shared.openFlights { mode = "Flights"; detent = .medium; FlightNotifications.shared.openFlights = false }
        }
        .onChange(of: mode) { selection = nil; if mode != "Flights" { selectedFlightID = nil; tracker = FlightTracker() } }
        .task(id: api.account?.id) { await api.loadSavedFlights() }
        .navigationDestination(isPresented: $showSaved) { SavedView().toolbar(.visible, for: .navigationBar) }
        .sheet(item: $adding) { ExploreAddToTripView(place: $0) }
        .sheet(isPresented: $editingFlight) { if let selectedFlight { FlightReservationEditor(documentID: selectedFlight.tripID, reservation: selectedFlight.flight) } }
        .sheet(isPresented: $newTrip) { TripCreationView() }
        .sheet(isPresented: $showExploreFilters) {
            NavigationStack {
                Form {
                    if interest == .restaurants { DiningFilterFields(preferences: $diningFilters) }
                    Section("Results") {
                        Picker("Sort places", selection: $exploreSort) { ForEach(ExploreSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        Toggle("With a website", isOn: $websiteOnly)
                        Toggle("Only saved places", isOn: $savedOnly)
                    }
                    Section { Button("Reset filters", action: resetExploreFilters) }
                }.navigationTitle(interest == .restaurants ? "Restaurant filters" : "Explore filters")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showExploreFilters = false } } }
            }.presentationDetents([.large])
        }
        .onChange(of: diningFilters) { if let searchArea, interest == .restaurants { Task { await browse(searchArea) } } }
        .sheet(isPresented: $flightInfo) { FlightDataInfoView() }
        .sheet(isPresented: $addingFlight) { FlightAddView { flight in
            mode = "Flights"; selectedFlightID = nil; tracker = FlightTracker()
            addedFlightNumber = flight.flightNumber.uppercased()
            focusRoute(MapFlight(tripID: nil, tripTitle: "My flights", flight: flight)); resizePanel(.medium)
        } }
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
                Annotation("Reported aircraft position", coordinate: position.coordinate) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Image(systemName: "airplane").rotationEffect(.degrees((position.heading ?? 0) - 90)).font(.title2.weight(.semibold)).foregroundStyle(.white).padding(12)
                            .background(position.isRecent(at: context.date) ? FlightDisplay.teal : Color.gray, in: .circle)
                            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
                            .accessibilityLabel(position.isRecent(at: context.date) ? "Reported aircraft position" : "Last known aircraft position")
                    }
                }
            }
        }.mapStyle(satellite ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll) : .standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .safeAreaPadding(.bottom, mapBottomPadding)
            .onMapCameraChange(frequency: .onEnd) { context in
                center = context.region.center
                #if DEBUG
                if FlightMapFixtures.enabled {
                    cameraProbe = [context.camera.centerCoordinate.latitude, context.camera.centerCoordinate.longitude, context.camera.distance, context.camera.heading, context.camera.pitch].map { String($0) }.joined(separator: ",")
                }
                #endif
            }
            .accessibilityIdentifier("world-map")
    }
    private var topControls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) { Image(systemName: "globe.europe.africa"); Text("Your world").font(.system(.headline, design: .serif)) }.padding(.horizontal, 17).padding(.vertical, 13).glassEffect(.regular, in: .capsule)
            Spacer()
            Button { store.searchPresented = true } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }.buttonStyle(.glass).accessibilityLabel("Search").accessibilityIdentifier("global-search")
            Button { showSaved = true } label: { Image(systemName: "bookmark").frame(width: 44, height: 44) }.buttonStyle(.glass).accessibilityLabel("Saved places and collections").accessibilityIdentifier("map-saved")
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
                Button { closeFlight() } label: { Label("All flights", systemImage: "chevron.left") }.font(.subheadline.weight(.medium))
                Spacer()
            } else {
                HStack(spacing: 2) {
                    ForEach(["Explore", "Trips", "Flights"], id: \.self) { section in
                        Button {
                            guard mode != section else { return }
                            mode = section
                        } label: {
                            Text(section).font(.subheadline.weight(mode == section ? .semibold : .medium))
                                .foregroundStyle(mode == section ? Color.primary : Color.secondary)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background { if mode == section { Capsule().fill(Color.primary.opacity(0.07)).matchedGeometryEffect(id: "map-section", in: sectionSelection) } }
                        }.buttonStyle(.plain).accessibilityIdentifier("map-section-" + section)
                            .accessibilityAddTraits(mode == section ? .isSelected : [])
                    }
                }.animation(reduceMotion ? nil : .smooth(duration: 0.22), value: mode)
                Spacer(minLength: 0)
            }
        }.lineLimit(1).dynamicTypeSize(...DynamicTypeSize.xxxLarge).padding(.horizontal, 16).padding(.bottom, 12)
    }
    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let selectedFlight { FlightDetailPanel(flight: selectedFlight, tracker: tracker, edit: { editingFlight = true }, track: { position in move(.camera(MapCamera(centerCoordinate: position.coordinate, distance: 500_000))); resizePanel(.medium) }).id(selectedFlight.id) }
            else if mode == "Explore" { explorePanel }
            else if mode == "Trips" { tripsPanel }
            else { flightsPanel }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, selectedFlight == nil ? 20 : 12).padding(.bottom, 24)
            .id(selectedFlightID ?? "flight-list")
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
    }

    private var explorePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                LocationAutocompleteField("Search any city", text: $cityQuery, kind: .city, identifier: "world-city-search", onEdit: { if detent != .large { resizePanel(.large) } }, onSelect: { result in
                    guard let city = ExploreCity(result) else { return }; selectedCity = city; store.rememberExploreCity(city); move(.region(city.region)); resizePanel(.medium); Task { await browse(city) }
                }).padding(15).cardSurface(cornerRadius: 19)
                HStack(spacing: 14) {
                    Menu {
                        ForEach(ExploreInterest.allCases) { value in
                            Button(value.title, systemImage: value.symbol) { interest = value; if let searchArea { Task { await browse(searchArea) } } }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: interest.symbol).foregroundStyle(Color.bronze)
                            Text(interest.title).foregroundStyle(.primary).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.accessibilityIdentifier("map-explore-category")
                    Divider().frame(height: 20)
                    Button { showExploreFilters = true } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "slider.horizontal.3").foregroundStyle(Color.bronze)
                            Text("Filters").foregroundStyle(.primary)
                            if exploreFiltersActive || !placeQuery.isEmpty || widerSearch { Circle().fill(Color.bronze).frame(width: 5, height: 5) }
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("map-explore-filters")
                }.font(.subheadline.weight(.medium))
                if !exploreSearchSummary.isEmpty {
                    HStack(alignment: .top) {
                        Text(exploreSearchSummary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Reset", action: resetExploreFilters).font(.caption)
                    }
                }
            }
            if let selectedCity {
                NavigationLink { CityGuideView(city: selectedCity).toolbar(.visible, for: .navigationBar) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "globe.europe.africa").foregroundStyle(Color.bronze)
                        Text("Explore " + selectedCity.name).foregroundStyle(.primary)
                        Spacer()
                        Text("City guide").foregroundStyle(.secondary)
                    }.font(.subheadline).padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("map-city-guide")
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Text(searchArea == nil ? "On the map" : "Places nearby").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        let city = ExploreCity(name: selectedCity?.name ?? "Map area", country: selectedCity?.country ?? "", latitude: center.latitude, longitude: center.longitude)
                        Task { await browse(city) }; resizePanel(.medium)
                    } label: { Label("Search this area", systemImage: "scope").font(.caption.weight(.semibold)).padding(.vertical, 8) }
                        .accessibilityIdentifier("map-search-area")
                }
                if search.loading { ProgressView("Finding places…").font(.subheadline) }
                else if let error = search.sections.first(where: { $0.error != nil })?.error { Text(error).font(.subheadline).foregroundStyle(.secondary) }
                else if searchArea == nil { Text("Choose a city or search the area shown on your map.").font(.caption).foregroundStyle(.secondary) }
                else if visiblePlaces.isEmpty { Text(exploreFiltersActive ? "No places match. Try changing your filters or searching another area." : "No places found. Try another area.").font(.subheadline).foregroundStyle(.secondary) }
                if let selected = selectedPlace { exploreResultRow(selected) }
                ForEach(visiblePlaces.filter { $0.id != selectedPlace?.id }) { place in exploreResultRow(place) }
            }
            if selectedCity == nil {
                NavigationLink { CityExplorerView().toolbar(.visible, for: .navigationBar) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "globe.europe.africa").foregroundStyle(Color.bronze)
                        Text("Browse city guides").foregroundStyle(.primary)
                        Spacer()
                    }.font(.subheadline).padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
    private var exploreSearchSummary: String {
        [interest == .restaurants && diningFilters.active ? diningFilters.summary : nil,
         websiteOnly ? "Has website" : nil, savedOnly ? "Saved places" : nil,
         exploreSort == .suggested ? nil : exploreSort.rawValue,
         placeQuery.isEmpty ? nil : "Search: " + placeQuery,
         widerSearch ? "Wider city" : nil].compactMap { $0 }.joined(separator: " · ")
    }
    private func resetExploreFilters() {
        let reloadSearch = !placeQuery.isEmpty || widerSearch
        let diningWillReload = interest == .restaurants && diningFilters.active
        diningFilters = DiningSearchPreferences(); exploreSort = .suggested; websiteOnly = false; savedOnly = false
        placeQuery = ""; widerSearch = false
        if reloadSearch && !diningWillReload, let searchArea { Task { await browse(searchArea) } }
    }
    private func exploreResultRow(_ place: ExplorePlace) -> some View {
        VStack(spacing: 0) {
            ExplorePlaceRow(place: place, add: { adding = place }, inset: false)
            Divider()
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
                ForEach(library.trips) { document in Button { tripID = document.id; focus(document); resizePanel(.medium) } label: { HStack { Image(systemName: "suitcase.rolling").font(.title2); VStack(alignment: .leading, spacing: 6) { Text(document.title).font(.system(.headline, design: .serif)); Text(document.routeLabel).font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(17).cardSurface(cornerRadius: 22) }.buttonStyle(.plain).accessibilityIdentifier("map-trip-" + document.id.uuidString) }
                if library.trips.isEmpty { HStack { Label("No trips yet", systemImage: "suitcase.rolling").foregroundStyle(.secondary); Spacer(); Button { newTrip = true } label: { Label("Create trip", systemImage: "plus") }.buttonStyle(.glassProminent) }.font(.subheadline).padding(.vertical, 8) }
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
            .lineLimit(1).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            if let addedFlightNumber { Label(addedFlightNumber + " added to your map", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Color.bronze).accessibilityIdentifier("flight-added-confirmation") }
            if let error = api.savedFlightsError { Text(error).font(.caption).foregroundStyle(.secondary); Button("Try again") { Task { await api.loadSavedFlights() } } }
            ForEach(flights) { flight in flightRow(flight) }
        }
    }
    private func flightRow(_ value: MapFlight) -> some View {
        Button { openFlight(value) } label: {
            FlightCard(flight: value.flight, subtitle: value.tripTitle)
        }.buttonStyle(PressStyle()).accessibilityIdentifier("map-flight-" + value.id)
    }
    private func selected(_ value: String?) {
        guard let value else { return }
        if let city = cities.first(where: { value == "city:" + $0.id }) { selectedCity = city; cityQuery = city.name; resizePanel(.medium); move(.region(city.region)) }
        if value.hasPrefix("place:") { resizePanel(.medium) }
        if let flight = flights.first(where: { value == "flight:" + $0.id }) { openFlight(flight) }
        if value.hasPrefix("tripplace:") { resizePanel(.medium) }
    }
    private func browse(_ city: ExploreCity) async { searchArea = city; await search.load(city: city, interest: interest, term: diningFilters.searchTerm(placeQuery, interest: interest), wider: widerSearch) }
    private func openFlight(_ value: MapFlight) {
        mode = "Flights"; selectFlight(value)
    }

    private func selectFlight(_ value: MapFlight) {
        animateFlightContent { selectedFlightID = value.id; tracker = FlightTracker(); addedFlightNumber = nil }
        resizePanel(.medium); focusRoute(value)
    }
    private func closeFlight() {
        animateFlightContent { selectedFlightID = nil; tracker = FlightTracker(); selection = nil }
    }
    private func animateFlightContent(_ change: () -> Void) {
        // Keep the same scroll surface and material; animate only the new content.
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { change() }
    }
    private func focusRoute(_ value: MapFlight) {
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
    private func move(_ position: MapCameraPosition) { withAnimation(reduceMotion ? nil : .smooth(duration: 0.42)) { camera = position } }

}

struct MapPanelLayout {
    let availableHeight: CGFloat
    let flightDetail: Bool
    var maximum: CGFloat { max(300, availableHeight - 8) }
    var compact: CGFloat { min(260, maximum * 0.48) }
    var medium: CGFloat { max(compact, maximum * (flightDetail ? 0.80 : 0.60)) }
    func expansion(for height: CGFloat) -> CGFloat {
        min(1, max(0, (height - compact) / max(1, maximum - compact)))
    }
    func surfaceInset(for height: CGFloat) -> CGFloat { 12 * (1 - expansion(for: height)) }
    func height(for detent: PresentationDetent) -> CGFloat {
        detent == .large ? maximum : detent == .medium ? medium : compact
    }
}

/// Keeps a drag anchored to the visible sheet, including an interrupted spring.
struct MapPanelDrag {
    private(set) var origin: CGFloat?
    private(set) var height: CGFloat?
    mutating func update(distance: CGFloat, presentedHeight: CGFloat, bounds: ClosedRange<CGFloat>) {
        let start = origin ?? presentedHeight
        let next = min(bounds.upperBound, max(bounds.lowerBound, start - distance))
        // Rebase at the limits so reversing an overshoot responds immediately.
        origin = next + distance
        height = next
    }
    mutating func finish() { origin = nil; height = nil }
}

private final class MapPanelPresentation {
    var height: CGFloat?
}

/// This panel belongs to the map, so the original system tab bar never moves or changes owners.
/// Drag state stays here, keeping continuous gesture updates out of the map renderer.
// Content stops at the tab-bar safe area, while the same sheet material continues
// behind the root's native tab bar to the physical bottom edge of the screen.
private struct PersistentMapPanel<Header: View, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var detent: PresentationDetent
    var contentID: String
    var flightDetail: Bool
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @State private var drag = MapPanelDrag()
    @State private var presentation = MapPanelPresentation()
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88) }
    var body: some View {
        GeometryReader { geo in
            let layout = MapPanelLayout(availableHeight: geo.size.height, flightDetail: flightDetail)
            let maximum = layout.maximum
            let compact = layout.compact
            let medium = layout.medium
            let resting = layout.height(for: detent)
            let height = drag.height ?? resting
            let progress = layout.expansion(for: height)
            let shape = UnevenRoundedRectangle(topLeadingRadius: 30 - progress * 6, bottomLeadingRadius: 30 * (1 - progress), bottomTrailingRadius: 30 * (1 - progress), topTrailingRadius: 30 - progress * 6)
            let change: (CGFloat) -> Void = { distance in
                // Follow the finger directly; only settling into a detent springs.
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) {
                    drag.update(distance: distance, presentedHeight: presentation.height ?? resting, bounds: compact...maximum)
                }
            }
            let end: (CGFloat, CGFloat) -> Void = { distance, velocity in
                guard let draggedHeight = drag.height else { return }
                let projected = draggedHeight - velocity * 0.18
                let target = [compact, medium, maximum].min(by: { abs($0 - projected) < abs($1 - projected) }) ?? compact
                withAnimation(spring) { drag.finish(); detent = target == maximum ? .large : target == medium ? .medium : .height(260) }
            }
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Capsule().fill(.secondary.opacity(0.25)).frame(width: 32, height: 4).padding(.top, 10).padding(.bottom, 7)
                        .accessibilityIdentifier("map-panel-handle").accessibilityLabel("Map panel height").accessibilityAdjustableAction { direction in withAnimation(spring) { detent = direction == .increment ? .large : .height(260) } }
                    header()
                }.contentShape(Rectangle()).simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in if drag.height != nil || abs(value.translation.height) > abs(value.translation.width) { change(value.translation.height) } }
                    .onEnded { value in end(value.translation.height, value.velocity.height) })
                // Keep one scroll view and one gesture bridge across sections. Replacing
                // a scroll view inside a crossfade duplicates its scroll-edge material.
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 0).id("map-panel-top")
                            content()
                        }.background(MapScrollBridge(expanded: detent == .large, sheetDragging: drag.height != nil, contentID: contentID, onDrag: change, onEnd: end).frame(width: 0, height: 0))
                    }.scrollDismissesKeyboard(.interactively)
                        .accessibilityIdentifier("map-panel-scroll")
                        .onChange(of: contentID) {
                            var transaction = Transaction(); transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                drag.finish()
                                proxy.scrollTo("map-panel-top", anchor: .top)
                            }
                        }
                }
            }
            // The scroll viewport stays at expanded size. Only the outer reveal
            // changes during dragging, avoiding per-frame layout of long details.
            .frame(height: maximum, alignment: .top)
            .frame(height: height, alignment: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { presentation.height = $0 }
            .clipShape(.rect(topLeadingRadius: 30 - progress * 6, topTrailingRadius: 30 - progress * 6))
            .background(alignment: .top) {
                // A large refractive glass surface distorts moving map tiles.
                // Standard material keeps the sheet translucent without that lens.
                shape.fill(.regularMaterial)
                    .overlay { shape.fill(Color.canvas.opacity(0.7 + progress * 0.3)) }
                    .frame(width: geo.size.width - 2 * layout.surfaceInset(for: height), height: height + geo.safeAreaInsets.bottom)
                    .shadow(color: .black.opacity(0.12), radius: 16, y: -2)
                    .accessibilityIdentifier("map-panel-surface")
            }
            // The surface expands to the edges while content keeps stable side insets.
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// Observe the native scroll pan instead of adding a competing full-surface gesture.
// A collapsed sheet consumes vertical movement; an expanded sheet scrolls normally
// until a downward pull reaches the top. Buttons retain native cancellation behavior.
private struct MapScrollBridge: UIViewRepresentable {
    var expanded: Bool
    var sheetDragging: Bool
    var contentID: String
    var onDrag: (CGFloat) -> Void
    var onEnd: (CGFloat, CGFloat) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> Probe {
        let probe = Probe(); probe.attach = { [weak coordinator = context.coordinator] view in coordinator?.attach(from: view) }; return probe
    }
    func updateUIView(_ view: Probe, context: Context) { context.coordinator.update(self) }
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
        private var heldOffset: CGFloat?
        private var pinning = false
        init(parent: MapScrollBridge) { self.parent = parent }
        private var holdsContent: Bool { movingSheet || finishedSheetPan || !parent.expanded || parent.sheetDragging }
        func update(_ parent: MapScrollBridge) {
            let contentChanged = self.parent.contentID != parent.contentID
            self.parent = parent
            guard let scroll else { return }
            if parent.sheetDragging { finishedSheetPan = false }
            if contentChanged {
                movingSheet = false; finishedSheetPan = false; origin = 0
                heldOffset = -scroll.adjustedContentInset.top
                scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
            }
            if holdsContent {
                if heldOffset == nil {
                    heldOffset = max(-scroll.adjustedContentInset.top, scroll.contentOffset.y)
                    // Stop an existing fling once, before a header drag takes over.
                    if scroll.isDecelerating { scroll.setContentOffset(scroll.contentOffset, animated: false) }
                }
                pinContent(scroll)
            } else { heldOffset = nil }
            // Keep the native pan available even when a short list fits the
            // expanded viewport. Pinning absorbs bounce while the sheet owns it.
            scroll.bounces = true
        }
        private func pinContent(_ scroll: UIScrollView) {
            guard holdsContent, !pinning else { return }
            let offset = heldOffset ?? max(-scroll.adjustedContentInset.top, scroll.contentOffset.y)
            heldOffset = offset
            guard abs(scroll.contentOffset.y - offset) > 0.1 else { return }
            pinning = true
            scroll.contentOffset.y = offset
            pinning = false
        }
        func attach(from view: UIView) {
            var ancestor = view.superview
            while let current = ancestor {
                if let candidate = current as? UIScrollView {
                    guard scroll !== candidate else { return }; detach(); scroll = candidate
                    candidate.alwaysBounceVertical = true
                    candidate.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
                    observation = candidate.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                        self?.pinContent(scroll)
                    }
                    update(parent)
                    return
                }
                ancestor = current.superview
            }
        }
        func detach() {
            observation = nil
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(pan(_:)))
            scroll?.bounces = true
            scroll = nil; heldOffset = nil; movingSheet = false; finishedSheetPan = false
        }
        @objc private func pan(_ gesture: UIPanGestureRecognizer) {
            guard let scroll else { return }
            let dy = gesture.translation(in: scroll.window).y
            let velocity = gesture.velocity(in: scroll.window)
            let top = -scroll.adjustedContentInset.top
            switch gesture.state {
            case .began:
                finishedSheetPan = false; origin = 0
                movingSheet = !parent.expanded || (scroll.contentOffset.y <= top + 1 && velocity.y > 0)
                heldOffset = movingSheet ? max(top, scroll.contentOffset.y) : nil
                update(parent)
            case .changed:
                if !movingSheet && scroll.contentOffset.y <= top + 1 && velocity.y > 0 {
                    movingSheet = true; origin = dy; heldOffset = top
                    update(parent)
                }
                if movingSheet { pinContent(scroll); parent.onDrag(dy - origin) }
            case .ended, .cancelled:
                if movingSheet {
                    finishedSheetPan = true
                    pinContent(scroll)
                    parent.onEnd(dy - origin, gesture.state == .cancelled ? 0 : velocity.y)
                    // UIScrollView decides its deceleration after pan targets run.
                    // Cancel that unused momentum on the next turn, after ownership
                    // has gone to the sheet spring, rather than fighting each frame.
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.finishedSheetPan, let scroll = self.scroll, let offset = self.heldOffset else { return }
                        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
                    }
                }
                movingSheet = false
            default: break
            }
        }
    }
}
