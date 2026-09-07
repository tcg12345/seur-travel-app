import SwiftUI

struct PlaceFields: View {
    @Binding var place: PlaceRecord
    var fixedCategory: PlaceCategory?
    var search: () -> Void
    @State private var coordinates = false
    var body: some View {
        Section("The place") {
            Button(action: search) { Label(fixedCategory == .hotel ? "Search hotels" : "Find a restaurant or place", systemImage: "magnifyingglass") }
            LocationAutocompleteField("Place name", text: $place.name, kind: .place, identifier: "place-name", category: fixedCategory ?? place.category, onEdit: { clearLocation() }) { selected in var value = selected.place; value.category = fixedCategory ?? place.category; place = value }
            if let fixedCategory { Text(fixedCategory.title).foregroundStyle(.secondary) }
            else { Picker("Category", selection: $place.category) { ForEach(PlaceCategory.allCases) { Text($0.title).tag($0) } } }
            if place.hasCoordinate {
                Label("Ready for your trip map", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Color.bronze).accessibilityIdentifier("place-map-ready")
                if !place.address.isEmpty { Text(place.address).font(.caption).foregroundStyle(.secondary) }
            } else { Text("Choose a search suggestion to add this place to your map.").font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("Location & contact") {
                LocationAutocompleteField("City", text: $place.city, kind: .city, identifier: "place-city", onEdit: { clearLocation() }) { _ in clearLocation() }
                LocationAutocompleteField("Address", text: $place.address, kind: .address, identifier: "place-address", onEdit: { clearLocation() }) { selected in
                    clearLocation(); place.city = selected.place.city; place.latitude = selected.place.latitude; place.longitude = selected.place.longitude
                    place.source = "Apple Maps"; place.sourceURL = nil
                }
                TextField("Phone", text: $place.phone).keyboardType(.phonePad)
                TextField("Website", text: $place.website).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if let rating = place.rating {
                HStack {
                    Text("Provider rating").font(.caption)
                    Spacer()
                    if let imageURL = place.ratingImageURL, let url = validatedURL(imageURL) { AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Text("\(rating, specifier: "%.1f") / 5") }.frame(width: 100, height: 22) }
                    else { Text("\(rating, specifier: "%.1f") / 5").font(.caption) }
                }
            }
            if place.source != "Manual entry" {
                if let link = place.sourceURL.flatMap(validatedURL) { Link("View on \(place.source)", destination: link).font(.caption) }
                else { Text("Source: \(place.source)").font(.caption).foregroundStyle(.secondary) }
            }
            DisclosureGroup("Map coordinates", isExpanded: $coordinates) {
                TextField("Latitude", value: $place.latitude, format: .number).keyboardType(.numbersAndPunctuation)
                TextField("Longitude", value: $place.longitude, format: .number).keyboardType(.numbersAndPunctuation)
                Text("Search fills these automatically when available.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { if let fixedCategory { place.category = fixedCategory } }
    }
    private func clearLocation() { place.latitude = nil; place.longitude = nil; place.rating = nil; place.ratingImageURL = nil; place.sourceURL = nil; place.source = "Manual entry" }

}

extension View {
    /// Attach to the editor's NavigationStack, never a Section in the recycling Form.
    func placeSearchSheet(isPresented: Binding<Bool>, place: Binding<PlaceRecord>, category: PlaceCategory? = nil) -> some View {
        sheet(isPresented: isPresented) {
            PlaceSearchView(category: category ?? place.wrappedValue.category) { selected in
                var result = selected
                result.category = category ?? place.wrappedValue.category
                place.wrappedValue = result
            }
        }
    }
}

struct PlaceSearchView: View {
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    let category: PlaceCategory
    var citySearch = false
    var select: (PlaceRecord) -> Void
    @State private var query = ""
    @State private var source = "Apple Maps"
    @State private var results: [PlaceRecord] = []
    @State private var loading = false
    @State private var error: String?
    @State private var didSearch = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            List {
                if !citySearch { Section { Picker("Search with", selection: $source) { Text("Places").tag("Apple Maps"); Text("Tripadvisor").tag("Tripadvisor") }.pickerStyle(.segmented) } }
                Section {
                    if source == "Apple Maps" {
                        LocationAutocompleteField(citySearch ? "City or airport" : "Name, cuisine or place + city", text: $query, kind: citySearch ? .airport : .place, identifier: "live-place-query", category: category, onSelect: { selected in select(selected.place); dismiss() })
                    } else {
                        TextField("Name, cuisine or place + city", text: $query).submitLabel(.search).onSubmit(runSearch).accessibilityIdentifier("live-place-query")
                    }
                    Button(action: runSearch) { Label(loading ? "Searching…" : "Search", systemImage: "magnifyingglass") }.disabled(loading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: { Text(citySearch ? "Live city and airport lookup with Apple Maps." : "Find a place as you type. Apple Maps supplies location and contact details; Tripadvisor offers additional reviews when connected.") }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error { Section { Text(error).foregroundStyle(.red); Button("Try again", action: runSearch) } }
                if didSearch && !loading && results.isEmpty && error == nil { ContentUnavailableView.search(text: query) }
                ForEach(results) { place in
                    Button { choose(place) } label: {
                        VStack(alignment: .leading, spacing: 7) { Text(place.name).font(.system(.headline, design: .serif)).foregroundStyle(.primary); Text(place.address.isEmpty ? place.city : place.address).font(.caption).foregroundStyle(.secondary); Text(place.source).font(.caption2).foregroundStyle(Color.bronze) }.padding(.vertical, 6)
                    }.disabled(loading)
                }
            }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Color.canvas).navigationTitle(citySearch ? "Find your destination" : "Find your place").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onDisappear { task?.cancel() }
                .onChange(of: source) { scheduleSearch() }
                .onChange(of: query) { scheduleSearch() }
        }
    }
    private func scheduleSearch() {
        task?.cancel(); results = []; error = nil; loading = false; didSearch = false
        guard source == "Tripadvisor", query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
        task = Task { do { try await Task.sleep(for: .milliseconds(450)) } catch { return }; guard !Task.isCancelled else { return }; runSearch() }
    }
    private func runSearch() {
        task?.cancel(); let text = query.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }
        let provider = source; loading = true; error = nil; results = []; didSearch = true
        task = Task {
            do { let found = provider == "Apple Maps" ? try await ApplePlaceSearch.search(text, category: category, citiesOnly: citySearch) : try await api.searchPlaces(text, category: category); guard !Task.isCancelled else { return }; results = found }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
    }
    private func choose(_ place: PlaceRecord) {
        if source == "Apple Maps" { select(place); dismiss(); return }
        loading = true; error = nil
        task = Task {
            do { var detailed = try await api.placeDetails(place.id); detailed.category = category; guard !Task.isCancelled else { return }; select(detailed); dismiss() }
            catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}

struct FlightLookupSelection { let search: FlightSearch; let departure: PlaceRecord?; let arrival: PlaceRecord? }

struct FlightLookupView: View {
    @Environment(\.dismiss) private var dismiss
    var select: (FlightLookupSelection) -> Void
    @State private var search = FlightSearch()
    @State private var browser: BrowserDestination?
    @State private var departure: PlaceRecord?
    @State private var arrival: PlaceRecord?
    @State private var choosingOrigin = false
    @State private var choosingDestination = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Your route") {
                    LocationAutocompleteField("From", text: $search.origin, kind: .airport, identifier: "lookup-origin", onEdit: { departure = nil }) { departure = $0.place }
                    Button("Find departure city or airport") { choosingOrigin = true }
                    LocationAutocompleteField("To", text: $search.destination, kind: .airport, identifier: "lookup-destination", onEdit: { arrival = nil }) { arrival = $0.place }
                    Button("Find arrival city or airport") { choosingDestination = true }
                }
                Section("The journey") {
                    Toggle("One way", isOn: $search.oneWay)
                    DatePicker("Departure", selection: $search.dates.start, in: Date.now..., displayedComponents: .date)
                    if !search.oneWay { DatePicker("Return", selection: $search.dates.end, in: search.dates.start..., displayedComponents: .date) }
                    Stepper("\(search.dates.guests) travelers", value: $search.dates.guests, in: 1...9)
                    Picker("Cabin", selection: $search.cabin) { ForEach(["Economy", "Premium economy", "Business", "First class"], id: \.self) { Text($0) } }
                }
                Section {
                    Button { if let url = search.url { browser = BrowserDestination(url: url) } } label: { Label("Compare live flights", systemImage: "arrow.up.right") }.disabled(search.error != nil)
                    Text("Current flights and prices open in Google Flights. After choosing or booking a flight, use these route details and enter the airline, flight number, airport-local times and price from your booking.").font(.caption).foregroundStyle(.secondary)
                    if let error = search.error { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Find a flight").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Use route") { select(FlightLookupSelection(search: search, departure: departure, arrival: arrival)); dismiss() }.disabled(search.error != nil) } }
                .sheet(item: $browser) { InAppBrowser(url: $0.url).ignoresSafeArea() }
                .sheet(isPresented: $choosingOrigin) { PlaceSearchView(category: .other, citySearch: true) { search.origin = $0.name; departure = $0 } }
                .sheet(isPresented: $choosingDestination) { PlaceSearchView(category: .other, citySearch: true) { search.destination = $0.name; arrival = $0 } }
        }
    }
}

struct ActivityIdeasView: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    @State private var city = ""
    @State private var interests = "Art, food and a little time outdoors"
    @State private var response: AITravelResponse?
    @State private var error: String?
    @State private var loading = false
    @State private var event: JourneyEvent?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Eyebrow(text: "Your AI travel editor")
                    Editorial("A little inspiration.\nA very personal day.", size: 33)
                    LocationAutocompleteField("Destination", text: $city, identifier: "ideas-destination").padding(16).background(.background, in: .rect(cornerRadius: 18))
                    TextField("What do you love?", text: $interests, axis: .vertical).lineLimit(3...6).padding(15).background(.background, in: .rect(cornerRadius: 18))
                    Button { Task { loading = true; error = nil; defer { loading = false }; do { response = try await api.recommendations(city: city, interests: interests) } catch { self.error = error.localizedDescription } } } label: { Label(loading ? "Gathering ideas…" : "Find my inspiration", systemImage: "sparkles").frame(maxWidth: .infinity).padding(.vertical, 11) }.buttonStyle(.glassProminent).disabled(loading || city.isEmpty)
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
                    if let response {
                        Text(response.text).font(.body).lineSpacing(5)
                        ForEach(response.places) { place in
                            Button { guard let document = library.documents.first(where: { $0.id == documentID }), let stop = document.stops.first(where: { $0.name.localizedCaseInsensitiveContains(city) }) ?? document.stops.first else { return }; event = JourneyEvent(stopID: stop.id, place: place) } label: {
                                HStack { VStack(alignment: .leading, spacing: 6) { Text(place.name).font(.system(.headline, design: .serif)); Text(place.address).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "plus.circle") }.padding(18).background(.background, in: .rect(cornerRadius: 22))
                            }.buttonStyle(.plain)
                        }
                        Text("AI suggestions use provider search results. Review the place and choose its day/time before adding. Confirm hours and availability with the venue.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(24)
            }.background(Color.canvas).navigationTitle("Ideas for your days").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear { city = library.documents.first(where: { $0.id == documentID })?.stops.first?.name ?? "" }
                .sheet(item: $event) { JourneyEventEditor(documentID: documentID, event: $0) }
        }
    }
}

