import SwiftUI
import MapKit

struct TravelHubView: View {
    @Environment(TravelAPI.self) private var api
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelStore.self) private var store
    @State private var query = ""
    @State private var grid = false
    @State private var newJourney = false
    @State private var account = false
    @State private var filter = "All"
    @State private var section = "Trips"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var documents: [JourneyDocument] {
        library.documents.filter { $0.isTemplate != true && (query.isEmpty || ($0.title + " " + $0.routeLabel).localizedCaseInsensitiveContains(query)) && (filter == "All" || $0.visibility.title == filter) }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if section == "Trips" && query.isEmpty { TodayHubView() }
                HStack(spacing: 28) {
                    ForEach(["Trips", "Wishlist", "Templates"], id: \.self) { title in
                        Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { section = title; query = "" } } label: {
                            VStack(spacing: 10) {
                                Text(title).font(.headline).foregroundStyle(section == title ? Color.bronze : .secondary)
                                Capsule().fill(section == title ? Color.bronze : .clear).frame(height: 3)
                            }.fixedSize(horizontal: true, vertical: false)
                        }.buttonStyle(.plain).accessibilityIdentifier("travel-section-" + title).accessibilityAddTraits(section == title ? .isSelected : [])
                    }
                    Spacer()
                }
                if section == "Templates" { TemplateLibraryView(search: query) }
                else if section == "Wishlist" { WishlistContent(query: query) }
                else { Group {
                    if query.isEmpty { TravelStatsPreview(compact: true) }
                    if !library.trips.isEmpty { HStack {
                        Menu { Picker("Show", selection: $filter) { ForEach(["All", "Private", "Friends", "Public"], id: \.self) { Text($0) } } } label: { Label(filter == "All" ? "All trips" : filter, systemImage: "line.3.horizontal.decrease") }.font(.subheadline)
                        Spacer()
                        Button { withAnimation(.smooth) { grid.toggle() } } label: { Image(systemName: grid ? "list.bullet" : "square.grid.2x2").frame(width: 38, height: 38) }.buttonStyle(.glass).accessibilityLabel(grid ? "List view" : "Grid view")
                    } }
                    if documents.isEmpty {
                        VStack(spacing: 18) {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Color.bronze)
                            Text(query.isEmpty && filter == "All" ? "Your next trip" : "No trips found").font(.title2.weight(.semibold))
                            if !query.isEmpty || filter != "All" {
                                Button("Clear filters") { query = ""; filter = "All" }.buttonStyle(.glass)
                            } else {
                                Button { newJourney = true } label: { Label("Create trip", systemImage: "plus").padding(.vertical, 10) }.buttonStyle(.glassProminent).accessibilityIdentifier("travel-create")
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 15).cardSurface(cornerRadius: 28)
                        if query.isEmpty && filter == "All" { TemplateDiscoveryRow() }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: grid ? 2 : 1), spacing: 16) {
                            ForEach(documents) { document in
                                NavigationLink { JourneyDetailView(id: document.id) } label: { JourneyCard(document: document, compact: grid) }.buttonStyle(PressStyle())
                            }
                        }
                    }
                    if !store.plans.isEmpty {
                        NavigationLink { TripsView() } label: { Label("Earlier saved plans · \(store.plans.count)", systemImage: "tray.full").font(.subheadline).frame(maxWidth: .infinity).padding(18).cardSurface(cornerRadius: 22) }
                    }
                } }
            }.padding(22)
        }.background(Color.canvas).navigationTitle("Travel").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: section == "Wishlist" ? "Search ideas, destinations or notes" : "Search trips or destinations")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { account = true } label: { if api.isSignedIn { Image(systemName: "person.crop.circle") } else { Text("Sign in").font(.subheadline.weight(.medium)) } }.accessibilityLabel("Travel account") }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newJourney = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New trip").accessibilityIdentifier("travel-new-trip")
                }
            }
            .sheet(isPresented: $newJourney) { TripCreationView(onCreated: { _ in section = "Trips"; query = "" }) }
            .navigationDestination(isPresented: $account) { TravelAccountPage() }
            .alert("Travel", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) { Button("OK") { library.error = nil } } message: { Text(library.error ?? "") }
    }
}

