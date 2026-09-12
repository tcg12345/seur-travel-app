import SwiftUI
import MapKit

/// Global search begins with destinations and discovery, never rate criteria.
struct SearchView: View {
    @State private var hotels = false
    var body: some View {
        Group {
            if hotels { HotelNameSearchView(isGlobalSearch: true) }
            else { CityExplorerView(isGlobalSearch: true) }
        }.safeAreaInset(edge: .top, spacing: 0) {
            Picker("Search for", selection: $hotels) {
                Text("Destinations").tag(false)
                Text("Hotels").tag(true)
            }.pickerStyle(.segmented).padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 10)
                .background(StayStyle.background).accessibilityIdentifier("explore-search-scope")
        }.sensoryFeedback(.selection, trigger: hotels)
    }
}

struct CityExplorerView: View {
    var initialQuery = ""
    var initialInterest: ExploreInterest = .highlights
    var isGlobalSearch = false
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var region = "All regions"
    @State private var selected: ExploreCity?
    @State private var error: String?
    private var destinations: [CityBrowseRegion] {
        CityBrowseRegion.all.filter { query.isEmpty ? region == "All regions" || region == $0.name : true }
    }
    private var inspiration: [ExploreCity] { ["Tokyo", "Lisbon", "Rome"].compactMap { name in DestinationSuggestions.cities.first { $0.name == name } } }
    private func matches(_ city: ExploreCity) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (city.name + " " + city.country).foldedCityText.contains(query.foldedCityText)
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                if query.isEmpty {
                    if isGlobalSearch { discoveryLinks }
                    if !store.recentExploreCities.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Pick up where you left off").font(.subheadline.weight(.semibold))
                            ScrollView(.horizontal) {
                                HStack(spacing: 10) {
                                    ForEach(store.recentExploreCities.prefix(6)) { city in
                                        Button { selected = city } label: { Label(city.name, systemImage: "clock").font(.subheadline).padding(.horizontal, 15).padding(.vertical, 12).background(StayStyle.surface, in: .capsule) }.buttonStyle(StayPressStyle()).tint(.primary)
                                    }
                                }
                            }.scrollIndicators(.hidden)
                        }
                    }
                    if region == "All regions" {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Somewhere new").font(.title3.weight(.semibold))
                            ScrollView(.horizontal) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(inspiration) { city in
                                        VStack(alignment: .leading, spacing: 8) {
                                        Button { selected = city } label: {
                                            VStack(alignment: .leading, spacing: 10) {
                                                ExploreDestinationImage(city: city).frame(width: 218, height: 168).clipShape(.rect(cornerRadius: 18))
                                                HStack { VStack(alignment: .leading, spacing: 4) { Text(city.name).font(.headline); Text(city.country).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary) }
                                            }.frame(width: 218)
                                        }.buttonStyle(StayPressStyle()).tint(.primary).accessibilityIdentifier("explore-inspiration-" + city.name)
                                        ExplorePhotoCredit(city: city).frame(width: 218, alignment: .leading)
                                        }
                                    }
                                }
                            }.scrollIndicators(.hidden)
                        }
                    }
                }
                HStack {
                    Text(query.isEmpty ? "Explore cities" : "Destinations").font(.title3.weight(.semibold))
                    Spacer()
                    if query.isEmpty {
                        Menu { Picker("Region", selection: $region) { Text("All regions").tag("All regions"); ForEach(CityBrowseRegion.all) { Text($0.name).tag($0.name) } } } label: { HStack(spacing: 5) { Text(region); Image(systemName: "chevron.down").font(.caption2) }.font(.caption) }.tint(.secondary).accessibilityIdentifier("explore-city-region")
                    }
                }
                if !query.isEmpty && !destinations.flatMap(\.cities).contains(where: matches) {
                    Text("Choose a suggestion above to explore any city.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(destinations) { group in
                    let cities = group.cities.filter(matches)
                    if !cities.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.name).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 0) {
                                ForEach(cities) { city in
                                    Button { selected = city } label: {
                                        HStack { VStack(alignment: .leading, spacing: 5) { Text(city.name).font(.subheadline.weight(.semibold)); Text(city.country).font(.caption).foregroundStyle(.secondary) }; Spacer(minLength: 5); Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary) }
                                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading).contentShape(.rect).overlay(alignment: .bottom) { Divider().opacity(0.5) }
                                    }.buttonStyle(StayPressStyle()).tint(.primary).accessibilityIdentifier("explore-city-" + city.name)
                                }
                            }
                        }
                    }
                }
            }.padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 30)
        }.scrollDismissesKeyboard(.interactively).background(StayStyle.background)
            .safeAreaInset(edge: .top, spacing: 0) { searchBar }
            .navigationTitle(isGlobalSearch ? "Explore" : initialInterest == .highlights ? "Explore cities" : initialInterest.title).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                if isGlobalSearch { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "arrow.left") }.accessibilityLabel("Close search").accessibilityIdentifier("explore-search-close") } }
                ToolbarItem(placement: .topBarTrailing) { NavigationLink { SavedExplorePlacesView() } label: { Image(systemName: "bookmark") }.accessibilityLabel("Saved city discoveries") }
            }
            .navigationDestination(item: $selected) { city in
                CityGuideView(city: city, initialInterest: initialInterest)
            }
            .onAppear { if query.isEmpty { query = initialQuery } }
            .sensoryFeedback(.selection, trigger: selected?.id)
    }
    private var searchBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "magnifyingglass").font(.body).foregroundStyle(.secondary).padding(.top, 2)
            LocationAutocompleteField("Search cities and destinations", text: $query, kind: .city, identifier: "explore-city-query", onSelect: { selection in
                if let city = ExploreCity(selection) { selected = city; error = nil }
                else { error = "Choose a city suggestion to explore nearby places." }
            })
        }.padding(17).background(StayStyle.surface, in: .rect(cornerRadius: 19)).padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 12).background(StayStyle.background)
    }
    private var discoveryLinks: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                NavigationLink { CityExplorerView(initialInterest: .restaurants) } label: { Label("Dining", systemImage: "fork.knife") }.accessibilityIdentifier("explore-dining")
                NavigationLink { CityExplorerView(initialInterest: .attractions) } label: { Label("Things to do", systemImage: "sparkles") }.accessibilityIdentifier("explore-experiences")
                NavigationLink { GuideHubView() } label: { Label("Guides", systemImage: "book.closed") }.accessibilityIdentifier("explore-guides")
            }.font(.caption.weight(.medium)).buttonStyle(ExploreShortcutStyle())
        }.scrollIndicators(.hidden)
    }
}
private struct ExploreShortcutStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.padding(.horizontal, 15).padding(.vertical, 12).foregroundStyle(.primary).background(StayStyle.surface.opacity(configuration.isPressed ? 0.5 : 1), in: .capsule) }
}
struct ExploreDestinationImage: View {
    let city: ExploreCity
    var body: some View {
        GeometryReader { geometry in
            if let cover = BundledDestinationCover.cover(city: city.name + ", " + city.country) {
                Image(uiImage: cover.image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped().accessibilityLabel(city.name + ". " + cover.photo.attribution)
            } else {
                ZStack { StayStyle.surface; Image(systemName: "building.2.crop.circle").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityLabel(city.name)
            }
        }
    }
}

private struct ExplorePhotoCredit: View {
    let city: ExploreCity
    var body: some View {
        if let photo = BundledDestinationCover.cover(city: city.name + ", " + city.country)?.photo, let source = photo.sourceURL {
            Link(destination: source) {
                Text("Photo: " + (photo.authors.first?.name ?? "Photographer") + " · " + (photo.isPexels ? "Pexels" : "Wikimedia Commons"))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }.accessibilityLabel(photo.attribution)
        }
    }
}

struct CityGuideView: View {
    @Environment(TravelStore.self) private var store
    let city: ExploreCity
    @State private var model = CityExploreModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    init(city: ExploreCity, initialInterest: ExploreInterest = .highlights) {
        self.city = city
        self._interest = State(initialValue: initialInterest)
    }
    @State private var interest: ExploreInterest = .highlights
    @State private var query = ""
    @State private var sort: ExploreSort = .suggested
    @State private var wider = false
    @State private var savedOnly = false
    @State private var websiteOnly = false
    @State private var bookingHotel = false
    @State private var showInterests = false
    @State private var showFilters = false
    @State private var diningFilters = DiningSearchPreferences()
    @State private var adding: ExplorePlace?
    private var collection: [ExplorePlace] { ExplorePlace.collection(store.hotels, city: city) }
    private var savedPlaces: [ExplorePlace] { store.savedDiscoveries.filter { city.contains($0) } }
    private var savedIDs: Set<String> { Set(savedPlaces.map(\.id)) }
    private var visible: [ExplorePlace] {
        guard savedOnly else { return model.visible(sort: sort, savedOnly: false, websiteOnly: websiteOnly, savedIDs: savedIDs) }
        let places = savedPlaces.filter { place in
            (!(interest == .restaurants && diningFilters.active) || model.places.contains { $0.id == place.id }) && (interest == .highlights || place.record.category == interest.category) && (query.isEmpty || (place.record.name + " " + place.cuisine + " " + place.hotelName).localizedCaseInsensitiveContains(query)) && (!websiteOnly || validatedURL(place.record.website) != nil)
        }
        switch sort {
        case .suggested: return places
        case .name: return places.sorted { $0.record.name.localizedStandardCompare($1.record.name) == .orderedAscending }
        case .distance: return places.sorted { (city.distance(to: $0.record) ?? .infinity) < (city.distance(to: $1.record) ?? .infinity) }
        }
    }
    private var loadID: String { city.id + interest.id + diningFilters.searchTerm(query, interest: interest) + "\(wider)" }
    private var overview: Bool { interest == .highlights && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !savedOnly && !filtersActive }
    private var filtersActive: Bool { websiteOnly || wider || sort != .suggested || (interest == .restaurants && diningFilters.active) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                cityHeader
                searchControls
                if !collection.isEmpty && !diningFilters.active && query.isEmpty && [.highlights, .restaurants].contains(interest) && !savedOnly { diningCollection }
                if model.loading && (!savedOnly || (interest == .restaurants && diningFilters.active)) {
                    ProgressView("Finding places…").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 30).accessibilityIdentifier("city-loading")
                } else if overview {
                    ForEach(model.sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(section.interest.title).font(.headline)
                                Spacer()
                                Button("See all") { selectInterest(section.interest) }.font(.subheadline).accessibilityIdentifier("city-see-" + section.id)
                            }.padding(.bottom, 6)
                            if let error = section.error { retryRow(error) }
                            else if section.places.isEmpty { Text("No matches nearby. Try another category or a wider area.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12) }
                            ForEach(section.places.prefix(2)) { place in placeRow(place) }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(savedOnly ? "Saved places" : interest.title).font(.headline)
                            Spacer()
                            Text("\(visible.count) places").font(.caption).foregroundStyle(.secondary)
                        }.padding(.bottom, 6)
                        if !savedOnly, let error = model.sections.first(where: { $0.error != nil })?.error { retryRow(error) }
                        else if visible.isEmpty { emptyResults }
                        else { ForEach(visible) { place in placeRow(place) } }
                    }
                }
                Text("Places from Apple Maps. Confirm hours and availability with the venue.").font(.caption2).foregroundStyle(.secondary).padding(.top, 8)
            }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 30)
        }.scrollDismissesKeyboard(.interactively).background(StayStyle.background).navigationTitle("City guide").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                if !searchFocused {
                    hotelBookingLink.padding(.trailing, 22).padding(.top, 10).padding(.bottom, 12)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { store.toggleExploreCity(city) } label: { Image(systemName: store.isExploreCitySaved(city) ? "bookmark.fill" : "bookmark") }.accessibilityLabel(store.isExploreCitySaved(city) ? "Unsave city" : "Save city").accessibilityIdentifier("city-save") } }
            .task(id: loadID) { await load() }
            .onAppear { store.rememberExploreCity(city) }
            .refreshable { await load(refresh: true) }
            .navigationDestination(isPresented: $bookingHotel) { HotelBookingFlow(city: city) }
            .sensoryFeedback(.selection, trigger: bookingHotel)
            .sensoryFeedback(.selection, trigger: interest)
            .sensoryFeedback(.selection, trigger: savedOnly)
            .sheet(item: $adding) { ExploreAddToTripView(place: $0) }
            .sheet(isPresented: $showInterests) { interestsSheet }
            .sheet(isPresented: $showFilters) { filtersSheet }
    }
    private var hotelBookingLink: some View {
        Button { bookingHotel = true } label: {
            Label("Hotels", systemImage: "bed.double")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20).padding(.vertical, 17)
                .foregroundStyle(StayStyle.background)
                .background(Color.primary, in: .capsule)
                .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
        }.buttonStyle(StayPressStyle())
            .accessibilityLabel("Find a hotel in " + city.name)
            .accessibilityIdentifier("city-book-hotel")
    }
    private var cityHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                ExploreDestinationImage(city: city).frame(height: 190).clipShape(.rect(cornerRadius: 22))
                ExplorePhotoCredit(city: city)
            }
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: city.country.isEmpty ? "Explore" : city.country)
                Editorial(city.name, size: 32)
            }
            HStack(spacing: 10) {
                Button {
                    store.cityMapRequest = CityMapRequest(city: city, interest: interest, term: query, dining: diningFilters, sort: sort, wider: wider, savedOnly: savedOnly, websiteOnly: websiteOnly, places: visible)
                    store.searchPresented = false
                    store.selectedTab = 1
                } label: { Label("Open map", systemImage: "map").font(.subheadline.weight(.medium)).padding(.vertical, 6) }
                    .buttonStyle(.glass).disabled(model.loading && !savedOnly).accessibilityIdentifier("city-open-map")
                Button { withAnimation(StayStyle.motion(reduceMotion)) { savedOnly.toggle() } } label: { Label("Saved (\(savedPlaces.count))", systemImage: savedOnly ? "bookmark.fill" : "bookmark").font(.subheadline.weight(.medium)).padding(.vertical, 6) }
                    .buttonStyle(.glass).accessibilityIdentifier("city-saved-places").accessibilityValue(savedOnly ? "Selected" : "Not selected")
            }
            CityTemplateLink(city: city.name)
        }
    }
    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search places in \(city.name)", text: $query).submitLabel(.search).autocorrectionDisabled().accessibilityIdentifier("city-place-query").focused($searchFocused)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Clear city search") }
            }.padding(15).background(StayStyle.surface, in: .rect(cornerRadius: 16))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach([ExploreInterest.highlights, .restaurants, .attractions, .hotels]) { category in
                        Button { selectInterest(category) } label: {
                            Label(category.title, systemImage: category.symbol).font(.caption.weight(.medium)).fixedSize().padding(.horizontal, 14).frame(minHeight: 44)
                                .foregroundStyle(interest == category ? StayStyle.background : Color.primary)
                                .background(interest == category ? Color.primary : StayStyle.surface, in: .capsule)
                        }.buttonStyle(StayPressStyle()).accessibilityIdentifier("city-category-" + category.id).accessibilityAddTraits(interest == category ? .isSelected : [])
                    }
                }
            }.scrollIndicators(.hidden)
            HStack {
                categoryPicker
                Spacer()
                Button { showFilters = true } label: { Label(filtersActive ? "Filters •" : "Filters", systemImage: "slider.horizontal.3") }.font(.subheadline).accessibilityIdentifier("city-filters")
            }.frame(minHeight: 36).tint(.primary)
            if filtersActive {
                HStack(alignment: .top) {
                    Text([websiteOnly ? "Has website" : nil, wider ? "Wider city" : nil, sort != .suggested ? sort.rawValue : nil, interest == .restaurants && diningFilters.active ? diningFilters.summary : nil].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { websiteOnly = false; wider = false; sort = .suggested; diningFilters = DiningSearchPreferences() }.font(.caption).tint(.primary)
                }
            }
        }
    }
    private func selectInterest(_ value: ExploreInterest) {
        searchFocused = false
        withAnimation(StayStyle.motion(reduceMotion)) { interest = value }
    }
    private var categoryPicker: some View {
        Button { showInterests = true } label: {
            Label(interest == .highlights ? "All categories" : interest.title, systemImage: interest == .highlights ? "square.grid.2x2" : interest.symbol)
            Image(systemName: "chevron.down").font(.caption2)
        }.font(.subheadline.weight(.medium)).fixedSize().accessibilityIdentifier("city-all-interests")
    }
    private var diningCollection: some View {
        NavigationLink { CityDiningCollectionView(city: city) } label: {
            HStack(spacing: 12) {
                Image(systemName: "fork.knife").foregroundStyle(Color.bronze)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hotel dining collection").font(.subheadline.weight(.semibold)).foregroundStyle(.primary).accessibilityIdentifier("city-dining-collection")
                    Text("Restaurants, bars and cafés to discover").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.vertical, 12).contentShape(Rectangle())
                .overlay(alignment: .bottom) { Divider() }
        }.buttonStyle(.plain).accessibilityIdentifier("city-collection-all")
    }
    private func placeRow(_ place: ExplorePlace) -> some View {
        VStack(spacing: 0) {
            ExplorePlaceRow(place: place, add: { adding = place }, inset: false)
            Divider()
        }
    }
    private var emptyResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(savedOnly && savedPlaces.isEmpty ? "Build your city shortlist" : "No matching places").font(.headline)
            Text(savedOnly ? (savedPlaces.isEmpty ? "Tap the bookmark beside a place to save it here." : "No saved places match this search. Try another interest or reset your filters.") : "Try another category, change your search or explore a wider area.").font(.subheadline).foregroundStyle(.secondary)
            if savedOnly { Button("Browse places") { savedOnly = false; query = "" }.font(.subheadline) }
            else if !wider { Button("Search wider area") { wider = true }.font(.subheadline) }
        }.padding(.vertical, 20).accessibilityIdentifier("city-empty-results")
    }
    private func retryRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Button("Try again") { Task { await load(refresh: true) } }.font(.subheadline)
        }.padding(.vertical, 16)
    }
    private func load(refresh: Bool = false) async { await model.load(city: city, interest: interest, term: diningFilters.searchTerm(query, interest: interest), wider: wider, refresh: refresh) }
    private var interestsSheet: some View {
        NavigationStack {
            List { ForEach(ExploreInterest.allCases) { value in
                Button {
                    selectInterest(value)
                    showInterests = false
                } label: {
                    HStack { Label(value.title, systemImage: value.symbol).foregroundStyle(.primary); Spacer(); if interest == value { Image(systemName: "checkmark").foregroundStyle(Color.bronze) } }.padding(.vertical, 6)
                }.accessibilityIdentifier("city-choose-" + value.id)
            } }.navigationTitle("Choose a category").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showInterests = false } } }
        }
    }
    private var filtersSheet: some View {
        NavigationStack {
            Form {
                if interest == .restaurants { DiningFilterFields(preferences: $diningFilters) }
                Section("Results") {
                    Picker("Sort places", selection: $sort) { ForEach(ExploreSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Toggle("With a website", isOn: $websiteOnly)
                    Toggle("Explore the wider city", isOn: $wider)
                }
                Section { Text("Distances are measured from the city center.").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showFilters = false } } }
        }
    }
}

