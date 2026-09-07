import SwiftUI

struct RestaurantPlace: Hashable, Identifiable {
    let hotel: Hotel
    let venue: DiningVenue
    // Venue names can recur at different hotels.
    var id: String { hotel.id + "::" + venue.id }
}

struct RestaurantVisit: Codable, Equatable {
    var rating = 0
    var note = ""
}

struct RestaurantDetailView: View {
    @Environment(TravelStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let place: RestaurantPlace
    @State private var existingTrip = false
    @State private var compactAdd = false
    @State private var planner = false
    @State private var journal = false
    @State private var concierge = false
    @State private var browser: BrowserDestination?
    private var hotel: Hotel { place.hotel }
    private var venue: DiningVenue { place.venue }
    private var saved: Bool { store.savedRestaurants.contains(place.id) }
    private var visit: RestaurantVisit { store.restaurantVisits[place.id] ?? RestaurantVisit() }
    private var symbol: String { venue.type.localizedCaseInsensitiveContains("bar") ? "wineglass" : "fork.knife" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 28) {
                    identity
                    quickActions
                    VStack(alignment: .leading, spacing: 13) {
                        SectionHeading(title: "A taste of the place")
                        Text(available(venue.description) ? venue.description : "Discover this dining venue at \(hotel.name). Contact the hotel for its latest menu and dining experience.")
                            .font(.body).foregroundStyle(.secondary).lineSpacing(5)
                    }
                    essentials
                    conciergeCard
                    visitCard
                    location
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "Make a stay of it", subtitle: "One address. More to discover.")
                        NavigationLink { HotelDetailView(hotel: hotel) } label: { HotelRow(hotel: hotel) }.buttonStyle(PressStyle())
                    }
                    Text("From the Seur hotel collection. Menus, opening hours and availability are confirmed by the hotel.")
                        .font(.caption).foregroundStyle(.secondary).lineSpacing(3).padding(.bottom, 12)
                }.padding(24).background(Color.canvas, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)).padding(.top, -28)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            if offset > 80 { compactAdd = true } else if offset < 24 { compactAdd = false }
        }
        .background(Color.canvas).ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { existingTrip = true } label: { Image(systemName: "suitcase.rolling.badge.plus") }.accessibilityLabel("Add restaurant to an existing trip")
                Button { store.toggleRestaurantSave(place) } label: {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark").contentTransition(.symbolEffect(.replace))
                }.accessibilityLabel(saved ? "Unsave restaurant" : "Save restaurant").accessibilityIdentifier("restaurant-save")
                ShareLink(item: "\(venue.name)\nAt \(hotel.name), \(hotel.city)\n\(hotel.website)") { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share restaurant")
            }
        }
        .safeAreaInset(edge: .bottom) {
            PlaceTripAction(title: "Plan a visit", compact: compactAdd, identifier: "restaurant-plan") { planner = true }
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 20).frame(height: 70)
        }
        .sensoryFeedback(.selection, trigger: saved)
        .sheet(isPresented: $existingTrip) {
            if let city = ExploreCity.collection.first(where: { $0.name == hotel.city }), let discovery = ExplorePlace.collection([hotel], city: city).first(where: { $0.record.id == place.id }) { ExploreAddToTripView(place: discovery) }
        }
        .sheet(isPresented: $planner) { DiningVisitPlanner(hotel: hotel, venue: venue).presentationDetents([.large]).presentationDragIndicator(.visible) }
        .sheet(isPresented: $journal) { RestaurantVisitEditor(place: place) }
        .sheet(isPresented: $concierge) {
            NavigationStack {
                ConciergeView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { concierge = false } } }
            }
        }
        .sheet(item: $browser) { InAppBrowser(url: $0.url).ignoresSafeArea() }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            if hotel.image != nil { HotelPhoto(hotel: hotel) }
            else {
                Rectangle().fill(LinearGradient(colors: [Color.brandInk, Color(red: 0.35, green: 0.30, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: symbol).font(.system(size: 86, weight: .ultraLight)).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Label("THE DINING COLLECTION", systemImage: symbol).font(.caption2.weight(.semibold)).tracking(2)
                Text(hotel.city).font(.system(size: 39, weight: .regular, design: .serif))
                Text(hotel.image != nil ? "Hotel exterior · \(hotel.shortName)" : "Restaurant photography coming soon")
                    .font(.caption2).foregroundStyle(.white.opacity(0.8))
            }.foregroundStyle(.white).padding(.horizontal, 26).padding(.bottom, 54)
        }.frame(height: 345).clipped().accessibilityElement(children: .combine)
    }
    private var identity: some View {
        VStack(alignment: .leading, spacing: 13) {
            Eyebrow(text: "At \(hotel.shortName)")
            Editorial(venue.name, size: 38).accessibilityAddTraits(.isHeader).accessibilityIdentifier("restaurant-title")
            Text(venue.cuisine).font(.subheadline).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { tags }
                VStack(alignment: .leading, spacing: 8) { tags }
            }
        }
    }
    @ViewBuilder private var tags: some View {
        Label(venue.type, systemImage: symbol).font(.caption).padding(.horizontal, 12).padding(.vertical, 9).background(Color.bronze.opacity(0.09), in: .capsule)
        if available(venue.price) { Text(venue.price).font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 9).background(Color.bronze.opacity(0.09), in: .capsule) }
    }
    private var quickActions: some View {
        HStack(spacing: 12) {
            if let url = hotel.officialURL {
                Button { browser = BrowserDestination(url: url) } label: {
                    Label("Hotel website", systemImage: "globe").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.glass)
            }
            Button(action: openMap) { Label("Directions", systemImage: "location").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 12) }.buttonStyle(.glass)
        }
    }
    private var essentials: some View {
        VStack(spacing: 18) {
            detailRow("The setting", value: available(venue.location) ? venue.location : "Inside \(hotel.shortName)", icon: "door.left.hand.open")
            Divider()
            detailRow("Opening hours", value: "Confirm with the hotel", icon: "clock")
        }.padding(21).background(.background, in: .rect(cornerRadius: 24))
    }
    private func detailRow(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3.weight(.light)).foregroundStyle(Color.bronze).frame(width: 23)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.subheadline.weight(.medium)); Text(value).font(.subheadline).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
    }
    private var conciergeCard: some View {
        Button {
            store.concierge.send("Tell me about \(venue.name) at \(hotel.name)", store: store)
            concierge = true
        } label: {
            HStack(spacing: 15) {
                Image(systemName: "sparkles").font(.title2.weight(.light)).foregroundStyle(Color.bronze)
                VStack(alignment: .leading, spacing: 5) {
                    Text("A little inside knowledge").font(.system(.headline, design: .serif)).foregroundStyle(.primary)
                    Text("Ask your concierge · Demo").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right").foregroundStyle(Color.bronze)
            }.padding(21).background(Color.bronze.opacity(0.07), in: .rect(cornerRadius: 24))
        }.buttonStyle(PressStyle()).disabled(store.concierge.isReplying).accessibilityIdentifier("restaurant-concierge")
    }
    private var visitCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "Your visit", subtitle: "For your own little black book.")
                Spacer()
                Button { journal = true } label: { Image(systemName: "square.and.pencil").frame(width: 44, height: 44) }.buttonStyle(.glass).accessibilityLabel("Edit visit notes").accessibilityIdentifier("restaurant-journal")
            }
            if visit.rating > 0 {
                HStack(spacing: 5) { ForEach(1...5, id: \.self) { star in Image(systemName: star <= visit.rating ? "star.fill" : "star").foregroundStyle(Color.bronze) }; Text("Your rating").font(.caption).foregroundStyle(.secondary).padding(.leading, 6) }.accessibilityElement(children: .ignore).accessibilityLabel("Your rating: \(visit.rating) out of 5")
            }
            Text(visit.note.isEmpty ? "The dish you loved. The perfect table. Keep a private note for next time." : visit.note).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
            Text("Private · saved on this device").font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 4)
    }
    private var location: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().padding(.bottom, 8)
            SectionHeading(title: "Find your way")
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(Color.bronze).frame(width: 42, height: 48)
                VStack(alignment: .leading, spacing: 7) {
                    Text(hotel.name).font(.subheadline.weight(.medium))
                    if available(hotel.address) { Text(hotel.address).font(.subheadline).foregroundStyle(.secondary) }
                    Text("\(hotel.city), \(hotel.country)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button(action: openMap) { Label("Open in Apple Maps", systemImage: "arrow.up.right").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 10) }.buttonStyle(.glass)
        }
    }
    private func openMap() {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: "\(venue.name), \(hotel.name), \(hotel.city)")]
        if let url = components.url { UIApplication.shared.open(url) }
    }
    private func available(_ value: String) -> Bool { !value.isEmpty && value.lowercased() != "n/a" }
}

