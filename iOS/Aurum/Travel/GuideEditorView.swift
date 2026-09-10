import SwiftUI
import PhotosUI

struct GuideStartView: View {
    var trip: JourneyDocument? = nil
    @Environment(JourneyLibrary.self) private var trips
    @Environment(GuideLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var destination = ""
    @State private var title = ""
    @State private var choosingTrip = false
    @State private var created: TravelGuide?
    var body: some View {
        NavigationStack {
            Group {
                if let created { GuideEditorView(initial: created, onDone: { dismiss() }) }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            GuideEyebrow(text: "YOUR PERSPECTIVE")
                            Text("A place, through your eyes.").font(.system(size: 36, weight: .regular, design: .serif))
                            Text("Share the places you’d send a friend.").font(.subheadline).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 20) {
                                Text("Where is your guide for?").font(.headline)
                                LocationAutocompleteField("City, region or country", text: $destination, kind: .destination, identifier: "guide-destination")
                                    .padding(16).background(Color.cardSurface, in: .rect(cornerRadius: 16))
                                TextField("Guide title (optional)", text: $title).accessibilityIdentifier("guide-start-title")
                                    .padding(16).background(Color.cardSurface, in: .rect(cornerRadius: 16))
                            }
                            Button { begin(TravelGuide(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My guide to " + destination : title, destination: destination)) } label: {
                                HStack { Text("Start writing"); Spacer(); Image(systemName: "arrow.right") }.font(.headline).padding(18).frame(maxWidth: .infinity)
                            }.buttonStyle(.glassProminent).disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("guide-start-writing")
                            if !trips.trips.isEmpty {
                                Button { choosingTrip = true } label: { Label("Start from one of your trips", systemImage: "suitcase").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 12) }.buttonStyle(.plain)
                            }
                            Text("Private while you write. Publish when you’re ready.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                            if let error = library.error { Text(error).font(.caption).foregroundStyle(.red) }
                        }.padding(26)
                    }.background(Color.canvas).navigationTitle("Create a guide").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                }
            }.onAppear { if let trip, created == nil { begin(.fromTrip(trip)) } }
                .sheet(isPresented: $choosingTrip) {
                    NavigationStack {
                        List(trips.trips) { trip in Button { choosingTrip = false; begin(.fromTrip(trip)) } label: { VStack(alignment: .leading, spacing: 5) { Text(trip.title).foregroundStyle(.primary); Text(trip.routeLabel).font(.caption).foregroundStyle(.secondary) } } }
                            .navigationTitle("Choose a trip").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosingTrip = false } } }
                            .safeAreaInset(edge: .bottom) { Text("Only recommended places are copied. Add your own guide notes next.").font(.caption).foregroundStyle(.secondary).padding() }
                    }
                }
        }
    }
    private func begin(_ value: TravelGuide) { if library.save(value) { created = value } }
}

