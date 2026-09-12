import SwiftUI

enum WishlistSaveType: String, CaseIterable, Identifiable {
    case trip, destination, hotel, restaurant, activity, sight
    var id: String { rawValue }
    var title: String { switch self { case .trip: "Trip"; case .destination: "Destination"; case .hotel: "Hotel"; case .restaurant: "Restaurant"; case .activity: "Activity"; case .sight: "Sight" } }
    var subtitle: String { switch self { case .trip: "Build a future itinerary"; case .destination: "Cities, islands & escapes"; case .hotel: "Somewhere to stay"; case .restaurant: "A table worth a visit"; case .activity: "Something to experience"; case .sight: "Landmarks & must-sees" } }
    var kind: WishlistKind { switch self { case .trip, .destination: .destinations; case .hotel: .stays; case .restaurant: .dining; case .activity: .experiences; case .sight: .sights } }
    var symbol: String { self == .trip ? "suitcase.rolling" : kind.symbol }
    var prompt: String { switch self { case .trip: "Plan a trip"; case .destination: "Find a destination"; case .hotel: "Find a hotel"; case .restaurant: "Find a restaurant"; case .activity: "Find an activity"; case .sight: "Find a sight" } }
    var placeholder: String { switch self { case .trip, .destination: "Search cities or destinations"; case .hotel: "Search hotels"; case .restaurant: "Search restaurants"; case .activity: "Search activities or experiences"; case .sight: "Search landmarks, museums & sights" } }
}

private struct WishlistSaveChoices: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var select: (WishlistSaveType) -> Void
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
            ForEach(WishlistSaveType.allCases) { type in
                Button { select(type) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: type.symbol).font(.system(size: 22, weight: .light)).foregroundStyle(Color.bronze)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(type.title).font(.headline).foregroundStyle(.primary)
                            Text(type.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading).padding(16)
                        .background(Color.cardSurface, in: .rect(cornerRadius: 20))
                        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1) }
                        .contentShape(.rect(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityIdentifier("wishlist-save-" + type.rawValue)
            }
        }
    }
}

private struct WishlistSavePlaceView: View {
    let type: WishlistSaveType
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var destination = ""
    @State private var selected: LocationSelection?
    @State private var reviewing = false
    @State private var details = WishlistDetails()
    @State private var website = ""
    @State private var addingDetails = false
    @State private var error: String?
    @State private var savedID = UUID().uuidString
    private var canContinue: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(type.prompt).font(.system(.largeTitle, design: .serif))
                        Text(type == .destination ? "Keep a destination for a future escape." : "Search by name. Add a city to narrow it down.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        LocationAutocompleteField(type.placeholder, text: $name, kind: type == .destination ? .city : .place,
                            identifier: "wishlist-name", category: type.kind.category, searchContext: destination,
                            suggestionSymbol: type.symbol, onEdit: { selected = nil; website = "" }) { value in
                                selected = value
                                name = value.place.name.isEmpty ? value.text : value.place.name
                                destination = type == .destination ? value.country : value.place.city
                                website = value.place.website
                                reviewing = true
                            }
                        if type != .destination {
                            Divider()
                            LocationAutocompleteField("City or destination (optional)", text: $destination, kind: .city,
                                identifier: "wishlist-destination", onEdit: { selected = nil; website = "" })
                        }
                    }.padding(18).background(Color.cardSurface, in: .rect(cornerRadius: 22))
                    if canContinue {
                        Button { reviewing = true } label: {
                            HStack { Text("Continue with this name"); Spacer(); Image(systemName: "arrow.right") }.font(.subheadline.weight(.medium))
                        }.padding(.vertical, 12).accessibilityIdentifier("wishlist-continue")
                    }
                }.padding(22)
            }.scrollDismissesKeyboard(.interactively).background(Color.canvas)
                .navigationTitle("Save a " + type.title.lowercased()).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .navigationDestination(isPresented: $reviewing) { review }
        }
    }
    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Label(type.title, systemImage: type.symbol).font(.subheadline).foregroundStyle(Color.bronze)
                    Text(name).font(.system(.largeTitle, design: .serif)).fixedSize(horizontal: false, vertical: true)
                    if !destination.isEmpty { Text(destination).font(.subheadline).foregroundStyle(.secondary) }
                    if type != .destination, let address = selected?.place.address, !address.isEmpty, address != destination {
                        Text(address).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(22).cardSurface(cornerRadius: 24)
                DisclosureGroup("Add a note or collection", isExpanded: $addingDetails) {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField("A note for later", text: $details.notes, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("wishlist-notes")
                        Divider()
                        TextField("Collection (optional)", text: $details.collection).accessibilityIdentifier("wishlist-collection")
                        TextField("Website (optional)", text: $website).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("wishlist-website")
                        Toggle("Top pick", isOn: $details.topPick)
                    }.padding(.top, 16)
                }.font(.subheadline).tint(.bronze).padding(18).cardSurface(cornerRadius: 20)
                if let error { Text(error).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("wishlist-editor-error") }
            }.padding(22)
        }.scrollDismissesKeyboard(.interactively).background(Color.canvas).navigationTitle("Save to wishlist").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: save) { Label("Save to wishlist", systemImage: "bookmark").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12) }
                    .buttonStyle(.glassProminent).padding(.horizontal, 22).padding(.vertical, 12).background(Color.canvas).accessibilityIdentifier("wishlist-save")
            }
    }
    private func save() {
        let value = WishlistIdea(id: savedID, name: name, destination: destination, kind: type.kind, website: website, selectedPlace: selected?.place)
        if store.wishlist.saveIdea(value, details: details) { dismiss() }
        else { error = store.wishlist.error; store.wishlist.error = nil }
    }
}


