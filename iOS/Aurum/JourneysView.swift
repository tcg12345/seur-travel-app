import SwiftUI

struct FlightForm: View {
    @State private var search = FlightSearch()
    @State private var browser: BrowserDestination?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("A better way there", systemImage: "airplane").font(.system(.title3, design: .serif))
                Spacer()
            }
            Picker("Journey", selection: $search.oneWay) { Text("Round trip").tag(false); Text("One way").tag(true) }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 0) {
                routeField("FROM", text: $search.origin, symbol: "airplane.departure")
                HStack { Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1); Button { let previous = search.origin; search.origin = search.destination; search.destination = previous } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 36, height: 36) }.buttonStyle(.glass).accessibilityLabel("Swap airports") }.padding(.horizontal, 20)
                routeField("TO", text: $search.destination, symbol: "airplane.arrival")
            }.background(.background, in: .rect(cornerRadius: 25))
            VStack(spacing: 16) {
                DatePicker("Departure", selection: $search.dates.start, in: Date.now..., displayedComponents: .date)
                if !search.oneWay { Divider(); DatePicker("Return", selection: $search.dates.end, in: search.dates.start..., displayedComponents: .date) }
                Divider()
                Picker("Cabin", selection: $search.cabin) { ForEach(["Economy", "Premium economy", "Business", "First class"], id: \.self) { Text($0) } }
                Divider()
                Stepper("\(search.dates.guests) adults", value: $search.dates.guests, in: 1...9)
            }.padding(20).background(.background, in: .rect(cornerRadius: 25))
            Button {
                error = search.error
                if let url = search.url { browser = BrowserDestination(url: url) }
            } label: { Label("Find flights", systemImage: "arrow.up.right").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13) }.buttonStyle(.glassProminent).accessibilityIdentifier("find-flights")
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("flight-error") }
            Text("Compare current fares on Google Flights. Availability, payment, and booking are handled by your selected airline or provider. Review your search details there.").font(.footnote).foregroundStyle(.secondary).lineSpacing(4)
        }
        .sheet(item: $browser) { InAppBrowser(url: $0.url).ignoresSafeArea() }
        .onChange(of: search.dates.start) { _, value in if search.dates.end <= value { search.dates.end = Calendar.current.date(byAdding: .day, value: 1, to: value)! } }
    }
    private func routeField(_ label: String, text: Binding<String>, symbol: String) -> some View {
        HStack(spacing: 17) {
            Image(systemName: symbol).font(.title3.weight(.light)).foregroundStyle(Color.bronze)
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.caption2).tracking(1.8).foregroundStyle(.secondary)
                LocationAutocompleteField("City or airport", text: text, kind: .airport, identifier: label == "FROM" ? "flight-origin" : "flight-destination").font(.system(.title2, design: .serif))
            }
        }.padding(22)
    }
}

struct ExperiencesView: View {
    @Environment(TravelStore.self) private var store
    @State private var city = "Paris"
    @State private var browser: BrowserDestination?
    @State private var planned: Set<String> = []
    let experiences = [
        ("Taste the city", "Market walks, cooking classes, and wine tastings with local hosts.", "wineglass", "food wine tasting"),
        ("Culture, up close", "Private guides, extraordinary museums, and the stories behind the city.", "building.columns", "private cultural tour"),
        ("A different perspective", "Scenic cruises and day trips that take you beyond the familiar.", "sailboat", "cruise day trip")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Explore in").foregroundStyle(.secondary); Spacer(); Picker("Destination", selection: $city) { ForEach(TravelStore.cities, id: \.self) { Text($0) } }.pickerStyle(.menu) }.font(.subheadline)
            ForEach(experiences, id: \.0) { name, description, symbol, query in
                VStack(alignment: .leading, spacing: 15) {
                    Image(systemName: symbol).font(.system(size: 30, weight: .ultraLight)).foregroundStyle(Color.bronze).padding(.bottom, 5)
                    Editorial(name, size: 27)
                    Text(description).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                    Button {
                        var parts = URLComponents(string: "https://www.getyourguide.com/s/")!; parts.queryItems = [URLQueryItem(name: "q", value: city + " " + query)]
                        if let url = parts.url { browser = BrowserDestination(url: url) }
                    } label: { Label("Explore experiences", systemImage: "arrow.up.right").frame(maxWidth: .infinity).padding(.vertical, 7) }.buttonStyle(.glass)
                    Button {
                        if store.addPlan(name: name, city: city, kind: "Experience", hotelID: nil, dates: store.dates) { planned.insert(city + name) }
                    } label: { Label(planned.contains(city + name) ? "Idea added" : "Add idea to my trip", systemImage: planned.contains(city + name) ? "checkmark" : "plus").font(.caption) }.disabled(planned.contains(city + name))
                }.padding(25).background(.background, in: .rect(cornerRadius: 28))
            }
            Text("Ideas to explore, not confirmed departures. Check current activities and book with GetYourGuide. Trip ideas use your current travel dates; edit them in Trips.").font(.footnote).foregroundStyle(.secondary)
        }.sheet(item: $browser) { InAppBrowser(url: $0.url).ignoresSafeArea() }
    }
}