struct ExplorePlaceRow: View {
    @Environment(TravelStore.self) private var store
    let place: ExplorePlace
    var add: (() -> Void)?
    var inset = true
    var body: some View {
        HStack(spacing: 12) {
            NavigationLink { ExplorePlaceDetailView(place: place) } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: place.record.category.symbol).font(.system(size: 23, weight: .light)).foregroundStyle(Color.bronze).frame(width: 30, height: 44)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(place.record.name).font(.system(.headline, design: .serif)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        Text(place.isCollection ? place.hotelName : place.record.category.title).font(.caption).foregroundStyle(Color.bronze)
                        Text(place.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(.rect)
            }.buttonStyle(.plain).accessibilityIdentifier("explore-place-" + place.record.id)
            VStack(spacing: 10) {
                Button { store.toggleDiscovery(place) } label: { Image(systemName: store.isDiscoverySaved(place) ? "bookmark.fill" : "bookmark").frame(width: 34, height: 34) }.buttonStyle(.plain).accessibilityLabel(store.isDiscoverySaved(place) ? "Unsave " + place.record.name : "Save " + place.record.name)
                if let add { Button(action: add) { Image(systemName: "plus").frame(width: 34, height: 34) }.buttonStyle(.glass).accessibilityLabel("Add " + place.record.name + " to a trip") }
            }.foregroundStyle(Color.bronze)
        }.padding(.horizontal, inset ? 17 : 0).padding(.vertical, 14)
            .cardSurface(cornerRadius: 24, enabled: inset)
    }
}

