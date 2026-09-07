import SwiftUI

struct TravelAccountView: View {
    var createAccount = false
    var body: some View { NavigationStack { TravelAccountPage(register: createAccount) } }
}

/// Full-page account access shared by profile, travel, and contextual entry points.
struct TravelAccountPage: View {
    @Environment(TravelAPI.self) private var api
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State var register = false
    @State private var handle = ""
    @State private var name = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var loading = false
    @State private var message: String?
    @State private var cloud: [RemoteJourney] = []
    @State private var confirmingDeletion = false
    @State private var justAuthenticated = false
    @FocusState private var focus: Field?
    private enum Field { case name, handle, password, confirmation }
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if let account = api.account, api.isSignedIn {
                Form {
                    Section {
                        HStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(Color.bronze)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(account.name).font(.title3.weight(.semibold))
                                Text("@" + account.handle).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 10)
                        if justAuthenticated { Label("You’re signed in", systemImage: "checkmark.circle.fill").foregroundStyle(Color.bronze).accessibilityIdentifier("account-success") }
                        Button("Continue exploring") { dismiss() }.accessibilityIdentifier("account-continue")
                    }
                    Section("Cloud trips") {
                        Button("Refresh cloud journeys") { Task { await loadCloud() } }.disabled(loading)
                        ForEach(cloud) { remote in
                            Button { Task { do { let full = try await api.document(remote.id); _ = try library.importData(JSONEncoder().encode(JourneyArchive(document: full.document))); message = "A private copy was saved on this device." } catch { message = error.localizedDescription } } } label: {
                                HStack { Text(remote.document.title); Spacer(); Image(systemName: "arrow.down.circle") }
                            }
                        }
                    }
                    Section {
                        NavigationLink("Connected services") { TravelServicesSettingsView() }
                        Button("Sign out") { Task { loading = true; defer { loading = false }; do { try await api.logout(); cloud = []; justAuthenticated = false; register = false; message = nil } catch { message = "Couldn’t turn off this device’s flight alerts. Reconnect and try signing out again." } } }.disabled(loading)
                    }
                    Section { Button("Delete cloud account", role: .destructive) { confirmingDeletion = true }.disabled(loading) }
                        footer: { Text("Trips saved on this device stay on this device.") }

                    if let message { Section { Text(message).font(.subheadline).accessibilityIdentifier("account-message") } }
                }.scrollContentBackground(.hidden)
            } else { guestPage }
        }
        .background(Color.canvas).scrollDismissesKeyboard(.interactively)
        .navigationTitle(api.isSignedIn ? "Your account" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(loading) } }
        .interactiveDismissDisabled(loading)
        .onChange(of: register) { focus = nil; password = ""; confirmation = ""; message = nil }
        .onDisappear { password = ""; confirmation = "" }
        .task { try? await api.refresh(); if api.isSignedIn { await loadCloud() } }
        .confirmationDialog("Delete your cloud account and all cloud trips?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { loading = true; defer { loading = false }; do { try await api.deleteAccount(); cloud = []; justAuthenticated = false } catch { message = error.localizedDescription } } }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var guestPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    GeometryReader { geometry in
                        Image("bangkok").resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }
                    LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            SeurLogo(size: 34)
                            Text("SEUR").font(.subheadline.weight(.medium)).tracking(5)
                        }
                        Text("Made for the journey.").font(.system(.title, design: .serif)).fixedSize(horizontal: false, vertical: true)
                    }.foregroundStyle(.white).padding(24)
                }
                .frame(height: typeSize.isAccessibilitySize ? 250 : 205)
                .clipShape(.rect(cornerRadius: 28))
                .padding(.horizontal, 16).accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(register ? "A world of your own." : "Welcome back.")
                            .font(.system(.largeTitle, design: .serif)).tracking(-0.8)
                            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        Text(register ? "Save your trips. Keep your discoveries." : "Your next journey is waiting.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Picker("Account", selection: $register) {
                        Text("Sign in").tag(false)
                        Text("Create account").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("account-mode").disabled(loading)

                    VStack(spacing: 0) {
                        if register {
                            field("Your name", icon: "person") {
                                TextField("Display name", text: $name).textContentType(.name).focused($focus, equals: .name)
                                    .submitLabel(.next).onSubmit { focus = .handle }.accessibilityIdentifier("account-name")
                            }
                            Divider().padding(.leading, 52)
                        }
                        field("Username", icon: "at") {
                            TextField(register ? "Choose a username" : "Username", text: $handle).textContentType(.username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus, equals: .handle)
                                .submitLabel(.next).onSubmit { focus = .password }.accessibilityIdentifier("account-handle")
                        }
                        Divider().padding(.leading, 52)
                        field("Password", icon: "lock") {
                            SecureField(register ? "12 or more characters" : "Password", text: $password).textContentType(register ? .newPassword : .password)
                                .focused($focus, equals: .password).submitLabel(register ? .next : .go)
                                .onSubmit { if register { focus = .confirmation } else { submit() } }.accessibilityIdentifier("account-password")
                        }
                        if register {
                            Divider().padding(.leading, 52)
                            field("Confirm password", icon: "checkmark.shield") {
                                SecureField("Repeat your password", text: $confirmation).textContentType(.newPassword).focused($focus, equals: .confirmation)
                                    .submitLabel(.go).onSubmit { submit() }.accessibilityIdentifier("account-confirmation")
                            }
                        }
                    }
                    .cardSurface(cornerRadius: 24)
                    .disabled(loading)
                    if let message {
                        Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("account-message")
                    }
                    Button(action: submit) {
                        HStack(spacing: 12) {
                            Spacer()
                            if loading { ProgressView().tint(.white) }
                            Text(loading ? "Connecting…" : register ? "Create account" : "Sign in").fontWeight(.semibold)
                            if !loading { Image(systemName: "arrow.right") }
                            Spacer()
                        }.padding(.vertical, 14).frame(minHeight: 48)
                    }.buttonStyle(.glassProminent).tint(Color.bronze).disabled(loading).accessibilityIdentifier("account-submit")
                }.padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 32)
            }
        }.scrollEdgeEffectHidden(true, for: .top).accessibilityIdentifier("account-full-page")
    }

    private func field<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon).font(.body.weight(.light)).foregroundStyle(Color.bronze).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                content().font(.body)
            }
        }.padding(18)
    }
    private func submit() {
        guard !loading else { return }
        message = nil
        let username = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard username.range(of: "^[a-z0-9_]{3,32}$", options: .regularExpression) != nil else { message = "Enter a username with 3–32 letters, numbers or underscores."; focus = .handle; return }
        guard !password.isEmpty else { message = "Enter your password."; focus = .password; return }
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if register {
            guard !displayName.isEmpty && displayName.count <= 100 else { message = "Enter your name (up to 100 characters)."; focus = .name; return }
            guard (12...256).contains(password.count) else { message = "Use a password with 12–256 characters."; focus = .password; return }
            guard password == confirmation else { message = "Your passwords don’t match."; focus = .confirmation; return }
        }
        focus = nil; loading = true
        Task { @MainActor in
            defer { loading = false }
            do {
                try await api.authenticate(handle: username, name: displayName, password: password, register: register)
                password = ""; confirmation = ""; justAuthenticated = true
                await loadCloud()
            } catch { message = error.localizedDescription }
        }
    }
    private func loadCloud() async { do { cloud = try await api.documents() } catch { message = error.localizedDescription } }
}

