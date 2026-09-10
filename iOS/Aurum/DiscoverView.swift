import SwiftUI

struct DiscoverView: View {
    @Environment(TravelStore.self) private var store
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var hotelTransition
    @State private var showProfile = false
    @State private var createTrip = false
    @State private var clockDate = Date.now

    private var latestTrip: JourneyDocument? { library.documents.filter { $0.isTemplate != true }.max { $0.updatedAt < $1.updatedAt } }

    var body: some View {
        let now = TodayClock.now(clockDate)
        let activeTrip = TodayPlanner.activeTrip(library.documents, now: now)
        ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let activeTrip { DiscoverCurrentTripCard(trip: activeTrip, now: now) }
                    VStack(alignment: .leading, spacing: 12) {
                        startingPoint
                        browseShortcuts
                    }
                    if latestTrip == nil || latestTrip?.id != activeTrip?.id { planningShortcut }
                    inspiration
                    conciergeShortcut
                }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 32)
        }
        .task {
            clockDate = .now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                clockDate = .now
            }
        }
        .background(Color.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { store.searchPresented = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search").accessibilityIdentifier("global-search")
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    SeurLogo(size: 26)
                    Text("SEUR").font(.system(size: 14, weight: .medium, design: .serif)).tracking(4)
                }.accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showProfile = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Your workspace")
            }
        }
        .navigationDestination(isPresented: $showProfile) { ProfileView() }
        .navigationDestination(for: Hotel.self) { hotel in
            HotelDetailView(hotel: hotel).navigationTransition(.zoom(sourceID: hotel.id, in: hotelTransition))
        }
        .sheet(isPresented: $createTrip) { TripCreationView() }
    }

    private var startingPoint: some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink { CityExplorerView() } label: {
                HStack(spacing: 13) {
                    Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(Color.bronze)
                    Text("Explore cities").font(.body.weight(.medium)).foregroundStyle(.primary)
                    Spacer(minLength: 4)
                }.padding(16).cardSurface(cornerRadius: 16, emphasized: true)
            }.buttonStyle(PressStyle()).accessibilityIdentifier("explore-cities")
                .accessibilityHint("Search any destination for restaurants, stays and things to do")
        }
    }

    private var browseShortcuts: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 18) {
                Button {
                    store.query = ""; store.city = "Everywhere"; store.cuisine = "Any cuisine"; store.sort = .featured
                    store.searchPresented = true
                } label: { shortcutLabel("Stays", symbol: "bed.double") }
                    .accessibilityIdentifier("category-Stays")
                NavigationLink { CityExplorerView(initialInterest: .restaurants) } label: {
                    shortcutLabel("Dining", symbol: "fork.knife")
                }.accessibilityIdentifier("category-Dining")
                NavigationLink { CityExplorerView(initialInterest: .attractions) } label: {
                    shortcutLabel("Things to do", symbol: "sparkles")
                }.accessibilityIdentifier("category-Experiences")
                NavigationLink {
                    ScrollView { FlightForm().padding(22) }.background(Color.canvas)
                        .navigationTitle("Find flights").navigationBarTitleDisplayMode(.inline)
                } label: { shortcutLabel("Flights", symbol: "airplane") }
                    .accessibilityIdentifier("category-Flights")
            }.buttonStyle(PressStyle())
        }
    }

    private func shortcutLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.bronze).frame(height: 24)
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.primary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, minHeight: 58, alignment: .top).padding(.top, 6).contentShape(.rect)
    }

    private var planningShortcut: some View {
        VStack(spacing: 0) {
            Divider()
            if let trip = latestTrip {
                NavigationLink { JourneyDetailView(id: trip.id) } label: {
                    planningLabel("Continue planning", detail: trip.title.isEmpty ? trip.routeLabel : trip.title, symbol: "suitcase.rolling")
                }.accessibilityIdentifier("discover-continue-trip")
            } else {
                Button { createTrip = true } label: {
                    planningLabel("Start a trip", detail: "Keep your plans together in one itinerary.", symbol: "plus")
                }.accessibilityIdentifier("discover-create-trip")
            }
            Divider()
        }.buttonStyle(PressStyle())
    }

    private func planningLabel(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.bronze).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 6)
        }.padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
    }

    private var inspiration: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Editorial("A little inspiration", size: 26)
                Spacer(minLength: 8)
                NavigationLink("Travel guides") { GuideHubView() }.font(.subheadline).foregroundStyle(Color.bronze)
            }
            if let hotel = store.featured.first {
                heroCard(hotel)
                ForEach(store.featured.dropFirst().prefix(2)) { hotel in
                    NavigationLink(value: hotel) {
                        HStack(spacing: 14) {
                            HotelPhoto(hotel: hotel).frame(width: 76, height: 76).clipShape(.rect(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(hotel.city).font(.caption).foregroundStyle(Color.bronze)
                                Text(hotel.shortName).font(.system(.headline, design: .serif)).foregroundStyle(.primary)
                                Text("Stay & dine").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                        }.contentShape(.rect)
                    }.buttonStyle(PressStyle()).matchedTransitionSource(id: hotel.id, in: hotelTransition)
                }
            } else {
                Text("Explore a city to find stays, restaurants and things to do.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func heroCard(_ hotel: Hotel) -> some View {
        NavigationLink(value: hotel) {
            VStack(alignment: .leading, spacing: 12) {
                HotelPhoto(hotel: hotel).frame(height: 200).clipShape(.rect(cornerRadius: 20))
                    .overlay(alignment: .bottomLeading) {
                        Text(hotel.city + ", " + hotel.country).font(.caption.weight(.medium))
                            .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.black.opacity(0.65), in: .capsule).padding(14)
                    }
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(hotel.name).font(.system(.title3, design: .serif)).foregroundStyle(.primary)
                        Text("Discover the stay and its dining collection.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                }
            }.contentShape(.rect)
        }.buttonStyle(PressStyle()).matchedTransitionSource(id: hotel.id, in: hotelTransition)
            .accessibilityIdentifier("hero-hotel")
    }

    private var conciergeShortcut: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { store.selectedTab = 4 }
            } label: {
                planningLabel("Let’s plan it together", detail: "Ask Concierge for ideas or a complete itinerary.", symbol: "sparkles")
            }.buttonStyle(PressStyle()).accessibilityIdentifier("discover-concierge")
        }
    }
}


