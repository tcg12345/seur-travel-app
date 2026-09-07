import SwiftUI

struct DiscoverView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(TravelStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var hotelTransition
    @Namespace private var categoryGlass
    @State private var showProfile = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 9) {
                    Eyebrow(text: "The art of travel")
                    Editorial(store.category == .dining ? "A destination\nin every dish." : store.category == .flights ? "Enjoy the\ngetting there." : store.category == .experiences ? "Go a little\nfurther." : "Somewhere\nextraordinary.", size: 40)
                        .contentTransition(.numericText())
                    Text(store.category == .dining ? "Remarkable tables. Exceptional stays." : "Thoughtful journeys, beautifully connected.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 8)
                categoryPicker
                cityExplorerEntry
                if onboarding.profile.hasPreferences { personalStartingPoint }
                Group {
                    switch store.category {
                    case .hotels: hotelContent
                    case .dining: diningContent
                    case .flights: FlightForm()
                    case .experiences: ExperiencesView()
                    }
                }.transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
            }.padding(.horizontal, 22).padding(.bottom, 32)
        }
        .background(Color.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { store.searchPresented = true } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search").accessibilityIdentifier("global-search") }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    SeurLogo(size: 30)
                    Text("SEUR").font(.system(size: 14, weight: .medium, design: .serif)).tracking(4)
                }.accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showProfile = true } label: { Image(systemName: "person.crop.circle").fontWeight(.light) }.accessibilityLabel("Your workspace")
            }
        }
        .navigationDestination(isPresented: $showProfile) { ProfileView() }
        .navigationDestination(for: Hotel.self) { hotel in
            HotelDetailView(hotel: hotel).navigationTransition(.zoom(sourceID: hotel.id, in: hotelTransition))
        }
    }
    private var cityExplorerEntry: some View {
        NavigationLink { CityExplorerView() } label: {
            HStack(spacing: 16) {
                Image(systemName: "globe.europe.africa").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(Color.bronze)
                VStack(alignment: .leading, spacing: 6) { Text("Explore a city").font(.system(.title3, design: .serif)).foregroundStyle(.primary); Text("Great tables, little detours & everything between.").font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(Color.bronze)
            }.padding(20).cardSurface(cornerRadius: 26)
        }.buttonStyle(PressStyle()).accessibilityIdentifier("explore-cities")
    }
    private var personalStartingPoint: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Your starting point")
            if !onboarding.profile.destination.isEmpty {
                NavigationLink { CityExplorerView(initialQuery: onboarding.profile.destination) } label: {
                    HStack { Text("Explore " + onboarding.profile.destination).font(.system(.title3, design: .serif)); Spacer(); Image(systemName: "arrow.up.right") }
                }.accessibilityIdentifier("personal-destination")
            }
            if let cuisine = onboarding.profile.cuisines.sorted().first {
                Button { store.cuisine = cuisine; store.city = "Everywhere"; store.query = ""; store.searchPresented = true } label: { Label(cuisine + " tables to discover", systemImage: "fork.knife").font(.subheadline) }
            }
            if !onboarding.profile.interests.isEmpty {
                Text(onboarding.profile.interests.sorted().joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).cardSurface(cornerRadius: 24, emphasized: true)
    }
    private var categoryPicker: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(TravelCategory.allCases) { category in
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) { store.category = category }
                        } label: {
                            Label(category.rawValue, systemImage: category.symbol)
                                .font(.system(.subheadline, weight: store.category == category ? .semibold : .regular))
                                .padding(.horizontal, 15).frame(height: 44)
                                .foregroundStyle(store.category == category ? .white : .primary)
                        }
                        .glassEffect(.regular.tint(store.category == category ? Color.bronze : .clear).interactive(), in: .capsule)
                        .glassEffectID(category, in: categoryGlass)
                        .accessibilityAddTraits(store.category == category ? .isSelected : [])
                        .accessibilityIdentifier("category-\(category.rawValue)")
                    }
                }.padding(.vertical, 4)
            }
        }.scrollIndicators(.hidden).sensoryFeedback(.selection, trigger: store.category)
    }
    @ViewBuilder private var hotelContent: some View {
        if let error = store.loadError { EmptyState(title: "Collection unavailable", message: error, symbol: "wifi.exclamationmark") }
        if let hero = store.featured.first {
            heroCard(hero)
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(title: "Worth the journey", subtitle: "Iconic stays. Unforgettable tables.")
                Button("View all") { store.searchPresented = true }.font(.subheadline).foregroundStyle(Color.bronze)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(store.featured.dropFirst()) { hotel in
                        NavigationLink(value: hotel) { compactCard(hotel) }
                            .buttonStyle(PressStyle()).matchedTransitionSource(id: hotel.id, in: hotelTransition)
                    }
                }.padding(.bottom, 8)
            }.scrollIndicators(.hidden).contentMargins(.trailing, 22)
            destinationSection
            collectionNote
        }
    }
    private func heroCard(_ hotel: Hotel) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: hotel) {
                ZStack(alignment: .bottomLeading) {
                    HotelPhoto(hotel: hotel)
                    LinearGradient(colors: [.clear, .black.opacity(0.05), .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("BANGKOK, THAILAND").font(.caption2.weight(.medium)).tracking(2).foregroundStyle(.white.opacity(0.8))
                        Editorial("A legend on\nthe river.", size: 37).foregroundStyle(.white)
                        Text(hotel.name).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                        HStack {
                            Label("\(hotel.venues.count) dining experiences", systemImage: "fork.knife").font(.caption)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .medium))
                        }.foregroundStyle(.white.opacity(0.95)).padding(.top, 7)
                    }.padding(24)
                    VStack {
                        HStack {
                            Label("THE DINING COLLECTION", systemImage: "sparkle")
                                .font(.system(size: 10, weight: .semibold)).tracking(1)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .glassEffect(.clear, in: .capsule).foregroundStyle(.white)
                            Spacer()
                        }
                        Spacer()
                    }.padding(18)
                }.frame(height: 386).clipShape(.rect(cornerRadius: 30))
            }.buttonStyle(PressStyle()).matchedTransitionSource(id: hotel.id, in: hotelTransition)
                .accessibilityIdentifier("hero-hotel")
            SaveButton(hotel: hotel).padding(14)
        }.shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 9)
    }
    private func compactCard(_ hotel: Hotel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HotelPhoto(hotel: hotel).frame(height: 168).clipped()
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow(text: hotel.city)
                Text(hotel.shortName).font(.system(.title3, design: .serif)).foregroundStyle(.primary)
                Label("\(hotel.venues.count) dining options", systemImage: "fork.knife").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }.frame(width: 252).cardSurface(cornerRadius: 24).clipShape(.rect(cornerRadius: 24))
    }
    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Follow your curiosity")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(ExploreCity.collection) { city in
                        NavigationLink { CityGuideView(city: city) } label: {
                            HStack { Text(city.name); Image(systemName: "arrow.up.right").font(.caption) }.font(.subheadline).padding(.horizontal, 18).padding(.vertical, 13)
                        }.buttonStyle(.glass)
                    }
                }.padding(.vertical, 4)
            }.scrollIndicators(.hidden)
        }
    }
    private var diningContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let hotel = store.featured.first { heroCard(hotel) }
            SectionHeading(title: "Choose your table", subtitle: "Search by cuisine, restaurant, or city.")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(["French", "Japanese", "Chinese", "Italian", "Thai", "Indian"], id: \.self) { cuisine in
                    Button { store.cuisine = cuisine; store.searchPresented = true } label: {
                        HStack { Text(cuisine); Spacer(); Image(systemName: "arrow.up.right") }.font(.subheadline).padding(19)
                            .cardSurface(cornerRadius: 19)
                    }.buttonStyle(PressStyle())
                }
            }
            Button { store.sort = .dining; store.searchPresented = true } label: {
                HStack(spacing: 16) {
                    Image(systemName: "fork.knife.circle").font(.largeTitle).fontWeight(.ultraLight)
                    VStack(alignment: .leading, spacing: 5) { Text("More tables, more possibilities").font(.headline); Text("Explore hotels with the widest dining selection.").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Image(systemName: "chevron.right").font(.caption)
                }.padding(20).cardSurface(cornerRadius: 24, emphasized: true)
            }.buttonStyle(PressStyle())
            collectionNote
        }
    }
    private var collectionNote: some View {
        VStack(spacing: 7) {
            Image(systemName: "sparkle").foregroundStyle(Color.bronze)
            Text("Your next destination. Your next chapter.").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 18)
    }
}

