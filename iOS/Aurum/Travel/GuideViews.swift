import SwiftUI
import MapKit

struct GuideLink: Identifiable { let id: UUID; init?(url: URL) { guard url.scheme == "seur", url.host == "guide", let id = UUID(uuidString: url.lastPathComponent) else { return nil }; self.id = id } }

struct GuideHubView: View {
    var initialCity = ""
    @Environment(GuideLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @State private var search = ""
    @State private var tag = ""
    @State private var shelf = "Explore"
    @State private var creating = false
    @State private var remote: [PublishedGuide] = []
    @State private var loading = false
    @State private var message: String?
    @State private var more = false
    @State private var cloud = false
    @State private var blocked = false
    private var drafts: [GuideDraft] { library.drafts.filter { matches($0.guide) }.sorted { $0.updatedAt > $1.updatedAt } }
    private func matches(_ g: TravelGuide) -> Bool { (search.isEmpty || (g.title + " " + g.destination).localizedCaseInsensitiveContains(search)) && (shelf != "Explore" || tag.isEmpty || g.tags.contains(tag)) }
    private var visibleRemote: [PublishedGuide] { remote.filter { library.visible($0) } }
    private var requestKey: String {
        [shelf, search, tag, api.baseURL, api.account?.id ?? "", String(api.status?.travelGuides == true)].joined(separator: "|")
    }
    var body: some View {
        page
            .sheet(isPresented: $creating, onDismiss: { shelf = "Your guides" }) { GuideStartView() }
            .sheet(isPresented: $cloud) { GuideCloudLibraryView() }
            .sheet(isPresented: $blocked) { GuideBlockedAuthorsView() }
            .onAppear { if search.isEmpty { search = initialCity } }
            .task(id: requestKey) {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                await load()
            }
            .refreshable { await load() }
    }
    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GuideEyebrow(text: "TRAVEL, PERSONALLY")
                Text("Good places.\nGreat perspectives.").font(.system(size: 34, weight: .regular, design: .serif))
                GuideShelfTabs(selection: $shelf)
                if shelf == "Explore" { exploreShelf }
                else if shelf == "Your guides" { ownShelf }
                else { savedShelf }
            }.padding(24)
        }.background(Color.canvas).navigationTitle("Travel guides").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search guides or destinations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { creating = true } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("Create guide").accessibilityIdentifier("guides-create") }
                ToolbarItem(placement: .topBarTrailing) { if !library.blockedAuthors.isEmpty { Button { blocked = true } label: { Image(systemName: "person.crop.circle.badge.xmark") }.accessibilityLabel("Blocked guide authors") } }
            }
    }
    @ViewBuilder private var exploreShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { themeButton("All", value: ""); ForEach(TravelGuide.themes, id: \.self) { themeButton($0, value: $0) } }
        }
        if loading && remote.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(30) }
        else if visibleRemote.isEmpty { empty(title: "The next great guide could be yours.", detail: message ?? "Share your favorite corners, memorable meals, and advice worth passing on.", action: true) }
        ForEach(visibleRemote) { value in publicCard(value) }
        if more { Button(action: loadMore) { Text("More guides") }.disabled(loading) }
        if !remote.isEmpty, let message { Text(message).font(.caption).foregroundStyle(.secondary) }
    }
    private func loadMore() { Task { await load(append: true) } }
    @ViewBuilder private var ownShelf: some View {
        if drafts.isEmpty { empty(title: "Your experience is the starting point.", detail: "Create a guide from scratch or begin with places from a trip.", action: true) }
        ForEach(drafts) { draft in draftCard(draft) }
        if api.isSignedIn { Button("Find your published guides", systemImage: "icloud.and.arrow.down") { cloud = true }.font(.subheadline) }
    }
    @ViewBuilder private var savedShelf: some View {
        let saved = library.saved.filter { library.visible($0) && matches($0.guide) }
        if saved.isEmpty { empty(title: "Keep a little inspiration.", detail: "Save a guide to read it offline and return to its recommendations.", action: false) }
        ForEach(saved) { value in savedCard(value) }
    }
    private func draftCard(_ value: GuideDraft) -> some View {
        let count = value.guide.places.count
        let subtitle = value.status + " · " + (count == 1 ? "1 place" : "\(count) places")
        return NavigationLink { GuideEditorView(initial: value.guide) } label: { GuideCard(guide: value.guide, subtitle: subtitle) }.buttonStyle(.plain)
    }
    private func savedCard(_ value: PublishedGuide) -> some View {
        let subtitle = "Saved for offline reading · @\(value.author.handle)"
        return NavigationLink { GuideReaderView(id: value.id, cached: value) } label: { GuideCard(guide: value.guide, subtitle: subtitle) }.buttonStyle(.plain)
    }
    private func publicCard(_ value: PublishedGuide) -> some View {
        let count = value.placeCount
        let subtitle = "By @\(value.author.handle) · " + (count == 1 ? "1 place" : "\(count) places")
        return NavigationLink { GuideReaderView(id: value.id) } label: { GuideCard(guide: value.guide, subtitle: subtitle) }.buttonStyle(.plain)
    }
    private func themeButton(_ title: String, value: String) -> some View {
        Button { tag = value } label: { Text(title).font(.caption.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 10).background(tag == value ? Color.bronze.opacity(0.15) : Color.cardSurface, in: .capsule) }.buttonStyle(.plain).accessibilityAddTraits(tag == value ? .isSelected : [])
    }
    private func empty(title: String, detail: String, action: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "book.closed").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(Color.bronze)
            Text(title).font(.system(.title2, design: .serif))
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
            if action { Button("Create your first guide") { creating = true }.buttonStyle(.glassProminent).accessibilityIdentifier("guide-first") }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color.cardSurface, in: .rect(cornerRadius: 24))
    }
    private func load(append: Bool = false) async {
        guard shelf == "Explore", api.status?.travelGuides == true else { message = nil; return }
        let requestSearch = search, requestTag = tag, server = api.baseURL
        loading = true; defer { loading = false }
        do { let values = try await api.guides(search: search, tag: tag, offset: append ? remote.count : 0); guard !Task.isCancelled, search == requestSearch, tag == requestTag, api.baseURL == server else { return }; var seen = Set<UUID>(); remote = (append ? remote + values : values).filter { seen.insert($0.id).inserted }; more = values.count == 20; message = nil }
        catch { if !Task.isCancelled { message = "Community guides couldn’t be loaded. Your drafts and saved guides are still available." } }
    }
}
private struct GuideShelfTabs: View {
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 22) {
            shelfButton("Explore")
            shelfButton("Your guides")
            shelfButton("Saved")
            Spacer(minLength: 0)
        }
    }
    private func shelfButton(_ title: String) -> some View {
        Button(action: { selection = title }) {
            VStack(spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(selection == title ? Color.bronze : Color.secondary)
                Capsule().fill(selection == title ? Color.bronze : Color.clear).frame(height: 2)
            }
        }.buttonStyle(.plain).fixedSize().accessibilityIdentifier("guides-shelf-" + title)
    }
}
struct GuideCard: View {
    let guide: TravelGuide
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GuideCover(guide: guide, height: 165)
            VStack(alignment: .leading, spacing: 9) {
                Text(guide.destination.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(Color.bronze)
                Text(guide.title).font(.system(.title2, design: .serif)).foregroundStyle(.primary).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.frame(maxWidth: .infinity, alignment: .leading).background(Color.cardSurface, in: .rect(cornerRadius: 24)).clipShape(.rect(cornerRadius: 24))
    }
}
struct GuideCover: View {
    let guide: TravelGuide
    var height: CGFloat = 225
    var body: some View {
        GeometryReader { size in
            if let data = guide.coverJPEG, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: size.size.width, height: size.size.height).clipped()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.20, green: 0.25, blue: 0.25), Color(red: 0.11, green: 0.15, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().stroke(.white.opacity(0.12), lineWidth: 1).frame(width: 240, height: 240).offset(x: 70, y: 30)
                    Circle().stroke(.white.opacity(0.08), lineWidth: 1).frame(width: 180, height: 180).offset(x: 70, y: 30)
                    HStack(alignment: .bottom) { Text(String(guide.destination.prefix(1)).uppercased()).font(.system(size: 92, weight: .regular, design: .serif)); Spacer(); Image(systemName: "book.closed").font(.system(size: 30, weight: .ultraLight)) }.foregroundStyle(.white.opacity(0.65)).padding(25)
                }.frame(width: size.size.width, height: size.size.height).clipped()
            }
        }.frame(height: height).accessibilityHidden(true)
    }
}