private struct TravelServicesSettingsView: View {
    @Environment(TravelAPI.self) private var api
    @State private var address = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section("Services") {
                LabeledContent("Seur Cloud", value: "Connected")
                LabeledContent("Apple Maps", value: "Available")
                LabeledContent("FlightAware", value: api.status?.flightTracking == true ? "Connected" : "Unavailable")
                LabeledContent("Google Places", value: api.status?.googlePlaces == true ? "Connected" : "Apple Maps fallback")
                LabeledContent("Tripadvisor", value: api.status?.tripadvisor == true ? "Configured" : "Unavailable")
                LabeledContent("AI recommendations", value: api.status?.ai == true ? "Connected" : "Unavailable")
                LabeledContent("Public links", value: api.status?.publicSharing == true ? "Available" : "Unavailable")
            }
            #if DEBUG
            Section("Development") {
                TextField("Backend address", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Connect to server") { Task { api.baseURL = address.trimmingCharacters(in: .whitespacesAndNewlines); do { try await api.refresh() } catch { self.error = error.localizedDescription } } }
            }
            #endif
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Connected services").navigationBarTitleDisplayMode(.inline)
            .task { address = api.baseURL; try? await api.refresh() }
    }
}

enum FriendsTripFilter: String, CaseIterable { case all = "All trips", upcoming = "Upcoming", traveling = "Traveling now", saved = "Saved", past = "Past trips" }
enum FriendsTravel {
    static func range(_ trip: JourneyDocument) -> (String, String)? {
        guard trip.dateMode == .dates else { return nil }
        let starts = trip.stops.map(\.arrival).filter { TravelDay.date($0) != nil }
        let ends = trip.stops.filter { TravelDay.date($0.arrival) != nil }.map { TravelDay.adding($0.nights, to: $0.arrival) }
        guard let start = starts.min() ?? trip.startDate, let end = ends.max() ?? trip.endDate,
              TravelDay.date(start) != nil, TravelDay.date(end) != nil, start <= end else { return nil }
        return (start, end)
    }
    static func dates(_ trip: JourneyDocument) -> String { guard let (start, end) = range(trip) else { return "Dates flexible" }; return TravelDay.label(start) + " – " + TravelDay.label(end) }
    static func phase(_ trip: JourneyDocument, today: String = TravelDay.key(.now)) -> FriendsTripFilter? {
        guard let (start, end) = range(trip) else { return nil }
        return end < today ? .past : start > today ? .upcoming : .traveling
    }
    static func matches(_ remote: RemoteJourney, query: String, filter: FriendsTripFilter, saved: Set<String>, today: String = TravelDay.key(.now)) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = remote.document.title + " " + remote.document.routeLabel + " " + remote.owner.name + " " + remote.owner.handle
        return (term.isEmpty || text.localizedCaseInsensitiveContains(term)) && (filter == .all || (filter == .saved ? saved.contains(remote.id) : phase(remote.document, today: today) == filter))
    }
    static func overlap(_ remote: JourneyDocument, with local: [JourneyDocument], today: String = TravelDay.key(.now)) -> String? {
        guard remote.dateMode == .dates else { return nil }
        for own in local where own.dateMode == .dates && own.id != remote.id {
            for a in own.stops { for b in remote.stops {
                guard !a.name.isEmpty, a.name.localizedCaseInsensitiveCompare(b.name) == .orderedSame,
                      a.country.localizedCaseInsensitiveCompare(b.country) == .orderedSame,
                      TravelDay.date(a.arrival) != nil, TravelDay.date(b.arrival) != nil else { continue }
                let start = max(a.arrival, b.arrival, today), end = min(TravelDay.adding(a.nights, to: a.arrival), TravelDay.adding(b.nights, to: b.arrival))
                if start <= end { return "Your dates overlap in " + b.name + " · " + TravelDay.label(start) }
            } }
        }
        return nil
    }
    static func directConversation(friend: String, owner: String, chats: [TravelConversation]) -> TravelConversation? {
        chats.first { Set($0.members.map(\.id)) == Set([friend, owner]) && $0.members.count == 2 }
    }
}

