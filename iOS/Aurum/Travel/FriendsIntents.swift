import SwiftUI

struct TripRequestIntent: Codable, Hashable {
    var city: String
    /// A calendar month, independent of device time zone (YYYY-MM).
    var month: String
    var monthLabel: String {
        guard let date = TravelDay.date(month + "-01") else { return month }
        let formatter = DateFormatter(); formatter.calendar = TravelDay.calendar
        formatter.timeZone = TravelDay.calendar.timeZone; formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    var prompt: String { "I’m going to \(city) in \(monthLabel) — what did you do? Share a trip or template with me." }
}

struct FriendOverlap: Identifiable {
    let remote: RemoteJourney
    let localID: UUID
    let city: String
    let start: String
    let end: String
    let id: String
    var dates: String { start == end ? TravelDay.label(start) : TravelDay.label(start) + " – " + TravelDay.label(end) }
}

enum FriendOverlaps {
    static func sameCity(_ a: JourneyStop, _ b: JourneyStop) -> Bool {
        let name = TravelStatistics.normalized(a.name)
        guard !name.isEmpty, name == TravelStatistics.normalized(b.name) else { return false }
        let ac = TravelStatistics.countryCode(a.countryCode) ?? TravelStatistics.countryCode(a.country)
        let bc = TravelStatistics.countryCode(b.countryCode) ?? TravelStatistics.countryCode(b.country)
        if let ac, let bc, ac != bc { return false }
        if let ap = RoutePoint(a), let bp = RoutePoint(b) { return ap.distance(to: bp) <= 35 }
        // A city name alone is ambiguous (e.g. London or Springfield).
        return ac != nil && ac == bc
    }
    static func matches(remote: [RemoteJourney], local: [JourneyDocument], friendIDs: Set<String>, today: String = TravelDay.key(.now)) -> [FriendOverlap] {
        var result: [FriendOverlap] = []; var seen = Set<String>()
        for shared in remote where friendIDs.contains(shared.owner.id) && shared.document.isTemplate != true && shared.document.dateMode == .dates {
            for own in local where own.isTemplate != true && own.dateMode == .dates && own.id != shared.document.id {
                for a in own.stops { for b in shared.document.stops {
                    guard sameCity(a, b), TravelDay.date(a.arrival) != nil, TravelDay.date(b.arrival) != nil, a.nights >= 0, b.nights >= 0 else { continue }
                    let first = max(a.arrival, b.arrival), last = min(a.departure, b.departure)
                    guard first <= last, last >= today else { continue }
                    // Keep identity stable as today advances; changed dates produce a new notice.
                    let identity = [shared.owner.id, TravelStatistics.normalized(b.name), TravelStatistics.countryCode(b.countryCode) ?? TravelStatistics.countryCode(b.country) ?? b.country, first, last].joined(separator: "|")
                    guard seen.insert(identity).inserted else { continue }
                    result.append(FriendOverlap(remote: shared, localID: own.id, city: b.name, start: max(first,today), end: last, id: identity))
                } }
            }
        }
        return result.sorted { ($0.start, $0.city, $0.remote.owner.name) < ($1.start, $1.city, $1.remote.owner.name) }
    }
}

struct TripRequestComposer: View {
    @Environment(TravelAPI.self) private var api
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let friends: [TravelFriend]
    let chats: [TravelConversation]
    var initialFriend: String? = nil
    var conversation: TravelConversation? = nil
    var onSent: (TravelConversation) -> Void = { _ in }
    @State private var friendID = ""
    @State private var city = ""
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var note = ""
    @State private var sending = false
    @State private var error: String?
    private var intent: TripRequestIntent { .init(city: city.trimmingCharacters(in: .whitespacesAndNewlines), month: String(format: "%04d-%02d", year, month)) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Ask someone who’s been there").font(.headline)
                    Text("Your friend can send back an itinerary or a reusable template, right in your conversation.").font(.subheadline).foregroundStyle(.secondary)
                }
                if conversation == nil {
                    Section("Ask a friend") {
                        if friends.isEmpty { Text("Add a friend first. You can send a request once they accept.").foregroundStyle(.secondary) }
                        else { Picker("Friend", selection: $friendID) { Text("Choose a friend").tag(""); ForEach(friends) { Text($0.name).tag($0.id) } } }
                    }
                }
                Section("Where are you going?") {
                    TextField("City, e.g. Tokyo", text: $city).onChange(of: city) { _, value in if value.count > 120 { city = String(value.prefix(120)) } }
                    HStack {
                        Picker("Month", selection: $month) { ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) } }
                        Picker("Year", selection: $year) { ForEach(Calendar.current.component(.year, from: .now)...2100, id: \.self) { Text(String($0)).tag($0) } }
                    }
                    if !library.documents.filter({ $0.isTemplate != true && $0.dateMode == .dates }).isEmpty {
                        Menu("Use a destination from my trips") {
                            ForEach(library.documents.filter { $0.isTemplate != true && $0.dateMode == .dates }) { trip in
                                Menu(trip.title) { ForEach(trip.stops) { stop in Button(stop.name) { city = stop.name; let parts = stop.arrival.split(separator: "-"); if parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), y >= Calendar.current.component(.year, from: .now), y <= 2100 { year = y; month = m } } } }
                            }
                        }
                    }
                }
                Section("Your message") { TextField(intent.prompt, text: $note, axis: .vertical).lineLimit(3...6); Text("Only the people in this conversation see your request.").font(.caption).foregroundStyle(.secondary) }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("Ask about a trip").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(sending) }
                    ToolbarItem(placement: .confirmationAction) { Button(sending ? "Sending…" : "Send request") { Task { await send() } }.disabled(sending || intent.city.isEmpty || (conversation == nil && friendID.isEmpty) || note.count > 5000) }
                }.interactiveDismissDisabled(sending)
                .onAppear { if friendID.isEmpty { friendID = initialFriend ?? (friends.count == 1 ? friends[0].id : "") } }
        }
    }
    private func send() async {
        sending = true; defer { sending = false }
        do {
            let target: TravelConversation
            if let conversation { target = conversation }
            else if let existing = FriendsTravel.directConversation(friend: friendID, owner: api.account?.id ?? "", chats: chats) { target = existing }
            else { target = try await api.createConversation(name: (friends.first { $0.id == friendID }?.name ?? "Friend") + " & " + (api.account?.name ?? "You"), members: [friendID]) }
            _ = try await api.requestTrip(target.id, intent: intent, note: note)
            dismiss(); onSent(target)
        } catch { self.error = error.localizedDescription }
    }
}