struct GuidePublishView: View {
    let id: UUID
    @Environment(GuideLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?
    @State private var account = false
    @State private var confirming = false
    @State private var unpublishing = false
    @State private var deleting = false
    @State private var published = false
    @State private var latest: PublishedGuide?
    private var draft: GuideDraft? { library.drafts.first { $0.id == id } }
    private var owned: Bool { draft?.ownerID == nil || (draft?.ownerID == api.account?.id && draft?.server == api.baseURL) }
    var body: some View {
        Group {
            if let draft {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        GuideEyebrow(text: "READER PREVIEW")
                        GuideArticle(guide: draft.guide, author: api.account?.name ?? "You", preview: true)
                        VStack(alignment: .leading, spacing: 14) {
                            Text(draft.isPublished ? "Your public guide" : "Ready to share?").font(.system(.title2, design: .serif))
                            Text("Publishing makes your guide, photos, and author profile visible to everyone. Share only writing and images you have permission to publish.").font(.subheadline).foregroundStyle(.secondary)
                            if let issue = draft.guide.publicationIssue { Label(issue, systemImage: "pencil.line").font(.subheadline).foregroundStyle(Color.bronze).accessibilityIdentifier("guide-publish-issue") }
                            if !owned { Text("Sign in with the account that published this guide to update it.").font(.subheadline).foregroundStyle(.secondary) }
                            else if !api.isSignedIn { Button("Sign in to publish") { account = true }.buttonStyle(.glassProminent).accessibilityIdentifier("guide-signin-publish") }
                            else if api.status?.travelGuides != true { Text("Publishing is temporarily unavailable. Your draft is saved.").font(.subheadline).foregroundStyle(.secondary) }
                            else { Button(draft.isPublished ? "Publish update" : "Publish guide", systemImage: "globe") { confirming = true }.buttonStyle(.glassProminent).disabled(busy || draft.guide.publicationIssue != nil || (draft.isPublished && !draft.hasChanges)).accessibilityIdentifier("guide-publish-button") }
                            if draft.isPublished, let url = api.guideShareURL(id) { ShareLink(item: url) { Label("Share published guide", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("guide-share-link") }
                            if busy { ProgressView() }
                            if let error {
                                Text(error).foregroundStyle(.red).font(.subheadline)
                                if owned && api.isSignedIn { Button("Review latest published version") { Task { do { latest = try await api.guide(id, own: true) } catch { self.error = error.localizedDescription } } }.font(.subheadline) }
                            }
                            if published { Label("Your guide is published", systemImage: "checkmark.circle.fill").foregroundStyle(Color.bronze).accessibilityIdentifier("guide-published") }
                        }.padding(22).background(Color.cardSurface, in: .rect(cornerRadius: 22))
                        if draft.isPublished && owned { Button("Unpublish guide", role: .destructive) { unpublishing = true }.disabled(busy) }
                        if !draft.isPublished { Button("Delete local draft", role: .destructive) { deleting = true } }
                    }.padding(24)
                }.background(Color.canvas)
            } else { ContentUnavailableView("Draft unavailable", systemImage: "book.closed") }
        }.navigationTitle("Preview & publish").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $account) { NavigationStack { TravelAccountPage().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { account = false } } } } }
            .sheet(item: $latest) { value in
                NavigationStack {
                    ScrollView { VStack(alignment: .leading, spacing: 24) {
                        Text("The current published version").font(.headline)
                        GuideArticle(guide: value.guide, author: value.author.name, preview: true)
                        Text("Choose which content to keep before publishing another update.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Keep my draft") { if library.accept(value, server: api.baseURL, replaceDraft: false) { latest = nil; error = nil } }.buttonStyle(.glassProminent)
                        Button("Use published version") { if library.accept(value, server: api.baseURL) { latest = nil; error = nil } }.buttonStyle(.glass)
                    }.padding(24) }.background(Color.canvas).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { latest = nil } } }
                }
            }
            .confirmationDialog("Publish this guide for everyone?", isPresented: $confirming, titleVisibility: .visible) { Button("Publish now") { Task { await publish() } }.accessibilityIdentifier("guide-confirm-publish") } message: { Text("Your private trip stays private. Only this guide will be published.") }
            .confirmationDialog("Remove this guide from public discovery?", isPresented: $unpublishing, titleVisibility: .visible) { Button("Unpublish", role: .destructive) { Task { await unpublish() } } } message: { Text("Your draft stays on this device. Previously downloaded copies cannot be recalled.") }
            .confirmationDialog("Delete this private draft?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete draft", role: .destructive) { if library.remove(id) { dismiss() } } }
    }
    private func publish() async {
        guard !busy, let draft, owned, draft.guide.publicationIssue == nil else { return }; busy = true; defer { busy = false }
        do { let remote = try await api.publishGuide(draft.guide, revision: draft.revision); guard library.accept(remote, server: api.baseURL) else { error = library.error; return }; published = true; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func unpublish() async {
        guard !busy, let draft, owned else { return }; busy = true; defer { busy = false }
        do { let remote = try await api.unpublishGuide(id, revision: draft.revision); guard library.accept(remote, server: api.baseURL, replaceDraft: false) else { error = library.error; return }; published = false; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct GuideReaderView: View {
    let id: UUID
    var cached: PublishedGuide? = nil
    @Environment(GuideLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var remote: PublishedGuide?
    @State private var loading = false
    @State private var error: String?
    @State private var report = false
    @State private var blocked = false
    @State private var notice: String?
    private var value: PublishedGuide? { remote ?? cached }
    var body: some View {
        Group {
            if let value, library.visible(value) {
                ScrollView { VStack(alignment: .leading, spacing: 24) {
                    if cached != nil && remote == nil { Label("Saved for offline reading", systemImage: "arrow.down.circle").font(.caption).foregroundStyle(.secondary) }
                    GuideArticle(guide: value.guide, author: value.author.name + " · @" + value.author.handle)
                    Text("Updated " + Date(timeIntervalSince1970: value.updatedAt).formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.secondary).font(.caption) }
                    if let notice { Text(notice).foregroundStyle(Color.bronze).font(.subheadline) }
                }.padding(24) }.background(Color.canvas)
            } else if loading { ProgressView("Opening guide…") }
            else { ContentUnavailableView("Guide unavailable", systemImage: "book.closed", description: Text(error ?? "The author may have unpublished this guide.")) }
        }.navigationTitle("Travel guide").navigationBarTitleDisplayMode(.inline)
            .toolbar { if let value, library.visible(value) {
                ToolbarItem(placement: .topBarTrailing) { Button { if !library.bookmark(value) { error = library.error } } label: { Image(systemName: library.saved.contains(where: { $0.id == id }) ? "bookmark.fill" : "bookmark") }.accessibilityLabel("Save guide for offline reading") }
                ToolbarItem(placement: .topBarTrailing) { if let url = api.guideShareURL(id) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } } }
                ToolbarItem(placement: .topBarTrailing) { Menu {
                    Button("Refresh guide", systemImage: "arrow.clockwise") { Task { await load() } }
                    if value.author.id != api.account?.id {
                        Button("Report guide", systemImage: "flag") { report = true }
                        Button("Hide this guide", systemImage: "eye.slash") { _ = library.hide(id); dismiss() }
                        Button("Block author", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { blocked = true }
                    }
                } label: { Image(systemName: "ellipsis") } }
            } }
            .task(id: id) { if cached == nil { await load() } }
            .confirmationDialog("Report guide", isPresented: $report, titleVisibility: .visible) {
                ForEach(["Spam","Inappropriate content","Inaccurate information","Copyright concern"], id: \.self) { reason in Button(reason) { Task { do { try await api.reportGuide(id, reason: reason); _ = library.hide(id); dismiss() } catch { self.error = error.localizedDescription } } }.disabled(!api.isSignedIn) }
            } message: { Text(api.isSignedIn ? "Choose a reason. Reports are sent for review." : "Sign in from Travel to send a report. You can hide this guide now.") }
            .confirmationDialog("Block this author’s guides?", isPresented: $blocked, titleVisibility: .visible) { Button("Block author", role: .destructive) { guard let value else { return }; Task { do { if api.isSignedIn { try await api.blockGuideAuthor(value.author.id, blocked: true) }; _ = library.block(value.author.id, blocked: true); dismiss() } catch { self.error = error.localizedDescription } } } }
    }
    private func load() async { loading = true; defer { loading = false }; do { remote = try await api.guide(id); error = nil } catch { self.error = "This guide couldn’t be opened. Check your connection or try again." } }
}

struct GuideArticle: View {
    let guide: TravelGuide
    let author: String
    var preview = false
    @State private var map = false
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            GuideCover(guide: guide).clipShape(.rect(cornerRadius: 24))
            GuideEyebrow(text: guide.destination.uppercased())
            Text(guide.title).font(.system(size: 34, weight: .regular, design: .serif)).fixedSize(horizontal: false, vertical: true)
            Text("By " + author).font(.subheadline).foregroundStyle(.secondary)
            if !guide.tags.isEmpty { Text(guide.tags.joined(separator: " · ")).font(.caption).foregroundStyle(Color.bronze) }
            Text(guide.introduction).font(.body).lineSpacing(5)
            if guide.places.contains(where: { $0.place.hasCoordinate }) { Button { map = true } label: { HStack { Label("See the places on a map", systemImage: "map"); Spacer(); Image(systemName: "arrow.up.right") }.font(.subheadline.weight(.medium)).padding(17) }.buttonStyle(.glass) }
            ForEach(Array(guide.sections.enumerated()), id: \.element.id) { number, section in
                VStack(alignment: .leading, spacing: 20) {
                    Divider().padding(.vertical, 4)
                    GuideEyebrow(text: "CHAPTER " + String(format: "%02d", number + 1))
                    Text(section.title).font(.system(.title, design: .serif))
                    if !section.note.isEmpty { Text(section.note).lineSpacing(4) }
                    ForEach(section.places) { item in GuideRecommendation(item: item, guideTitle: guide.title, preview: preview) }
                }
            }
        }.sheet(isPresented: $map) { GuideMapView(guide: guide) }
    }
}
struct GuideRecommendation: View {
    let item: GuidePlace
    let guideTitle: String
    var preview = false
    @Environment(TravelStore.self) private var store
    @State private var trip = false
    @State private var notice: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let data = item.photoJPEG, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().clipShape(.rect(cornerRadius: 16)) }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.place.category.symbol).foregroundStyle(Color.bronze).padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) { Text(item.place.name).font(.headline); if !item.place.address.isEmpty { Text(item.place.address).font(.caption).foregroundStyle(.secondary) } }
                Spacer()
                if !preview { Menu {
                    Button("Save to Wishlist", systemImage: "bookmark") {
                        let p = item.place
                        let idea = WishlistIdea(name: p.name, destination: p.city, kind: WishlistKind.forPlace(p), website: p.website)
                        notice = store.wishlist.saveIdea(idea, details: WishlistDetails(notes: item.note, collection: guideTitle)) ? "Saved to Wishlist" : store.wishlist.error
                    }
                    Button("Add to a trip", systemImage: "suitcase") { trip = true }
                    if item.place.hasCoordinate { Link("Directions", destination: URL(string: "https://maps.apple.com/?ll=\(item.place.latitude!),\(item.place.longitude!)")!) }
                    if let url = validatedURL(item.place.website) { Link("Website", destination: url) }
                } label: { Image(systemName: "plus.circle").font(.title3).frame(width: 44, height: 44) }.accessibilityLabel("Save " + item.place.name) }
            }
            if !item.note.isEmpty { Text(item.note).font(.subheadline).lineSpacing(4) }
            if let notice { Text(notice).font(.caption).foregroundStyle(Color.bronze) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.cardSurface, in: .rect(cornerRadius: 20))
            .sheet(isPresented: $trip) { GuideAddToTripView(item: item) }
    }
}
struct GuideMapView: View {
    let guide: TravelGuide
    @Environment(\.dismiss) private var dismiss
    @State private var sectionID: UUID?
    private var places: [GuidePlace] { (sectionID.flatMap { id in guide.sections.first { $0.id == id }?.places } ?? guide.places).filter { $0.place.hasCoordinate } }
    var body: some View {
        NavigationStack {
            Map { ForEach(places) { item in Annotation(item.place.name, coordinate: .init(latitude: item.place.latitude!, longitude: item.place.longitude!)) { Image(systemName: item.place.category.symbol).font(.subheadline).foregroundStyle(.white).padding(10).background(Color.bronze, in: .circle) } } }
                .mapStyle(.standard(elevation: .flat)).safeAreaInset(edge: .top) { Picker("Chapter", selection: $sectionID) { Text("All places").tag(UUID?.none); ForEach(guide.sections) { Text($0.title).tag(Optional($0.id)) } }.pickerStyle(.menu).padding(10).glassEffect(.regular, in: .capsule).padding(12) }
                .navigationTitle("Guide map").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
struct GuideAddToTripView: View {
    let item: GuidePlace
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var tripID: UUID?
    @State private var dayID: String?
    @State private var error: String?
    private var trip: JourneyDocument? { library.trips.first { $0.id == tripID } }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(item.place.name).font(.headline) }
                if library.trips.isEmpty { Text("Create a trip from Travel first, then add this recommendation.") }
                else {
                    Picker("Trip", selection: $tripID) { Text("Choose a trip").tag(UUID?.none); ForEach(library.trips) { Text($0.title).tag(Optional($0.id)) } }
                    if let trip { Picker("Day", selection: $dayID) { Text("Choose a day").tag(String?.none); ForEach(trip.days) { Text($0.label).tag(Optional($0.id)) } } }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.navigationTitle("Add to a trip").navigationBarTitleDisplayMode(.inline).onChange(of: tripID) { dayID = nil }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") {
                    guard var trip, let day = trip.days.first(where: { $0.id == dayID }) else { return }
                    if trip.events.contains(where: { $0.stopID == day.stopID && $0.day == day.localDay && $0.place.name == item.place.name }) { error = "This place is already on that day."; return }
                    trip.events.append(JourneyEvent(stopID: day.stopID, day: day.localDay, place: item.place.guideLocation, description: item.note, allDay: true))
                    if library.save(trip) { dismiss() } else { error = library.error }
                }.disabled(dayID == nil) } }
        }
    }
}
struct GuideCloudLibraryView: View {
    @Environment(TravelAPI.self) private var api
    @Environment(GuideLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var values: [PublishedGuide] = []
    @State private var error: String?
    @State private var busy = false
    @State private var more = false
    var body: some View {
        NavigationStack {
            List {
                Text("Open a published guide to continue writing on this device. Existing local drafts are kept.").font(.subheadline).foregroundStyle(.secondary)
                ForEach(values) { value in Button { Task { busy = true; defer { busy = false }; do { let full = try await api.guide(value.id, own: true); if library.drafts.contains(where: { $0.id == value.id }) { error = "This guide already has a local draft. Open it from Your guides." } else if library.accept(full, server: api.baseURL) { dismiss() } else { error = library.error } } catch { self.error = error.localizedDescription } } } label: { VStack(alignment: .leading, spacing: 5) { Text(value.guide.title); Text(value.isPublished ? "Published" : "Unpublished").font(.caption).foregroundStyle(.secondary) } }.disabled(busy) }
                if more { Button("More guides") { Task { await load(append: true) } }.disabled(busy) }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
                if values.isEmpty && error == nil { Text("No published guides yet.").foregroundStyle(.secondary) }
            }.navigationTitle("Your cloud guides").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task { await load() }
        }
    }
    private func load(append: Bool = false) async {
        busy = true; defer { busy = false }
        do { let page = try await api.myGuides(offset: append ? values.count : 0); var seen = Set<UUID>(); values = (append ? values + page : page).filter { seen.insert($0.id).inserted }; more = page.count == 20; error = nil }
        catch { self.error = error.localizedDescription }
    }
}
struct GuideBlockedAuthorsView: View {
    @Environment(GuideLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List { ForEach(Array(library.blockedAuthors).sorted(), id: \.self) { id in HStack { Text("Blocked author"); Spacer(); Button("Unblock") { Task { do { if api.isSignedIn { try await api.blockGuideAuthor(id, blocked: false) }; _ = library.block(id, blocked: false) } catch { self.error = error.localizedDescription } } } } }; if let error { Text(error).foregroundStyle(.red) } }
                .navigationTitle("Blocked authors").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