struct WishlistContent: View {
    @Environment(TravelStore.self) private var store
    @Environment(JourneyLibrary.self) private var library
    @State private var kind: WishlistKind?
    @State private var collection: String?
    @State private var topPicks = false
    @State private var sort: WishlistSort = .newest
    @State private var saving: WishlistSaveType?
    @State private var createdTrip: UUID?
    private var tripPlans: [JourneyDocument] { library.wishlistTrips.filter { query.isEmpty || ($0.title + " " + $0.routeLabel).localizedCaseInsensitiveContains(query) }.sorted { $0.updatedAt > $1.updatedAt } }
    private var entries: [WishlistEntry] { store.wishlistMatches(query: query, kind: kind, collection: collection, topPicks: topPicks, sort: sort) }
    private var filtered: Bool { kind != nil || collection != nil || topPicks || sort != .newest }
    @State private var exploring = false
    @Binding var query: String
    private var hasSavedContent: Bool { !library.wishlistTrips.isEmpty || !store.wishlistEntries.isEmpty }
    private var filterLabel: String {
        [kind?.title, collection.map { $0.isEmpty ? "Unsorted" : $0 }, topPicks ? "Top picks" : nil, sort != .newest ? sort.rawValue : nil].compactMap { $0 }.joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            if !hasSavedContent {
                emptyState
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search wishlist", text: $query).submitLabel(.search).accessibilityIdentifier("wishlist-search")
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Clear search") }
                }.padding(14).background(Color.cardSurface, in: .rect(cornerRadius: 16))
                if tripPlans.isEmpty && entries.isEmpty && !query.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No matches").font(.headline)
                        Text("Try another trip or place.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Clear search & filters") { query = ""; resetFilters() }.font(.subheadline)
                    }.padding(.vertical, 24).accessibilityIdentifier("wishlist-no-results")
                } else {
                    if !tripPlans.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("Trip plans", count: tripPlans.count)
                            ForEach(tripPlans) { trip in
                                NavigationLink { JourneyDetailView(id: trip.id) } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.title2).foregroundStyle(Color.bronze)
                                            .frame(width: 44, height: 50)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(trip.title).font(.system(.headline, design: .serif)).foregroundStyle(.primary).lineLimit(2)
                                            if !trip.routeLabel.isEmpty { Text(trip.routeLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                            Text("\(trip.nights) nights · Dates flexible").font(.caption).foregroundStyle(Color.bronze)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).cardSurface(cornerRadius: 22)
                                }.buttonStyle(.plain).accessibilityIdentifier("wishlist-trip-plan-" + trip.id.uuidString)
                            }
                        }
                    }
                    if !store.wishlistEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                sectionTitle("Saved places", count: entries.count)
                                Spacer()
                                filters
                            }
                            if filtered {
                                HStack {
                                    Text(filterLabel).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Reset") { resetFilters() }.font(.caption).accessibilityIdentifier("wishlist-reset")
                                }
                            }
                            if entries.isEmpty {
                                Text("No places match these filters.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 18)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(entries) { entry in
                                        NavigationLink { WishlistDetailView(entryID: entry.id) } label: { row(entry) }
                                            .buttonStyle(.plain).accessibilityIdentifier("wishlist-item-" + entry.id)
                                        if entry.id != entries.last?.id { Divider().padding(.leading, 43) }
                                    }
                                }.padding(.horizontal, 16).cardSurface(cornerRadius: 22)
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(WishlistSaveType.allCases) { type in
                        Button(type.title, systemImage: type.symbol) { saving = type }
                            .accessibilityIdentifier("wishlist-menu-" + type.rawValue)
                    }
                    Divider()
                    Button("Explore destinations", systemImage: "globe.europe.africa") { exploring = true }.accessibilityIdentifier("wishlist-find-places")
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add to wishlist").accessibilityIdentifier("wishlist-actions")
            }
        }
        .sheet(item: $saving) { type in
            if type == .trip { TripCreationView(wishlist: true, onCreated: { createdTrip = $0 }) }
            else { WishlistSavePlaceView(type: type) }
        }
        .navigationDestination(item: $createdTrip) { JourneyDetailView(id: $0) }
        .navigationDestination(isPresented: $exploring) { CityExplorerView() }
        .alert("Wishlist", isPresented: Binding(get: { store.wishlist.error != nil }, set: { if !$0 { store.wishlist.error = nil } })) { Button("OK") { store.wishlist.error = nil } } message: { Text(store.wishlist.error ?? "") }
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("What would you like to save?").font(.system(.title, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                Text("A whole trip or a place along the way.").font(.subheadline).foregroundStyle(.secondary)
            }
            WishlistSaveChoices { saving = $0 }
        }.padding(.top, 12).accessibilityIdentifier("wishlist-empty")
    }
    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.headline)
            Text(count.formatted()).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    private var filters: some View {
        Menu {
            Picker("Type", selection: $kind) { Text("All types").tag(nil as WishlistKind?); ForEach(WishlistKind.allCases) { Text($0.title).tag(Optional($0)) } }
            Picker("Collection", selection: $collection) { Text("All collections").tag(nil as String?); Text("Unsorted").tag(Optional("")); ForEach(store.wishlistCollections, id: \.self) { Text($0).tag(Optional($0)) } }
            Toggle("Top picks only", isOn: $topPicks)
            Picker("Sort", selection: $sort) { ForEach(WishlistSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            if filtered { Button("Reset filters") { resetFilters() } }
        } label: {
            Image(systemName: filtered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .frame(width: 44, height: 44).contentShape(.rect)
        }.accessibilityLabel(filtered ? "Filter saved places, active" : "Filter saved places").accessibilityIdentifier("wishlist-filters")
    }
    private func resetFilters() { kind = nil; collection = nil; topPicks = false; sort = .newest }
    private func row(_ entry: WishlistEntry) -> some View {
        let info = store.wishlist.info(entry.id)
        return HStack(alignment: .top, spacing: 15) {
            Image(systemName: entry.kind.symbol).font(.title3).foregroundStyle(entry.kind == .experiences ? Color.teal : .bronze).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title).font(.system(.headline, design: .serif)).foregroundStyle(.primary)
                    if info.topPick { Image(systemName: "star.fill").font(.caption).foregroundStyle(Color.bronze).accessibilityLabel("Top pick") }
                }
                Text(entry.subtitle + (entry.kind == .destinations ? "" : " · " + entry.kind.title)).font(.caption).foregroundStyle(.secondary)
                if !info.notes.isEmpty { Text(info.notes).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 10) {
                    if !info.collection.isEmpty { Label(info.collection, systemImage: "folder").lineLimit(1) }
                    if (library.trips + library.wishlistTrips).contains(where: { entry.isPlanned(in: $0) }) { Label("In your plans", systemImage: "checkmark.circle") }
                }.font(.caption2).foregroundStyle(Color.bronze)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 19).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
    }
}

