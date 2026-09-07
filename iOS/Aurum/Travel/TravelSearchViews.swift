import SwiftUI

// One editor surface can be pushed inside the trip's sheet or presented on its own.
private struct TripEditorEmbeddedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var tripEditorEmbedded: Bool { get { self[TripEditorEmbeddedKey.self] } set { self[TripEditorEmbeddedKey.self] = newValue } }
}
struct TripEditorNavigation<Content: View>: View {
    @Environment(\.tripEditorEmbedded) private var embedded
    @ViewBuilder var content: () -> Content
    var body: some View {
        if embedded { content().navigationBarBackButtonHidden(true) }
        else { NavigationStack { content() } }
    }
}
struct TripEditorBackButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tripEditorEmbedded) private var embedded
    var body: some View { Button(embedded ? "Back" : "Cancel") { dismiss() }.accessibilityIdentifier("trip-editor-back") }
}

struct PlaceFields: View {
    @Binding var place: PlaceRecord
    var fixedCategory: PlaceCategory?
    var context = ""
    var optional = false
    var identifier = "place-name"
    var suggestionSymbol: String?
    var journalEntry = false
    private var category: PlaceCategory { fixedCategory ?? place.category }
    private var title: String { journalEntry ? "Place you visited" : optional ? "Location · optional" : category == .hotel ? "Your hotel" : category == .restaurant ? "Your restaurant" : "Your place" }
    private var prompt: String { journalEntry ? "Search for a place you visited" : optional ? "Search for a venue or address" : category == .hotel ? "Search hotel name" : category == .restaurant ? "Search restaurant name" : "Search for a place" }
    var body: some View {
        Section {
            if journalEntry && fixedCategory == nil {
                Picker("Type of place", selection: $place.category) { ForEach(PlaceCategory.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.bronze).padding(.top, 2)
                LocationAutocompleteField(prompt, text: $place.name, kind: .place, identifier: identifier, category: category, searchContext: context, suggestionSymbol: suggestionSymbol, onEdit: {
                    place = PlaceRecord(name: place.name, category: category, city: context)
                }) { selection in var value = selection.place; value.category = category; place = value }
            }.padding(.vertical, 5)
            if place.hasCoordinate {
                VStack(alignment: .leading, spacing: 9) {
                    if !place.address.isEmpty { Text(place.address).font(.subheadline).foregroundStyle(.secondary) }
                    HStack {
                        Label("Ready for your trip map", systemImage: "checkmark.circle.fill").foregroundStyle(Color.bronze).accessibilityIdentifier("place-map-ready")
                        Spacer(minLength: 0)
                        if let rating = place.rating { Label(String(format: "%.1f", rating), systemImage: "star.fill").foregroundStyle(.secondary) }
                    }.font(.caption)
                    if !place.phone.isEmpty || !place.website.isEmpty {
                        DisclosureGroup("Place information") {
                            if !place.phone.isEmpty { LabeledContent("Phone", value: place.phone).textSelection(.enabled) }
                            if !place.website.isEmpty { Text(place.website).textSelection(.enabled).font(.caption).foregroundStyle(.secondary) }
                        }.font(.subheadline)
                    }
                    if place.source != "Manual entry" { Text(place.source).font(.caption2).foregroundStyle(.secondary) }
                }.padding(.vertical, 3)
            }
            if fixedCategory == nil && !journalEntry { Picker("Type of place", selection: $place.category) { ForEach(PlaceCategory.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu) }
        } header: { Text(title) } footer: {
            if !place.hasCoordinate { Text(optional ? "Leave blank for online plans or free time. Choosing a suggestion adds its location automatically." : "Choose a suggestion to include it on your map. You can also save a name now and choose its location later.") }
        }
        .onAppear { if let fixedCategory { place.category = fixedCategory } }
    }
}

struct ActivityIdeasView: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    var onSaved: () -> Void = {}
    @State private var city = ""
    @State private var interests = "Art, food and a little time outdoors"
    @State private var response: AITravelResponse?
    @State private var error: String?
    @State private var loading = false
    @State private var event: JourneyEvent?
    var body: some View {
        TripEditorNavigation {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Eyebrow(text: "Your AI travel editor")
                    Editorial("A little inspiration.\nA very personal day.", size: 33)
                    LocationAutocompleteField("Destination", text: $city, identifier: "ideas-destination").padding(16).cardSurface(cornerRadius: 18)
                    TextField("What do you love?", text: $interests, axis: .vertical).lineLimit(3...6).padding(15).cardSurface(cornerRadius: 18)
                    Button { Task { loading = true; error = nil; defer { loading = false }; do { response = try await api.recommendations(city: city, interests: interests) } catch { self.error = error.localizedDescription } } } label: { Label(loading ? "Gathering ideas…" : "Find my inspiration", systemImage: "sparkles").frame(maxWidth: .infinity).padding(.vertical, 11) }.buttonStyle(.glassProminent).disabled(loading || city.isEmpty)
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
                    if let response {
                        Text(response.text).font(.body).lineSpacing(5)
                        ForEach(response.places) { place in
                            Button { guard let document = library.documents.first(where: { $0.id == documentID }), let stop = document.stops.first(where: { $0.name.localizedCaseInsensitiveContains(city) }) ?? document.stops.first else { return }; event = JourneyEvent(stopID: stop.id, place: place) } label: {
                                HStack { VStack(alignment: .leading, spacing: 6) { Text(place.name).font(.system(.headline, design: .serif)); Text(place.address).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "plus.circle") }.padding(18).cardSurface(cornerRadius: 22)
                            }.buttonStyle(.plain)
                        }
                        Text("AI suggestions use provider search results. Review the place and choose its day/time before adding. Confirm hours and availability with the venue.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(24)
            }.background(Color.canvas).navigationTitle("Ideas for your days").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear { city = library.documents.first(where: { $0.id == documentID })?.stops.first?.name ?? "" }
                .navigationDestination(item: $event) { JourneyEventEditor(documentID: documentID, event: $0, onSaved: onSaved).environment(\.tripEditorEmbedded, true) }
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
                places.append(RatedPlace(place: PlaceRecord(id: key, name: venue.name, category: .restaurant, city: hotel.city, address: hotel.address, website: hotel.website, source: "Seur collection"), overall: Double(visit.rating) * 2, notes: visit.note))
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
