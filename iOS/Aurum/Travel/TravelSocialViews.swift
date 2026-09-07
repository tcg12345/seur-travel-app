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
                        Button("Sign out") { Task { loading = true; await api.logout(); cloud = []; justAuthenticated = false; register = false; message = nil; loading = false } }.disabled(loading)
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

struct TravelFriendsView: View {
    @Environment(TravelAPI.self) private var api
    @State private var friends: [TravelFriend] = []
    @State private var feed: [RemoteJourney] = []
    @State private var chats: [TravelConversation] = []
    @State private var handle = ""
    @State private var error: String?
    @State private var account = false
    @State private var group = false
    @State private var refreshing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !api.isSignedIn {
                ContentUnavailableView("Good journeys are worth sharing", systemImage: "person.2", description: Text("Connect your travel account to discover your friends’ itineraries and make plans together."))
                Button("Connect my account") { account = true }.buttonStyle(.glassProminent).frame(maxWidth: .infinity)
            } else {
                HStack { SectionHeading(title: "Your inner circle"); Spacer(); Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }.disabled(refreshing) }
                HStack { TextField("Friend’s username", text: $handle).textInputAutocapitalization(.never).autocorrectionDisabled(); Button("Invite") { Task { do { try await api.requestFriend(handle); handle = ""; await refresh() } catch { self.error = error.localizedDescription } } }.disabled(handle.isEmpty) }.padding(16).cardSurface(cornerRadius: 18)
                ForEach(friends) { friend in
                    HStack {
                        Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(Color.bronze)
                        VStack(alignment: .leading, spacing: 4) { Text(friend.name).font(.subheadline.weight(.medium)); Text("@\(friend.handle) · \(friend.status)").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if friend.status == "pending" && friend.incoming { Button("Accept") { Task { do { try await api.respondFriend(friend.id, accept: true); await refresh() } catch { self.error = error.localizedDescription } } }.font(.caption) }
                        Menu { Button(friend.status == "accepted" ? "Remove friend" : "Decline / cancel request", role: .destructive) { Task { do { try await api.respondFriend(friend.id, accept: false); await refresh() } catch { self.error = error.localizedDescription } } } } label: { Image(systemName: "ellipsis") }
                    }.padding(15).cardSurface(cornerRadius: 20)
                }
                HStack { SectionHeading(title: "Conversations"); Spacer(); Button { group = true } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("New conversation") }
                ForEach(chats) { chat in NavigationLink { TravelChatView(conversation: chat) } label: { HStack { Label(chat.name, systemImage: "bubble.left.and.bubble.right"); Spacer(); Image(systemName: "chevron.right") }.font(.subheadline).padding(18).cardSurface(cornerRadius: 20) } }
                SectionHeading(title: "Through a friend’s eyes", subtitle: "Shared trips, from day-by-day plans to favourite memories.")
                if feed.isEmpty { Text("Your friends’ shared journeys will appear here.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(feed) { remote in NavigationLink { SharedJourneyPreview(remote: remote) } label: { VStack(alignment: .leading, spacing: 9) { Eyebrow(text: "By \(remote.owner.name)"); Text(remote.document.title).font(.system(.title3, design: .serif)).foregroundStyle(.primary); Text(remote.document.routeLabel).font(.caption).foregroundStyle(.secondary); Label("Open & import a copy", systemImage: "arrow.up.right").font(.caption) }.frame(maxWidth: .infinity, alignment: .leading).padding(21).cardSurface(cornerRadius: 23) }.buttonStyle(PressStyle()) }
            }
            if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
        }.task { if !api.isSignedIn { try? await api.refresh() }; if api.isSignedIn { await refresh() } }
            .fullScreenCover(isPresented: $account, onDismiss: { Task { if api.isSignedIn { await refresh() } } }) { TravelAccountView() }
            .sheet(isPresented: $group, onDismiss: { Task { await refresh() } }) { ConversationEditor(friends: friends.filter { $0.status == "accepted" }) }
    }
    private func refresh() async { refreshing = true; defer { refreshing = false }; do { friends = try await api.friends(); feed = try await api.documents(feed: true); chats = try await api.conversations(); error = nil } catch { self.error = error.localizedDescription } }
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
    let remote: RemoteJourney
    @Environment(TravelAPI.self) private var api
    @State private var loaded: RemoteJourney?
    @State private var loading = false
    private var current: RemoteJourney { loaded ?? remote }
    @State private var imported = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "Shared by \(current.owner.name)")
                Editorial(current.document.title, size: 36)
                Text(current.document.routeLabel).foregroundStyle(.secondary)
                Label("Read-only shared journey", systemImage: "lock").font(.caption)
                Button { do { _ = try library.importData(JSONEncoder().encode(JourneyArchive(document: current.document))); imported = true } catch { self.error = error.localizedDescription } } label: { Label(imported ? "Private copy imported" : "Import my own copy", systemImage: imported ? "checkmark" : "square.and.arrow.down").frame(maxWidth: .infinity).padding(.vertical, 11) }.buttonStyle(.glassProminent).disabled(imported || loading || (remote.isSummary == true && loaded == nil))
                Text(JourneyExporter.text(current.document)).font(.subheadline).lineSpacing(5).textSelection(.enabled)
                JourneyMapView(places: current.document.mapPlaces).frame(height: 280).clipShape(.rect(cornerRadius: 22))
                ForEach(current.document.places) { place in
                    if !place.photos.isEmpty { Text(place.place.name).font(.headline); ScrollView(.horizontal) { HStack { ForEach(place.photos) { photo in if let image = UIImage(data: photo.jpeg) { Image(uiImage: image).resizable().scaledToFit().frame(height: 200).clipShape(.rect(cornerRadius: 20)) } } } } }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.padding(24)
        }.background(Color.canvas).navigationTitle("A shared journey").navigationBarTitleDisplayMode(.inline)
            .overlay { if loading { ProgressView("Loading shared photos…").padding(20).glassEffect(.regular, in: .rect(cornerRadius: 20)) } }
            .task(id: remote.id) { await loadFullJourney() }
            .refreshable { await loadFullJourney() }
    }
    private func loadFullJourney() async {
        guard remote.isSummary == true else { return }
        loading = true; defer { loading = false }
        do { loaded = try await api.document(remote.id); error = nil }
        catch { loaded = nil; self.error = error.localizedDescription }

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
                            if friends.isEmpty && chats.isEmpty { Text("Add friends or create a group in Travel → Friends.").font(.caption).foregroundStyle(.secondary) }
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
