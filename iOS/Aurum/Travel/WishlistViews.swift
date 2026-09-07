import SwiftUI

struct WishlistContent: View {
    @Environment(TravelStore.self) private var store
    @Environment(JourneyLibrary.self) private var library
    let query: String
    @State private var kind: WishlistKind?
    @State private var collection: String?
    @State private var topPicks = false
    @State private var sort: WishlistSort = .newest
    @State private var adding = false
    private var entries: [WishlistEntry] { store.wishlistMatches(query: query, kind: kind, collection: collection, topPicks: topPicks, sort: sort) }
    private var filtered: Bool { kind != nil || collection != nil || topPicks || sort != .newest }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Editorial("Someday starts here.", size: 28)
                Text("Saved places and ideas, ready for your next trip.").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack {
                Menu {
                    Picker("Type", selection: $kind) { Text("All types").tag(nil as WishlistKind?); ForEach(WishlistKind.allCases) { Text($0.rawValue).tag(Optional($0)) } }
                    Picker("Collection", selection: $collection) { Text("All collections").tag(nil as String?); Text("Unsorted").tag(Optional("")); ForEach(store.wishlistCollections, id: \.self) { Text($0).tag(Optional($0)) } }
                    Toggle("Top picks only", isOn: $topPicks)
                    Picker("Sort", selection: $sort) { ForEach(WishlistSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    if filtered { Button("Reset filters") { resetFilters() } }
                } label: { Label(filtered ? "Filtered" : "All saved ideas", systemImage: "line.3.horizontal.decrease") }
                    .font(.subheadline).accessibilityIdentifier("wishlist-filters")
                Spacer()
                Button { adding = true } label: { Label("Add idea", systemImage: "plus") }
                    .font(.subheadline.weight(.medium)).accessibilityIdentifier("wishlist-add")
            }
            if filtered {
                HStack {
                    Text([kind?.rawValue, collection.map { $0.isEmpty ? "Unsorted" : $0 }, topPicks ? "Top picks" : nil].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    Spacer(); Button("Reset") { resetFilters() }.font(.caption).accessibilityIdentifier("wishlist-reset")
                }
            }
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(store.wishlistEntries.isEmpty ? "Keep the places you don’t want to forget." : "No ideas match your search.").font(.headline)
                    Text(store.wishlistEntries.isEmpty ? "Tap the heart or bookmark on a stay, restaurant or city. Or add your own idea, even if you haven’t chosen the dates yet." : "Try another name, destination or note, or reset your filters.").font(.subheadline).foregroundStyle(.secondary)
                    if filtered { Button("Show all types & collections") { resetFilters() }.font(.subheadline) }
                    if store.wishlistEntries.isEmpty { Button("Add your first idea") { adding = true }.buttonStyle(.glassProminent).accessibilityIdentifier("wishlist-first-idea") }
                }.padding(.vertical, 18).accessibilityIdentifier("wishlist-empty")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        NavigationLink { WishlistDetailView(entryID: entry.id) } label: { row(entry) }
                            .buttonStyle(.plain).accessibilityIdentifier("wishlist-item-" + entry.id)
                        Divider()
                    }
                }
            }
            NavigationLink { CityExplorerView() } label: {
                HStack { Label("Find more places", systemImage: "globe.europe.africa"); Spacer(); Image(systemName: "arrow.right") }.font(.subheadline).padding(.vertical, 12)
            }.accessibilityIdentifier("wishlist-find-places")
            Label("Private · Saved on this device", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $adding) { WishlistEditor() }
        .alert("Wishlist", isPresented: Binding(get: { store.wishlist.error != nil }, set: { if !$0 { store.wishlist.error = nil } })) { Button("OK") { store.wishlist.error = nil } } message: { Text(store.wishlist.error ?? "") }
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
                Text(entry.subtitle + (entry.kind == .destinations ? "" : " · " + entry.kind.rawValue)).font(.caption).foregroundStyle(.secondary)
                if !info.notes.isEmpty { Text(info.notes).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                HStack(spacing: 10) {
                    if !info.collection.isEmpty { Label(info.collection, systemImage: "folder").lineLimit(1) }
                    if library.documents.contains(where: { entry.isPlanned(in: $0) }) { Label("In your plans", systemImage: "checkmark.circle") }
                }.font(.caption2).foregroundStyle(Color.bronze)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.top, 6)
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
        .confirmationDialog("Remove this idea from your wishlist?", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove from wishlist", role: .destructive) { if let entry, store.removeFromWishlist(entry) { dismiss() } }.accessibilityIdentifier("wishlist-confirm-remove")
        } message: { Text("This also removes its bookmark. Plans you’ve already added to a trip will stay.") }
        .alert("Wishlist", isPresented: Binding(get: { store.wishlist.error != nil }, set: { if !$0 { store.wishlist.error = nil } })) { Button("OK") { store.wishlist.error = nil } } message: { Text(store.wishlist.error ?? "") }
    }
    private func content(_ entry: WishlistEntry) -> some View {
        let info = store.wishlist.info(entry.id)
        let trips = library.documents.filter { entry.isPlanned(in: $0) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(entry.kind.rawValue, systemImage: entry.kind.symbol).font(.subheadline).foregroundStyle(Color.bronze)
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
                if case .idea = entry.source {
                    if let url = validatedURL(entry.place.website) { Link(destination: url) { Label("Open saved link", systemImage: "arrow.up.right") }.font(.subheadline) }
                } else {
                    NavigationLink { sourceDetail(entry) } label: {
                        HStack { Text(entry.kind == .destinations ? "Explore this city" : "View place details"); Spacer(); Image(systemName: "arrow.up.right") }.font(.subheadline).padding(.vertical, 10)
                    }.accessibilityIdentifier("wishlist-source")
                }
                if !trips.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("In your plans").font(.headline)
                        ForEach(trips) { trip in
                            NavigationLink { JourneyDetailView(id: trip.id) } label: {
                                HStack { Label(trip.title, systemImage: "suitcase.rolling"); Spacer(); Image(systemName: "chevron.right") }.font(.subheadline)
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
                    Section("Your idea") {
                        TextField("Name or idea", text: $idea.name).accessibilityIdentifier("wishlist-name")
                        Picker("Type", selection: $idea.kind) { ForEach(WishlistKind.allCases) { Text($0.rawValue).tag($0) } }.accessibilityIdentifier("wishlist-kind")
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
                } header: { Text("Collection") } footer: { Text("Group ideas with names like Japan, Summer escapes or Family adventures. Leave blank to keep an idea unsorted.") }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("wishlist-editor-error") } }
            }.scrollContentBackground(.hidden).background(Color.canvas).scrollDismissesKeyboard(.interactively)
                .navigationTitle(entry == nil ? "Add an idea" : "Edit wishlist idea").navigationBarTitleDisplayMode(.inline)
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
                Section { Text(entry.title).font(.headline); Text("Choose a trip, then review the dates and details. Your wishlist idea stays saved.").font(.subheadline).foregroundStyle(.secondary) }
                Section("Your trips") {
                    ForEach(library.documents.sorted { $0.updatedAt > $1.updatedAt }) { trip in
                        Button { choose(trip.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(trip.title).foregroundStyle(.primary)
                                Text(entry.isPlanned(in: trip) ? "Already planned · Review details" : trip.routeLabel).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }.accessibilityIdentifier("wishlist-trip-" + trip.id.uuidString)
                    }
                    if library.documents.isEmpty { Text("No trips yet. Create one to give this idea a place in your plans.").foregroundStyle(.secondary) }
                    Button("Create a new trip", systemImage: "plus") { route = .create }.accessibilityIdentifier("wishlist-new-trip")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Add to a trip").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .sheet(item: $route, onDismiss: {
            if saved { store.showMessage("Saved to your trip"); dismiss() }
            else if let id = pending { pending = nil; if library.documents.first(where: { $0.id == id })?.stops.isEmpty == false { choose(id) } }
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
        guard var trip = library.documents.first(where: { $0.id == id }) else { error = "That trip is no longer available."; return }
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