struct CityDiningCollectionView: View {
    @Environment(TravelStore.self) private var store
    let city: ExploreCity
    @State private var query = ""
    @State private var cuisine = "All cuisines"
    @State private var limit = 30
    @State private var adding: ExplorePlace?
    private var places: [ExplorePlace] { ExplorePlace.collection(store.hotels, city: city) }
    private var cuisines: [String] { Array(Set(places.map(\.cuisine).filter { !$0.isEmpty })).sorted() }
    private var filtered: [ExplorePlace] { places.filter { (cuisine == "All cuisines" || $0.cuisine == cuisine) && (query.isEmpty || [$0.record.name, $0.hotelName, $0.cuisine].joined(separator: " ").localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 15) {
            Eyebrow(text: city.name + " · Hotel dining"); Editorial("Find your\nkind of table.", size: 37)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.bronze)
                TextField("Restaurant, hotel, or cuisine", text: $query).autocorrectionDisabled().submitLabel(.search).accessibilityIdentifier("city-collection-query")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear collection search") }
            }.padding(17).cardSurface(cornerRadius: 22)
            Picker("Cuisine", selection: $cuisine) { Text("All cuisines").tag("All cuisines"); ForEach(cuisines, id: \.self) { Text($0).tag($0) } }.tint(.bronze)
            Text("\(filtered.count) venues in the hotel dining collection").font(.caption).foregroundStyle(.secondary)
            ForEach(filtered.prefix(limit)) { place in ExplorePlaceRow(place: place, add: { adding = place }) }
            if filtered.count > limit { Button("Show more tables") { limit += 30 }.buttonStyle(.glass).frame(maxWidth: .infinity) }
            if filtered.isEmpty { ContentUnavailableView.search(text: query) }
        }.padding(22) }.background(Color.canvas).navigationTitle("The dining collection").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively).onChange(of: query) { limit = 30 }.onChange(of: cuisine) { limit = 30 }.sheet(item: $adding) { ExploreAddToTripView(place: $0) }
    }
}