@MainActor @Observable final class FriendsHomeModel {
    var friends: [TravelFriend] = []
    var trips: [RemoteJourney] = []
    var chats: [TravelConversation] = []
    var saved = Set<String>()
    var error: String?
    var loading = false
    private var owner: String?
    private var generation = UUID()
    var accepted: [TravelFriend] { friends.filter { $0.status == "accepted" }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    var incoming: [TravelFriend] { friends.filter { $0.status == "pending" && $0.incoming } }
    var outgoing: [TravelFriend] { friends.filter { $0.status == "pending" && !$0.incoming } }
    func reset() { generation = UUID(); owner = nil; friends = []; trips = []; chats = []; saved = []; error = nil; loading = false }
    func refresh(api: TravelAPI) async {
        guard api.isSignedIn, let user = api.account?.id else { reset(); return }
        if owner != user { reset(); owner = user; saved = Set(UserDefaults.standard.stringArray(forKey: "seur.friends.saved." + user) ?? []) }
        guard !loading else { return }
        let request = UUID(); generation = request; loading = true
        defer { if generation == request { loading = false } }
        do {
            async let people = api.friends(); async let shared = api.documents(feed: true); async let conversations = api.conversations()
            let result = try await (people, shared, conversations)
            guard !Task.isCancelled, generation == request, api.account?.id == user else { return }
            friends = result.0; trips = result.1; chats = result.2; error = nil
            saved.formIntersection(Set(trips.map(\.id))); persist()
        } catch { if generation == request, api.account?.id == user, !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func bookmark(_ id: String) { if !saved.insert(id).inserted { saved.remove(id) }; persist() }
    private func persist() { if let owner { UserDefaults.standard.set(Array(saved), forKey: "seur.friends.saved." + owner) } }
}

struct FriendsHubView: View {
    @Environment(TravelAPI.self) private var api
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = FriendsHomeModel()
    @State private var section = "Trips"
    @State private var query = ""
    @State private var filter = FriendsTripFilter.all
    @State private var signingIn = false
    @State private var inviting = false
    @State private var sharing = false
    @State private var grouping = false
    @State private var busy = false
    @State private var chat: TravelConversation?
    @State private var removing: TravelFriend?
    private var shownTrips: [RemoteJourney] { model.trips.filter { FriendsTravel.matches($0, query: query, filter: filter, saved: model.saved) }.sorted { $0.document.updatedAt > $1.document.updatedAt } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if api.isSignedIn {
                    intro
                    sections
                    if model.loading && model.friends.isEmpty && model.trips.isEmpty { ProgressView("Loading your circle…").frame(maxWidth: .infinity).padding(.vertical, 30) }
                    if let error = model.error { Label(error, systemImage: "wifi.exclamationmark").font(.subheadline).foregroundStyle(.secondary); Button("Try again") { Task { await model.refresh(api: api) } } }
                    if section == "Trips" { sharedTrips }
                    else if section == "People" { people }
                    else { conversations }
                } else { guest }
            }.padding(22)
        }.background(Color.canvas).navigationTitle("Friends").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if api.isSignedIn {
                        Menu {
                            Button("Add a friend", systemImage: "person.badge.plus") { inviting = true }
                            Button("Share an itinerary", systemImage: "square.and.arrow.up") { sharing = true }
                            Button("Create a group", systemImage: "person.3") { grouping = true }
                        } label: { Image(systemName: "plus") }.accessibilityLabel("Friends actions")
                    }
                }
            }
            .refreshable { await model.refresh(api: api) }
            .task(id: "\(api.account?.id ?? "guest")-\(store.selectedTab)-\(scenePhase)") {
                guard store.selectedTab == 5, scenePhase == .active else { return }
                if !api.isSignedIn { try? await api.refresh() }
                await model.refresh(api: api)
                while !Task.isCancelled && api.isSignedIn {
                    do { try await Task.sleep(for: .seconds(60)) } catch { break }
                    await model.refresh(api: api)
                }
            }
            .onChange(of: api.account?.id) { _, _ in model.reset() }
            .fullScreenCover(isPresented: $signingIn) { TravelAccountView() }
            .sheet(isPresented: $inviting, onDismiss: reload) { FriendInviteView() }
            .sheet(isPresented: $grouping, onDismiss: reload) { ConversationEditor(friends: model.accepted) }
            .sheet(isPresented: $sharing, onDismiss: reload) { FriendsShareComposer(friends: model.accepted, chats: model.chats) }
            .navigationDestination(item: $chat) { TravelChatView(conversation: $0) }
            .confirmationDialog("Remove this friend?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove friend", role: .destructive) { if let friend = removing { respond(friend, accept: false) }; removing = nil }
            } message: { Text("You’ll no longer see each other’s friends-only trips. Existing conversation history remains.") }
    }
    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Good company.\nGreat journeys.").font(.system(.largeTitle, design: .serif)).accessibilityIdentifier("friends-home-title")
            Text("Share the plan, swap ideas and make room for each other.").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                Label("\(model.accepted.count) friends", systemImage: "person.2")
                Label("\(model.trips.count) shared trips", systemImage: "map")
            }.font(.caption).foregroundStyle(FlightDisplay.blue)
            Button { sharing = true } label: { Label("Share an itinerary", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6) }.buttonStyle(.glassProminent).accessibilityIdentifier("friends-share-trip")
        }
    }
    private var sections: some View {
        HStack(spacing: 26) {
            ForEach(["Trips", "People", "Messages"], id: \.self) { value in
                Button { section = value; query = "" } label: {
                    VStack(spacing: 10) {
                        HStack(spacing: 5) { Text(value); if value == "People", !model.incoming.isEmpty { Text("\(model.incoming.count)").font(.caption.weight(.bold)).foregroundStyle(FlightDisplay.blue) } }
                        Rectangle().fill(section == value ? Color.bronze : .clear).frame(height: 2)
                    }.fixedSize(horizontal: true, vertical: false)
                }.buttonStyle(.plain).font(.subheadline.weight(.semibold)).foregroundStyle(section == value ? Color.bronze : .secondary).accessibilityIdentifier("friends-section-" + value)
            }
            Spacer(minLength: 0)
        }.overlay(alignment: .bottom) { Divider() }
    }
    private var sharedTrips: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Shared with you").font(.headline)
                Spacer()
                Menu { Picker("Trips", selection: $filter) { ForEach(FriendsTripFilter.allCases, id: \.self) { Text($0.rawValue) } } } label: { Label(filter.rawValue, systemImage: "line.3.horizontal.decrease") }.font(.caption)
            }
            searchField("Search friends or destinations")
            if shownTrips.isEmpty {
                empty(title: model.trips.isEmpty ? "A window into their journeys" : "No matching trips", symbol: "map", text: model.trips.isEmpty ? "When a friend shares an itinerary with you, it appears here. Share yours to start planning together." : "Try another search or trip filter.")
                if model.accepted.isEmpty { Button("Add your first friend", systemImage: "person.badge.plus") { inviting = true } }
            }
            ForEach(shownTrips) { remote in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        FriendsAvatar(name: remote.owner.name, size: 28)
                        Text(remote.owner.name).font(.caption.weight(.medium))
                        Spacer()
                        Button { model.bookmark(remote.id) } label: { Image(systemName: model.saved.contains(remote.id) ? "bookmark.fill" : "bookmark").frame(width: 36, height: 36) }.buttonStyle(.plain).accessibilityLabel(model.saved.contains(remote.id) ? "Unsave shared trip" : "Save shared trip")
                    }
                    NavigationLink { SharedJourneyPreview(remote: remote) } label: { FriendsTripRow(remote: remote) }.buttonStyle(.plain).accessibilityIdentifier("friends-trip-" + remote.id)
                    if let overlap = FriendsTravel.overlap(remote.document, with: library.documents) { Label(overlap, systemImage: "person.2.wave.2").font(.caption).foregroundStyle(FlightDisplay.teal) }
                }.padding(.vertical, 4)
                Divider()
            }
            Text("Only trips shared with you appear here. Saving a trip keeps a shortcut; its owner controls access.").font(.caption).foregroundStyle(.secondary)
            NavigationLink { FriendsSharingSettingsView() } label: { Label("Manage your shared itineraries", systemImage: "person.badge.shield.checkmark").font(.subheadline) }
        }
    }
    private var people: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Your people").font(.headline); Spacer(); Button("Add friend", systemImage: "person.badge.plus") { inviting = true }.font(.subheadline).accessibilityIdentifier("friends-add-person") }
            if let user = api.account {
                ShareLink(item: "Add me on Seur: @" + user.handle) { Label("Share your username · @" + user.handle, systemImage: "square.and.arrow.up").font(.caption) }
            }
            searchField("Search your friends")
            if !model.incoming.isEmpty {
                Text("Invitations").font(.subheadline.weight(.semibold))
                ForEach(model.incoming) { friend in
                    HStack {
                        personLabel(friend)
                        Spacer()
                        Button("Accept") { respond(friend, accept: true) }.font(.caption.weight(.semibold)).disabled(busy)
                        Button { respond(friend, accept: false) } label: { Image(systemName: "xmark").frame(width: 32, height: 36) }.accessibilityLabel("Decline " + friend.name).disabled(busy)
                    }.padding(.vertical, 6)
                }
                Divider()
            }
            ForEach(model.accepted.filter { query.isEmpty || ($0.name + $0.handle).localizedCaseInsensitiveContains(query) }) { friend in
                HStack {
                    NavigationLink { FriendProfileView(friend: friend, trips: model.trips.filter { $0.owner.id == friend.id }, chats: model.chats) } label: { personLabel(friend) }.buttonStyle(.plain)
                    Spacer()
                    Menu {
                        Button("Message", systemImage: "bubble.left") { message(friend) }
                        Button("Remove friend", role: .destructive) { removing = friend }
                    } label: { Image(systemName: "ellipsis").frame(width: 40, height: 40) }.accessibilityLabel("Actions for " + friend.name)
                }
                Divider()
            }
            if model.accepted.isEmpty { empty(title: "Bring your people along", symbol: "person.2", text: "Add friends and family by username. Once they accept, you can share trips and start a conversation.") }
            if !model.outgoing.isEmpty {
                Text("Invitations sent").font(.subheadline.weight(.semibold))
                ForEach(model.outgoing) { friend in HStack { personLabel(friend); Spacer(); Button("Cancel") { respond(friend, accept: false) }.font(.caption).disabled(busy) } }
            }
        }
    }
    private var conversations: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Plan it together").font(.headline); Spacer(); Button { grouping = true } label: { Image(systemName: "square.and.pencil").frame(width: 40, height: 40) }.accessibilityLabel("New conversation") }
            searchField("Search conversations")
            if model.chats.isEmpty { empty(title: "One place for the conversation", symbol: "bubble.left.and.bubble.right", text: "Create a family or travel group, share an itinerary and keep ideas beside the plan.") }
            ForEach(model.chats.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { conversation in
                NavigationLink { TravelChatView(conversation: conversation) } label: {
                    HStack(spacing: 12) {
                        FriendsAvatar(name: conversation.name, size: 44)
                        VStack(alignment: .leading, spacing: 4) { Text(conversation.name).font(.subheadline.weight(.semibold)); Text(conversation.members.filter { $0.id != api.account?.id }.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 7)
                }.buttonStyle(.plain)
                Divider()
            }
        }
    }
    private var guest: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "person.2").font(.system(size: 42, weight: .light)).foregroundStyle(FlightDisplay.blue)
            Text("Travel is better\ntogether.").font(.system(.largeTitle, design: .serif))
            Text("A shared itinerary. A family group. A friend’s next adventure. Keep everyone in the picture.").font(.body).foregroundStyle(.secondary)
            Label("Share plans with the people you choose", systemImage: "map")
            Label("Swap ideas in private conversations", systemImage: "bubble.left.and.bubble.right")
            Label("Find out when your travel dates overlap", systemImage: "calendar")
            Button("Sign in to connect") { signingIn = true }.buttonStyle(.glassProminent).accessibilityIdentifier("friends-sign-in")
        }.padding(.vertical, 24)
    }
    private func searchField(_ prompt: String) -> some View { HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField(prompt, text: $query).textInputAutocapitalization(.never).autocorrectionDisabled(); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Clear search") } }.font(.subheadline).padding(13).background(Color.primary.opacity(0.055), in: .rect(cornerRadius: 15)) }
    private func empty(title: String, symbol: String, text: String) -> some View { VStack(alignment: .leading, spacing: 10) { Image(systemName: symbol).font(.title2).foregroundStyle(FlightDisplay.blue); Text(title).font(.headline); Text(text).font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical, 16) }
    private func personLabel(_ friend: TravelFriend) -> some View { HStack(spacing: 12) { FriendsAvatar(name: friend.name, size: 42); VStack(alignment: .leading, spacing: 3) { Text(friend.name).font(.subheadline.weight(.semibold)); Text("@" + friend.handle).font(.caption).foregroundStyle(.secondary) } } }
    private func reload() { Task { await model.refresh(api: api) } }
    private func respond(_ friend: TravelFriend, accept: Bool) { busy = true; Task { defer { busy = false }; do { try await api.respondFriend(friend.id, accept: accept); await model.refresh(api: api) } catch { model.error = error.localizedDescription } } }
    private func message(_ friend: TravelFriend) { Task { do { chat = FriendsTravel.directConversation(friend: friend.id, owner: api.account?.id ?? "", chats: model.chats); if chat == nil { chat = try await api.createConversation(name: friend.name + " & " + (api.account?.name ?? "You"), members: [friend.id]) } } catch { model.error = error.localizedDescription } } }
}

