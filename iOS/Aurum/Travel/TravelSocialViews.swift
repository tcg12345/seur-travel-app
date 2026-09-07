import SwiftUI

struct TravelAccountView: View {
    @Environment(TravelAPI.self) private var api
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var handle = ""
    @State private var name = ""
    @State private var password = ""
    @State private var register = false
    @State private var loading = false
    @State private var error: String?
    @State private var cloud: [RemoteJourney] = []
    @State private var confirmingDeletion = false
    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("account-message") } }
                if let account = api.account {
                    Section("Your account") { Label(account.name, systemImage: "person.crop.circle"); Text("@" + account.handle).foregroundStyle(.secondary); Button("Sign out") { Task { await api.logout(); cloud = [] } } }
                    Section("Cloud copies") {
                        Button("Refresh cloud journeys") { Task { await loadCloud() } }
                        ForEach(cloud) { remote in
                            Button { Task { do { let full = try await api.document(remote.id); _ = try library.importData(JSONEncoder().encode(JourneyArchive(document: full.document))); error = "A private copy was saved on this device." } catch { self.error = error.localizedDescription } } } label: { VStack(alignment: .leading, spacing: 5) { Text(remote.document.title); Text("Download a separate copy").font(.caption).foregroundStyle(.secondary) } }
                        }
                    }
                } else {
                    Section {
                        Picker("Account", selection: $register) { Text("Sign in").tag(false); Text("Create account").tag(true) }.pickerStyle(.segmented)
                        TextField("Username", text: $handle).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username).accessibilityIdentifier("account-handle")
                        if register { TextField("Display name", text: $name).textContentType(.name) }
                        SecureField("Password (12+ characters)", text: $password).textContentType(register ? .newPassword : .password).accessibilityIdentifier("account-password")
                        Button(loading ? "Connecting…" : register ? "Create my account" : "Sign in") { Task { loading = true; error = nil; defer { loading = false }; do { try await api.authenticate(handle: handle, name: name, password: password, register: register); password = ""; await loadCloud() } catch { self.error = error.localizedDescription } } }.accessibilityIdentifier("account-submit").disabled(loading || handle.isEmpty || password.isEmpty)
                    } header: { Text("Travel is better together") } footer: { Text("Your local journeys work without an account. Sign in to save cloud copies, find friends, and share.") }
                }
                Section("Travel services") {
                    LabeledContent("Seur Cloud", value: "Supabase")
                    LabeledContent("Apple Maps", value: "Available on iOS")
                    LabeledContent("FlightAware", value: api.status?.flightTracking.map { $0 ? "Connected" : "Not connected" } ?? "Not checked")
                    LabeledContent("Google Places", value: api.status?.googlePlaces.map { $0 ? "Connected" : "Apple Maps fallback" } ?? "Not checked")
                    LabeledContent("Tripadvisor", value: api.status.map { $0.tripadvisor ? "Connected" : "Key needed on server" } ?? "Not checked")
                    LabeledContent("AI recommendations", value: api.status.map { $0.ai ? "Connected" : "Key needed on server" } ?? "Not checked")
                    LabeledContent("Public links", value: api.status.map { $0.publicSharing ? "Available" : "Not connected" } ?? "Not checked")
                }
                #if DEBUG
                Section {
                    TextField("https://your-backend.example", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Connect to server") { Task { api.baseURL = address.trimmingCharacters(in: .whitespacesAndNewlines); await refresh() } }
                } header: { Text("Backend address") } footer: { Text("API keys stay on the backend. Your app connects to Seur Cloud on Supabase. Override this address only for development.") }
                #endif
                if api.isSignedIn { Section { Button("Delete cloud account", role: .destructive) { confirmingDeletion = true } } footer: { Text("Deletes your cloud account and shared journeys. Trips saved on this device remain available.") } }
            }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Your travel account").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task { address = api.baseURL; await refresh() }
                .confirmationDialog("Delete your cloud account and all cloud journeys?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                    Button("Delete account", role: .destructive) { Task { do { try await api.deleteAccount(); cloud = [] } catch { self.error = error.localizedDescription } } }
                    Button("Cancel", role: .cancel) { }
                }
        }
    }
    private func refresh() async { do { try await api.refresh(); error = nil; if api.isSignedIn { await loadCloud() } } catch { self.error = error.localizedDescription } }
    private func loadCloud() async { do { cloud = try await api.documents() } catch { self.error = error.localizedDescription } }
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
                HStack { TextField("Friend’s username", text: $handle).textInputAutocapitalization(.never).autocorrectionDisabled(); Button("Invite") { Task { do { try await api.requestFriend(handle); handle = ""; await refresh() } catch { self.error = error.localizedDescription } } }.disabled(handle.isEmpty) }.padding(16).background(.background, in: .rect(cornerRadius: 18))
                ForEach(friends) { friend in
                    HStack {
                        Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(Color.bronze)
                        VStack(alignment: .leading, spacing: 4) { Text(friend.name).font(.subheadline.weight(.medium)); Text("@\(friend.handle) · \(friend.status)").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if friend.status == "pending" && friend.incoming { Button("Accept") { Task { do { try await api.respondFriend(friend.id, accept: true); await refresh() } catch { self.error = error.localizedDescription } } }.font(.caption) }
                        Menu { Button(friend.status == "accepted" ? "Remove friend" : "Decline / cancel request", role: .destructive) { Task { do { try await api.respondFriend(friend.id, accept: false); await refresh() } catch { self.error = error.localizedDescription } } } } label: { Image(systemName: "ellipsis") }
                    }.padding(15).background(.background, in: .rect(cornerRadius: 20))
                }
                HStack { SectionHeading(title: "Conversations"); Spacer(); Button { group = true } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("New conversation") }
                ForEach(chats) { chat in NavigationLink { TravelChatView(conversation: chat) } label: { HStack { Label(chat.name, systemImage: "bubble.left.and.bubble.right"); Spacer(); Image(systemName: "chevron.right") }.font(.subheadline).padding(18).background(.background, in: .rect(cornerRadius: 20)) } }
                SectionHeading(title: "Through a friend’s eyes", subtitle: "Shared trips, from day-by-day plans to favourite memories.")
                if feed.isEmpty { Text("Your friends’ shared journeys will appear here.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(feed) { remote in NavigationLink { SharedJourneyPreview(remote: remote) } label: { VStack(alignment: .leading, spacing: 9) { Eyebrow(text: "By \(remote.owner.name)"); Text(remote.document.title).font(.system(.title3, design: .serif)).foregroundStyle(.primary); Text(remote.document.routeLabel).font(.caption).foregroundStyle(.secondary); Label("Open & import a copy", systemImage: "arrow.up.right").font(.caption) }.frame(maxWidth: .infinity, alignment: .leading).padding(21).background(.background, in: .rect(cornerRadius: 23)) }.buttonStyle(PressStyle()) }
            }
            if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
        }.task { if !api.isSignedIn { try? await api.refresh() }; if api.isSignedIn { await refresh() } }
            .sheet(isPresented: $account, onDismiss: { Task { if api.isSignedIn { await refresh() } } }) { TravelAccountView() }
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
            .background(isOwn ? Color.bronze.opacity(0.10) : Color.cardSurface, in: .rect(cornerRadius: 22))
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
                    } header: { Text("Take it with you") } footer: { Text("Use the Apple share sheet for Mail, Messages, AirDrop and Files. Exports include the booking details and private notes in your local copy. JSON can be imported back into Aurum.") }
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
                .sheet(isPresented: $account, onDismiss: { Task { await refresh() } }) { TravelAccountView() }
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