struct ExplorePlaceDetailView: View {
    @Environment(TravelStore.self) private var store
    @State var place: ExplorePlace
    @State private var adding = false
    @State private var compactAdd = false
    @State private var locating = false
    private var hotel: Hotel? { store.hotels.first { $0.id == place.hotelID } }
    private var mapQuery: URL { TravelPlaceActions.directions(place.record) ?? URL(string: "maps://")! }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                if let hotel, hotel.image != nil {
                    HotelPhoto(hotel: hotel).frame(height: 235).clipShape(.rect(cornerRadius: 28)).overlay(alignment: .bottomLeading) { Text("At \(hotel.name) · Hotel exterior").font(.caption2).padding(11).glassEffect(.regular, in: .capsule).padding(12) }
                } else if place.record.hasCoordinate {
                    JourneyMapView(places: [place.record]).frame(height: 250).clipShape(.rect(cornerRadius: 27))
                } else {
                    ZStack { Color.bronze.opacity(0.08); Image(systemName: place.record.category.symbol).font(.system(size: 65, weight: .ultraLight)).foregroundStyle(Color.bronze) }.frame(height: 175).clipShape(.rect(cornerRadius: 28))
                }
                VStack(alignment: .leading, spacing: 13) {
                    Eyebrow(text: place.city.name + " · " + place.record.category.title)
                    Editorial(place.record.name, size: 37).accessibilityIdentifier("explore-place-title")
                    if place.isCollection { Text("At " + place.hotelName).font(.title3).foregroundStyle(.secondary) }
                    if !place.cuisine.isEmpty || !place.priceBand.isEmpty { Text([place.cuisine, place.priceBand].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(Color.bronze) }
                    if let rating = place.record.rating { Label(String(format: "%.1f / 5", rating) + " · " + place.record.source, systemImage: "star.fill").font(.subheadline).foregroundStyle(Color.bronze) }
                }
                HStack(spacing: 10) {
                    Button(action: openMaps) { Label("Directions", systemImage: "location").frame(maxWidth: .infinity).padding(.vertical, 10) }.buttonStyle(.glass)
                    if let url = validatedURL(place.record.website) { Link(destination: url) { Label(place.isCollection ? "Hotel site" : "Website", systemImage: "globe").frame(maxWidth: .infinity).padding(.vertical, 10) }.buttonStyle(.glass) }
                }.font(.subheadline)
                TripadvisorDetailsLink(place: place.record)
                if !place.record.overview.isEmpty { VStack(alignment: .leading, spacing: 12) { SectionHeading(title: "A little more to discover"); Text(place.record.overview).font(.body).foregroundStyle(.secondary).lineSpacing(5) } }
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "The useful details")
                    detail("Location", value: place.record.address.isEmpty ? place.city.name : place.record.address, symbol: "mappin.and.ellipse")
                    if !place.venueLocation.isEmpty { detail("Within the hotel", value: place.venueLocation, symbol: "building.2") }
                    if !place.record.phone.isEmpty { detail("Phone", value: place.record.phone, symbol: "phone"); if let url = URL(string: "tel:" + place.record.phone.filter { $0.isNumber || $0 == "+" }) { Link("Call this place", destination: url).font(.subheadline) } }
                    if locating { Label("Finding the hotel’s map position…", systemImage: "location.magnifyingglass").font(.caption).foregroundStyle(.secondary) }
                    if place.record.hasCoordinate { Label(place.isCollection ? "Mapped at the hotel’s address" : "Ready for your trip map", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Color.bronze) }
                    else if !locating { Text("A precise map pin isn’t available yet. Directions can search for this address in Maps.").font(.caption).foregroundStyle(.secondary) }
                }.padding(22).cardSurface(cornerRadius: 26)
                if let hotel { VStack(alignment: .leading, spacing: 14) { SectionHeading(title: "Make a stay of it"); NavigationLink { HotelDetailView(hotel: hotel) } label: { HotelRow(hotel: hotel) }.buttonStyle(PressStyle()) } }
                VStack(alignment: .leading, spacing: 10) {
                    Text(place.record.source).font(.caption.weight(.medium)).foregroundStyle(Color.bronze)
                    Text(place.isCollection ? "Dining details come from the supplied hotel collection. Check the hotel’s current menus, hours and availability. A map pin identifies the hotel address." : "Location and available contact details are supplied by Apple Maps. Check directly for opening hours, tickets and reservations.").font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(.bottom, 16)
            }.padding(22)
        }.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            if offset > 80 { compactAdd = true } else if offset < 24 { compactAdd = false }
        }.background(Color.canvas).navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { store.toggleDiscovery(place) } label: { Image(systemName: store.isDiscoverySaved(place) ? "bookmark.fill" : "bookmark") }.accessibilityLabel(store.isDiscoverySaved(place) ? "Unsave place" : "Save place").accessibilityIdentifier("explore-place-save") }
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: "\(place.record.name)\n\(place.subtitle)\n\(place.record.website.isEmpty ? mapQuery.absoluteString : place.record.website)") { Image(systemName: "square.and.arrow.up") } }
            }
            .safeAreaInset(edge: .bottom) {
                PlaceTripAction(title: "Add to trip", compact: compactAdd, identifier: "explore-add-trip") { adding = true }
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 20).frame(height: 70)
            }
            .sheet(isPresented: $adding) { ExploreAddToTripView(place: place) }
            .task { if place.isCollection && !place.record.hasCoordinate { locating = true; place = await CityExploreSearch.locateCollection(place); store.refreshSavedDiscovery(place); locating = false } }
    }
    private func detail(_ title: String, value: String, symbol: String) -> some View { HStack(alignment: .top, spacing: 13) { Image(systemName: symbol).foregroundStyle(Color.bronze).frame(width: 23); VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline).textSelection(.enabled) } } }
    private func openMaps() {
        if place.record.hasCoordinate { let item = MKMapItem(location: CLLocation(latitude: place.record.latitude!, longitude: place.record.longitude!), address: nil); item.name = place.record.name; item.openInMaps() }
        else { UIApplication.shared.open(mapQuery) }
    }
}