struct FriendsAvatar: View {
    let name: String
    var size: CGFloat = 44
    var body: some View { Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()).font(.system(size: size * 0.34, weight: .semibold)).foregroundStyle(FlightDisplay.blue).frame(width: size, height: size).background(FlightDisplay.blue.opacity(0.12), in: .circle).accessibilityHidden(true) }
}
struct FriendsTripRow: View {
    let remote: RemoteJourney
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) { Text(remote.document.title).font(.system(.title3, design: .serif)).foregroundStyle(.primary); Spacer(); Image(systemName: "arrow.up.right").font(.subheadline).foregroundStyle(Color.bronze) }
            Text(remote.document.routeLabel).font(.subheadline).foregroundStyle(.secondary)
            HStack { Label(FriendsTravel.dates(remote.document), systemImage: "calendar"); Spacer(); Text("\(remote.document.planCount) plans") }.font(.caption).foregroundStyle(.secondary)
            if FriendsTravel.phase(remote.document) == .traveling { Label("Traveling now", systemImage: "airplane").font(.caption.weight(.semibold)).foregroundStyle(FlightDisplay.teal) }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

struct FriendInviteView: View {
    @Environment(TravelStore.self) private var store
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var handle = ""
    @State private var busy = false
    @State private var error: String?
    private var normalized: String { handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@")) }
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Username", text: $handle).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("friend-invite-username") } header: { Text("Find your friend") } footer: { Text("Ask for their Seur username. They’ll receive an invitation here in the app.") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("Add a friend").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Send invitation") { busy = true; Task { defer { busy = false }; do { try await api.requestFriend(normalized); store.showMessage("Invitation sent to @" + normalized); dismiss() } catch { self.error = error.localizedDescription } } }.disabled(busy || normalized.count < 3) } }
        }
    }
}