struct WishlistDetailView: View {
    @Environment(TravelStore.self) private var store
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let entryID: String
    @State private var editing = false
    @State private var removing = false
    @State private var planning = false
    @State private var creating = false
    private var entry: WishlistEntry? { store.wishlistEntries.first { $0.id == entryID } }
    var body: some View {
        Group {
            if let entry { content(entry) }
            else { ContentUnavailableView("Removed from your wishlist", systemImage: "bookmark", description: Text("You can save this place again whenever you like.")) }
        }.background(Color.canvas).navigationTitle("Wishlist").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { if let entry { WishlistEditor(entry: entry) } }
        .sheet(isPresented: $planning) { if let entry { WishlistPlanView(entry: entry, notes: store.wishlist.info(entry.id).notes) } }
        .sheet(isPresented: $creating) { if let entry { TripCreationView(initialDestination: entry.tripDestination, initialCity: entry.city, onCreated: { _ in store.showMessage("Your new trip is ready in Travel") }) } }
        .confirmationDialog("Remove this place from your wishlist?", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove from wishlist", role: .destructive) { if let entry, store.removeFromWishlist(entry) { dismiss() } }.accessibilityIdentifier("wishlist-confirm-remove")
        } message: { Text("This also removes its bookmark. Plans you’ve already added to a trip will stay.") }
        .alert("Wishlist", isPresented: Binding(get: { store.wishlist.error != nil }, set: { if !$0 { store.wishlist.error = nil } })) { Button("OK") { store.wishlist.error = nil } } message: { Text(store.wishlist.error ?? "") }
    }
    private func content(_ entry: WishlistEntry) -> some View {
        let info = store.wishlist.info(entry.id)
        let trips = (library.trips + library.wishlistTrips).filter { entry.isPlanned(in: $0) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(entry.kind.title, systemImage: entry.kind.symbol).font(.subheadline).foregroundStyle(Color.bronze)
                    Editorial(entry.title, size: 32).accessibilityIdentifier("wishlist-detail-title")
                    Text(entry.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        var value = info; value.topPick.toggle(); store.wishlist.update(value, for: entry.id)
                    } label: { Label(info.topPick ? "Top pick" : "Make a top pick", systemImage: info.topPick ? "star.fill" : "star") }
                        .font(.subheadline).accessibilityIdentifier("wishlist-top-pick").accessibilityValue(info.topPick ? "Selected" : "Not selected")
                    Spacer()
                    Button("Edit") { editing = true }.font(.subheadline).accessibilityIdentifier("wishlist-edit")
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Why it’s on your list").font(.headline)
                    if info.notes.isEmpty {
                        Button("Add a note — what would you love to do here?") { editing = true }.font(.subheadline).foregroundStyle(.secondary)
                    } else { Text(info.notes).font(.body).textSelection(.enabled).accessibilityIdentifier("wishlist-notes-display") }
                    if !info.collection.isEmpty { Label(info.collection, systemImage: "folder").font(.subheadline).foregroundStyle(Color.bronze) }
                }
                if entry.place.id.hasPrefix("liteapi:") {
                    NavigationLink("View hotel details") { LiveHotelDetailView(hotel: .bookmark(entry.place)) }.accessibilityIdentifier("wishlist-source")
                } else if case .idea = entry.source {
                    if let url = validatedURL(entry.place.website) { Link(destination: url) { Label("Open saved link", systemImage: "arrow.up.right").labelStyle(.titleOnly) }.font(.subheadline) }
                } else {
                    NavigationLink { sourceDetail(entry) } label: {
                        HStack { Text(entry.kind == .destinations ? "Explore this city" : "View place details"); Spacer() }.font(.subheadline).padding(.vertical, 10)
                    }.accessibilityIdentifier("wishlist-source")
                }
                if !trips.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("In your plans").font(.headline)
                        ForEach(trips) { trip in
                            NavigationLink { JourneyDetailView(id: trip.id) } label: {
                                HStack { Label(trip.title, systemImage: "suitcase.rolling"); Spacer() }.font(.subheadline)
                            }.accessibilityIdentifier("wishlist-planned-trip")
                        }
                    }
                }
                Button { removing = true } label: { Label("Remove from wishlist", systemImage: "bookmark.slash").font(.subheadline) }
                    .foregroundStyle(.secondary).padding(.top, 16).accessibilityIdentifier("wishlist-remove")
            }.padding(22)
        }
        .safeAreaInset(edge: .bottom) {
            Button { if entry.kind == .destinations { creating = true } else { planning = true } } label: {
                Label(entry.kind == .destinations ? "Plan a trip here" : "Add to a trip", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.glassProminent).padding(.horizontal, 22).padding(.vertical, 10).background(Color.canvas)
                .accessibilityIdentifier("wishlist-plan")
        }
    }
    @ViewBuilder private func sourceDetail(_ entry: WishlistEntry) -> some View {
        switch entry.source {
        case .hotel(let hotel): HotelDetailView(hotel: hotel)
        case .restaurant(let place): RestaurantDetailView(place: place)
        case .discovery(let place): ExplorePlaceDetailView(place: place)
        case .city(let city): CityGuideView(city: city)
        case .idea: EmptyView()
        }
    }
}