struct SavedView: View {
    @Environment(TravelStore.self) private var store
    @Namespace private var transition
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) { Eyebrow(text: "Your personal collection"); Editorial("Keep a little\nwanderlust close.", size: 38); Text("\(store.saved.count + store.savedRestaurants.count + store.savedDiscoveries.filter { !$0.isCollection }.count) places, waiting for you.").font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical, 16)
                if store.savedHotels.isEmpty && store.savedRestaurants.isEmpty && store.savedDiscoveries.isEmpty && store.savedExploreCities.isEmpty {
                    EmptyState(title: "A collection of possibilities", message: "Save a hotel or bookmark a restaurant for another day.", symbol: "heart")
                    Button("Find your first stay") { store.selectedTab = 0 }.buttonStyle(.glassProminent).frame(maxWidth: .infinity)
                }
                NavigationLink { SavedExplorePlacesView() } label: {
                    HStack(spacing: 15) { Image(systemName: "globe.europe.africa").font(.title2.weight(.light)); VStack(alignment: .leading, spacing: 5) { Text("Your city collection").font(.system(.title3, design: .serif)); Text("\(store.savedDiscoveries.count) discoveries · \(store.savedExploreCities.count) cities").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption) }.padding(20).background(Color.cardSurface, in: .rect(cornerRadius: 24))
                }.buttonStyle(PressStyle()).accessibilityIdentifier("saved-city-collection")
                ForEach(store.savedHotels) { hotel in
                    HStack(alignment: .center) {
                        NavigationLink(value: hotel) { HotelRow(hotel: hotel) }.buttonStyle(PressStyle()).matchedTransitionSource(id: hotel.id, in: transition)
                        Button { withAnimation(.smooth) { store.toggleSave(hotel) } } label: { Image(systemName: "heart.fill").frame(width: 35, height: 44) }.accessibilityLabel("Unsave \(hotel.name)")
                    }
                }
                if !store.savedDiningPlaces.isEmpty {
                    SectionHeading(title: "Tables to remember").padding(.top, 12)
                    ForEach(store.savedDiningPlaces) { place in
                        NavigationLink { RestaurantDetailView(place: place) } label: {
                            HStack(spacing: 15) {
                                Image(systemName: "fork.knife").font(.title2.weight(.light)).foregroundStyle(Color.bronze).frame(width: 44, height: 58)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(place.venue.name).font(.system(.headline, design: .serif)).foregroundStyle(.primary)
                                    Text("\(place.hotel.shortName) · \(place.hotel.city)").font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(16).background(.background, in: .rect(cornerRadius: 23))
                        }.buttonStyle(PressStyle())
                    }
                }
                Text("Saved on this device.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 25)
            }.padding(22)
        }.background(Color.canvas).navigationTitle("Saved places").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Hotel.self) { HotelDetailView(hotel: $0).navigationTransition(.zoom(sourceID: $0.id, in: transition)) }
    }
}