struct FriendProfileView: View {
    @Environment(TravelAPI.self) private var api
    let friend: TravelFriend
    let trips: [RemoteJourney]
    let chats: [TravelConversation]
    @State private var chat: TravelConversation?
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FriendsAvatar(name: friend.name, size: 64)
                VStack(alignment: .leading, spacing: 5) { Text(friend.name).font(.title.bold()); Text("@" + friend.handle).foregroundStyle(.secondary) }
                Button("Message", systemImage: "bubble.left") { busy = true; Task { defer { busy = false }; do { chat = FriendsTravel.directConversation(friend: friend.id, owner: api.account?.id ?? "", chats: chats); if chat == nil { chat = try await api.createConversation(name: friend.name + " & " + (api.account?.name ?? "You"), members: [friend.id]) } } catch { self.error = error.localizedDescription } } }.buttonStyle(.glassProminent).disabled(busy)
                Text("Shared journeys").font(.headline)
                if trips.isEmpty { Text("No trips shared with you yet.").foregroundStyle(.secondary) }
                ForEach(trips) { remote in NavigationLink { SharedJourneyPreview(remote: remote) } label: { FriendsTripRow(remote: remote) }.buttonStyle(.plain); Divider() }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }.padding(24)
        }.background(Color.canvas).navigationTitle("Friend").navigationBarTitleDisplayMode(.inline).navigationDestination(item: $chat) { TravelChatView(conversation: $0) }
    }
}

struct FriendsSharingSettingsView: View {
    @Environment(JourneyLibrary.self) private var library
    @State private var selected: JourneyDocument?
    var body: some View {
        List {
            Section { Text("Choose an itinerary to publish updates, change its audience or revoke shared access.").font(.subheadline).foregroundStyle(.secondary) }
            Section("Your itineraries") {
                ForEach(library.documents) { document in Button { selected = document } label: { VStack(alignment: .leading, spacing: 5) { Text(document.title); Text(document.routeLabel).font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain) }
                if library.documents.isEmpty { Text("Your trips will appear here.").foregroundStyle(.secondary) }
            }
        }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Manage sharing").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { JourneyShareView(documentID: $0.id) }
    }
}

struct FriendsShareComposer: View {
    @Environment(TravelStore.self) private var store
    @Environment(TravelAPI.self) private var api
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let friends: [TravelFriend]
    let chats: [TravelConversation]
    @State private var tripID: UUID?
    @State private var recipient = ""
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Itinerary") {
                    if library.documents.isEmpty { Text("Create a trip in Travel first, then share it here.") }
                    ForEach(library.documents) { trip in Button { tripID = trip.id } label: { HStack { VStack(alignment: .leading, spacing: 4) { Text(trip.title); Text(FriendsTravel.dates(trip)).font(.caption).foregroundStyle(.secondary) }; Spacer(); if tripID == trip.id { Image(systemName: "checkmark.circle.fill") } } }.buttonStyle(.plain) }
                }
                if let trip = library.documents.first(where: { $0.id == tripID }), trip.visibility != .private {
                    Section { Label("This itinerary also uses " + trip.visibility.title.lowercased() + " visibility. Its existing audience is preserved.", systemImage: "person.2").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Share with") {
                    ForEach(friends) { friend in recipientRow(friend.name, value: "friend:" + friend.id, symbol: "person") }
                    ForEach(chats) { chat in recipientRow(chat.name, value: "chat:" + chat.id, symbol: "person.3") }
                    if friends.isEmpty && chats.isEmpty { Text("Add a friend or create a group from the Friends page first.").foregroundStyle(.secondary) }
                }
                Section { TextField("Add a note (optional)", text: $note, axis: .vertical).lineLimit(2...4) } footer: { Text("They can view the itinerary and discuss ideas in your conversation. Photos and journal notes are included; booking references and private booking notes are hidden. Share again after editing to publish your latest plan.") }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Share an itinerary").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }; ToolbarItem(placement: .confirmationAction) { Button("Share") { send() }.disabled(busy || tripID == nil || recipient.isEmpty) } }
                .interactiveDismissDisabled(busy)
        }
    }
    private func recipientRow(_ name: String, value: String, symbol: String) -> some View { Button { recipient = value } label: { HStack { Label(name, systemImage: symbol); Spacer(); Image(systemName: recipient == value ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.bronze) } }.buttonStyle(.plain) }
    private func send() {
        guard let document = library.documents.first(where: { $0.id == tripID }) else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let target: TravelConversation
                if recipient.hasPrefix("chat:"), let chat = chats.first(where: { "chat:" + $0.id == recipient }) { target = chat }
                else if let friend = friends.first(where: { "friend:" + $0.id == recipient }) {
                    if let existing = FriendsTravel.directConversation(friend: friend.id, owner: api.account?.id ?? "", chats: chats) { target = existing }
                    else { target = try await api.createConversation(name: friend.name + " & " + (api.account?.name ?? "You"), members: [friend.id]) }
                } else { throw JourneyError.message("Choose a friend or group.") }
                _ = try await api.upload(document)
                _ = try await api.send(target.id, text: note, documentID: document.id.uuidString)
                store.showMessage("Itinerary shared in " + target.name)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct ConversationEditor: View {
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    let friends: [TravelFriend]
    @State private var name = ""
    @State private var selected = Set<String>()
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Conversation or group name", text: $name) }
                Section("Invite your friends") {
                    if friends.isEmpty { Text("Add a friend first.").foregroundStyle(.secondary) }
                    ForEach(friends) { friend in Button { if selected.contains(friend.id) { selected.remove(friend.id) } else { selected.insert(friend.id) } } label: { HStack { Text(friend.name); Spacer(); Image(systemName: selected.contains(friend.id) ? "checkmark.circle.fill" : "circle") } } }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("A new conversation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Create") { Task { loading = true; defer { loading = false }; do { _ = try await api.createConversation(name: name, members: Array(selected)); dismiss() } catch { self.error = error.localizedDescription } } }.disabled(loading || selected.isEmpty || name.isEmpty) } }
        }
    }
}