/// A local, offline-ready snapshot of the active trip; the full itinerary stays one tap away.
private struct DiscoverCurrentTripCard: View {
    let trip: JourneyDocument
    let now: Date
    @Environment(TravelAPI.self) private var api
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var statuses = TodayFlightStatusStore.shared

    var body: some View {
        let context = TodayPlanner.context(trip, now: now)
        let destination = context.stop?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Reuse cached flight updates without adding background requests on Discover.
        let snapshots = Dictionary(uniqueKeysWithValues: trip.flights.compactMap { flight in
            statuses.snapshot(flight, server: api.baseURL).map { (flight.id, $0) }
        })
        let items = TodayPlanner.items(trip, day: context.day, zone: context.zone, snapshots: snapshots)
        NavigationLink { JourneyDetailView(id: trip.id) } label: {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.teal).frame(width: 5, height: 5)
                        Text("ON YOUR TRIP").font(.caption2.weight(.semibold)).tracking(1)
                        Spacer()
                    }.foregroundStyle(Color.bronze)
                    Text(destination.isEmpty ? "Your trip today" : "Today in " + destination)
                        .font(.system(.title2, design: .serif).weight(.medium))
                        .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    Text("Day \(TravelDay.distance(trip.startDate ?? context.day, context.day) + 1) · " + TravelDay.label(context.day))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.bronze.opacity(0.65)).frame(width: 2)
                    VStack(alignment: .leading, spacing: 10) {
                        if items.isEmpty {
                            Text("No activities today").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ForEach(items.prefix(3)) { item in activity(item) }
                            if items.count > 3 {
                                Text("+\(items.count - 3) more today").font(.caption.weight(.medium)).foregroundStyle(Color.bronze)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.fixedSize(horizontal: false, vertical: true)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(cornerRadius: 20, emphasized: true)
                .contentShape(.rect(cornerRadius: 20))
        }.buttonStyle(PressStyle())
            .accessibilityIdentifier("discover-current-trip")
            .accessibilityHint("Open " + (trip.title.isEmpty ? "this trip’s itinerary" : trip.title))
    }

    private func activity(_ item: TodayItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.symbol).font(.caption).foregroundStyle(Color.bronze)
                .frame(width: 18).accessibilityHidden(true)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3)) : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Text(item.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Text(item.schedule).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(Color.bronze)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
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