struct WishlistEditor: View {
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var entry: WishlistEntry? = nil
    @State private var idea = WishlistIdea()
    @State private var details = WishlistDetails()
    @State private var initialized = false
    @State private var error: String?
    private var isCustom: Bool { entry == nil || entry?.customIdea != nil }
    var body: some View {
        NavigationStack {
            Form {
                if isCustom {
                    Section("Place") {
                        TextField("Name", text: $idea.name).accessibilityIdentifier("wishlist-name")
                        Picker("Type", selection: $idea.kind) { ForEach(WishlistKind.allCases) { Text($0.title).tag($0) } }.accessibilityIdentifier("wishlist-kind")
                        TextField(idea.kind == .destinations ? "Country or region (optional)" : "City or destination (optional)", text: $idea.destination).accessibilityIdentifier("wishlist-destination")
                        TextField("Website link (optional)", text: $idea.website).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("wishlist-website")
                    }
                } else if let entry { Section { Label(entry.title, systemImage: entry.kind.symbol) } }
                Section("Make it yours") {
                    TextField("Why would you love to go?", text: $details.notes, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("wishlist-notes")
                    Toggle("Top pick", isOn: $details.topPick).accessibilityIdentifier("wishlist-priority")
                }
                Section {
                    TextField("Collection name (optional)", text: $details.collection).accessibilityIdentifier("wishlist-collection")
                    if !store.wishlistCollections.isEmpty {
                        Menu("Choose an existing collection") { Button("Unsorted") { details.collection = "" }; ForEach(store.wishlistCollections, id: \.self) { name in Button(name) { details.collection = name } } }
                    }
                } header: { Text("Collection") } footer: { Text("Group places with names like Japan, Summer escapes or Family adventures. Leave blank to keep a place unsorted.") }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("wishlist-editor-error") } }
            }.scrollContentBackground(.hidden).background(Color.canvas).scrollDismissesKeyboard(.interactively)
                .navigationTitle(entry == nil ? "Save a place" : "Edit saved place").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityIdentifier("wishlist-save") }
                }
                .onAppear { guard !initialized else { return }; initialized = true; if let entry { details = store.wishlist.info(entry.id); if let value = entry.customIdea { idea = value } } }
        }
    }
    private func save() {
        let saved: Bool
        if isCustom { saved = store.wishlist.saveIdea(idea, details: details) }
        else if let entry { saved = store.wishlist.update(details, for: entry.id) }
        else { return }
        if saved { dismiss() } else { error = store.wishlist.error; store.wishlist.error = nil }
    }
}