private struct JourneyCard: View {
    let document: JourneyDocument
    var compact = false
    private var accent: Color { Color.brandInk }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [accent, accent.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "airplane").font(.system(size: compact ? 70 : 100, weight: .ultraLight)).rotationEffect(.degrees(-15)).foregroundStyle(.white.opacity(0.12)).frame(maxWidth: .infinity, alignment: .trailing).padding(15)
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.routeLabel.isEmpty ? "Your journey" : document.routeLabel).font(.system(compact ? .title3 : .title2, design: .serif)).lineLimit(2)
                }.foregroundStyle(.white).padding(20)
            }.frame(height: compact ? 138 : 150)
            VStack(alignment: .leading, spacing: 12) {
                Text(document.title).font(.system(.title3, design: .serif)).foregroundStyle(.primary).lineLimit(2)
                Text("\(document.planCount) plans · \(document.places.count) journal places" + (document.nights > 0 ? " · \(document.nights) nights" : "")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Label(document.visibility.title, systemImage: document.visibility == .private ? "lock" : "person.2").font(.caption2).foregroundStyle(.secondary)
                    Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(Color.bronze)
                }
            }.padding(19)
        }.cardSurface(cornerRadius: 27).clipShape(.rect(cornerRadius: 27))
    }
}

struct JourneyDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var compactAdd = false
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var mode = "Agenda"
    @State private var choseInitialMode = false
    @State private var chapter = "Plan"
    @State private var selectedDay: String?
    @State private var editInfo = false
    @State private var routing = false
    @State private var event: JourneyEvent?
    @State private var addingPlan = false
    @State private var addingDay: JourneyAgendaDay?
    @State private var hotel: HotelReservation?
    @State private var flight: FlightReservation?
    @State private var rated: RatedPlace?
    @State private var share = false
    @State private var importing = false
    @State private var savedRatings = false
    @State private var journalPlanPicker = false
    @State private var deleting = false
    @State private var exportURL: ExportedJourney?
    @State private var error: String?
    @State private var placeFilter: PlaceCategory?
    @State private var placeGrid = false
    private var document: JourneyDocument? { library.documents.first { $0.id == id } }
    var body: some View {
        Group {
            if let document {
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        header(document)
                        if chapter == "Plan" && !document.stops.isEmpty {
                            Button { if document.stops.count > 1 { routing = true } else { editInfo = true } } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.title2).foregroundStyle(Color.bronze)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(document.stops.count > 1 ? "Plan your route" : "Add another destination").font(.headline).foregroundStyle(.primary)
                                        Text(document.stops.count > 1 ? "Compare city order and transfer days" : "Turn this into a multi-city trip").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.bronze)
                                }.padding(16).cardSurface(cornerRadius: 18)
                            }.buttonStyle(.plain).accessibilityIdentifier("trip-route-planner")
                        }
                        if chapter != "Recap" && TripRecap(document: document).hasEnded() {
                            Button { withAnimation { chapter = "Recap" } } label: {
                                Label("Your trip recap is ready", systemImage: "sparkles").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            }.buttonStyle(.glass).accessibilityIdentifier("recap-ready")
                        }
                        tripNavigation
                        if chapter == "Plan" { if mode == "Today" { TodayView(document: document) } else { itinerary(document) } } else if chapter == "Recap" { TripRecapView(document: document) { chapter = "Journal"; journalPlanPicker = true } } else { journal(document) }
                    }.padding(22)
                }.background(Color.canvas)
                    .accessibilityIdentifier("journey-scroll")
                    .onAppear { if !choseInitialMode { mode = TodayPlanner.isActive(document, now: TodayClock.now()) ? "Today" : "Agenda"; choseInitialMode = true } }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                    } action: { _, offset in
                        // Separate thresholds keep the button steady near the top and during bounce.
                        if offset > 80 { compactAdd = true }
                        else if offset < 24 { compactAdd = false }
                    }
                    .navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button { share = true } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share journey") }
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("Edit journey", systemImage: "pencil") { editInfo = true }
                                Button("Log a visit from your plan", systemImage: "square.and.pencil") {
                                    chapter = "Journal"; journalPlanPicker = true
                                }.accessibilityIdentifier("trip-journal-planned")
                                Button("Import places from a trip", systemImage: "square.and.arrow.down") { importing = true }
                                Button("Add a rated restaurant", systemImage: "star") { savedRatings = true }
                                Menu("Export", systemImage: "square.and.arrow.up") {
                                    ForEach(JourneyExportFormat.allCases) { format in Button(format.rawValue.uppercased()) { do { exportURL = ExportedJourney(url: try JourneyExporter.export(document, format: format)) } catch { self.error = error.localizedDescription } } }
                                }
                                Button("Delete journey", systemImage: "trash", role: .destructive) { deleting = true }
                            } label: { Image(systemName: "ellipsis") }.accessibilityIdentifier("journey-menu")
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HStack {
                            Spacer(minLength: 0)
                            if chapter != "Recap" { addButton }
                        }
                        .padding(.horizontal, 22)
                        .frame(height: chapter == "Recap" ? 0 : 70, alignment: .top)
                    }
                    .sheet(isPresented: $routing) { RoutePlannerView(document: document) { updated in
                        guard library.documents.first(where: { $0.id == id }) == document else { return "This trip changed while you were planning. Close and reopen the route planner to use the latest version." }
                        return library.save(updated) ? nil : library.error
                    } }
                    .sheet(isPresented: $editInfo) { JourneyEditor(document: document) }
                    .sheet(isPresented: $addingPlan) { TripAddFlowView(documentID: id, day: addingDay) }
                    .sheet(item: $event) { JourneyEventEditor(documentID: id, event: $0) }
                    .sheet(item: $hotel) { HotelReservationEditor(documentID: id, reservation: $0) }
                    .sheet(item: $flight) { FlightReservationEditor(documentID: id, reservation: $0) }
                    .sheet(item: $rated) { RatedPlaceEditor(documentID: id, rated: $0) }
                    .sheet(isPresented: $journalPlanPicker) { JournalPlanPlacesView(documentID: id) }
                    .sheet(isPresented: $share) { JourneyShareView(documentID: id) }
                    .sheet(isPresented: $importing) { ItineraryIntoTripView(tripID: id) }
                    .sheet(isPresented: $savedRatings) { RatedRestaurantImportView(tripID: id) }
                    .sheet(item: $exportURL) { ActivityShareSheet(items: [$0.url]) }
                    .confirmationDialog("Delete this local journey?", isPresented: $deleting, titleVisibility: .visible) {
                        Button("Delete from device", role: .destructive) { if library.remove(id) { dismiss() } }
                    } message: { Text("A shared cloud copy is managed separately in Sharing. Removing the local copy does not revoke a link.") }
            } else { ContentUnavailableView("Journey unavailable", systemImage: "suitcase", description: Text("This journey may have been removed.")) }
        }.alert("Travel", isPresented: Binding(get: { error != nil || library.error != nil }, set: { if !$0 { error = nil; library.error = nil } })) { Button("OK") { error = nil; library.error = nil } } message: { Text(error ?? library.error ?? "") }
    }
    private var tripNavigation: some View {
        HStack(spacing: 16) {
            ForEach(["Plan", "Journal", "Recap"], id: \.self) { tab in
                let selected = chapter == tab
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { chapter = tab }
                } label: {
                    Text(tab)
                        .font(.subheadline.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.bronze : .secondary)
                        .lineLimit(1)
                        .frame(minHeight: 46)
                        .padding(.horizontal, 2)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(selected ? Color.bronze : .clear).frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
            if chapter == "Plan" {
                Menu {
                    Picker("Plan view", selection: Binding(get: { mode }, set: { value in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { mode = value }
                    })) {
                        Label("Today", systemImage: "sun.max").tag("Today")
                        Label("List", systemImage: "list.bullet").tag("Agenda")
                        Label("Calendar", systemImage: "calendar").tag("Calendar")
                        Label("Map", systemImage: "map").tag("Map")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode == "Today" ? "sun.max" : mode == "Agenda" ? "list.bullet" : mode == "Calendar" ? "calendar" : "map")
                        Text(mode == "Agenda" ? "List" : mode)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.caption.weight(.medium)).lineLimit(1)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Plan view")
                .accessibilityValue(mode == "Agenda" ? "List" : mode)
                .accessibilityIdentifier("trip-plan-view")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(alignment: .bottom) { Rectangle().fill(.quaternary).frame(height: 1) }
    }
    private var addButton: some View {
        Button {
            if chapter == "Plan" { addingDay = nil; addingPlan = true }
            else { rated = RatedPlace() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.title3.weight(.medium)).frame(width: 22)
                if !compactAdd {
                    Text(chapter == "Plan" ? "Add to plan" : "Log a visit")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, compactAdd ? 16 : 20)
            .frame(height: 54)
            .contentShape(Capsule())
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: compactAdd)
        .accessibilityLabel(chapter == "Plan" ? "Add to plan" : "Log a visit")
        .accessibilityValue(compactAdd ? "Compact" : "Expanded")
        .accessibilityIdentifier(chapter == "Plan" ? "journey-add" : "trip-add-place")
    }
    private func header(_ d: JourneyDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let source = d.templateMeta?.sourceTitle, d.importedFrom != nil { Text("Based on " + source + (d.templateMeta?.authorHandle.isEmpty == false ? " · @" + d.templateMeta!.authorHandle : "")).font(.caption).foregroundStyle(.secondary) }
            Editorial(d.title, size: 32).accessibilityIdentifier("journey-title")
            Label(d.routeLabel.isEmpty ? "Add your destination" : d.routeLabel, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
            if let start = d.startDate { Text(TravelDay.label(start) + (d.endDate.map { " – " + TravelDay.label($0) } ?? "")).font(.caption).foregroundStyle(Color.bronze) }
            if !d.description.isEmpty { Text(d.description).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4) }
            if chapter != "Recap" { HStack(spacing: 0) {
                metric("\(d.nights)", "Nights")
                Divider().frame(height: 34)
                metric("\(d.planCount)", "Plans")
                Divider().frame(height: 34)
                metric("\(d.places.count)", "Journal entries")
            }.padding(.top, 8) }
        }
    }
    private func metric(_ value: String, _ caption: String) -> some View { VStack(spacing: 6) { Text(value).font(.system(.title2, design: .serif)); Text(caption).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
    private func itinerary(_ d: JourneyDocument) -> some View {
        let conflicts = JourneyConflicts.detect(d)
        return VStack(alignment: .leading, spacing: 24) {
            if d.stops.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Give your plans a place", subtitle: "Add route stops to organise events by day. You can already save bookings and log visits.")
                    Button("Add destinations", systemImage: "mappin.and.ellipse") { editInfo = true }.buttonStyle(.glass).accessibilityIdentifier("trip-add-route")
                }.padding(20).cardSurface(cornerRadius: 24)
            }
            if mode != "Map" && (!d.hotels.isEmpty || !d.flights.isEmpty) { bookingSection(d, conflicts: conflicts) }
            if mode == "Map" { JourneyMapView(places: d.mapPlaces).frame(height: 380).clipShape(.rect(cornerRadius: 26)) }
            else {
                if mode == "Calendar" {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 95))], spacing: 10) {
                        ForEach(d.days) { day in
                            Button { selectedDay = selectedDay == day.id ? nil : day.id } label: {
                                VStack(spacing: 6) { Text(day.label).font(.subheadline.weight(.medium)); Text(day.city).font(.caption2).lineLimit(1); Text("\(d.events.filter { $0.stopID == day.stopID && $0.day == day.localDay }.count) plans").font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(13).cardSurface(cornerRadius: 17, emphasized: selectedDay == day.id)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                ForEach(d.days.filter { mode != "Calendar" || selectedDay == nil || selectedDay == $0.id }) { day in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { SectionHeading(title: day.label, subtitle: day.city); Spacer(); Button { addingDay = day; addingPlan = true } label: { Image(systemName: "plus").frame(width: 35, height: 35) }.buttonStyle(.glass).accessibilityLabel("Add event on \(day.label) in \(day.city)") }
                        DestinationWeatherRow(city: day.city, day: day.date, tripID: d.id, latitude: d.stops.first { $0.id == day.stopID }?.latitude, longitude: d.stops.first { $0.id == day.stopID }?.longitude)
                        let events = d.events.filter { $0.stopID == day.stopID && $0.day == day.localDay }.sorted { $0.sortMinute < $1.sortMinute }
                        if events.isEmpty { Text("No plans yet").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 10) }
                        ForEach(events) { item in
                            Button { event = item } label: {
                                HStack(alignment: .top, spacing: 15) {
                                    Text(item.allDay == true ? "All day" : item.timeLabel).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Color.bronze).frame(width: 42).padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 7) { Text(item.displayTitle).font(.system(.headline, design: .serif)).foregroundStyle(.primary); Text(item.categoryTitle + (item.endTimeLabel.map { " · Until " + $0 } ?? "")).font(.caption).foregroundStyle(.secondary); if !item.isPlaceVisit && !item.place.name.isEmpty { Text(item.place.name).font(.caption).foregroundStyle(.secondary) }; if let attendees = item.attendees, !attendees.isEmpty { Text(attendees).font(.caption).foregroundStyle(.secondary) }; if !item.description.isEmpty { Text(item.description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }; if let cost = item.cost { Text(cost.formatted).font(.caption).foregroundStyle(Color.bronze) } }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: item.symbol).foregroundStyle(Color.bronze)
                                }.padding(18).cardSurface(cornerRadius: 22)
                            }.buttonStyle(PressStyle()).accessibilityIdentifier("agenda-event-\(day.localDay)")
                            .contextMenu {
                                if item.isPlaceVisit {
                                    Button("Log or rate visit", systemImage: "star.bubble") { rated = d.places.first(where: { $0.place.id == item.place.id && $0.place.source == item.place.source }) ?? RatedPlace(place: item.place) }
                                }
                            }
                            ForEach(conflicts.filter { $0.eventIDs.contains(item.id) }) { warning in
                                conflictWarning(warning) { event = item }
                            }
                        }
                    }
                }
            }
            if mode == "Map" || (d.hotels.isEmpty && d.flights.isEmpty) { bookingSection(d, conflicts: conflicts) }
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Budget")
                priceRows(d.eventTotals, label: "Events")
                Divider()
                priceRows(d.totals, label: "Total planned cost")
                DisclosureGroup("How totals work") { Text("Repeated events count once per day. Currencies stay separate. Only added prices count.").font(.caption).foregroundStyle(.secondary) }.font(.caption)
            }.padding(21).cardSurface(cornerRadius: 25)
        }
    }
    private func bookingSection(_ d: JourneyDocument, conflicts: [JourneyConflicts.Warning]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Bookings")
            ForEach(d.hotels) { item in Button { hotel = item } label: { bookingRow(item.place.name, subtitle: "\(TravelDay.label(item.checkIn)) – \(TravelDay.label(item.checkOut)) · \(item.rooms) rooms", symbol: "bed.double", cost: item.cost) }.buttonStyle(PressStyle()).contextMenu { Button("Log or rate stay", systemImage: "star.bubble") { rated = d.places.first(where: { $0.place.id == item.place.id && $0.place.source == item.place.source }) ?? RatedPlace(place: item.place) } }
                if mode != "Map" { ForEach(conflicts.filter { $0.hotelID == item.id }) { warning in conflictWarning(warning) { hotel = item } } }
            }
            ForEach(d.flights) { item in Button { flight = item } label: { bookingRow("\(item.departureAirport) → \(item.arrivalAirport)", subtitle: "\(item.airline) \(item.flightNumber) · \(item.departureDay)", symbol: "airplane", cost: item.cost) }.buttonStyle(PressStyle()) }
            if d.hotels.isEmpty && d.flights.isEmpty { Text("Attach a hotel or flight using Add to plan.").font(.subheadline).foregroundStyle(.secondary) }
        }
    }
    private func conflictWarning(_ warning: JourneyConflicts.Warning, edit: @escaping () -> Void) -> some View {
        Button(action: edit) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.bronze).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(warning.title).font(.caption.weight(.semibold)).foregroundStyle(Color.bronze)
                    Text(warning.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Review timing").font(.caption.weight(.medium)).foregroundStyle(Color.bronze)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 4).padding(.bottom, 4)
        }.buttonStyle(.plain).accessibilityIdentifier("agenda-conflict-" + warning.id)
    }
    private func priceRows(_ totals: [String: Decimal], label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(label).font(.subheadline.weight(.medium)); if totals.isEmpty { Text("No prices added").font(.caption).foregroundStyle(.secondary) }; ForEach(totals.keys.sorted(), id: \.self) { currency in HStack { Text(currency).foregroundStyle(.secondary); Spacer(); Text(TravelMoney(amount: totals[currency]!, currency: currency).formatted) }.font(.subheadline) } }
    }
    private func bookingRow(_ name: String, subtitle: String, symbol: String, cost: TravelMoney?) -> some View {
        HStack(spacing: 16) { Image(systemName: symbol).font(.title2.weight(.light)).foregroundStyle(Color.bronze); VStack(alignment: .leading, spacing: 7) { Text(name).font(.system(.headline, design: .serif)).foregroundStyle(.primary); Text(subtitle).font(.caption).foregroundStyle(.secondary); if let cost { Text(cost.formatted).font(.caption).foregroundStyle(Color.bronze) } }.frame(maxWidth: .infinity, alignment: .leading); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(19).cardSurface(cornerRadius: 23)
    }
    private func journal(_ d: JourneyDocument) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your visits & memories").font(.title2.weight(.semibold))
                Text("Choose a place you visited, add your photos, notes or rating, and save your entry.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.accessibilityIdentifier("trip-journal-intro")
            if !d.places.isEmpty { HStack {
                metric(d.averageScore.map { String(format: "%.1f", $0) } ?? "—", "Average / 10")
                Divider().frame(height: 32)
                metric("\(d.places.reduce(0) { $0 + $1.photos.count })", "Photos")
                Divider().frame(height: 32)
                metric("\(d.stops.count)", "Destinations")
            }.padding(.vertical, 12) }
            if d.events.contains(where: { $0.isPlaceVisit }) || !d.hotels.isEmpty {
                Button { journalPlanPicker = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "calendar.badge.checkmark").font(.title3).foregroundStyle(Color.bronze)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("From your plan").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("Choose a place you visited and add its details.").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.bronze)
                    }.padding(16).cardSurface(cornerRadius: 20)
                }.buttonStyle(PressStyle()).accessibilityIdentifier("trip-journal-planned")
            }
            if !d.places.isEmpty { HStack {
                Menu { Button("All places") { placeFilter = nil }; ForEach(PlaceCategory.allCases) { category in Button(category.title) { placeFilter = category } } } label: { Label(placeFilter?.title ?? "All places", systemImage: "line.3.horizontal.decrease") }
                Spacer()
                Button { placeGrid.toggle() } label: { Image(systemName: placeGrid ? "list.bullet" : "square.grid.2x2").frame(width: 35, height: 35) }.buttonStyle(.glass)
            } }
            if d.places.isEmpty { ContentUnavailableView("Start with a visit", systemImage: "camera.on.rectangle", description: Text("Tap Log a visit to find a place, or choose one from your plan. You can save a few details now and add more later.")) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: placeGrid ? 2 : 1), spacing: 16) {
                ForEach(d.places.filter { placeFilter == nil || $0.place.category == placeFilter }) { place in
                    Button { rated = place } label: {
                        VStack(alignment: .leading, spacing: 13) {
                            if let photo = place.photos.first, let image = UIImage(data: photo.jpeg) { Image(uiImage: image).resizable().scaledToFill().frame(height: 140).clipped().clipShape(.rect(cornerRadius: 17)) }
                            HStack { Image(systemName: place.place.category.symbol).foregroundStyle(Color.bronze); Spacer(); Text(place.overall > 0 ? String(format: "%.1f", place.overall) : "To rate").font(.headline).foregroundStyle(Color.bronze) }
                            Text(place.place.name).font(.system(.headline, design: .serif)).foregroundStyle(.primary)
                            Text(place.place.category.title + (place.visitedOn.map { " · " + TravelDay.label($0) } ?? "")).font(.caption).foregroundStyle(.secondary)
                            if !place.notes.isEmpty { Text(place.notes).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                            Divider()
                            HStack {
                                Label(place.overall == 0 && place.notes.isEmpty && place.photos.isEmpty && place.visitedOn == nil ? "Add visit details" : "Edit entry", systemImage: "square.and.pencil")
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                            }.font(.caption.weight(.semibold)).foregroundStyle(Color.bronze)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).cardSurface(cornerRadius: 23)
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("journal-entry-" + place.id.uuidString)
                }
            }
            if !d.places.isEmpty { SectionHeading(title: "Your trip, on the map"); JourneyMapView(places: d.places.filter { placeFilter == nil || $0.place.category == placeFilter }.map(\.place)).frame(height: 320).clipShape(.rect(cornerRadius: 25)) }
        }
    }
}