private struct RestaurantVisitEditor: View {
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let place: RestaurantPlace
    @State private var visit = RestaurantVisit()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(place.venue.name).font(.system(.title2, design: .serif))
                    HStack(spacing: 16) {
                        ForEach(1...5, id: \.self) { star in
                            Button { visit.rating = star == visit.rating ? 0 : star } label: { Image(systemName: star <= visit.rating ? "star.fill" : "star").font(.title2).frame(minWidth: 32, minHeight: 44) }
                                .buttonStyle(.plain).foregroundStyle(Color.bronze).accessibilityLabel("Rate \(star) stars").accessibilityIdentifier("visit-rating-\(star)")
                        }
                    }
                } header: { Text("Your rating") } footer: { Text("Tap your selected rating again to clear it.") }
                Section("A note for next time") {
                    TextEditor(text: $visit.note).frame(minHeight: 160).accessibilityLabel("Private visit note").accessibilityIdentifier("visit-note")
                }
                Section { Text("Only you can see this. Your notes and rating stay on this device.").foregroundStyle(.secondary) }
            }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Your visit").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { store.saveRestaurantVisit(visit, for: place); dismiss() }.accessibilityIdentifier("save-visit") }
                }
                .onAppear { visit = store.restaurantVisits[place.id] ?? RestaurantVisit() }
        }
    }
}