struct ItineraryIntoTripView: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Restaurants and attractions become places to rate. Other events, hotel bookings and flights are skipped. Imported places are unrated and aren’t marked visited.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(library.documents.filter { $0.id != tripID && !$0.plannedPlacesToRate.isEmpty }) { itinerary in
                    Button { guard var trip = library.documents.first(where: { $0.id == tripID }) else { return }; trip.addPlannedPlacesToJournal(from: itinerary); if library.save(trip) { dismiss() } else { error = library.error } } label: { VStack(alignment: .leading, spacing: 5) { Text(itinerary.title); Text(itinerary.routeLabel).font(.caption).foregroundStyle(.secondary) } }
                }
                if library.documents.allSatisfy({ $0.id == tripID || $0.plannedPlacesToRate.isEmpty }) { Text("No other trips have planned restaurants or attractions yet.").foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Import planned places").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
struct RatedRestaurantImportView: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    private var candidates: [RatedPlace] {
        var seen = Set<String>()
        var places = library.documents.filter { $0.id != tripID }.flatMap(\.places).filter { $0.place.category == .restaurant && $0.overall > 0 }
        for hotel in store.hotels { for venue in hotel.venues {
            let key = RestaurantPlace(hotel: hotel, venue: venue).id
            if let visit = store.restaurantVisits[key], visit.rating > 0 {
                places.append(RatedPlace(place: PlaceRecord(id: key, name: venue.name, category: .restaurant, city: hotel.city, address: hotel.address, website: hotel.website, source: "Aurum collection"), overall: Double(visit.rating) * 2, notes: visit.note))
            }
        } }
        return places.filter { seen.insert($0.place.id).inserted }
    }
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Your existing 5-star restaurant ratings are converted to the trip journal’s 10-point scale.").font(.caption).foregroundStyle(.secondary) }
                if candidates.isEmpty { ContentUnavailableView("No rated restaurants yet", systemImage: "star", description: Text("Rate a restaurant from its detail page or another trip.")) }
                ForEach(candidates) { candidate in
                    Button { guard var trip = library.documents.first(where: { $0.id == tripID }) else { return }; guard !trip.places.contains(where: { $0.place.id == candidate.place.id }) else { return }; var copy = candidate; copy.id = UUID(); trip.places.append(copy); if library.save(trip) { dismiss() } } label: { HStack { Text(candidate.place.name); Spacer(); Text(String(format: "%.1f", candidate.overall)).foregroundStyle(Color.bronze) } }.disabled(library.documents.first(where: { $0.id == tripID })?.places.contains(where: { $0.place.id == candidate.place.id }) == true)
                }
            }.navigationTitle("Your rated restaurants").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