struct ExploreAddToTripView: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State var place: ExplorePlace
    @State private var query = ""
    @State private var journal = false
    @State private var editor: Editor?
    @State private var saved = false
    @State private var pending: UUID?
    @State private var locating = false
    @State private var error: String?
    private enum Editor: Identifiable {
        case event(UUID, JourneyEvent), hotel(UUID, HotelReservation), journal(UUID, RatedPlace), destination(UUID), create
        var id: String { switch self { case .event(let id, _): "event-\(id)"; case .hotel(let id, _): "hotel-\(id)"; case .journal(let id, _): "journal-\(id)"; case .destination(let id): "destination-\(id)"; case .create: "create" } }
    }
    private var trips: [JourneyDocument] {
        library.trips.filter { query.isEmpty || ($0.title + " " + $0.routeLabel).localizedCaseInsensitiveContains(query) }.sorted {
            let a = $0.routeLabel.localizedCaseInsensitiveContains(place.city.name), b = $1.routeLabel.localizedCaseInsensitiveContains(place.city.name)
            return a == b ? $0.updatedAt > $1.updatedAt : a
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 9) { Eyebrow(text: place.city.name); Editorial("A place in\nyour plans.", size: 35); Text(place.record.name).font(.subheadline).foregroundStyle(.secondary) }
                    Picker("Add as", selection: $journal) { Text(place.record.category == .hotel ? "Hotel stay" : "Plan a visit").tag(false); Text("Log a visit").tag(true) }.pickerStyle(.segmented).accessibilityIdentifier("explore-trip-mode")
                    Text(journal ? "Keep a memory, add photos and rate your visit." : place.record.category == .hotel ? "Choose a trip, then add your stay dates and booking details." : "Choose a trip, then set the day, time and any little details.").font(.subheadline).foregroundStyle(.secondary)
                    if locating { HStack { ProgressView(); Text("Locating the hotel address…").font(.caption) } }
                    TextField("Find an existing trip", text: $query).padding(16).cardSurface(cornerRadius: 19).accessibilityIdentifier("explore-trip-query")
                    ForEach(trips) { trip in
                        Button { choose(trip.id) } label: {
                            HStack(spacing: 15) { Image(systemName: "suitcase.rolling").font(.title2.weight(.light)).foregroundStyle(Color.bronze); VStack(alignment: .leading, spacing: 7) { Text(trip.title).font(.system(.headline, design: .serif)).foregroundStyle(.primary); Text(trip.routeLabel.isEmpty ? "Destination to come" : trip.routeLabel).font(.caption).foregroundStyle(.secondary); if let start = trip.startDate { Text(TravelDay.label(start) + (trip.endDate.map { " – " + TravelDay.label($0) } ?? "")).font(.caption2).foregroundStyle(Color.bronze) } }; Spacer() }.padding(19).cardSurface(cornerRadius: 23)
                        }.buttonStyle(PressStyle()).disabled(locating).accessibilityIdentifier("explore-trip-" + trip.id.uuidString)
                    }
                    if trips.isEmpty { Text(library.trips.isEmpty ? "Create your first trip, then choose when you’ll visit." : "No trips match that search.").font(.subheadline).foregroundStyle(.secondary) }
                    Button { editor = .create } label: { Label("Create a new trip", systemImage: "plus").frame(maxWidth: .infinity).padding(12) }.buttonStyle(.glass)
                    if let error { Text(error).foregroundStyle(.red).font(.subheadline) }
                }.padding(24)
            }.background(Color.canvas).navigationTitle("Add to a trip").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .task { if place.isCollection && !place.record.hasCoordinate { locating = true; place = await CityExploreSearch.locateCollection(place); locating = false } }
        .sheet(item: $editor, onDismiss: {
            if saved { dismiss() }
            else if let id = pending { pending = nil; if library.documents.first(where: { $0.id == id })?.stops.isEmpty == false { choose(id) } }
        }) { editor in
            switch editor {
            case .event(let id, let event): JourneyEventEditor(documentID: id, event: event, onSaved: { saved = true })
            case .hotel(let id, let hotel): HotelReservationEditor(documentID: id, reservation: hotel, onSaved: { saved = true })
            case .journal(let id, let rated): RatedPlaceEditor(documentID: id, rated: rated, onSaved: { saved = true })
            case .destination(let id): AddTripDestinationView(documentID: id, fallbackDestination: place.city.name)
            case .create: TripCreationView()
            }
        }
    }
    private func choose(_ id: UUID) {
        guard var trip = library.documents.first(where: { $0.id == id }) else { return }
        saved = false
        if journal {
            editor = .journal(id, trip.places.first(where: { $0.place.id == place.record.id && $0.place.source == place.record.source }) ?? RatedPlace(place: place.record)); return
        }
        if trip.preparePlanningRoute(), !library.save(trip) { error = library.error; return }
        if place.record.category == .hotel {
            let stop = trip.stops.first(where: { $0.name.localizedCaseInsensitiveContains(place.city.name) }) ?? trip.stops.first
            var hotel = HotelReservation(place: place.record)
            hotel.checkIn = stop?.arrival ?? trip.startDate ?? hotel.checkIn
            hotel.checkOut = stop?.departure ?? trip.endDate ?? TravelDay.adding(3, to: hotel.checkIn)
            if hotel.checkOut <= hotel.checkIn { hotel.checkOut = TravelDay.adding(1, to: hotel.checkIn) }
            editor = .hotel(id, hotel); return
        }
        guard let stop = trip.stops.first(where: { $0.name.localizedCaseInsensitiveContains(place.city.name) }) ?? trip.stops.first else { pending = id; editor = .destination(id); return }
        editor = .event(id, JourneyEvent(stopID: stop.id, place: place.record, kind: .place))
    }
}