struct TravelChatView: View {
    @Environment(TravelAPI.self) private var api
    @Environment(\.scenePhase) private var scenePhase
    let conversation: TravelConversation
    @State private var messages: [TravelChatMessage] = []
    @State private var text = ""
    @State private var error: String?
    @State private var sending = false
    @State private var shared: RemoteJourney?
    @State private var attaching = false
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 17) {
                    Text(conversation.members.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    ForEach(messages) { message in
                        TravelMessageBubble(message: message, isOwn: message.sender.id == api.account?.id) { documentID in
                            Task { do { shared = try await api.document(documentID) } catch { self.error = error.localizedDescription } }
                        }.id(message.id)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(22)
            }.refreshable { await refresh() }
                .onChange(of: messages.count) { if let last = messages.last { withAnimation(.smooth) { proxy.scrollTo(last.id, anchor: .bottom) } } }
        }.background(Color.canvas).navigationTitle(conversation.name).navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { attaching = true } label: { Image(systemName: "paperclip") }.accessibilityLabel("Share a journey") } }
            .safeAreaInset(edge: .bottom) {
                HStack { TextField("A note to your friends…", text: $text, axis: .vertical).lineLimit(1...5); Button { Task { let draft = text; sending = true; defer { sending = false }; do { _ = try await api.send(conversation.id, text: draft, documentID: nil); text = ""; await refresh() } catch { self.error = error.localizedDescription } } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.padding(16).glassEffect(.regular, in: .rect(cornerRadius: 25)).padding(12)
            }
            .task {
                while !Task.isCancelled {
                    if scenePhase == .active { await refresh() }
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                }
            }
            .sheet(item: $shared) { remote in NavigationStack { SharedJourneyPreview(remote: remote) } }
            .sheet(isPresented: $attaching, onDismiss: { Task { await refresh() } }) { AttachJourneyView(conversation: conversation) }
    }
    private func refresh() async { do { messages = try await api.messages(conversation.id); error = nil } catch { self.error = error.localizedDescription } }
}

private struct TravelMessageBubble: View {
    let message: TravelChatMessage
    let isOwn: Bool
    var open: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.sender.name).font(.caption.weight(.semibold)).foregroundStyle(Color.bronze)
            if !message.text.isEmpty { Text(message.text).font(.body).textSelection(.enabled) }
            if let id = message.documentID { Button { open(id) } label: { Label("Open shared journey", systemImage: "map").font(.subheadline) } }
            Text(message.timestamp).font(.caption2).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: 22, emphasized: isOwn)
    }
}

private struct AttachJourneyView: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    let conversation: TravelConversation
    @State private var selected: UUID?
    @State private var message = ""
    @State private var error: String?
    @State private var sending = false
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Add a message", text: $message, axis: .vertical) }
                Section("Journey to share") { ForEach(library.documents) { document in Button { selected = document.id } label: { HStack { Text(document.title); Spacer(); if selected == document.id { Image(systemName: "checkmark") } } } } }
                Section { Text("Shares a read-only copy with everyone in this conversation. Photos and place notes are included; hotel confirmation numbers and booking notes are hidden.").font(.caption).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Share in \(conversation.name)").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Send") { Task { guard let document = library.documents.first(where: { $0.id == selected }) else { return }; sending = true; defer { sending = false }; do { _ = try await api.upload(document); _ = try await api.send(conversation.id, text: message, documentID: document.id.uuidString); dismiss() } catch { self.error = error.localizedDescription } } }.disabled(selected == nil || sending) } }
        }
    }
}

