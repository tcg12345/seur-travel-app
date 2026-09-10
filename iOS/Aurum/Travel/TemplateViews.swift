import SwiftUI

@MainActor @Observable final class TemplateDirectory {
    static let shared = TemplateDirectory()
    private(set) var remote: [RemoteJourney] = []
    private(set) var message: String?
    private var loaded: Date?
    private var server = ""
    private var loading = false
    func load(_ api: TravelAPI, force: Bool = false) async {
        guard !loading else { return }
        if server != api.baseURL { remote = []; loaded = nil; server = api.baseURL }
        guard force || loaded.map({ Date.now.timeIntervalSince($0) > 300 }) ?? true else { return }
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        loading = true; defer { loading = false }; let requestedServer = server
        do {
            let values = try await api.templates()
            guard api.baseURL == requestedServer else { return }
            remote = values; loaded = .now; message = nil
        } catch { message = "Showing saved starting points. Connect to load the latest community templates." }
    }
    func entries(city: String = "", tag: String = "") -> [TemplateEntry] {
        let remoteIDs = Set(remote.map { $0.document.id })
        return (remote.map { TemplateEntry(document: $0.document, remote: true) } + TemplateCatalog.bundled.filter { !remoteIDs.contains($0.id) }.map { TemplateEntry(document: $0) })
            .filter { TemplateCatalog.matches($0.document, city: city, tag: tag) }
    }
}
struct TemplateEntry: Identifiable { var document: JourneyDocument; var remote = false; var id: UUID { document.id } }
/// A quiet entry point, visible only when a city has a saved or discoverable template.
struct CityTemplateLink: View {
    let city: String
    @Environment(TravelAPI.self) private var api
    @Environment(JourneyLibrary.self) private var library
    @State private var directory = TemplateDirectory.shared
    private var hasTemplates: Bool {
        !directory.entries(city: city).isEmpty || library.documents.contains { TemplateCatalog.matches($0, city: city) }
    }
    var body: some View {
        Group {
            if hasTemplates {
                NavigationLink { TemplateBrowseView(initialCity: city) } label: {
                    Label("Trip templates", systemImage: "doc.on.doc")
                        .font(.subheadline).foregroundStyle(Color.bronze)
                        .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("city-trip-templates")
                    .accessibilityHint("Browse itineraries for " + city)
            }
        }.task(id: api.baseURL) { await directory.load(api) }
    }
}
private struct TemplateCard: View {
    let document: JourneyDocument
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("\(document.nights) nights · " + document.routeLabel, systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.caption.weight(.medium)).foregroundStyle(Color.bronze).lineLimit(2)
            Text(document.title).font(.system(.title3, design: .serif)).foregroundStyle(.primary).lineLimit(2)
            Text(document.templateMeta?.tagline ?? "Make this itinerary your own.").font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            Text((document.templateMeta?.tags ?? []).map { $0.capitalized }.joined(separator: " · ")).font(.caption).foregroundStyle(Color.bronze)
        }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Color.bronze.opacity(0.45)).frame(height: 2) }
            .accessibilityElement(children: .combine)
    }
}
struct TemplateLibraryView: View {
    var search = ""
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @State private var directory = TemplateDirectory.shared
    @State private var tag = ""
    private var own: [JourneyDocument] { library.documents.filter { TemplateCatalog.matches($0, city: search, tag: tag) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Travel style", selection: $tag) { Text("All styles").tag(""); ForEach(["luxury", "food", "beach", "art", "design", "culture", "city"], id: \.self) { Text($0.capitalized).tag($0) } }.pickerStyle(.menu)
            if !own.isEmpty {
                Text("Your templates").font(.headline)
                ForEach(own) { template in NavigationLink { TemplateDetailView(entry: TemplateEntry(document: template)) } label: { TemplateCard(document: template) }.buttonStyle(.plain) }
            }
            Text("Ready to make your own").font(.headline)
            Text("Choose a starting point, set your dates, and change anything.").font(.subheadline).foregroundStyle(.secondary)
            ForEach(directory.entries(city: search, tag: tag)) { entry in NavigationLink { TemplateDetailView(entry: entry) } label: { TemplateCard(document: entry.document) }.buttonStyle(.plain) }
            if let message = directory.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if own.isEmpty && directory.entries(city: search, tag: tag).isEmpty { Text("No matching templates. Try another city.").foregroundStyle(.secondary) }
        }.task { await directory.load(api) }
    }
}
struct TemplateBrowseView: View {
    var initialCity = ""
    @State private var search = ""
    var body: some View {
        ScrollView { TemplateLibraryView(search: search).padding(22) }.background(Color.canvas).navigationTitle("Trip templates")
            .searchable(text: $search, prompt: "Search by city or itinerary")
            .onAppear { if search.isEmpty { search = initialCity } }
    }
}
struct TemplateDetailView: View {
    let entry: TemplateEntry
    var previewOnly = false
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: JourneyDocument?
    @State private var error: String?
    @State private var using = false
    @State private var created: UUID?
    @State private var publishing = false
    @State private var sharing = false
    private var document: JourneyDocument { library.documents.first { $0.id == entry.id } ?? loaded ?? entry.document }
    private var canUse: Bool { !entry.remote || loaded != nil }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TemplateCard(document: document)
                if let meta = document.templateMeta {
                    if !meta.authorHandle.isEmpty { Text("By @" + meta.authorHandle).font(.subheadline).foregroundStyle(.secondary) }
                    if !meta.suggestedSeason.isEmpty { Label(meta.suggestedSeason, systemImage: "sun.max").font(.subheadline) }
                    if meta.cloneCount > 0 { Text("\(meta.cloneCount) trips started from this itinerary").font(.caption).foregroundStyle(.secondary) }
                }
                Text("A plan to personalize. Hotels and meals are suggestions, not reservations. Check opening days, seasonal dates and availability before booking.").font(.subheadline).foregroundStyle(.secondary)
                if !canUse { if let error { Text(error).foregroundStyle(.secondary); Button("Retry") { Task { await load() } } } else { ProgressView("Loading itinerary…") } }
                else {
                    ForEach(document.stops) { stop in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(stop.name).font(.title2.weight(.semibold))
                            Text("\(stop.nights) nights").font(.caption).foregroundStyle(Color.bronze)
                            ForEach(document.hotels.filter { stop.arrival <= $0.checkIn && $0.checkIn < stop.departure }) { hotel in
                                Label(hotel.place.name, systemImage: "bed.double").font(.subheadline.weight(.medium))
                            }
                            ForEach(document.days.filter { $0.stopID == stop.id }) { day in
                                let events = document.events.filter { $0.stopID == day.stopID && $0.day == day.localDay }.sorted { $0.sortMinute < $1.sortMinute }
                                DisclosureGroup("Day \(document.stops.prefix { $0.id != stop.id }.reduce(0) { $0 + $1.nights } + day.localDay + 1) · " + (day.localDay == stop.nights ? "Departure" : "Your day")) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        if events.isEmpty { Text("Unscheduled time to make your own.").foregroundStyle(.secondary) }
                                        ForEach(events) { event in HStack(alignment: .top, spacing: 12) { Text(event.scheduleLabel).font(.caption.monospacedDigit()).foregroundStyle(Color.bronze); Text(event.displayTitle).font(.subheadline) }.frame(maxWidth: .infinity, alignment: .leading) }
                                    }.padding(.vertical, 10)
                                }.tint(.primary)
                            }
                            Divider()
                        }
                    }
                    if document.templateMeta?.includesRatings == true && !document.places.isEmpty {
                        Text("The author's ratings").font(.headline)
                        ForEach(document.places) { place in HStack { Text(place.place.name); Spacer(); Label(place.overall.formatted(), systemImage: "star.fill").foregroundStyle(Color.bronze) }.font(.subheadline) }
                    }
                    if document.templateMeta?.includesCosts == true { Text("Included costs are the author's planning estimates, not current quotes.").font(.caption).foregroundStyle(.secondary) }
                    if !previewOnly && library.documents.contains(where: { $0.id == entry.id }) {
                        Button("Publish or update public template", systemImage: "globe") { publishing = true }.disabled(!api.isSignedIn)
                        if !api.isSignedIn { Text("Sign in from Travel to publish. Your saved template works offline.").font(.caption).foregroundStyle(.secondary) }
                        Button("Remove local template", role: .destructive) { if library.remove(entry.id) { dismiss() } }
                        Button("Sharing & audience") { sharing = true }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }.padding(22)
        }.background(Color.canvas).navigationTitle("Trip template").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if !previewOnly { Button("Use this template") { using = true }.font(.headline).frame(maxWidth: .infinity).padding(14).buttonStyle(.glassProminent).disabled(!canUse).padding(.horizontal, 22).padding(.bottom, 8).accessibilityIdentifier("template-use") }
            }
            .task(id: entry.id) { await load() }
            .sheet(isPresented: $sharing) { JourneyShareView(documentID: entry.id) }
            .sheet(isPresented: $using) { UseTemplateSheet(document: document) { created = $0 } }
            .navigationDestination(item: $created) { JourneyDetailView(id: $0) }
            .confirmationDialog("Publish this template for everyone?", isPresented: $publishing, titleVisibility: .visible) {
                Button("Publish template") { Task {
                    do { var copy = document; copy.visibility = .public; copy.updatedAt = Date.now.timeIntervalSince1970; let saved = try await api.upload(copy); _ = library.save(saved.document); await TemplateDirectory.shared.load(api, force: true) }
                    catch { self.error = error.localizedDescription }
                } }
            } message: { Text("The itinerary, places and selected ratings or costs will appear in public template discovery.") }
    }
    private func load() async {
        guard entry.remote else { return }
        do {
            let remote = entry.document.visibility == .public ? try await api.template(entry.id) : try await api.document(entry.id.uuidString)
            guard remote.document.isTemplate == true else { throw TemplateError.invalid("This shared itinerary is no longer a template.") }
            loaded = remote.document; error = nil
        } catch { self.error = "The template couldn't be loaded. Check your connection or try another itinerary." }
    }
}
struct UseTemplateSheet: View {
    let document: JourneyDocument
    var onCreated: (UUID) -> Void
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var departure = Calendar.current.startOfDay(for: .now)
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(document.title).font(.headline); Text("\(document.nights) nights · Your copy is private and fully editable.").font(.subheadline).foregroundStyle(.secondary) }
                Section("When do you leave?") { DatePicker("Departure", selection: $departure, displayedComponents: .date).accessibilityIdentifier("template-departure") }
                if let scheduled = try? document.usingTemplate(departure: TravelDay.key(departure)) {
                    Section("Seasons along your route") {
                        ForEach(scheduled.stops) { stop in
                            SeasonalityCard(city: stop.name, countryCode: stop.countryCode ?? TravelStatistics.countryCode(stop.country), arrival: stop.arrival, departure: stop.departure)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Make it your trip").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Create trip") {
                        do {
                            let trip = try document.usingTemplate(departure: TravelDay.key(departure))
                            guard library.save(trip) else { error = library.error; return }
                            if api.isSignedIn { Task { try? await api.recordTemplateUse(document.id, clone: trip.id) } }
                            onCreated(trip.id); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("template-create-trip") }
                }
        }
    }
}
struct SaveTemplateSheet: View {
    let document: JourneyDocument
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var tagline = ""
    @State private var tags = ""
    @State private var season = ""
    @State private var costs = false
    @State private var ratings = false
    @State private var preview: JourneyDocument?
    @State private var error: String?
    private func draft() throws -> JourneyDocument {
        let tags = Array(Set(tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })).sorted()
        var template = try document.templated(meta: TemplateMeta(tagline: tagline, tags: tags, suggestedSeason: season, authorHandle: api.account?.handle ?? ""), includeCosts: costs, includeRatings: ratings)
        template.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = template.validationError() { throw TemplateError.invalid(error) }; return template
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("A starting point for another trip") {
                    TextField("Template title", text: $title)
                    TextField("A short tagline", text: $tagline, axis: .vertical)
                    TextField("Tags, separated by commas", text: $tags).textInputAutocapitalization(.never)
                    TextField("Suggested season", text: $season)
                }
                Section {
                    Toggle("Include estimated costs", isOn: $costs)
                    Toggle("Include my ratings", isOn: $ratings)
                } footer: { Text("Booking references, flights, notes, guest details and photos are removed. Review place names and activity titles before publishing.") }
                Section { Button("Preview cleaned itinerary") { do { preview = try draft() } catch { self.error = error.localizedDescription } } }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Save as template").navigationBarTitleDisplayMode(.inline)
                .onAppear { title = document.title }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save template") { do { let value = try draft(); if library.save(value) { dismiss() } else { error = library.error } } catch { self.error = error.localizedDescription } }.accessibilityIdentifier("template-save") }
                }
                .sheet(item: $preview) { template in NavigationStack { TemplateDetailView(entry: TemplateEntry(document: template), previewOnly: true).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { preview = nil } } } } }
        }
    }
}