struct WishlistPlanView: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entry: WishlistEntry
    let notes: String
    @State private var route: Route?
    @State private var pending: UUID?
    @State private var saved = false
    @State private var error: String?
    private enum Route: Identifiable {
        case create, destination(UUID), event(UUID, JourneyEvent), hotel(UUID, HotelReservation)
        var id: String { switch self { case .create: "create"; case .destination(let id): "destination" + id.uuidString; case .event(let id, _): "event" + id.uuidString; case .hotel(let id, _): "hotel" + id.uuidString } }
    }
    var body: some View {
        NavigationStack {
            List {
                Section { Text(entry.title).font(.headline); Text("Choose a trip or wishlist plan, then review its days and details. Your saved place stays on your wishlist.").font(.subheadline).foregroundStyle(.secondary) }
                Section("Trips & wishlist plans") {
                    ForEach((library.trips + library.wishlistTrips).sorted { $0.updatedAt > $1.updatedAt }) { trip in
                        Button { choose(trip.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(trip.title).foregroundStyle(.primary)
                                Text(entry.isPlanned(in: trip) ? "Already planned · Review details" : trip.routeLabel + (trip.isWishlistTrip ? " · Dates flexible" : "")).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }.accessibilityIdentifier("wishlist-trip-" + trip.id.uuidString)
                    }
                    if (library.trips + library.wishlistTrips).isEmpty { Text("No trips yet. Create one to start planning your visit.").foregroundStyle(.secondary) }
                    Button("Create a new trip", systemImage: "plus") { route = .create }.accessibilityIdentifier("wishlist-new-trip")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Add to a trip").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .sheet(item: $route, onDismiss: {
            if saved { store.showMessage("Saved to your trip"); dismiss() }
            else if let id = pending { pending = nil; if (library.trips + library.wishlistTrips).first(where: { $0.id == id })?.stops.isEmpty == false { choose(id) } }
        }) { value in
            switch value {
            case .create: TripCreationView(initialDestination: entry.place.city, onCreated: { pending = $0 })
            case .destination(let id): AddTripDestinationView(documentID: id, fallbackDestination: entry.place.city)
            case .event(let id, let event): JourneyEventEditor(documentID: id, event: event, onSaved: { saved = true })
            case .hotel(let id, let hotel): HotelReservationEditor(documentID: id, reservation: hotel, onSaved: { saved = true })
            }
        }
    }
    private func choose(_ id: UUID) {
        guard var trip = (library.trips + library.wishlistTrips).first(where: { $0.id == id }) else { error = "That trip is no longer available."; return }
        saved = false
        if trip.preparePlanningRoute(), !library.save(trip) { error = library.error; return }
        if entry.kind == .stays {
            var hotel = trip.hotels.first { $0.place.id == entry.place.id && $0.place.source == entry.place.source } ?? HotelReservation(place: entry.place, notes: notes)
            if !trip.hotels.contains(where: { $0.id == hotel.id }) {
                let stop = trip.stops.first { !$0.name.isEmpty && $0.name.localizedCaseInsensitiveContains(entry.place.city) } ?? trip.stops.first
                hotel.checkIn = stop?.arrival ?? trip.startDate ?? hotel.checkIn
                hotel.checkOut = stop?.departure ?? trip.endDate ?? TravelDay.adding(3, to: hotel.checkIn)
                if hotel.checkOut <= hotel.checkIn { hotel.checkOut = TravelDay.adding(1, to: hotel.checkIn) }
            }
            route = .hotel(id, hotel)
        } else {
            guard let stop = trip.stops.first(where: { !entry.place.city.isEmpty && $0.name.localizedCaseInsensitiveContains(entry.place.city) }) ?? trip.stops.first else { pending = id; route = .destination(id); return }
            let event = trip.events.first { $0.place.id == entry.place.id && $0.place.source == entry.place.source } ?? JourneyEvent(stopID: stop.id, place: entry.place, description: notes, links: validatedURL(entry.place.website) == nil ? [] : [entry.place.website], kind: .place)
            route = .event(id, event)
        }
    }
}

struct WishlistScheduleView: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    @State private var departure = Calendar.current.startOfDay(for: .now)
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("When will you go?") {
                    DatePicker("Departure", selection: $departure, displayedComponents: .date).accessibilityIdentifier("wishlist-departure-date")
                    Text("Each destination keeps its nights. Your stays and daily plans move with the route, and the itinerary appears in Trips.").font(.subheadline).foregroundStyle(.secondary)
                }
                if let document = library.documents.first(where: { $0.id == documentID }),
                   let scheduled = try? document.scheduledWishlist(departure: TravelDay.key(departure)) {
                    Section("Your route") { ForEach(scheduled.stops) { stop in
                        LabeledContent(stop.name, value: "\(TravelDay.label(stop.arrival)) – \(TravelDay.label(stop.departure))")
                        SeasonalityCard(city: stop.name, countryCode: stop.countryCode ?? TravelStatistics.countryCode(stop.country), arrival: stop.arrival, departure: stop.departure)
                    } }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Set travel dates").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Move to Trips") {
                        guard let document = library.documents.first(where: { $0.id == documentID }) else { return }
                        do { let scheduled = try document.scheduledWishlist(departure: TravelDay.key(departure)); if library.save(scheduled) { dismiss() } else { error = library.error } }
                        catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("wishlist-confirm-dates") }
                }
        }
    }
}