struct SavedExplorePlacesView: View {
    @Environment(TravelStore.self) private var store
    @State private var query = ""
    @State private var category: PlaceCategory?
    @State private var adding: ExplorePlace?
    private var places: [ExplorePlace] { store.savedDiscoveries.filter { (category == nil || $0.record.category == category) && (query.isEmpty || ($0.record.name + " " + $0.city.name + " " + $0.hotelName).localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "Your city collection"); Editorial("Keep the\npossibilities close.", size: 37)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.bronze)
                    TextField("Place, city, or hotel", text: $query).autocorrectionDisabled().submitLabel(.search).accessibilityIdentifier("saved-discoveries-query")
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear saved search") }
                }.padding(17).cardSurface(cornerRadius: 22)
                if !store.savedExploreCities.isEmpty {
                    SectionHeading(title: "Cities on your mind")
                    ScrollView(.horizontal) { HStack(spacing: 12) { ForEach(store.savedExploreCities) { city in NavigationLink { CityGuideView(city: city) } label: { VStack(alignment: .leading, spacing: 8) { Image(systemName: "globe").foregroundStyle(Color.bronze); Text(city.name).font(.system(.title3, design: .serif)).foregroundStyle(.primary); Text(city.country).font(.caption).foregroundStyle(.secondary) }.padding(18).cardSurface(cornerRadius: 22) }.buttonStyle(PressStyle()) } } }.scrollIndicators(.hidden)
                }
                HStack { SectionHeading(title: "Saved discoveries"); Menu { Button("All interests") { category = nil }; ForEach(PlaceCategory.allCases) { value in Button(value.title) { category = value } } } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 40, height: 40) }.buttonStyle(.glass).accessibilityLabel("Filter saved discoveries") }
                if let category { Text(category.title).font(.caption).foregroundStyle(Color.bronze) }
                ForEach(places) { place in ExplorePlaceRow(place: place, add: { adding = place }) }
                if places.isEmpty { ContentUnavailableView("Room for discovery", systemImage: "bookmark", description: Text("Save places from any city to keep them here. Try clearing your filters if something is missing.")) }
                NavigationLink("Explore another city") { CityExplorerView() }.buttonStyle(.glass).frame(maxWidth: .infinity)
            }.padding(22)
        }.background(Color.canvas).navigationTitle("City collection").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively).sheet(item: $adding) { ExploreAddToTripView(place: $0) }
    }
}