struct SearchView: View {
    @Environment(TravelStore.self) private var store
    @State private var filters = false
    @State private var comparing = false
    @State private var limit = 30
    @Namespace private var transition
    var body: some View {
        @Bindable var store = store
        let results = store.results
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 13) {
                NavigationLink { CityExplorerView() } label: { Label("Explore any city", systemImage: "globe.europe.africa").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(17).cardSurface(cornerRadius: 22) }.buttonStyle(PressStyle()).accessibilityIdentifier("search-explore-cities")
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.city == "Everywhere" ? "THE COLLECTION" : store.city.uppercased()).font(.caption).tracking(2).foregroundStyle(Color.bronze)
                        Text("\(results.count.formatted()) stays to discover").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { filters = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                        .buttonStyle(.glass).accessibilityLabel("Filter hotels").accessibilityIdentifier("filter-hotels")
                }.padding(.vertical, 8)
                if store.cuisine != "Any cuisine" || store.city != "Everywhere" {
                    HStack {
                        Text([store.city, store.cuisine].filter { $0 != "Everywhere" && $0 != "Any cuisine" }.joined(separator: " · ")).font(.caption)
                        Spacer(); Button("Reset") { store.city = "Everywhere"; store.cuisine = "Any cuisine" }.font(.caption)
                    }.padding(12).background(Color.bronze.opacity(0.08), in: .capsule)
                }
                ForEach(results.prefix(limit)) { hotel in
                    VStack(spacing: 3) {
                        NavigationLink(value: hotel) { HotelRow(hotel: hotel) }.buttonStyle(PressStyle()).matchedTransitionSource(id: hotel.id, in: transition)
                        HStack {
                            Button { store.toggleCompare(hotel) } label: { Label(store.compared.contains(hotel.id) ? "Selected" : "Compare dining", systemImage: store.compared.contains(hotel.id) ? "checkmark.circle.fill" : "circle") }.accessibilityIdentifier("compare-\(hotel.id)")
                            Spacer()
                            Text(hotel.price.hasPrefix("$") ? hotel.price + " · price band" : "See hotel rates").foregroundStyle(.secondary)
                        }.font(.caption).padding(.horizontal, 15).padding(.vertical, 9)
                    }
                }
                if results.isEmpty { EmptyState(title: "A little further afield?", message: "Try a different city, hotel, restaurant, or cuisine.", symbol: "magnifyingglass") }
                if results.count > limit { Button("Show more stays") { limit += 30 }.buttonStyle(.glass).frame(maxWidth: .infinity).padding() }
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
        .background(Color.canvas).navigationTitle("Find your somewhere").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.query, prompt: "City, hotel, restaurant, cuisine")
        .onChange(of: store.query) { limit = 30 }
        .safeAreaInset(edge: .bottom) {
            if !store.compared.isEmpty {
                HStack {
                    Text("\(store.compared.count) of 3 selected").font(.subheadline)
                    Spacer()
                    Button("Compare") { comparing = true }.buttonStyle(.glassProminent).disabled(store.compared.count < 2)
                    Button { store.compared = [] } label: { Image(systemName: "xmark") }.accessibilityLabel("Clear comparison")
                }.padding(13).glassEffect(.regular, in: .capsule).padding(.horizontal, 18).padding(.bottom, 5)
            }
        }
        .sheet(isPresented: $filters) { FilterSheet().presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        .sheet(isPresented: $comparing) { ComparisonView().presentationDragIndicator(.visible) }
        .navigationDestination(for: Hotel.self) { HotelDetailView(hotel: $0).navigationTransition(.zoom(sourceID: $0.id, in: transition)) }
    }
}

struct FilterSheet: View {
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Picker("Destination", selection: $store.city) { Text("Everywhere").tag("Everywhere"); ForEach(TravelStore.cities, id: \.self) { Text($0).tag($0) } }
                Picker("Cuisine", selection: $store.cuisine) { ForEach(["Any cuisine", "French", "Japanese", "Chinese", "Italian", "Thai", "Indian"], id: \.self) { Text($0).tag($0) } }
                Picker("Sort by", selection: $store.sort) { ForEach(HotelSort.allCases) { Text($0.rawValue).tag($0) } }
                Section { Text("Dining counts indicate variety, not a quality score. Details come from the supplied hotel collection.").font(.footnote).foregroundStyle(.secondary) }
                Button("Reset filters") { store.city = "Everywhere"; store.cuisine = "Any cuisine"; store.sort = .featured; store.query = "" }
            }.navigationTitle("Make it yours").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("filter-done") } }
        }
    }
}