struct GuideEditorView: View {
    let initial: TravelGuide
    var onDone: (() -> Void)? = nil
    @Environment(GuideLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var guide: TravelGuide
    @State private var section: GuideSection?
    @State private var photo: PhotosPickerItem?
    @State private var preview = false
    @State private var saveTask: Task<Void, Never>?
    @State private var photoError: String?
    init(initial: TravelGuide, onDone: (() -> Void)? = nil) { self.initial = initial; self.onDone = onDone; _guide = State(initialValue: initial) }
    private var draft: GuideDraft? { library.drafts.first { $0.id == guide.id } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { GuideEyebrow(text: "YOUR GUIDE"); Spacer(); Label(draft?.status ?? "Private draft", systemImage: draft?.isPublished == true ? "globe" : "lock").font(.caption).foregroundStyle(.secondary) }
                TextField("Name your guide", text: $guide.title, axis: .vertical).font(.system(.largeTitle, design: .serif)).accessibilityIdentifier("guide-title")
                LocationAutocompleteField("Destination", text: $guide.destination, kind: .destination, identifier: "guide-edit-destination").font(.subheadline).foregroundStyle(Color.bronze)
                PhotosPicker(selection: $photo, matching: .images) {
                    if let data = guide.coverJPEG, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 165).clipped().overlay(alignment: .bottomTrailing) { Label("Change cover", systemImage: "photo").font(.caption.weight(.semibold)).padding(10).background(.ultraThinMaterial, in: .capsule).padding(12) }
                    } else {
                        VStack(spacing: 10) { Image(systemName: "photo.badge.plus").font(.system(size: 28, weight: .ultraLight)); Text("Add a cover photo").font(.subheadline.weight(.medium)); Text("Optional · make it personal").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).frame(height: 145).background(Color.bronze.opacity(0.06))
                    }
                }.buttonStyle(.plain).clipShape(.rect(cornerRadius: 22)).accessibilityIdentifier("guide-cover")
                if guide.coverJPEG != nil { Button("Remove cover", role: .destructive) { guide.coverJPEG = nil; guide.thumbnailJPEG = nil }.font(.caption) }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set the scene").font(.headline)
                    TextField("What makes this place special to you?", text: $guide.introduction, axis: .vertical).lineLimit(3...8).font(.subheadline).padding(16).background(Color.cardSurface, in: .rect(cornerRadius: 16)).accessibilityIdentifier("guide-introduction")
                }
                DisclosureGroup("Themes · \(guide.tags.count)/3") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], alignment: .leading, spacing: 10) {
                        ForEach(TravelGuide.themes, id: \.self) { tag in Button { if guide.tags.contains(tag) { guide.tags.removeAll { $0 == tag } } else if guide.tags.count < 3 { guide.tags.append(tag) } } label: {
                            Text(tag).font(.caption).frame(maxWidth: .infinity).padding(10).background(guide.tags.contains(tag) ? Color.bronze.opacity(0.16) : Color.cardSurface, in: .capsule)
                        }.buttonStyle(.plain).accessibilityAddTraits(guide.tags.contains(tag) ? .isSelected : []) }
                    }.padding(.top, 12)
                }.font(.subheadline).tint(.bronze)
                Divider()
                HStack { Text("Chapters").font(.system(.title2, design: .serif)); Spacer(); Text(guide.places.count == 1 ? "1 place" : "\(guide.places.count) places").font(.caption).foregroundStyle(.secondary) }
                if guide.sections.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Start with your favorite places.").font(.headline)
                        Text("Group them by neighborhood, day, or theme—whatever tells your story best.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.cardSurface, in: .rect(cornerRadius: 20))
                }
                ForEach(Array(guide.sections.enumerated()), id: \.element.id) { index, value in
                    HStack(spacing: 14) {
                        Text(String(format: "%02d", index + 1)).font(.system(.title2, design: .serif)).foregroundStyle(Color.bronze)
                        Button { section = value } label: {
                            VStack(alignment: .leading, spacing: 5) { Text(value.title).font(.headline).foregroundStyle(.primary); Text((value.places.count == 1 ? "1 place" : "\(value.places.count) places") + (value.note.isEmpty ? "" : " · Notes")).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Menu {
                            Button("Edit chapter", systemImage: "pencil") { section = value }
                            Button("Move up", systemImage: "arrow.up") { guide.sections.swapAt(index, index - 1) }.disabled(index == 0)
                            Button("Move down", systemImage: "arrow.down") { guide.sections.swapAt(index, index + 1) }.disabled(index == guide.sections.count - 1)
                            Button("Delete chapter", role: .destructive) { guide.sections.removeAll { $0.id == value.id } }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Chapter options for " + value.title)
                    }.padding(16).background(Color.cardSurface, in: .rect(cornerRadius: 18))
                }
                Button { section = GuideSection() } label: { Label("Add a chapter", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(16) }.buttonStyle(.glass).disabled(guide.sections.count >= 20).accessibilityIdentifier("guide-add-section")
                if let error = photoError ?? library.error { Text(error).foregroundStyle(.red).font(.caption); Button("Save again") { _ = library.save(guide) } }
            }.padding(24)
        }.background(Color.canvas).scrollDismissesKeyboard(.interactively).navigationTitle("Write your guide").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if library.save(guide) { if let onDone { onDone() } else { dismiss() } } }.accessibilityIdentifier("guide-editor-done") } }
            .safeAreaInset(edge: .bottom) {
                Button { if library.save(guide) { preview = true } } label: { HStack { Text("Preview & publish"); Spacer(); Image(systemName: "arrow.right") }.font(.headline).padding(17).frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).padding(.horizontal, 24).padding(.bottom, 8).accessibilityIdentifier("guide-preview")
            }
            .sheet(item: $section) { value in GuideSectionEditor(section: value, destination: guide.destination) { changed in if let i = guide.sections.firstIndex(where: { $0.id == changed.id }) { guide.sections[i] = changed } else { guide.sections.append(changed) } } }
            .navigationDestination(isPresented: $preview) { GuidePublishView(id: guide.id).onDisappear { if let current = library.drafts.first(where: { $0.id == guide.id }) { guide = current.guide } } }
            .onChange(of: library.drafts.contains(where: { $0.id == guide.id })) { if !library.drafts.contains(where: { $0.id == guide.id }) { saveTask?.cancel(); if let onDone { onDone() } else { dismiss() } } }
            .onChange(of: guide) { saveTask?.cancel(); let value = guide; saveTask = Task { do { try await Task.sleep(for: .milliseconds(350)) } catch { return }; _ = library.save(value) } }
            .onDisappear { saveTask?.cancel(); if library.drafts.contains(where: { $0.id == guide.id }) { _ = library.save(guide) } }
            .task(id: photo) {
                guard let photo else { return }
                do { let data = try await GuidePhotoData.read(photo); guide.coverJPEG = data.full; guide.thumbnailJPEG = data.thumbnail; photoError = nil } catch { photoError = error.localizedDescription }
            }
    }
}