struct DiningFilterFields: View {
    @Binding var preferences: DiningSearchPreferences
    var body: some View {
        Section {
            Picker("Cuisine", selection: $preferences.cuisine) {
                ForEach(DiningSearchPreferences.cuisines, id: \.self) { Text($0).tag($0) }
            }.accessibilityIdentifier("explore-filter-cuisine")
            Picker("Price preference", selection: $preferences.price) {
                ForEach(DiningPricePreference.allCases) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("explore-filter-price")
        } header: { Text("Your table") } footer: {
            Text("Price and cuisine refine your restaurant search. Menu prices vary; confirm current prices with the restaurant.")
        }
    }
}

struct PlaceTripAction: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var title: String
    var compact: Bool
    var identifier: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.title3.weight(.medium)).frame(width: 22)
                if !compact { Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).transition(.opacity) }
            }.padding(.horizontal, compact ? 16 : 20).frame(height: 54).contentShape(Capsule())
        }.buttonStyle(.glassProminent).buttonBorderShape(.capsule)
            .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: compact)
            .accessibilityLabel(title).accessibilityValue(compact ? "Compact" : "Expanded").accessibilityIdentifier(identifier)
    }
}

/// Provider content stays in this temporary view. Saving a place or adding it to
/// a trip continues to use the original Apple Maps/collection record.
struct TripadvisorDetailsLink: View {
    let place: PlaceRecord
    var body: some View {
        NavigationLink { TripadvisorPlaceView(place: place) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ratings & more details").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text("Look up this place on Tripadvisor").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.vertical, 12).contentShape(.rect)
        }.buttonStyle(.plain).accessibilityIdentifier("place-tripadvisor-details")
    }
}

