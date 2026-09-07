import SwiftUI
import MapKit

struct CityExplorerView: View {
    var initialQuery = ""
    @Environment(TravelStore.self) private var store
    @State private var query = ""
    @State private var selected: ExploreCity?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Cities, without boundaries")
                    Editorial("The world,\nat your pace.", size: 42)
                    Text("A remarkable table. A quiet garden. Something you didn’t know you were looking for.").font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Label("Where shall we wander?", systemImage: "globe.europe.africa").font(.subheadline.weight(.medium)).foregroundStyle(Color.bronze)
                    LocationAutocompleteField("Search any city in the world", text: $query, kind: .city, identifier: "explore-city-query", onSelect: { selection in
                        if let city = ExploreCity(selection) { selected = city; error = nil } else { error = "Choose a city suggestion so we can find places around it." }
                    }).padding(15).background(Color.canvas, in: .rect(cornerRadius: 17))
                    Text("Start typing and choose a city. You’re free to explore beyond our hotel collection.").font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(20).background(Color.cardSurface, in: .rect(cornerRadius: 27))
                if !store.recentExploreCities.isEmpty {
                    SectionHeading(title: "Pick up where you left off")
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) { ForEach(store.recentExploreCities.prefix(8)) { city in
                            Button { selected = city } label: { VStack(alignment: .leading, spacing: 7) { Text(city.name).font(.system(.title3, design: .serif)); Text(city.country).font(.caption).foregroundStyle(.secondary) }.frame(minWidth: 125, alignment: .leading).padding(18).background(Color.cardSurface, in: .rect(cornerRadius: 22)) }.buttonStyle(PressStyle())
                        } }
                    }.scrollIndicators(.hidden)
                }
                SectionHeading(title: "A taste of our collection", subtitle: "Start with hotel dining. Stay for everything else.")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(ExploreCity.collection) { city in
                        Button { selected = city } label: {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack { Image(systemName: "building.2").font(.title2.weight(.ultraLight)); Spacer(); Image(systemName: "arrow.up.right").font(.caption) }.foregroundStyle(Color.bronze)
                                VStack(alignment: .leading, spacing: 6) { Text(city.name).font(.system(.title3, design: .serif)).foregroundStyle(.primary); Text(city.country).font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, minHeight: 92, alignment: .leading).padding(18).background(Color.cardSurface, in: .rect(cornerRadius: 24))
                        }.buttonStyle(PressStyle()).accessibilityIdentifier("explore-city-" + city.name)
                    }
                }
            }.padding(22).padding(.bottom, 25)
        }.scrollDismissesKeyboard(.interactively).background(Color.canvas).navigationTitle("Explore cities").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { SavedExplorePlacesView() } label: { Image(systemName: "bookmark") }.accessibilityLabel("Saved city discoveries") } }
            .navigationDestination(item: $selected) { CityGuideView(city: $0) }
            .onAppear { if query.isEmpty { query = initialQuery } }
    }
}

