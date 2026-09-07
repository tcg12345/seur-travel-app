import SwiftUI
import Observation

struct ConciergeMessage: Identifiable {
    enum Role { case traveler, concierge }
    let id = UUID()
    let role: Role
    let text: String
    var hotelIDs: [String] = []
    var suggestions: [String] = []
    var action: ConciergeAction?
}

enum ConciergeAction: String {
    case flights = "Explore flights"
    case experiences = "Explore experiences"
    case trips = "Open my itinerary"
    case collection = "Browse the collection"
}

struct ConciergeContext {
    var city: String?
    var cuisine: String?
}

/// Deliberately local preview. No LLM, network request, or reservation action.
@MainActor enum ConciergeEngine {
    static func reply(to prompt: String, context: inout ConciergeContext, store: TravelStore) -> ConciergeMessage {
        let text = prompt.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let words = Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        func contains(_ values: [String]) -> Bool { values.contains { words.contains($0) } }
        let destination = TravelStore.cities.first { text.contains($0.lowercased()) }
        if let destination { context.city = destination }
        if text.contains("any cuisine") || text.contains("all cuisines") { context.cuisine = nil }
        for cuisine in ["French", "Japanese", "Chinese", "Cantonese", "Italian", "Thai", "Indian"] {
            if text.contains(cuisine.lowercased()) { context.cuisine = cuisine }
        }
        if text.hasPrefix("tell me about "),
           let hotel = store.hotels.first(where: { text.contains($0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) }),
           let venue = hotel.venues.sorted(by: { $0.name.count > $1.name.count }).first(where: { text.contains($0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) }) {
            context.city = hotel.city
            let description = venue.description == "n/a" ? "This venue is part of the hotel's dining collection." : venue.description
            return ConciergeMessage(role: .concierge, text: "\(venue.name) at \(hotel.name)\n\n\(description)\n\nFor your visit, ask the hotel about its current menu, dietary requirements, dress code and table availability. You can save a dining plan from the restaurant page; it doesn’t reserve a table.", suggestions: ["Great dining in \(hotel.city)", "Show my itinerary"])
        }
        if contains(["book", "reserve", "reservation", "confirm", "pay"]) {
            return ConciergeMessage(role: .concierge, text: "I can help you choose a stay or a table, but this concierge preview can’t make reservations or take payment. Open a hotel below to choose dates and continue with its official website.", hotelIDs: matches(context: context, store: store).map(\.id), suggestions: ["Show my itinerary", "Find a hotel in Paris"])
        }
        if contains(["flight", "flights", "fly", "airfare", "airline"]) {
            return ConciergeMessage(role: .concierge, text: "Let’s make the journey part of the experience. In Flights, choose your route, dates, and cabin, then compare current fares with Google Flights. I don’t have live prices or seat availability in this preview.", suggestions: ["Find a hotel in Paris", "Plan a weekend in Bangkok"], action: .flights)
        }
        if contains(["saved", "favorites", "favourites"]) {
            let hotels = Array(store.savedHotels.prefix(2))
            return ConciergeMessage(role: .concierge, text: hotels.isEmpty ? "Your collection is still an open invitation. Save a hotel with the heart button, and I can bring it into this conversation. Shall we start with a city?" : "Here are \(hotels.count == 1 ? "a stay" : "two stays") from your saved collection. Open one to explore its restaurants and plan your visit.", hotelIDs: hotels.map(\.id), suggestions: ["Find a hotel in Paris", "Great dining in Bangkok"])
        }
        if text.contains("my trip") || text.contains("my itinerary") || text.contains("my plans") {
            let plans = store.plans.sorted { $0.start < $1.start }
            let summary = plans.prefix(4).map { "• \($0.start.formatted(date: .abbreviated, time: .omitted)): \($0.name), \($0.city)" }.joined(separator: "\n")
            return ConciergeMessage(role: .concierge, text: plans.isEmpty ? "Your itinerary is a fresh page. Add a stay, a dining plan, or an experience from the app, and I can summarize it here. Nothing is booked until you confirm with the provider." : "Here’s what you’re planning:\n\n\(summary)\n\nThese are draft plans, not confirmed reservations. You can edit dates and guests in Trips.", suggestions: ["Plan a weekend in Paris", "Show my saved places"], action: .trips)
        }
        if contains(["experience", "experiences", "activity", "activities", "tour", "tours", "museum"]) {
            return ConciergeMessage(role: .concierge, text: "\(context.city.map { "For \($0), I’d start with" } ?? "A few lovely starting points:") a food or wine experience, time with a local guide, or a scenic day trip. Explore the current options with local providers in Experiences; these are ideas rather than confirmed tours.", suggestions: ["Find a hotel in Paris", "Show my itinerary"], action: .experiences)
        }
        let wantsPlan = contains(["weekend", "itinerary", "days", "plan"])
        let wantsHotels = contains(["hotel", "hotels", "stay", "stays", "dining", "food", "restaurant", "restaurants", "table", "tables", "romantic", "best"])
        let isFollowUp = contains(["instead", "more", "options", "another"]) || text.contains("what about")
        if destination != nil || context.cuisine != nil || wantsHotels || wantsPlan || (context.city != nil && isFollowUp) {
            guard let city = context.city else {
                return ConciergeMessage(role: .concierge, text: "Of course. Which city is calling? Start with a destination, a hotel, or a cuisine.", suggestions: ["Paris", "Bangkok", "Tokyo"])
            }
            let hotels = matches(context: context, store: store)
            guard let first = hotels.first else {
                return ConciergeMessage(role: .concierge, text: "I couldn’t find a match for \(context.cuisine.map { "\($0) dining in " } ?? "")\(city) in this collection. Let’s try a different cuisine or broaden the search.", suggestions: ["Any cuisine in \(city)", "Find a hotel in Paris"], action: .collection)
            }
            if wantsPlan {
                let venue = first.venues.first { context.cuisine == nil || $0.cuisine.localizedCaseInsensitiveContains(context.cuisine!) } ?? first.venues.first
                let dinner = venue.map { "consider \($0.name) at the hotel" } ?? "explore the hotel’s dining options"
                return ConciergeMessage(role: .concierge, text: "A relaxed weekend idea for \(city):\n\nDAY ONE\nSettle into \(first.name). Leave time to explore nearby, then \(dinner).\n\nDAY TWO\nChoose a local food or cultural experience and keep the afternoon unhurried.\n\nThis is inspiration, not a booking or a checked schedule. Open the stay below to make the plan your own.", hotelIDs: [first.id], suggestions: ["Show dining in \(city)", "Explore experiences", "Show my itinerary"])
            }
            let intro = context.cuisine.map { "For \($0.lowercased()) dining in \(city), these hotels have matching venues in the collection." } ?? "A couple of starting points for \(city), with dining right at the heart of the stay."
            let details = hotels.map { hotel in
                let venue = hotel.venues.first { (context.cuisine == nil && $0.cuisine != "n/a") || (context.cuisine != nil && $0.cuisine.localizedCaseInsensitiveContains(context.cuisine!)) }
                return "\(hotel.name) has \(hotel.venues.count) listed dining options" + (venue.map { ", including \($0.name) (\($0.cuisine))." } ?? ".")
            }.joined(separator: "\n\n")
            return ConciergeMessage(role: .concierge, text: "\(intro)\n\n\(details)\n\nCheck current menus and availability with the hotel. Dining counts describe variety, not a quality rating.", hotelIDs: hotels.map(\.id), suggestions: ["Plan a weekend in \(city)", "Japanese dining instead", "Show my saved places"])
        }
        return ConciergeMessage(role: .concierge, text: "I’m a preview concierge using Seur’s hotel collection, so I’m best at stays, hotel dining, and simple trip ideas. Try a city and a cuisine, or ask for a weekend plan. What sounds like your kind of escape?", suggestions: ["Great dining in Bangkok", "Plan a weekend in Paris", "Help me find flights"])
    }
    private static func matches(context: ConciergeContext, store: TravelStore) -> [Hotel] {
        let candidates = store.search(query: "", city: context.city ?? "Everywhere", cuisine: context.cuisine ?? "Any cuisine")
        let luxury = candidates.filter { $0.stars == "5" }
        return Array((luxury.isEmpty ? candidates : luxury).prefix(2))
    }
}