struct GuideSectionEditor: View {
    @State var section: GuideSection
    let destination: String
    var onSave: (GuideSection) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var item: GuidePlace?
    @State private var savedPlaces = false
    @Environment(TravelStore.self) private var store
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Chapter title", text: $section.title).font(.title3.weight(.medium)).accessibilityIdentifier("guide-section-title")
                    TextField("A little context or practical advice (optional)", text: $section.note, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("guide-section-note")
                } header: { Text("The story") } footer: { Text("Try “A perfect first day”, “Where to eat”, or a neighborhood name.") }
                Section {
                    ForEach(section.places) { value in Button { item = value } label: { HStack { Image(systemName: value.place.category.symbol).foregroundStyle(Color.bronze); VStack(alignment: .leading, spacing: 5) { Text(value.place.name).foregroundStyle(.primary); if !value.note.isEmpty { Text(value.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) } } }
                        .onDelete { section.places.remove(atOffsets: $0) }.onMove { section.places.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add a place", systemImage: "plus") { item = GuidePlace(place: PlaceRecord(category: .attraction, city: destination)) }.accessibilityIdentifier("guide-add-place").disabled(section.places.count >= 50)
                    if !store.wishlistEntries.isEmpty { Button("Choose from Wishlist", systemImage: "bookmark") { savedPlaces = true }.disabled(section.places.count >= 50) }
                } header: { HStack { Text("Your recommendations"); Spacer(); EditButton().font(.caption) } }
            }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle(section.title.isEmpty ? "New chapter" : "Edit chapter").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(section); dismiss() }.disabled(section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("guide-section-save") }
                }
                .sheet(item: $item) { value in GuidePlaceEditor(item: value) { value in if let i = section.places.firstIndex(where: { $0.id == value.id }) { section.places[i] = value } else { section.places.append(value) } } }
                .sheet(isPresented: $savedPlaces) {
                    NavigationStack { List(store.wishlistEntries) { entry in Button { section.places.append(GuidePlace(place: entry.place.guideLocation)); savedPlaces = false } label: { Label(entry.place.name, systemImage: entry.place.category.symbol) } }.navigationTitle("From your Wishlist").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { savedPlaces = false } } } }
                }
        }
    }
}
struct GuidePlaceEditor: View {
    @State var item: GuidePlace
    var onSave: (GuidePlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("The place") {
                    LocationAutocompleteField("Search or enter a place", text: $item.place.name, kind: .place, identifier: "guide-place-name", category: item.place.category, searchContext: item.place.city, onEdit: { item.place.latitude = nil; item.place.longitude = nil }) { value in item.place = value.place.guideLocation }
                    Picker("Category", selection: $item.place.category) { ForEach(PlaceCategory.allCases) { Text($0.title).tag($0) } }
                    TextField("City", text: $item.place.city)
                    TextField("Address (optional)", text: $item.place.address)
                }
                Section("Why you recommend it") { TextField("Your experience, what to order, or when to go…", text: $item.note, axis: .vertical).lineLimit(4...12).accessibilityIdentifier("guide-place-note") }
                Section {
                    if let data = item.photoJPEG, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 170); Button("Remove photo", role: .destructive) { item.photoJPEG = nil } }
                    PhotosPicker(selection: $photo, matching: .images) { Label(item.photoJPEG == nil ? "Add your photo" : "Change photo", systemImage: "photo") }
                    TextField("Website (optional)", text: $item.place.website).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Recommendation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { guard item.place.website.isEmpty || validatedURL(item.place.website) != nil else { error = "Use a full website link."; return }; item.place = item.place.guideLocation; onSave(item); dismiss() }.disabled(item.place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("guide-place-save") } }
                .task(id: photo) { guard let photo else { return }; do { item.photoJPEG = try await GuidePhotoData.read(photo, maximum: 650_000).full } catch { self.error = error.localizedDescription } }
        }
    }
}
enum GuidePhotoData {
    @MainActor static func read(_ item: PhotosPickerItem, maximum: Int = 1_000_000) async throws -> (full: Data, thumbnail: Data) {
        guard let data = try await item.loadTransferable(type: Data.self), data.count < 30_000_000, let image = UIImage(data: data) else { throw JourneyError.message("Choose a photo smaller than 30 MB.") }
        func jpeg(width: CGFloat, quality: CGFloat) -> Data? {
            let scale = min(1, width / max(image.size.width, image.size.height)), size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: quality)
        }
        guard let full = jpeg(width: 1400, quality: 0.72), full.count <= maximum, let thumbnail = jpeg(width: 360, quality: 0.55), thumbnail.count <= 70_000 else { throw JourneyError.message("Choose a smaller photo.") }
        return (full, thumbnail) // Re-rendering strips location/EXIF metadata.
    }
}
struct GuideEyebrow: View { let text: String; var body: some View { Text(text).font(.system(size: 10, weight: .semibold)).tracking(2.5).foregroundStyle(Color.bronze) } }