struct CityGuideView: View {
    @Environment(TravelStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let city: ExploreCity
    @State private var model = CityExploreModel()
    @State private var interest: ExploreInterest = .highlights
    @State private var query = ""
    @State private var mode = "List"
    @State private var sort: ExploreSort = .suggested
    @State private var wider = false
    @State private var savedOnly = false
    @State private var websiteOnly = false
    @State private var showInterests = false
    @State private var showFilters = false
    @State private var adding: ExplorePlace?
    @State private var selectedPin: String?
    private var collection: [ExplorePlace] { ExplorePlace.collection(store.hotels, city: city) }
    private var savedIDs: Set<String> { Set(store.savedDiscoveries.map(\.id)) }
    private var visible: [ExplorePlace] {
        guard savedOnly else { return model.visible(sort: sort, savedOnly: false, websiteOnly: websiteOnly, savedIDs: savedIDs) }
        let places = store.savedDiscoveries.filter { place in
            let sameCity = place.city.id == city.id || (place.city.name.foldedCityText == city.name.foldedCityText && CLLocation(latitude: city.latitude, longitude: city.longitude).distance(from: CLLocation(latitude: place.city.latitude, longitude: place.city.longitude)) < 70_000)
            return sameCity && (interest == .highlights || place.record.category == interest.category) && (query.isEmpty || (place.record.name + " " + place.cuisine + " " + place.hotelName).localizedCaseInsensitiveContains(query)) && (!websiteOnly || validatedURL(place.record.website) != nil)
        }
        switch sort {
        case .suggested: return places
        case .name: return places.sorted { $0.record.name.localizedStandardCompare($1.record.name) == .orderedAscending }
        case .distance: return places.sorted { (city.distance(to: $0.record) ?? .infinity) < (city.distance(to: $1.record) ?? .infinity) }
        }
    }
    private var mapped: [ExplorePlace] { visible.filter { $0.record.hasCoordinate } }
    private var loadID: String { city.id + interest.id + query + "\(wider)" }
    private var overview: Bool { interest == .highlights && query.isEmpty && !savedOnly && !websiteOnly && sort == .suggested }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                cityHeader
                searchControls
                if !collection.isEmpty && query.isEmpty && [.highlights, .restaurants, .bars, .cafes].contains(interest) && !savedOnly && mode == "List" { diningCollection }
                HStack(alignment: .firstTextBaseline) {
                    SectionHeading(title: query.isEmpty ? (interest == .highlights ? "Follow your curiosity" : interest.title) : "Your city, your way", subtitle: wider ? "Across the wider city" : "In and around \(city.name)")
                    Picker("Explore view", selection: $mode) { Image(systemName: "list.bullet").accessibilityLabel("List").tag("List"); Image(systemName: "map").accessibilityLabel("Map").tag("Map") }.pickerStyle(.segmented).frame(width: 104).accessibilityIdentifier("city-results-view")
                }
                if model.loading && !savedOnly { VStack(spacing: 13) { ProgressView(); Text("Finding places in \(city.name)…").font(.subheadline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(38).accessibilityIdentifier("city-loading") }
                else if mode == "Map" { mapResults }
                else if overview {
                    ForEach(model.sections) { section in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { VStack(alignment: .leading, spacing: 5) { Label(section.interest.title, systemImage: section.interest.symbol).font(.headline); Text(section.interest.subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("See all") { interest = section.interest }.font(.subheadline).accessibilityIdentifier("city-see-" + section.id) }
                            if let error = section.error { retryCard(error) }
                            else if section.places.isEmpty { Text("No matches nearby. Try searching by name or explore a wider area.").font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(section.places.prefix(3)) { place in ExplorePlaceRow(place: place, add: { adding = place }) }
                        }
                    }
                } else {
                    if !savedOnly, let error = model.sections.first(where: { $0.error != nil })?.error { retryCard(error) }
                    else if visible.isEmpty { emptyResults }
                    else { Text("\(visible.count) places to explore").font(.caption).foregroundStyle(.secondary); LazyVStack(spacing: 12) { ForEach(visible) { place in ExplorePlaceRow(place: place, add: { adding = place }) } } }
                }
                Text("Live places and map details from Apple Maps. Results depend on local coverage. Opening hours, tickets and reservations are confirmed with each place.").font(.caption2).foregroundStyle(.secondary).lineSpacing(3).padding(.top, 12)
            }.padding(22).padding(.bottom, 25)
        }.scrollDismissesKeyboard(.interactively).background(Color.canvas).navigationTitle(city.name).navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { store.toggleExploreCity(city) } label: { Image(systemName: store.isExploreCitySaved(city) ? "bookmark.fill" : "bookmark") }.accessibilityLabel(store.isExploreCitySaved(city) ? "Unsave city" : "Save city").accessibilityIdentifier("city-save") } }
            .task(id: loadID) { await model.load(city: city, interest: interest, term: query, wider: wider) }
            .onAppear { store.rememberExploreCity(city) }
            .refreshable { await model.load(city: city, interest: interest, term: query, wider: wider, refresh: true) }
            .sheet(item: $adding) { ExploreAddToTripView(place: $0) }
            .sheet(isPresented: $showInterests) { interestsSheet }
            .sheet(isPresented: $showFilters) { filtersSheet }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: mode)
    }
    private var cityHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) { Eyebrow(text: city.country.isEmpty ? "Your city guide" : city.country); Editorial(city.name + ",\nyour way.", size: 40) }
                Spacer()
                Image(systemName: "location.north.circle").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(Color.bronze).padding(.top, 12)
            }
            Map(initialPosition: .region(city.region), interactionModes: []) { }.mapStyle(.standard(pointsOfInterest: .excludingAll)).frame(height: 160).clipShape(.rect(cornerRadius: 25)).allowsHitTesting(false).accessibilityLabel("Map of " + city.name)
            Text("Find a table, follow a little curiosity, and make room for something unexpected.").font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
        }.accessibilityIdentifier("city-guide-header")
    }
    private var searchControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.bronze)
                TextField("Search this city", text: $query).submitLabel(.search).autocorrectionDisabled().accessibilityIdentifier("city-place-query")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Clear city search") }
                Button { showFilters = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Filter city places").accessibilityIdentifier("city-filters")
            }.padding(17).background(Color.cardSurface, in: .rect(cornerRadius: 22))
            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { ForEach(ExploreInterest.allCases.prefix(7)) { value in interestChip(value) } }.padding(.vertical, 3)
                }.scrollIndicators(.hidden)
                Button { showInterests = true } label: { Image(systemName: "square.grid.2x2").frame(width: 44, height: 44) }.buttonStyle(.glass).accessibilityLabel("All interests").accessibilityIdentifier("city-all-interests")
            }
            if savedOnly || websiteOnly || wider {
                HStack { Text([savedOnly ? "Saved places" : nil, websiteOnly ? "Has website" : nil, wider ? "Wider city" : nil].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Reset") { savedOnly = false; websiteOnly = false; wider = false; sort = .suggested }.font(.caption) }
            }
        }
    }
    private func interestChip(_ value: ExploreInterest) -> some View {
        Button { interest = value } label: { Label(value.title, systemImage: value.symbol).font(.subheadline.weight(interest == value ? .semibold : .regular)).padding(.horizontal, 16).padding(.vertical, 12).foregroundStyle(interest == value ? .white : .primary).background(interest == value ? Color.bronze : Color.cardSurface, in: .capsule) }.buttonStyle(PressStyle()).accessibilityIdentifier("city-interest-" + value.id).accessibilityAddTraits(interest == value ? .isSelected : [])
    }
    private var diningCollection: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) { VStack(alignment: .leading, spacing: 9) { Eyebrow(text: "The Aurum dining collection").accessibilityIdentifier("city-dining-collection"); Editorial("Extraordinary tables.\nExceptional addresses.", size: 29) }; Spacer(); Image(systemName: "fork.knife.circle").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Color.bronze) }
            Text("\(collection.count) dining venues at \(Set(collection.compactMap(\.hotelID)).count) hotels in \(city.name).").font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 12) { ForEach(collection.prefix(12)) { place in
                    NavigationLink { ExplorePlaceDetailView(place: place) } label: {
                        VStack(alignment: .leading, spacing: 13) {
                            Text(place.cuisine.isEmpty ? "HOTEL DINING" : place.cuisine.uppercased()).font(.caption2.weight(.medium)).tracking(1).foregroundStyle(Color.bronze).lineLimit(2)
                            Text(place.record.name).font(.system(.title3, design: .serif)).foregroundStyle(.primary).lineLimit(2)
                            Text(place.hotelName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            HStack { Text(place.priceBand.isEmpty ? "Discover the table" : place.priceBand).lineLimit(1); Spacer(); Image(systemName: "arrow.up.right") }.font(.caption).foregroundStyle(Color.bronze)
                        }.frame(width: 222, height: 148, alignment: .topLeading).padding(19).background(Color.cardSurface, in: .rect(cornerRadius: 23))
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("city-collection-" + place.record.id)
                } }
            }.scrollIndicators(.hidden)
            NavigationLink { CityDiningCollectionView(city: city) } label: { HStack { Text("Explore the full dining collection"); Spacer(); Image(systemName: "arrow.right") }.font(.subheadline.weight(.medium)).padding(.vertical, 4) }.accessibilityIdentifier("city-collection-all")
        }.padding(20).background(Color.bronze.opacity(0.075), in: .rect(cornerRadius: 29))
    }
    private var mapResults: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !savedOnly, let error = model.sections.first(where: { $0.error != nil })?.error { retryCard(error) }
            if visible.isEmpty { emptyResults }
            else {
                Map(initialPosition: .region(city.region), selection: $selectedPin) { ForEach(mapped) { place in
                    Marker(place.record.name, systemImage: place.record.category.symbol, coordinate: CLLocationCoordinate2D(latitude: place.record.latitude!, longitude: place.record.longitude!)).tint(Color.bronze).tag(place.id)
                } }.id(loadID).mapStyle(.standard).mapControls { MapCompass(); MapScaleView() }.frame(height: 390).clipShape(.rect(cornerRadius: 26)).accessibilityIdentifier("city-results-map")
                Text("\(mapped.count) mapped \(mapped.count == 1 ? "place" : "places") · Tap a pin to explore").font(.caption).foregroundStyle(.secondary)
                if mapped.count < visible.count { Text("Some saved addresses do not yet have a verified pin. Open the place to locate its hotel address.").font(.caption).foregroundStyle(.secondary) }
                if let selectedPin, let place = visible.first(where: { $0.id == selectedPin }) { ExplorePlaceRow(place: place, add: { adding = place }) }
                else { ForEach(visible.prefix(5)) { place in ExplorePlaceRow(place: place, add: { adding = place }) } }
            }
        }
    }
    private var emptyResults: some View { VStack(alignment: .leading, spacing: 13) { Label("A little further afield?", systemImage: "sparkle.magnifyingglass").font(.headline); Text(savedOnly ? "No saved places match this search. Try another interest or reset your filters." : "Try a place name, another interest, or a wider city area.").font(.subheadline).foregroundStyle(.secondary); if !wider { Button("Explore a wider area") { wider = true }.buttonStyle(.glass) } }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Color.cardSurface, in: .rect(cornerRadius: 24)).accessibilityIdentifier("city-empty-results") }
    private func retryCard(_ message: String) -> some View { VStack(alignment: .leading, spacing: 12) { Text(message).font(.subheadline).foregroundStyle(.secondary); Button("Try again") { Task { await model.load(city: city, interest: interest, term: query, wider: wider, refresh: true) } }.buttonStyle(.glass) }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.cardSurface, in: .rect(cornerRadius: 23)) }
    private var interestsSheet: some View {
        NavigationStack { List { ForEach(ExploreInterest.allCases) { value in Button { interest = value; showInterests = false } label: { HStack { Label(value.title, systemImage: value.symbol).foregroundStyle(.primary); Spacer(); if interest == value { Image(systemName: "checkmark").foregroundStyle(Color.bronze) } }.padding(.vertical, 6) }.accessibilityIdentifier("city-choose-" + value.id) } }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("What moves you?").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showInterests = false } } } }
    }
    private var filtersSheet: some View {
        NavigationStack { Form { Section("Make it yours") { Picker("Sort places", selection: $sort) { ForEach(ExploreSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; Toggle("Only saved places", isOn: $savedOnly); Toggle("With a website", isOn: $websiteOnly); Toggle("Explore the wider city", isOn: $wider) }; Section { Text("Distances are measured from the city center. No device location permission is needed.").font(.caption).foregroundStyle(.secondary) } }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Your city, refined").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showFilters = false } } } }
    }
}

struct ExplorePlaceRow: View {
    @Environment(TravelStore.self) private var store
    let place: ExplorePlace
    var add: (() -> Void)?
    var body: some View {
        HStack(spacing: 12) {
            NavigationLink { ExplorePlaceDetailView(place: place) } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: place.record.category.symbol).font(.system(size: 23, weight: .light)).foregroundStyle(Color.bronze).frame(width: 44, height: 52).background(Color.bronze.opacity(0.07), in: .rect(cornerRadius: 15))
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
        }.padding(17).background(Color.cardSurface, in: .rect(cornerRadius: 24))
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
            }.padding(17).background(Color.cardSurface, in: .rect(cornerRadius: 22))
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
    @State private var locating = false
    private var hotel: Hotel? { store.hotels.first { $0.id == place.hotelID } }
    private var mapQuery: URL { var url = URLComponents(string: "https://maps.apple.com/")!; url.queryItems = [URLQueryItem(name: "q", value: place.record.name + " " + place.subtitle + " " + place.city.name)]; return url.url! }
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
                if !place.record.overview.isEmpty { VStack(alignment: .leading, spacing: 12) { SectionHeading(title: "A little more to discover"); Text(place.record.overview).font(.body).foregroundStyle(.secondary).lineSpacing(5) } }
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "The useful details")
                    detail("Location", value: place.record.address.isEmpty ? place.city.name : place.record.address, symbol: "mappin.and.ellipse")
                    if !place.venueLocation.isEmpty { detail("Within the hotel", value: place.venueLocation, symbol: "building.2") }
                    if !place.record.phone.isEmpty { detail("Phone", value: place.record.phone, symbol: "phone"); if let url = URL(string: "tel:" + place.record.phone.filter { $0.isNumber || $0 == "+" }) { Link("Call this place", destination: url).font(.subheadline) } }
                    if locating { Label("Finding the hotel’s map position…", systemImage: "location.magnifyingglass").font(.caption).foregroundStyle(.secondary) }
                    if place.record.hasCoordinate { Label(place.isCollection ? "Mapped at the hotel’s address" : "Ready for your trip map", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Color.bronze) }
                    else if !locating { Text("A precise map pin isn’t available yet. Directions can search for this address in Maps.").font(.caption).foregroundStyle(.secondary) }
                }.padding(22).background(Color.cardSurface, in: .rect(cornerRadius: 26))
                if let hotel { VStack(alignment: .leading, spacing: 14) { SectionHeading(title: "Make a stay of it"); NavigationLink { HotelDetailView(hotel: hotel) } label: { HotelRow(hotel: hotel) }.buttonStyle(PressStyle()) } }
                VStack(alignment: .leading, spacing: 10) {
                    Text(place.record.source).font(.caption.weight(.medium)).foregroundStyle(Color.bronze)
                    Text(place.isCollection ? "Dining details come from the supplied hotel collection. Check the hotel’s current menus, hours and availability. A map pin identifies the hotel address." : "Location and available contact details are supplied by Apple Maps. Check directly for opening hours, tickets and reservations.").font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(.bottom, 16)
            }.padding(22)
        }.background(Color.canvas).navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { store.toggleDiscovery(place) } label: { Image(systemName: store.isDiscoverySaved(place) ? "bookmark.fill" : "bookmark") }.accessibilityLabel(store.isDiscoverySaved(place) ? "Unsave place" : "Save place").accessibilityIdentifier("explore-place-save") }
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: "\(place.record.name)\n\(place.subtitle)\n\(place.record.website.isEmpty ? mapQuery.absoluteString : place.record.website)") { Image(systemName: "square.and.arrow.up") } }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) { VStack(alignment: .leading, spacing: 4) { Text("Make room for this").font(.subheadline.weight(.medium)); Text("A plan today. A memory tomorrow.").font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading); Button { adding = true } label: { Label("Add to trip", systemImage: "plus").padding(.vertical, 11) }.buttonStyle(.glassProminent).accessibilityIdentifier("explore-add-trip") }.padding(14).glassEffect(.regular, in: .rect(cornerRadius: 26)).padding(.horizontal, 16).padding(.bottom, 8)
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
        library.documents.filter { query.isEmpty || ($0.title + " " + $0.routeLabel).localizedCaseInsensitiveContains(query) }.sorted {
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
                    TextField("Find an existing trip", text: $query).padding(16).background(Color.cardSurface, in: .rect(cornerRadius: 19)).accessibilityIdentifier("explore-trip-query")
                    ForEach(trips) { trip in
                        Button { choose(trip.id) } label: {
                            HStack(spacing: 15) { Image(systemName: "suitcase.rolling").font(.title2.weight(.light)).foregroundStyle(Color.bronze); VStack(alignment: .leading, spacing: 7) { Text(trip.title).font(.system(.headline, design: .serif)).foregroundStyle(.primary); Text(trip.routeLabel.isEmpty ? "Destination to come" : trip.routeLabel).font(.caption).foregroundStyle(.secondary); if let start = trip.startDate { Text(TravelDay.label(start) + (trip.endDate.map { " – " + TravelDay.label($0) } ?? "")).font(.caption2).foregroundStyle(Color.bronze) } }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }.padding(19).background(Color.cardSurface, in: .rect(cornerRadius: 23))
                        }.buttonStyle(PressStyle()).disabled(locating).accessibilityIdentifier("explore-trip-" + trip.id.uuidString)
                    }
                    if trips.isEmpty { Text(library.documents.isEmpty ? "Create your first trip, then choose when you’ll visit." : "No trips match that search.").font(.subheadline).foregroundStyle(.secondary) }
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
                }.padding(17).background(Color.cardSurface, in: .rect(cornerRadius: 22))
                if !store.savedExploreCities.isEmpty {
                    SectionHeading(title: "Cities on your mind")
                    ScrollView(.horizontal) { HStack(spacing: 12) { ForEach(store.savedExploreCities) { city in NavigationLink { CityGuideView(city: city) } label: { VStack(alignment: .leading, spacing: 8) { Image(systemName: "globe").foregroundStyle(Color.bronze); Text(city.name).font(.system(.title3, design: .serif)).foregroundStyle(.primary); Text(city.country).font(.caption).foregroundStyle(.secondary) }.padding(18).background(Color.cardSurface, in: .rect(cornerRadius: 22)) }.buttonStyle(PressStyle()) } } }.scrollIndicators(.hidden)
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