struct SharedJourneyPreview: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    let remote: RemoteJourney
    @State private var loaded: RemoteJourney?
    @State private var loading = false
    @State private var imported = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let current = loaded {
                    HStack { FriendsAvatar(name: current.owner.name, size: 34); Text("Shared by " + current.owner.name).font(.subheadline); Spacer() }
                    Text(current.document.title).font(.system(.largeTitle, design: .serif)).accessibilityIdentifier("shared-itinerary-title")
                    VStack(alignment: .leading, spacing: 8) {
                        Label(current.document.routeLabel, systemImage: "mappin.and.ellipse")
                        Label(FriendsTravel.dates(current.document), systemImage: "calendar")
                    }.font(.subheadline).foregroundStyle(.secondary)
                    HStack { Label("Shared itinerary", systemImage: "person.2").foregroundStyle(FlightDisplay.blue); Spacer(); Text("\(current.document.planCount) plans").foregroundStyle(.secondary) }.font(.caption)
                    Text("View the owner’s latest shared plan here. Save a private copy to adapt it for your own trip.").font(.caption).foregroundStyle(.secondary)
                    Button { do { _ = try library.importData(JSONEncoder().encode(JourneyArchive(document: current.document))); imported = true } catch { self.error = error.localizedDescription } } label: { Label(imported ? "Private copy saved" : "Save a private copy", systemImage: imported ? "checkmark" : "square.and.arrow.down").font(.subheadline) }.buttonStyle(.glass).disabled(imported || loading).accessibilityIdentifier("shared-itinerary-copy")
                    if !current.document.description.isEmpty { Text(current.document.description).font(.subheadline).foregroundStyle(.secondary) }
                    Divider()
                    SharedItineraryContent(document: current.document)
                    if current.document.mapPlaces.contains(where: \.hasCoordinate) {
                        DisclosureGroup("Places on the map") { JourneyMapView(places: current.document.mapPlaces).frame(height: 260).clipShape(.rect(cornerRadius: 20)) }.font(.subheadline)
                    }
                    Text("Last shared " + Date(timeIntervalSince1970: current.document.updatedAt).formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                } else if loading { ProgressView("Opening the shared itinerary…").frame(maxWidth: .infinity).padding(.top, 50) }
                if let error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.secondary); Button("Try again") { Task { await refresh() } } }
            }.padding(24)
        }.background(Color.canvas).navigationTitle("Shared itinerary").navigationBarTitleDisplayMode(.inline)
            .task(id: remote.id) { await refresh() }.refreshable { await refresh() }
    }
    private func refresh() async {
        loading = true; defer { loading = false }
        do { let value = try await api.document(remote.id); guard !Task.isCancelled else { return }; loaded = value; error = nil }
        catch { loaded = nil; self.error = error.localizedDescription }
    }
}

private struct SharedItineraryContent: View {
    let document: JourneyDocument
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !document.flights.isEmpty {
                Text("Flights").font(.headline)
                ForEach(document.flights) { flight in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "airplane").foregroundStyle(FlightDisplay.blue).frame(width: 24)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(flight.departureAirport + " → " + flight.arrivalAirport).font(.headline)
                            Text(flight.airline + " " + flight.flightNumber).font(.subheadline).foregroundStyle(.secondary)
                            Text(TravelDay.label(flight.departureDay) + " · " + flight.departureTime + " → " + flight.arrivalTime + " · Airport local times").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
            }
            if !document.hotels.isEmpty {
                Text("Stays").font(.headline)
                ForEach(document.hotels) { stay in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "bed.double").foregroundStyle(Color.bronze).frame(width: 24)
                        VStack(alignment: .leading, spacing: 6) { Text(stay.place.name).font(.subheadline.weight(.medium)); Text(TravelDay.label(stay.checkIn) + " – " + TravelDay.label(stay.checkOut)).font(.caption).foregroundStyle(.secondary); if !stay.roomType.isEmpty { Text(stay.roomType).font(.caption).foregroundStyle(.secondary) } }
                    }
                }
                Divider()
            }
            ForEach(document.days) { day in
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) { Text(day.label).font(.system(.title2, design: .serif)); Text(day.city).font(.subheadline).foregroundStyle(.secondary) }
                    let events = document.events.filter { $0.stopID == day.stopID && $0.day == day.localDay }.sorted { $0.sortMinute < $1.sortMinute }
                    if events.isEmpty { Text("Room for something spontaneous").font(.caption).foregroundStyle(.secondary) }
                    ForEach(events) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Text(event.allDay == true ? "All day" : event.timeLabel).font(.caption.monospacedDigit()).foregroundStyle(Color.bronze).frame(width: 52, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                Label(event.displayTitle, systemImage: event.symbol).font(.subheadline.weight(.medium))
                                if !event.description.isEmpty { Text(event.description).font(.caption).foregroundStyle(.secondary) }
                                if !event.place.address.isEmpty { Text(event.place.address).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Divider()
            }
            if document.days.isEmpty && document.flights.isEmpty && document.hotels.isEmpty { Text("This itinerary is just getting started.").font(.subheadline).foregroundStyle(.secondary) }
            if !document.places.isEmpty {
                Text("From the journey").font(.headline)
                ForEach(document.places) { place in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { Text(place.place.name).font(.subheadline.weight(.semibold)); Spacer(); if place.overall > 0 { Label(String(format: "%.1f", place.overall), systemImage: "star.fill").font(.caption).foregroundStyle(Color.bronze) } }
                        if !place.notes.isEmpty { Text(place.notes).font(.subheadline).foregroundStyle(.secondary) }
                        if !place.photos.isEmpty { ScrollView(.horizontal) { HStack { ForEach(place.photos) { photo in if let image = UIImage(data: photo.jpeg) { Image(uiImage: image).resizable().scaledToFill().frame(width: 220, height: 160).clipped().clipShape(.rect(cornerRadius: 16)) } } } }.scrollIndicators(.hidden) }
                    }
                    Divider()
                }
            }
        }
    }
}

