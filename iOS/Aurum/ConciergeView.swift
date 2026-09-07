import SwiftUI
import Observation

struct ConciergeMessage: Codable, Identifiable {
    enum Role: String, Codable { case traveler = "user", concierge = "assistant" }
    var id = UUID()
    let role: Role
    let text: String
    var suggestions: [String] = []
    var itinerary: ConciergeItinerary?
    var places: [PlaceRecord] = []
}
struct ConciergeContext: Codable {
    var trip = ""
    var preferences = ""
    var savedPlaces = ""
    var reference = ""
    static func tripSummary(_ document: JourneyDocument?) -> String {
        guard let d = document else { return "No trip selected. Ask which trip when needed." }
        let stops = d.stops.map { "\($0.name): \($0.nights) nights" + (d.dateMode == .dates ? ", arrival \($0.arrival)" : "") }
        let events = d.events.prefix(40).map { "\(d.date(for: $0) ?? "Day \($0.day + 1)") · \($0.timeLabel) · \($0.displayTitle)" }
        let stays = d.hotels.prefix(8).map { "\($0.place.name), \($0.checkIn)–\($0.checkOut)" }
        let flights = d.flights.prefix(8).map { "\($0.flightNumber): \($0.departureAirport)–\($0.arrivalAirport), \($0.departureDay) \($0.departureTime) to \($0.arrivalDay) \($0.arrivalTime)" }
        return String((["Selected trip: \(d.title)", "Route: \(d.routeLabel)", "Destinations:\n" + stops.joined(separator: "\n"), "Existing plans (leave unchanged):\n" + events.joined(separator: "\n"), "Stays:\n" + stays.joined(separator: "\n"), "Flights:\n" + flights.joined(separator: "\n")]).joined(separator: "\n\n").prefix(13000))
    }
}
struct ConciergeSearch: Codable { var city: String; var query: String }
struct ConciergeTurn: Codable { var role: String; var text: String }
struct ConciergeRequest: Encodable {
    var messages: [ConciergeTurn]
    var context: ConciergeContext
    var places: [PlaceRecord]
    var allowSearch: Bool
    var searchNote = ""
}
struct ConciergeReply: Codable {
    var text: String
    var suggestions: [String]
    var searches: [ConciergeSearch]
    var itinerary: ConciergeItinerary?
}
struct ConciergeItinerary: Codable, Identifiable {
    var title: String
    var days: [Day]
    var id: String { title + days.map { $0.city + String($0.number) }.joined() }
    struct Day: Codable { var number: Int; var city: String; var summary: String; var items: [Item] }
    struct Item: Codable {
        var title: String; var time: String; var durationMinutes: Int; var placeID: String?; var notes: String
        var minute: Int { let parts = time.split(separator: ":").compactMap { Int($0) }; return parts.count == 2 ? parts[0] * 60 + parts[1] : 0 }
    }
    func applying(to existing: JourneyDocument?, places: [PlaceRecord], startDate: String?) throws -> JourneyDocument {
        guard !days.isEmpty, days.count <= 14 else { throw JourneyError.message("This draft has no valid days.") }
        var document = existing ?? JourneyDocument(title: title, destination: days.map(\.city).uniqued().joined(separator: " → "), dateMode: startDate == nil ? .nights : .dates, startDate: startDate, endDate: startDate.map { TravelDay.adding(days.count - 1, to: $0) })
        if existing == nil {
            for (index, day) in days.enumerated() {
                if index == 0 || days[index - 1].city.foldedCityText != day.city.foldedCityText {
                    let length = days.dropFirst(index).prefix { $0.city.foldedCityText == day.city.foldedCityText }.count
                    let nights = index + length == days.count ? max(1, length - 1) : length
                    document.stops.append(JourneyStop(name: day.city, arrival: TravelDay.adding(index, to: startDate ?? TravelDay.key(.now)), nights: nights))
                }
            }
        }
        var added = 0
        var segment = 0, segmentStart = 0
        for (index, day) in days.enumerated() {
            guard day.number == index + 1 else { throw JourneyError.message("The draft days need to be in order.") }
            let stop: JourneyStop, localDay: Int
            if existing != nil {
                guard let target = document.days.first(where: { $0.index == day.number - 1 && $0.city.foldedCityText == day.city.foldedCityText }), let found = document.stops.first(where: { $0.id == target.stopID }) else {
                    throw JourneyError.message("Day \(day.number) in \(day.city) does not match this trip’s route. Ask the concierge to adapt the draft to your selected trip, or save it as a new trip.")
                }
                stop = found; localDay = target.localDay
            } else {
                if index > 0 && days[index - 1].city.foldedCityText != day.city.foldedCityText { segment += 1; segmentStart = index }
                stop = document.stops[segment]; localDay = index - segmentStart
            }
            for item in day.items {
                guard JourneyDocument.validTime(item.time), (15...720).contains(item.durationMinutes), !item.title.isEmpty else { throw JourneyError.message("Check this draft’s times and activities.") }
                if document.events.contains(where: { $0.stopID == stop.id && $0.day == localDay && $0.minute == item.minute && $0.displayTitle.foldedCityText == item.title.foldedCityText }) { continue }
                let place = places.first { $0.id == item.placeID }
                var event = JourneyEvent(stopID: stop.id, day: localDay, minute: item.minute, place: place ?? PlaceRecord(name: "", category: .other, city: day.city), description: item.notes, kind: .custom, title: item.title, durationMinutes: item.durationMinutes)
                if let url = place?.website, validatedURL(url) != nil { event.links = [url] }
                document.events.append(event); added += 1
            }
        }
        guard added > 0 else { throw JourneyError.message("These activities are already in this trip.") }
        if let issue = document.validationError() { throw JourneyError.message(issue) }
        return document
    }
}
private extension Array where Element: Hashable { func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } } }

@MainActor @Observable final class ConciergeConversation {
    typealias Respond = (ConciergeRequest) async throws -> ConciergeReply
    typealias Search = (ConciergeSearch) async throws -> [PlaceRecord]
    private(set) var messages: [ConciergeMessage] = []
    private(set) var isReplying = false
    private(set) var progress = "Thinking through your trip…"
    private(set) var error: String?
    var selectedTripID: UUID?
    var usePreferences = true
    var useSavedPlaces = false
    var pendingInput = ""
    var reference = ""
    var savedDrafts = Set<UUID>()
    private var replyTask: Task<Void, Never>?
    private var generation = UUID()
    func send(_ input: String, context: ConciergeContext, respond: @escaping Respond, search: @escaping Search) {
        let text = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !text.isEmpty, !isReplying else { return }
        messages.append(ConciergeMessage(role: .traveler, text: text))
        run(context: context, respond: respond, search: search)
    }
    func retry(context: ConciergeContext, respond: @escaping Respond, search: @escaping Search) {
        guard messages.last?.role == .traveler, !isReplying else { return }
        run(context: context, respond: respond, search: search)
    }
    private func run(context: ConciergeContext, respond: @escaping Respond, search: @escaping Search) {
        isReplying = true; error = nil; progress = "Thinking through your trip…"
        generation = UUID(); let revision = generation
        var history = messages.suffix(12).map { message in
            var text = message.text
            if let plan = message.itinerary, let data = try? JSONEncoder().encode(plan), let encoded = String(data: data, encoding: .utf8) {
                text += "\n\nPreviously proposed draft (not proof of saving or booking):\n" + encoded
            }
            return ConciergeTurn(role: message.role.rawValue, text: String(text.prefix(message.role == .traveler ? 4000 : 12000)))
        }
        while history.map(\.text.count).reduce(0, +) > 24000 && history.count > 1 { history.removeFirst() }
        var known: [PlaceRecord] = []; var seen = Set<String>()
        for place in messages.reversed().flatMap(\.places) where seen.insert(place.id).inserted && known.count < 16 { known.append(place) }
        let initial = ConciergeRequest(messages: history, context: context, places: known, allowSearch: true)
        replyTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == revision { isReplying = false; replyTask = nil } }
            do {
                var request = initial
                var response = try await respond(request)
                try Task.checkCancellation()
                if !response.searches.isEmpty {
                    var found: [PlaceRecord] = []; var notes: [String] = []
                    for query in response.searches.prefix(2) {
                        progress = "Finding places in \(query.city)…"
                        do { found += try await search(query) }
                        catch { if Task.isCancelled { throw CancellationError() }; notes.append("No map results available for \(query.query) in \(query.city).") }
                        try Task.checkCancellation()
                    }
                    var ids = Set<String>()
                    request.places = Array((found + known).filter { $0.source == "Apple Maps" && $0.hasCoordinate && ids.insert($0.id).inserted }.prefix(16))
                    request.searchNote = notes.joined(separator: " ")
                    request.allowSearch = false
                    progress = "Putting your recommendations together…"
                    response = try await respond(request)
                    try Task.checkCancellation()
                }
                guard generation == revision else { return }
                messages.append(ConciergeMessage(role: .concierge, text: response.text, suggestions: response.suggestions, itinerary: response.itinerary, places: request.places))
            } catch { if generation == revision && !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func stop() { generation = UUID(); replyTask?.cancel(); replyTask = nil; isReplying = false; error = messages.last?.role == .traveler ? "Response stopped. You can retry when you’re ready." : nil }
    func reset() { stop(); messages = []; error = nil; reference = ""; pendingInput = ""; savedDrafts = [] }
}

struct ConciergeView: View {
    @Environment(TravelStore.self) private var store
    @Environment(TravelAPI.self) private var api
    @Environment(JourneyLibrary.self) private var library
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool
    @State private var draft = ""
    @State private var resetAlert = false
    @State private var review: ConciergeMessage?
    private var conversation: ConciergeConversation { store.concierge }
    private var available: Bool { api.isSignedIn || ConciergeFixtures.enabled }
    private var selectedTrip: JourneyDocument? { library.documents.first { $0.id == conversation.selectedTripID } }
    private var context: ConciergeContext {
        let profile = onboarding.profile
        let preferences = conversation.usePreferences ? "Interests: \(profile.interests.sorted().joined(separator: ", ")). Cuisines: \(profile.cuisines.sorted().joined(separator: ", ")). Destination interest: \(profile.destination)." : ""
        let saved = conversation.useSavedPlaces ? (store.savedHotels.prefix(6).map { "\($0.name), \($0.city)" } + store.savedDiscoveries.prefix(10).map { "\($0.record.name), \($0.city.name)" }).joined(separator: "\n") : ""
        return ConciergeContext(trip: ConciergeContext.tripSummary(selectedTrip), preferences: preferences, savedPlaces: saved, reference: conversation.reference)
    }
    private let starters = [
        ("Plan a trip from scratch", "Help me plan a trip. Start by asking what you need to know, and suggest a useful approach.", "calendar"),
        ("Make the most of my trip", "Review my selected trip and suggest a detailed plan for the gaps, taking existing plans and flights into account.", "suitcase.rolling"),
        ("Find places I’ll love", "Help me find restaurants and things to do that fit my tastes. Ask where I’m going if you don’t know.", "fork.knife"),
        ("Help me choose where to go", "Help me choose a destination. Ask about timing, budget and the kind of experience I want, then explain the trade-offs.", "globe.europe.africa")
    ]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    contextPicker
                    if conversation.messages.isEmpty { welcome }
                    ForEach(conversation.messages) { message in messageView(message).id(message.id) }
                    if conversation.isReplying {
                        HStack(spacing: 10) { ProgressView(); Text(conversation.progress).font(.subheadline).foregroundStyle(.secondary) }
                            .accessibilityIdentifier("concierge-progress")
                    }
                    if let error = conversation.error {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(error).font(.subheadline).foregroundStyle(.secondary)
                            Button("Try again") { conversation.retry(context: context, respond: api.conciergeReply, search: api.conciergeSearch) }.buttonStyle(.glass).disabled(!available)
                        }.accessibilityIdentifier("concierge-error")
                    }
                    Color.clear.frame(height: 1).id("conversation-bottom")
                }.padding(22)
            }.scrollDismissesKeyboard(.interactively)
                .onChange(of: conversation.messages.count) {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                        if let message = conversation.messages.last, message.role == .concierge { proxy.scrollTo(message.id, anchor: .top) }
                        else { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
                    }
                }
                .onChange(of: composerFocused) { if composerFocused { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { proxy.scrollTo("conversation-bottom", anchor: .bottom) } } }
        }.background(Color.canvas).navigationTitle("Concierge").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { resetAlert = true } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("New conversation").disabled(conversation.messages.isEmpty) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .confirmationDialog("Start a new conversation?", isPresented: $resetAlert, titleVisibility: .visible) { Button("Clear this conversation", role: .destructive) { conversation.reset(); draft = "" } }
            .sheet(item: $review) { message in
                if let itinerary = message.itinerary { ConciergePlanReview(itinerary: itinerary, places: message.places, selectedTripID: conversation.selectedTripID) { id in conversation.savedDrafts.insert(message.id); conversation.selectedTripID = id } }
            }
            .task { try? await api.refresh(); acceptPending() }
            .onChange(of: api.isSignedIn) { acceptPending() }
    }
    private var contextPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                Button("General travel advice") { conversation.selectedTripID = nil }
                ForEach(library.documents) { trip in Button(trip.title) { conversation.selectedTripID = trip.id } }
                Divider()
                Toggle("Use travel preferences", isOn: Binding(get: { conversation.usePreferences }, set: { conversation.usePreferences = $0 }))
                Toggle("Include saved places", isOn: Binding(get: { conversation.useSavedPlaces }, set: { conversation.useSavedPlaces = $0 }))
            } label: {
                HStack { Label(selectedTrip?.title ?? "General travel advice", systemImage: selectedTrip == nil ? "sparkles" : "suitcase.rolling").lineLimit(1); Spacer(); Image(systemName: "chevron.down").font(.caption) }.font(.subheadline).padding(.vertical, 10)
            }.disabled(conversation.isReplying).accessibilityIdentifier("concierge-context")
            Text("Uses this conversation, your selected trip’s schedule and the context you enable. Booking references, journal notes and photos aren’t shared.").font(.caption2).foregroundStyle(.secondary)
            Divider()
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Eyebrow(text: "Your AI travel concierge")
            Editorial("A better trip\nstarts here.", size: 36)
            Text("Build a day-by-day itinerary, find the right neighborhood, compare options or refine a trip you’re already planning.").font(.subheadline).foregroundStyle(.secondary)
            if !available { NavigationLink("Sign in to start planning") { TravelAccountView() }.buttonStyle(.glassProminent) }
            ForEach(starters, id: \.2) { title, prompt, icon in
                Button { send(prompt) } label: { HStack(spacing: 14) { Image(systemName: icon).foregroundStyle(Color.bronze).frame(width: 24); Text(title).font(.subheadline).foregroundStyle(.primary); Spacer(); Image(systemName: "arrow.up.left").font(.caption) }.padding(17).cardSurface(cornerRadius: 20) }.buttonStyle(PressStyle()).disabled(!available).accessibilityIdentifier("concierge-prompt-" + icon)
            }
        }
    }
    @ViewBuilder private func messageView(_ message: ConciergeMessage) -> some View {
        if message.role == .traveler {
            HStack { Spacer(minLength: 28); Text(message.text).font(.body).textSelection(.enabled).padding(16).cardSurface(cornerRadius: 22, emphasized: true) }.accessibilityIdentifier("concierge-user-message")
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Label { Text("SEUR CONCIERGE") } icon: { SeurLogo(size: 22) }.font(.caption2.weight(.semibold)).foregroundStyle(Color.bronze)
                ConciergeMarkdown(text: message.text).accessibilityElement(children: .combine).accessibilityIdentifier("concierge-reply")
                if let itinerary = message.itinerary {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        Text(itinerary.title).font(.headline)
                        Text("\(itinerary.days.count) days · \(itinerary.days.reduce(0) { $0 + $1.items.count }) suggested plans").font(.caption).foregroundStyle(.secondary)
                        Button { review = message } label: { Label(conversation.savedDrafts.contains(message.id) ? "Added to your trips" : "Review & add to a trip", systemImage: conversation.savedDrafts.contains(message.id) ? "checkmark" : "calendar.badge.plus") }.buttonStyle(.glassProminent).disabled(conversation.savedDrafts.contains(message.id)).accessibilityIdentifier("concierge-review-plan")
                    }
                }
                if message.id == conversation.messages.last?.id {
                    ForEach(message.suggestions, id: \.self) { suggestion in Button(suggestion) { send(suggestion) }.font(.subheadline).multilineTextAlignment(.leading).disabled(conversation.isReplying || !available) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(available ? "Ask, plan or refine…" : "Sign in to chat with your concierge", text: $draft, axis: .vertical).lineLimit(1...5).focused($composerFocused).padding(10).disabled(!available).accessibilityIdentifier("concierge-input")
                .onChange(of: draft) { if draft.count > 4000 { draft = String(draft.prefix(4000)) } }
            Button { if conversation.isReplying { conversation.stop() } else { send(draft) } } label: { Image(systemName: conversation.isReplying ? "stop.fill" : "arrow.up").frame(width: 40, height: 40) }.buttonStyle(.glassProminent).buttonBorderShape(.circle).disabled(!available || (!conversation.isReplying && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)).accessibilityLabel(conversation.isReplying ? "Stop response" : "Send message").accessibilityIdentifier("concierge-send")
        }.padding(8).glassEffect(.regular, in: .rect(cornerRadius: 26)).padding(.horizontal, 16).padding(.bottom, 8)
    }
    private func send(_ text: String) {
        guard available, !conversation.isReplying else { return }
        conversation.send(text, context: context, respond: api.conciergeReply, search: api.conciergeSearch)
        draft = ""; composerFocused = false
    }
    private func acceptPending() {
        guard !conversation.pendingInput.isEmpty else { return }
        draft = conversation.pendingInput
        if available { let input = conversation.pendingInput; conversation.pendingInput = ""; send(input) }
    }
}