@MainActor @Observable final class ConciergeConversation {
    private(set) var messages: [ConciergeMessage] = []
    private(set) var isReplying = false
    private(set) var context = ConciergeContext()
    private var replyTask: Task<Void, Never>?
    func send(_ input: String, store: TravelStore) {
        let text = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !text.isEmpty, !isReplying else { return }
        messages.append(ConciergeMessage(role: .traveler, text: text))
        isReplying = true
        replyTask = Task { [weak self] in
            // Short presentation delay for the demo typing state, not a server request.
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            let reply = ConciergeEngine.reply(to: text, context: &self.context, store: store)
            self.messages.append(reply)
            self.isReplying = false
        }
    }
    func reset() {
        replyTask?.cancel(); replyTask = nil
        messages = []; isReplying = false; context = ConciergeContext()
    }
}

private struct ConciergeHotelRoute: Hashable {
    let hotel: Hotel
    let sourceID: String
}

struct ConciergeView: View {
    @Environment(TravelStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool
    @State private var draft = ""
    @State private var resetAlert = false
    @Namespace private var hotelTransition
    private var conversation: ConciergeConversation { store.concierge }
    private let starters = [
        ("A stay worth the journey", "Find a hotel in Paris with great dining", "bed.double"),
        ("A table to remember", "Great dining in Bangkok", "fork.knife"),
        ("A weekend, thoughtfully planned", "Plan a weekend in Paris", "calendar"),
        ("Enjoy the getting there", "Help me find flights", "airplane")
    ]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if conversation.messages.isEmpty { welcome }
                    else {
                        Label("Preview · recommendations from your collection", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 10)
                    }
                    ForEach(conversation.messages) { message in
                        messageView(message)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                    if conversation.isReplying { typingIndicator }
                    Color.clear.frame(height: 1).id("conversation-bottom")
                }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.messages.count) {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            .onChange(of: composerFocused) {
                if composerFocused { withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { proxy.scrollTo("conversation-bottom", anchor: .bottom) } }
            }
        }
        .background(Color.canvas)
        .navigationTitle("Concierge").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Concierge").font(.headline)
                    Text("Demo · on device").font(.caption2).foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Image(systemName: "sparkles").foregroundStyle(Color.bronze).accessibilityHidden(true)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { resetAlert = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New conversation").disabled(conversation.messages.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .confirmationDialog("Start a new conversation?", isPresented: $resetAlert, titleVisibility: .visible) {
            Button("Clear this conversation", role: .destructive) { conversation.reset(); draft = ""; composerFocused = false }
        } message: { Text("This clears the chat. Your saved places and itinerary stay as they are.") }
        .navigationDestination(for: ConciergeHotelRoute.self) { HotelDetailView(hotel: $0.hotel).navigationTransition(.zoom(sourceID: $0.sourceID, in: hotelTransition)) }
        .sensoryFeedback(.selection, trigger: conversation.messages.count)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88), value: conversation.messages.count)
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "sparkles").font(.system(size: 30, weight: .light)).foregroundStyle(Color.bronze)
                    .frame(width: 72, height: 72).glassEffect(.regular.tint(Color.bronze.opacity(0.09)), in: .circle)
                    .padding(.top, 10)
                Eyebrow(text: "Your Seur concierge")
                Editorial("Where shall\nwe take you?", size: 39)
                Text("A place to stay. A table to remember.\nLet’s start with what you love.")
                    .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
            }
            VStack(spacing: 10) {
                ForEach(starters, id: \.1) { title, prompt, symbol in
                    Button { send(prompt) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: symbol).font(.system(size: 19, weight: .light)).foregroundStyle(Color.bronze).frame(width: 25)
                            Text(title).font(.subheadline).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
                        }.padding(.horizontal, 17).padding(.vertical, 18)
                            .cardSurface(cornerRadius: 20)
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("concierge-prompt-\(symbol)")
                }
            }
            Label("Demo concierge · works on device", systemImage: "sparkle")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Text("Uses your hotel collection. No live AI or reservations yet.")
                .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, -16)
        }.padding(.bottom, 3)
    }
    @ViewBuilder private func messageView(_ message: ConciergeMessage) -> some View {
        if message.role == .traveler {
            HStack {
                Spacer(minLength: 34)
                Text(message.text).font(.body).foregroundStyle(.white).padding(16)
                    .background(Color.bronze, in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 7, topTrailingRadius: 22))
                    .textSelection(.enabled)
            }.accessibilityIdentifier("concierge-user-message")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Label { Text("SEUR") } icon: { SeurLogo(size: 23) }.font(.caption2.weight(.semibold)).tracking(1.8).foregroundStyle(Color.bronze)
                Text(message.text).font(.body).lineSpacing(5).textSelection(.enabled).accessibilityIdentifier("concierge-reply")
                ForEach(message.hotelIDs, id: \.self) { id in
                    if let hotel = store.hotels.first(where: { $0.id == id }) {
                        NavigationLink(value: ConciergeHotelRoute(hotel: hotel, sourceID: hotel.id + message.id.uuidString)) { recommendationCard(hotel) }
                            .buttonStyle(PressStyle()).matchedTransitionSource(id: hotel.id + message.id.uuidString, in: hotelTransition)
                            .accessibilityIdentifier("concierge-hotel-\(id)")
                    }
                }
                if let action = message.action {
                    Button { perform(action) } label: { Label(action.rawValue, systemImage: "arrow.up.right").font(.subheadline).padding(.vertical, 5) }.buttonStyle(.glass)
                }
                if message.id == conversation.messages.last?.id {
                    ScrollView(.horizontal) {
                        HStack(spacing: 9) {
                            ForEach(message.suggestions, id: \.self) { suggestion in
                                Button(suggestion) { send(suggestion) }.font(.caption).padding(.horizontal, 13).padding(.vertical, 11)
                                    .background(Color.bronze.opacity(0.08), in: .capsule).disabled(conversation.isReplying)
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
        }
    }
    private func recommendationCard(_ hotel: Hotel) -> some View {
        HStack(spacing: 14) {
            Group {
                if hotel.image != nil { HotelPhoto(hotel: hotel) }
                else { Image(systemName: "building.2").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(Color.bronze).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.bronze.opacity(0.09)) }
            }.frame(width: 74, height: 90).clipShape(.rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: hotel.city)
                Text(hotel.name).font(.system(.headline, design: .serif)).foregroundStyle(.primary)
                Label("\(hotel.venues.count) dining options", systemImage: "fork.knife").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(13).cardSurface(cornerRadius: 23)
    }
    private var typingIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Color.bronze)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            Text("Looking through the collection…").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8).accessibilityLabel("Concierge is preparing a demo reply")
    }
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask your concierge…", text: $draft, axis: .vertical)
                .font(.body).lineLimit(1...4).focused($composerFocused).padding(.vertical, 12).padding(.leading, 8)
                .accessibilityIdentifier("concierge-input")
                .onChange(of: draft) { if draft.count > 1000 { draft = String(draft.prefix(1000)) } }
            Button { send(draft) } label: {
                Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)).frame(width: 40, height: 40)
            }.buttonStyle(.glassProminent).buttonBorderShape(.circle)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || conversation.isReplying)
                .accessibilityLabel("Send message").accessibilityIdentifier("concierge-send")
        }.padding(9).glassEffect(.regular, in: .rect(cornerRadius: 29)).padding(.horizontal, 16).padding(.bottom, 8)
    }
    private func send(_ text: String) {
        guard !conversation.isReplying else { return }
        conversation.send(text, store: store); draft = ""; composerFocused = false
    }
    private func perform(_ action: ConciergeAction) {
        switch action {
        case .flights: store.category = .flights; store.selectedTab = 0
        case .experiences: store.category = .experiences; store.selectedTab = 0
        case .trips: store.selectedTab = 2
        case .collection: store.city = conversation.context.city ?? "Everywhere"; store.selectedTab = 3
        }
    }
}