struct TripsView: View {
    @Environment(TravelStore.self) private var store
    @State private var editing: TripPlan?
    @State private var removing: TripPlan?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) { Eyebrow(text: "The next chapter"); Editorial("Less planning.\nMore possibility.", size: 38); Text("Your stays, tables, and little detours.").font(.subheadline).foregroundStyle(.secondary) }.padding(.top, 16)
                if store.plans.isEmpty {
                    EmptyState(title: "An open itinerary", message: "Choose a hotel or dining venue and add it to your trip. The best journeys start somewhere.", symbol: "suitcase.rolling")
                    Button("Start exploring") { store.selectedTab = 0 }.buttonStyle(.glassProminent).frame(maxWidth: .infinity)
                }
                ForEach(store.plans.sorted { $0.start < $1.start }) { plan in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 9) {
                            Image(systemName: plan.symbol).font(.system(size: 18, weight: .light)).frame(width: 42, height: 42).glassEffect(.regular)
                            Rectangle().fill(Color.bronze.opacity(0.2)).frame(width: 1, height: 70)
                        }.foregroundStyle(Color.bronze)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(plan.start.formatted(.dateTime.month(.abbreviated).day()).uppercased() + " · " + plan.kind.uppercased()).font(.caption2).tracking(1.4).foregroundStyle(Color.bronze)
                            Text(plan.name).font(.system(.title3, design: .serif))
                            Text("\(plan.city) · \(plan.guests) adults").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Label("Planned", systemImage: "circle.dotted").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Edit") { editing = plan }.font(.caption)
                                Button { removing = plan } label: { Image(systemName: "trash").frame(width: 32, height: 35) }.accessibilityLabel("Remove \(plan.name)")
                            }
                        }.padding(18).background(.background, in: .rect(cornerRadius: 23))
                    }
                }
                Text("Your itinerary is saved on this device. Plans are not reservations; complete bookings directly with providers.").font(.footnote).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(22)
        }.background(Color.canvas).navigationTitle("My trips").navigationBarTitleDisplayMode(.inline)
            .toolbar { if !store.plans.isEmpty { ToolbarItem(placement: .topBarTrailing) { ShareLink(item: store.exportText) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Export itinerary") } } }
            .sheet(item: $editing) { EditPlanView(plan: $0).presentationDetents([.medium, .large]) }
            .confirmationDialog("Remove this plan?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove plan", role: .destructive) { if let removing { withAnimation(.smooth) { store.removePlan(removing) } }; removing = nil }
            }
    }
}

struct EditPlanView: View {
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var plan: TripPlan
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(plan.name).font(.headline); Text(plan.city).foregroundStyle(.secondary) }
                DatePicker("Start", selection: $plan.start, in: Date.now..., displayedComponents: .date)
                if plan.kind == "Stay" { DatePicker("End", selection: $plan.end, in: plan.start..., displayedComponents: .date) }
                Stepper("\(plan.guests) adults", value: $plan.guests, in: 1...9)
            }.navigationTitle("Your plan").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { store.updatePlan(plan); dismiss() }.disabled(plan.kind == "Stay" && plan.end <= plan.start) }
                }
                .onChange(of: plan.start) { _, value in if plan.end <= value { plan.end = Calendar.current.date(byAdding: .day, value: 1, to: value)! } }
        }
    }
}

struct ProfileView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @State private var preferences = false
    @State private var membership = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("aurum.appearance") private var appearance = "System"
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "a.circle").font(.system(size: 56, weight: .ultraLight)).foregroundStyle(Color.bronze)
                    Editorial("Travel,\nthoughtfully.", size: 38)
                    Text("Your personal Aurum workspace").font(.subheadline).foregroundStyle(.secondary)
                    VStack(spacing: 20) {
                        LabeledContent("The collection", value: "1,513 hotels")
                        LabeledContent("At the table", value: "5,755 dining entries")
                        LabeledContent("A world of possibilities", value: "12 cities")
                        Picker("Appearance", selection: $appearance) { Text("System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark") }
                    }.font(.subheadline).padding(22).background(.background, in: .rect(cornerRadius: 25))
                    VStack(alignment: .leading, spacing: 16) {
                        Button { preferences = true } label: { Label("Your travel preferences", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, alignment: .leading) }.accessibilityIdentifier("profile-preferences")
                        Divider()
                        Button { membership = true } label: {
                            HStack { Label("Aurum Reserve", systemImage: "sparkles"); Spacer(); Text(onboarding.profile.previewPlan.map { $0.title + " preview" } ?? "Explore preview").font(.caption).foregroundStyle(.secondary) }
                        }.accessibilityIdentifier("profile-membership")
                        if onboarding.profile.previewPlan != nil {
                            Button("Clear membership preview", role: .destructive) { onboarding.selectPreview(nil) }.font(.caption)
                        }
                    }.padding(22).background(.background, in: .rect(cornerRadius: 25))
                    Text("Hotel favorites and earlier plans stay on this device. Hotel, flight, and activity bookings are completed with external providers. Travel itineraries and journals can be saved to your connected backend and shared with friends. Aurum does not process payments.").font(.footnote).foregroundStyle(.secondary).lineSpacing(4)
                    Text("Hotel and dining details come from the supplied collection. Featured hotel photography: WBP Stars, Polycor, and Architectural Digest India. Images belong to their respective owners.").font(.caption).foregroundStyle(.secondary)
                    Text("Made for the journey.").font(.system(.title3, design: .serif)).foregroundStyle(Color.bronze).padding(.top, 12)
                }.padding(25)
            }.background(Color.canvas).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .fullScreenCover(isPresented: $preferences) { OnboardingView(review: true) }
                .sheet(isPresented: $membership) { MembershipPreviewView(onFinish: { membership = false }) }
        }
    }
}