private struct ConciergeMarkdown: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, block in
                let heading = block.hasPrefix("#")
                let value = heading ? block.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) : block
                Text((try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)).font(heading ? .headline : .body).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ConciergePlanReview: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let itinerary: ConciergeItinerary
    let places: [PlaceRecord]
    let selectedTripID: UUID?
    let onSaved: (UUID) -> Void
    @State private var target: UUID?
    @State private var exactDates = false
    @State private var start = Date.now
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(itinerary.title).font(.title2.weight(.semibold))
                    Picker("Add to", selection: $target) { Text("Create a new trip").tag(UUID?.none); ForEach(library.documents) { Text($0.title).tag(Optional($0.id)) } }.pickerStyle(.menu)
                    if target == nil { Toggle("Choose exact dates", isOn: $exactDates); if exactDates { DatePicker("First day", selection: $start, displayedComponents: .date) } }
                    Text("Suggested local times, not reservations. Existing plans stay in place; check for overlaps before adding. You can edit every activity afterward.").font(.caption).foregroundStyle(.secondary)
                    ForEach(itinerary.days, id: \.number) { day in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Day \(day.number) · \(day.city)").font(.headline)
                            if !day.summary.isEmpty { Text(day.summary).font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(item.time).font(.caption.monospacedDigit()).foregroundStyle(Color.bronze).frame(width: 44)
                                    VStack(alignment: .leading, spacing: 5) { Text(item.title).font(.subheadline.weight(.medium)); Text(item.notes).font(.caption).foregroundStyle(.secondary); if let place = places.first(where: { $0.id == item.placeID }) { Text(place.address).font(.caption2).foregroundStyle(.secondary) } }
                                }
                            }
                            Divider()
                        }
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.subheadline) }
                }.padding(22)
            }.background(Color.canvas).navigationTitle("Review your plan").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add plan", action: save).accessibilityIdentifier("concierge-save-plan") } }
                .onAppear { target = selectedTripID }
        }
    }
    private func save() {
        do {
            let existing = library.documents.first { $0.id == target }
            if target != nil && existing == nil { throw JourneyError.message("This trip is no longer available.") }
            let document = try itinerary.applying(to: existing, places: places, startDate: target == nil && exactDates ? TravelDay.key(start) : nil)
            guard library.save(document) else { throw JourneyError.message(library.error ?? "Couldn’t save this plan.") }
            onSaved(document.id); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor enum ConciergeFixtures {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--concierge-testing") }
    static var plan: ConciergeItinerary { .init(title: "A thoughtful Paris weekend", days: [.init(number: 1, city: "Paris", summary: "An easy first day", items: [.init(title: "Explore the neighborhood", time: "10:00", durationMinutes: 90, placeID: nil, notes: "Keep the first morning flexible.")]), .init(number: 2, city: "Paris", summary: "Art and time outdoors", items: [.init(title: "An afternoon in the gardens", time: "14:00", durationMinutes: 90, placeID: nil, notes: "Leave time for a relaxed lunch.")])]) }
}