/// Choosing a planned place opens its details before anything is added to the journal.
private struct JournalPlanPlacesView: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    @State private var selected: RatedPlace?
    private var document: JourneyDocument? { library.documents.first { $0.id == documentID } }
    private var places: [PlaceRecord] {
        guard let document else { return [] }
        var seen = Set<String>()
        return (document.events.filter { $0.isPlaceVisit }.map(\.place) + document.hotels.map(\.place))
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.source + "::" + $0.id).inserted }
    }
    private func entry(for place: PlaceRecord) -> RatedPlace? {
        document?.places.first { $0.place.id == place.id && $0.place.source == place.source }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose a place you visited. Add your rating, notes or photos on the next screen.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(places, id: \.self) { place in
                    Button { selected = entry(for: place) ?? RatedPlace(place: place) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: place.category.symbol).foregroundStyle(Color.bronze).frame(width: 26)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(place.name).font(.headline).foregroundStyle(.primary)
                                Text(entry(for: place) == nil ? "Add visit details" : "Edit existing journal entry")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("journal-plan-place-" + place.id)
                }
                if places.isEmpty { Text("No places in this plan yet. Use Log a visit in Journal to find a place.").foregroundStyle(.secondary) }
            }
            .scrollContentBackground(.hidden).background(Color.canvas)
            .navigationTitle("Where did you go?").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .navigationDestination(item: $selected) { value in
                RatedPlaceEditor(documentID: documentID, rated: value, onSaved: { dismiss() })
                    .environment(\.tripEditorEmbedded, true)
            }
        }
    }
}