struct JourneyShareView: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    @State private var loading = false
    @State private var message: String?
    @State private var link: String?
    @State private var chats: [TravelConversation] = []
    @State private var friends: [TravelFriend] = []
    @State private var note = ""
    @State private var account = false
    @State private var export: ExportedJourney?
    private var document: JourneyDocument? { library.documents.first { $0.id == documentID } }
    var body: some View {
        NavigationStack {
            Form {
                if let document {
                    Section { Text(document.title).font(.system(.title2, design: .serif)); Text("Your journal, your audience.").foregroundStyle(.secondary) }
                    Section {
                        ForEach(JourneyExportFormat.allCases) { format in Button { do { export = ExportedJourney(url: try JourneyExporter.export(document, format: format)) } catch { message = error.localizedDescription } } label: { Label("Share \(format.rawValue.uppercased())", systemImage: "square.and.arrow.up") } }
                    } header: { Text("Take it with you") } footer: { Text("Use the Apple share sheet for Mail, Messages, AirDrop and Files. Exports include the booking details and private notes in your local copy. JSON can be imported back into Seur.") }
                    if api.isSignedIn {
                        Section("Cloud & audience") {
                            Button("Save cloud copy") { run { _ = try await api.upload(document); message = "Cloud copy saved with your current audience settings." } }
                            ForEach(JourneyVisibility.allCases, id: \.self) { visibility in
                                Button { run { var d = document; d.visibility = visibility; _ = try await api.upload(d); if visibility == .private { try await api.revoke(d.id); link = nil }; try saveLocal(d); message = "Audience updated to \(visibility.title)." } } label: { HStack { Label(visibility == .friends ? "Shared with friends" : visibility.title, systemImage: visibility == .private ? "lock" : "person.2"); Spacer(); if document.visibility == visibility { Image(systemName: "checkmark") } } }
                            }
                        }
                        Section {
                            Button("Create share link") { run { _ = try await api.upload(document); link = try await api.link(document.id).url } }
                            if let link { ShareLink(item: link) { Label("Share link", systemImage: "square.and.arrow.up") }; Button("Copy link") { UIPasteboard.general.string = link; message = "Link copied." } }
                            Button("Revoke all links & direct shares", role: .destructive) { run { try await api.revoke(document.id); var d = document; d.visibility = .private; try saveLocal(d); link = nil; message = "Links and direct shares revoked. Imported copies belong to their recipients." } }
                        } header: { Text("Share a read-only link") } footer: { Text("Link viewers see a read-only page. Hotel confirmation numbers and booking notes are hidden. Place notes and photos are shared. Revoking access cannot remove copies already imported or exported.") }
                        Section("Send to a friend or group") {
                            TextField("A message with your journey", text: $note, axis: .vertical)
                            ForEach(friends.filter { $0.status == "accepted" }) { friend in Button("Send to \(friend.name)") { run { let chat = try await api.createConversation(name: "\(api.account?.name ?? "You") & \(friend.name)", members: [friend.id]); _ = try await api.upload(document); _ = try await api.send(chat.id, text: note, documentID: document.id.uuidString); message = "Shared with \(friend.name)." } } }
                            ForEach(chats) { chat in Button("Send to \(chat.name)") { run { _ = try await api.upload(document); _ = try await api.send(chat.id, text: note, documentID: document.id.uuidString); message = "Shared in \(chat.name)." } } }
                            if friends.isEmpty && chats.isEmpty { Text("Add friends or create a group in Friends → People.").font(.caption).foregroundStyle(.secondary) }
                        }
                        Section { Button("Delete cloud copy", role: .destructive) { run { try await api.deleteDocument(document.id.uuidString); var d = document; d.visibility = .private; try saveLocal(d); link = nil; message = "Cloud copy deleted and its shares revoked. Your local copy remains." } } }
                    } else { Section { Button("Connect an account to share with friends") { account = true } } }
                    if loading { ProgressView() }
                    if let message { Section { Text(message).font(.subheadline) } }
                }
            }.disabled(loading).scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Share your journey").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task { await refresh() }
                .fullScreenCover(isPresented: $account, onDismiss: { Task { await refresh() } }) { TravelAccountView() }
                .sheet(item: $export) { ActivityShareSheet(items: [$0.url]) }
        }
    }
    private func saveLocal(_ document: JourneyDocument) throws {
        guard library.save(document) else {
            throw NSError(domain: "AurumStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "The server was updated, but this device could not save the change. " + (library.error ?? "Please try again.")])
        }
    }
    private func run(_ action: @escaping () async throws -> Void) { Task { loading = true; message = nil; defer { loading = false }; do { try await action() } catch { message = error.localizedDescription } } }
    private func refresh() async { if !api.isSignedIn { try? await api.refresh() }; if api.isSignedIn { do { friends = try await api.friends(); chats = try await api.conversations() } catch { message = error.localizedDescription } } }
}

#if DEBUG
/// Synthetic data only when explicitly launched by the Friends UI tests.
@MainActor enum FriendsFixtures {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--friends-testing") }
    static let owner = TravelAccount(id: "11111111-1111-4111-8111-111111111111", handle: "seur_tester", name: "Alex")
    static let maya = TravelAccount(id: "22222222-2222-4222-8222-222222222222", handle: "maya_test", name: "Maya Chen")
    static var friends: [TravelFriend] { [.init(id: maya.id, handle: maya.handle, name: maya.name, status: "accepted", incoming: true), .init(id: "33333333-3333-4333-8333-333333333333", handle: "sam_test", name: "Sam Rivera", status: "pending", incoming: true)] }
    static var trip: JourneyDocument {
        let stop = JourneyStop(name: "Paris", country: "France", arrival: TravelDay.adding(5, to: TravelDay.key(.now)), nights: 3)
        var trip = JourneyDocument(id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!, title: "Paris with Maya", visibility: .friends, stops: [stop])
        trip.events = [.init(stopID: stop.id, day: 0, minute: 600, place: PlaceRecord(name: "A morning at the museum", category: .museum, city: "Paris"))]
        return trip
    }
    static var remote: RemoteJourney { .init(id: trip.id.uuidString, owner: maya, document: trip, revision: 1, isSummary: true) }
    static var chat: TravelConversation { .init(id: "55555555-5555-4555-8555-555555555555", name: "Paris planning", members: [owner, maya]) }
    static func response(_ path: String, method: String) throws -> Data {
        guard method == "GET" else { throw JourneyError.message("Mutations are disabled for synthetic Friends fixtures.") }
        let encoder = JSONEncoder()
        if path == "/v1/me" { return try encoder.encode(owner) }
        if path == "/v1/status" { return try encoder.encode(TravelServiceStatus(tripadvisor: false, ai: false, publicSharing: true)) }
        if path == "/v1/friends" { return try encoder.encode(friends) }
        if path == "/v1/feed" { return try encoder.encode([remote]) }
        if path == "/v1/documents" { return try encoder.encode([RemoteJourney]()) }
        if path.hasPrefix("/v1/documents/") { var value = remote; value.isSummary = false; return try encoder.encode(value) }
        if path == "/v1/conversations" { return try encoder.encode([chat]) }
        if path.hasSuffix("/messages") { return try encoder.encode([TravelChatMessage]()) }
        if path == "/v1/my-flights" { return try encoder.encode([FlightReservation]()) }
        throw JourneyError.message("This service is disabled during Friends UI tests.")
    }
}
#endif