private struct TripadvisorBrand: View {
    var body: some View {
        Image("TripadvisorLogo").resizable().scaledToFit().frame(width: 140, height: 30)
            .padding(8).background(.white, in: .rect(cornerRadius: 8))
            .accessibilityLabel("Tripadvisor")
    }
}

private struct TripadvisorPlaceView: View {
    @Environment(TravelAPI.self) private var api
    let place: PlaceRecord
    @State private var matches: [PlaceRecord]?
    @State private var loading = false
    @State private var error: String?
    @State private var attempt = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(place.name).font(.title2.weight(.semibold))
                if !api.isSignedIn {
                    Text("Sign in to look up ratings and details. You can keep using Apple Maps without an account.").foregroundStyle(.secondary)
                    NavigationLink("Sign in") { TravelAccountView() }.buttonStyle(.glass)
                } else {
                    TripadvisorBrand()
                    Text("Choose the matching place. Check the address before opening its details.").font(.subheadline).foregroundStyle(.secondary)
                    if loading { ProgressView("Finding this place…") }
                    if let error {
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { attempt += 1 }.buttonStyle(.glass).disabled(loading)
                    }
                    if let matches {
                        if matches.isEmpty { Text("No matching places found. Apple Maps details are still available on the previous page.").foregroundStyle(.secondary) }
                        ForEach(matches) { match in
                            NavigationLink { TripadvisorRecordView(placeID: match.id) } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(match.name).font(.headline).foregroundStyle(.primary)
                                        Text(match.address).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }.padding(.vertical, 12).contentShape(.rect)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }.background(Color.canvas).navigationTitle("Place details").navigationBarTitleDisplayMode(.inline)
            .task(id: "\(api.isSignedIn)-\(attempt)") {
                guard api.isSignedIn, matches == nil else { return }
                loading = true; error = nil
                defer { loading = false }
                do {
                    let query = String((place.name + " " + (place.city.isEmpty ? place.address : place.city)).prefix(200))
                    let result = try await api.searchPlaces(query, category: place.category)
                    try Task.checkCancellation(); matches = result
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
    }
}

private struct TripadvisorRecordView: View {
    @Environment(TravelAPI.self) private var api
    let placeID: String
    @State private var detail: PlaceRecord?
    @State private var error: String?
    @State private var attempt = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TripadvisorBrand()
                if let detail {
                    Text(detail.name).font(.title2.weight(.semibold))
                    Text(detail.address).font(.subheadline).foregroundStyle(.secondary)
                    if let rating = detail.rating, let imageURL = validatedURL(detail.ratingImageURL ?? "") {
                        AsyncImage(url: imageURL) { image in
                            image.resizable().scaledToFit().frame(width: 110, height: 24)
                                .padding(8).background(.white, in: .rect(cornerRadius: 6))
                                .accessibilityLabel(String(format: "Tripadvisor rating %.1f out of 5", rating))
                        } placeholder: { EmptyView() }
                    }
                    if !detail.overview.isEmpty { Text(detail.overview).font(.body).foregroundStyle(.secondary).lineSpacing(4) }
                    if !detail.phone.isEmpty { Label(detail.phone, systemImage: "phone").font(.subheadline).textSelection(.enabled) }
                    if let website = validatedURL(detail.website) { Link("Visit website", destination: website) }
                    if let source = validatedURL(detail.sourceURL ?? "") { Link("Read reviews on Tripadvisor", destination: source).font(.subheadline.weight(.semibold)) }
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try again") { attempt += 1 }.buttonStyle(.glass)
                } else { ProgressView("Loading details…") }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }.background(Color.canvas).navigationTitle("Tripadvisor").navigationBarTitleDisplayMode(.inline)
            .task(id: attempt) {
                guard detail == nil else { return }
                error = nil
                do { let result = try await api.placeDetails(placeID); try Task.checkCancellation(); detail = result }
                catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
    }
}