struct JourneyMapView: View {
    let places: [PlaceRecord]
    @State private var selected: String?
    private var plotted: [PlaceRecord] { var ids = Set<String>(); return places.filter { $0.hasCoordinate && ids.insert($0.id).inserted } }
    private var initialCamera: MapCameraPosition {
        guard plotted.count == 1, let place = plotted.first else { return .automatic }
        return .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: place.latitude!, longitude: place.longitude!), span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)))
    }
    var body: some View {
        VStack(spacing: 9) {
            if plotted.isEmpty { ContentUnavailableView("No mapped places yet", systemImage: "map", description: Text("Choose a place to add it to your map.")) }
            else {
                Map(initialPosition: initialCamera, selection: $selected) { ForEach(plotted) { place in Marker(place.name, systemImage: place.category.symbol, coordinate: CLLocationCoordinate2D(latitude: place.latitude!, longitude: place.longitude!)).tint(Color.bronze).tag(place.id) } }.id(plotted).mapStyle(.standard(elevation: .realistic)).mapControls { MapCompass(); MapScaleView() }
                if let selected, let place = plotted.first(where: { $0.id == selected }) {
                    Button { let item = MKMapItem(location: CLLocation(latitude: place.latitude!, longitude: place.longitude!), address: nil); item.name = place.name; item.openInMaps() } label: { Label("\(place.name) · Open in Maps", systemImage: "arrow.up.right").font(.caption) }.padding(.horizontal)
                }
            }
            if !plotted.isEmpty { Text("\(plotted.count) \(plotted.count == 1 ? "place" : "places") on your map").font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("trip-map-count") }
            if places.count > plotted.count { Text("\(places.count - plotted.count) places without a map location").font(.caption2).foregroundStyle(.secondary).padding(.horizontal) }
        }
    }
}
struct ExportedJourney: Identifiable { let id = UUID(); let url: URL }
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ItineraryItemChooser: View {
    @Environment(\.dismiss) private var dismiss
    let select: (String) -> Void
    var body: some View {
        TripEditorNavigation {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Stays & flights").font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) { option("Hotel booking", symbol: "bed.double", value: "hotel"); option("Flight booking", symbol: "airplane", value: "flight") }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tables & discoveries").font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) { option("Restaurant", symbol: "fork.knife", value: "place"); option("Activity or place", symbol: "mappin.and.ellipse", value: "attraction") }
                    }
                    ForEach(ItineraryItemKind.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title).font(.subheadline.weight(.semibold))
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(group.items.filter { $0 != .place }) { kind in option(kind.title, symbol: kind.symbol, value: kind.rawValue) }
                            }
                        }
                    }
                    Button { select("ai") } label: { Label("AI activity ideas", systemImage: "sparkles").frame(maxWidth: .infinity).padding(12) }.buttonStyle(.glass)
                }.padding(22)
            }.background(Color.canvas).navigationTitle("Add to your trip").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.presentationDragIndicator(.visible)
    }
    private func option(_ title: String, symbol: String, value: String) -> some View {
        Button { select(value) } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Color.bronze)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading).padding(16).cardSurface(cornerRadius: 21)
        }.buttonStyle(PressStyle()).accessibilityIdentifier("add-plan-" + value)
    }
}

/// The chooser and each editor share one modal and one native navigation stack.
struct TripAddFlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    var day: JourneyAgendaDay?
    @State private var route: AddRoute?
    @State private var addingFlight = false
    @State private var pendingChoice: String?
    private var document: JourneyDocument? { library.documents.first { $0.id == documentID } }
    private enum AddRoute: Hashable, Identifiable {
        case event(JourneyEvent), hotel(HotelReservation), ideas, destination
        var id: String {
            switch self { case .event(let item): "event-" + item.id.uuidString; case .hotel(let item): "hotel-" + item.id.uuidString; case .ideas: "ideas"; case .destination: "destination" }
        }
    }
    var body: some View {
        Group {
            if addingFlight {
                FlightAddView(documentID: documentID, departureDay: day?.date ?? document?.startDate) { _ in dismiss() }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else { chooser }
        }
        .presentationDragIndicator(.visible)
    }
    private var chooser: some View {
        NavigationStack {
            ItineraryItemChooser(select: choose)
                .navigationDestination(item: $route) { route in
                    Group {
                        switch route {
                        case .event(let value): JourneyEventEditor(documentID: documentID, event: value, onSaved: { dismiss() })
                        case .hotel(let value): HotelReservationEditor(documentID: documentID, reservation: value, onSaved: { dismiss() })
                        case .ideas: ActivityIdeasView(documentID: documentID, onSaved: { dismiss() })
                        case .destination: AddTripDestinationView(documentID: documentID, onContinue: {
                            if let choice = pendingChoice { pendingChoice = nil; choose(choice) }
                        })
                        }
                    }.id(route.id)
                }
        }.environment(\.tripEditorEmbedded, true).presentationDragIndicator(.visible)
    }
    private func choose(_ choice: String) {
        guard var document else { return }
        if document.preparePlanningRoute(), !library.save(document) { return }
        let stop = document.stops.first(where: { $0.id == day?.stopID }) ?? document.stops.first
        switch choice {
        case "hotel":
            var hotel = HotelReservation()
            hotel.place.city = stop?.name ?? document.destination
            hotel.checkIn = stop?.arrival ?? document.startDate ?? hotel.checkIn
            hotel.checkOut = stop?.departure ?? document.endDate ?? TravelDay.adding(3, to: hotel.checkIn)
            if hotel.checkOut <= hotel.checkIn { hotel.checkOut = TravelDay.adding(1, to: hotel.checkIn) }
            route = .hotel(hotel)
        case "flight":
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { addingFlight = true }
        default:
            guard let stop else { pendingChoice = choice; route = .destination; return }
            if choice == "ai" { route = .ideas; return }
            guard let kind = choice == "attraction" ? ItineraryItemKind.place : ItineraryItemKind(rawValue: choice) else { return }
            let category: PlaceCategory = choice == "attraction" ? .attraction : kind == .place ? .restaurant : .other
            route = .event(JourneyEvent(stopID: stop.id, day: min(day?.localDay ?? 0, stop.nights), place: PlaceRecord(category: category, city: stop.name), kind: kind))
        }
    }
}

/// Older journal-only trips acquire a route without losing the user's selected add action.
struct AddTripDestinationView: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    var fallbackDestination = ""
    var onContinue: (() -> Void)? = nil
    @State private var destination = ""
    @State private var selection: LocationSelection?
    @State private var start = TravelDay.key(.now)
    @State private var end = TravelDay.adding(3, to: TravelDay.key(.now))
    @State private var error: String?
    var body: some View {
        TripEditorNavigation {
            Form {
                Section { LocationAutocompleteField("Destination", text: $destination, identifier: "add-trip-destination", onEdit: { selection = nil }) { selection = $0 } }
                Section("Travel dates") { DayField(title: "Arrival", value: $start); DayField(title: "Departure", value: $end) }
                if let error { Text(error).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Where will this happen?").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Continue") {
                        guard var document = library.documents.first(where: { $0.id == documentID }) else { return }
                        guard end > start else { error = "Choose a departure after your arrival."; return }
                        document.dateMode = .dates; document.startDate = start; document.endDate = end; document.destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
                        document.stops.append(JourneyStop(name: destination.trimmingCharacters(in: .whitespacesAndNewlines), country: selection?.country ?? "", arrival: start, nights: TravelDay.distance(start, end), latitude: selection?.place.latitude, longitude: selection?.place.longitude, timeZone: selection?.timeZone))
                        if library.save(document) { if let onContinue { onContinue() } else { dismiss() } } else { error = library.error }
                    }.disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("add-trip-continue") }
                }
                .onAppear { if let document = library.documents.first(where: { $0.id == documentID }) { destination = document.destination.isEmpty ? fallbackDestination : document.destination; start = document.startDate ?? start; end = document.endDate ?? TravelDay.adding(3, to: start) } }
        }
    }
}
