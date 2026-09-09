import SwiftUI
import MapKit

private extension RoutePoint {
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

enum RecapMapGeometry {
    /// Fit the smallest longitude arc so a Pacific route does not zoom out to Europe.
    static func region(_ points: [RoutePoint]) -> MKCoordinateRegion {
        guard !points.isEmpty else { return .init(center: .init(latitude: 25, longitude: 0), span: .init(latitudeDelta: 100, longitudeDelta: 180)) }
        let lons = points.map { ($0.longitude + 360).truncatingRemainder(dividingBy: 360) }.sorted()
        var largest = -1.0, start = lons[0]
        for i in lons.indices {
            let next = i + 1 < lons.count ? lons[i+1] : lons[0] + 360
            if next - lons[i] > largest { largest = next - lons[i]; start = next.truncatingRemainder(dividingBy: 360) }
        }
        let width = 360 - largest, middle = (start + width / 2 + 180).truncatingRemainder(dividingBy: 360) - 180
        let low = points.map(\.latitude).min()!, high = points.map(\.latitude).max()!
        return .init(center: .init(latitude: (low + high) / 2, longitude: middle), span: .init(latitudeDelta: min(160, max(1, (high-low)*1.4)), longitudeDelta: min(350, max(1.8, width*1.4))))
    }
    static func polyline(_ leg: TripRecap.Leg) -> MKPolyline {
        let coordinates = [leg.from.coordinate, leg.to.coordinate]
        return leg.flight ? MKGeodesicPolyline(coordinates: coordinates, count: 2) : MKPolyline(coordinates: coordinates, count: 2)
    }
}

struct RecapMapView: View {
    let recap: TripRecap
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera: MapCameraPosition = .automatic
    @State private var step: Int?
    @State private var playing = false
    var body: some View {
        VStack(spacing: 12) {
            Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {
                ForEach(recap.legs.filter { step == nil || $0.step <= step! }) { leg in
                    MapPolyline(RecapMapGeometry.polyline(leg)).stroke(leg.flight ? Color.teal : Color.bronze, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: leg.flight ? [7, 4] : []))
                }
                ForEach(Array(recap.stops.enumerated()), id: \.element.id) { index, stop in
                    Annotation(stop.name, coordinate: stop.coordinate) {
                        Text("\(index+1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 28, height: 28)
                            .background(step == index ? Color.teal : Color.bronze, in: Circle())
                            .accessibilityLabel("Stop \(index+1), \(stop.name)")
                    }
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .frame(height: 250).clipShape(.rect(cornerRadius: 22))
            .overlay(alignment: .topLeading) {
                if recap.mapPoints.isEmpty { Text("Add destination locations to see your route").font(.caption).padding(12).background(.regularMaterial, in: .rect(cornerRadius: 12)).padding(12) }
            }
            HStack {
                Text(step.flatMap { recap.stops.indices.contains($0) ? recap.stops[$0].name : nil } ?? "Your route, remembered")
                    .font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer()
                if !reduceMotion && !recap.stops.isEmpty {
                    Button(playing ? "Stop" : "Replay", systemImage: playing ? "stop.fill" : "play.fill") {
                        playing.toggle()
                        if !playing { step = nil; camera = .region(RecapMapGeometry.region(recap.mapPoints)) }
                    }.font(.caption.weight(.semibold)).accessibilityIdentifier("recap-replay")
                }
            }
            if !recap.legs.isEmpty { Text("Gold · city route    Teal · booked flights").font(.caption2).foregroundStyle(.secondary) }
        }
        .onAppear { camera = .region(RecapMapGeometry.region(recap.mapPoints)) }
        .onDisappear { playing = false }
        .onChange(of: reduceMotion) { _, _ in playing = false; step = nil; camera = .region(RecapMapGeometry.region(recap.mapPoints)) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playing = false; step = nil } }
        .task(id: playing) {
            guard playing && !reduceMotion else { return }
            do {
                for i in recap.stops.indices {
                    try Task.checkCancellation()
                    withAnimation(.smooth(duration: 1.1)) {
                        step = i
                        camera = .camera(.init(centerCoordinate: recap.stops[i].coordinate, distance: 900_000, heading: 0, pitch: 30))
                    }
                    try await Task.sleep(for: .seconds(2))
                }
                try Task.checkCancellation()
                withAnimation(.smooth(duration: 1)) { step = nil; camera = .region(RecapMapGeometry.region(recap.mapPoints)) }
                playing = false
            } catch { }
        }
    }
}

struct TripRecapView: View {
    let document: JourneyDocument
    var showsMap = true
    let logVisit: () -> Void
    @State private var sharing = false
    private var recap: TripRecap { .init(document: document) }
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: recap.hasEnded() ? "A trip to remember" : "Your story so far")
                    Text(recap.hasEnded() ? "The places. The moments." : "A recap that grows as you go.").font(.title2.weight(.semibold))
                }
                Spacer()
                Button { sharing = true } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }
                    .buttonStyle(.glass).accessibilityLabel("Share recap").accessibilityIdentifier("recap-share")
            }
            if showsMap { RecapMapView(recap: recap) }
            RecapMetrics(recap: recap)
            HStack { Text("Day by day").font(.title2.weight(.semibold)); Spacer(); Button("Log a visit", systemImage: "plus", action: logVisit).font(.caption.weight(.semibold)) }
            if recap.days.isEmpty { Text("Log a visit in Journal to start your story. Dates and destinations from your plan will appear here automatically.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(recap.days) { day in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(day.label).font(.headline)
                        Spacer()
                        Text(day.cities.joined(separator: " → ")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                    ForEach(day.stays) { stay in
                        HStack(spacing: 12) {
                            Image(systemName: "bed.double.fill").foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Stayed at " + stay.place.name).font(.subheadline.weight(.medium))
                                Text(TravelDay.label(stay.checkIn) + " – " + TravelDay.label(stay.checkOut)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let score = recap.rating(for: stay) { scoreLabel(score) }
                        }
                    }
                    ForEach(day.places) { place in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Image(systemName: place.place.category.symbol).foregroundStyle(Color.bronze).frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(place.place.name).font(.subheadline.weight(.medium))
                                    Text(place.place.category.title + ((place.michelinStars ?? 0) > 0 && place.place.category == .restaurant ? " · \(place.michelinStars!) Michelin stars" : "")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if place.overall > 0 { scoreLabel(place.overall) }
                            }
                            if !place.photos.isEmpty {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 8) { ForEach(place.photos) { photo in
                                        if let ui = UIImage(data: photo.jpeg) { Image(uiImage: ui).resizable().scaledToFill().frame(width: 150, height: 180).clipped().clipShape(.rect(cornerRadius: 12)).accessibilityLabel("Photo from " + place.place.name) }
                                    } }
                                }.scrollIndicators(.hidden)
                            }
                        }
                    }
                    if day.places.isEmpty && day.stays.isEmpty { Text("A little room for memories. Add yours in Journal.").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 5)
                Divider()
            }
        }.sheet(isPresented: $sharing) { RecapShareView(document: document) }
        .accessibilityElement(children: .contain).accessibilityIdentifier("trip-recap")
    }
    private func scoreLabel(_ score: Double) -> some View {
        Text(score.formatted(.number.precision(.fractionLength(1))) + "/10").font(.caption.weight(.semibold)).foregroundStyle(.teal)
    }
}

struct RecapMetrics: View {
    let recap: TripRecap
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 20) {
            metric("\(recap.document.nights)", "Nights")
            metric("\(recap.document.stops.count)", "City stops")
            metric(recap.flightMiles.formatted(), "Flight miles¹")
            metric("\(recap.ratedCount)", "Places rated")
            metric("\(recap.stars)", "Michelin stars")
            metric(recap.document.averageScore.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", "Average / 10")
        }.padding(.vertical, 8)
        Text("¹ Great-circle distance for flights with known airport locations.").font(.caption2).foregroundStyle(.secondary)
    }
    private func metric(_ number: String, _ label: String) -> some View {
        VStack(spacing: 5) { Text(number).font(.system(.title2, design: .serif)).foregroundStyle(Color.bronze); Text(label).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }
}

struct RecapShareRequest: Encodable { var document: JourneyDocument; var selectedPhotoIDs: [String]; var mapJPEG: Data? }

struct RecapShareView: View {
    let document: JourneyDocument
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID>
    @State private var busy = false
    @State private var error: String?
    @State private var message: String?
    @State private var export: ExportedJourney?
    @State private var shareLink: String?
    @State private var revoke = false
    init(document: JourneyDocument) { self.document = document; _selected = State(initialValue: Set(document.places.flatMap(\.photos).map(\.id))) }
    private var photos: [JournalPhoto] { document.places.flatMap(\.photos) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Choose what you share").font(.title2.weight(.semibold))
                    Text("Your route, stays and ratings. No booking details or private notes. Your trip stays \(document.visibility.title.lowercased()); anyone with this separate recap link can view the snapshot you publish.").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Text("\(selected.count) photos selected").font(.headline)
                        Spacer()
                        Button(selected.isEmpty ? "Select all" : "Deselect all") { selected = selected.isEmpty ? Set(photos.map(\.id)) : []; shareLink = nil }.font(.caption)
                    }
                    if photos.count > 60 { Text("Choose up to 60 photos for a link. Images use your first three selected photos.").font(.caption).foregroundStyle(.secondary) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 85))], spacing: 8) {
                        ForEach(photos) { photo in
                            if let ui = UIImage(data: photo.jpeg) {
                                Button {
                                    if selected.contains(photo.id) { selected.remove(photo.id) } else { selected.insert(photo.id) }
                                    shareLink = nil
                                } label: {
                                    Image(uiImage: ui).resizable().scaledToFill().frame(height: 100).clipped()
                                        .overlay(alignment: .topTrailing) { Image(systemName: selected.contains(photo.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.white, Color.bronze).padding(6).shadow(radius: 2) }
                                        .clipShape(.rect(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityLabel("Include photo \(photos.firstIndex(where: { $0.id == photo.id })! + 1)").accessibilityAddTraits(selected.contains(photo.id) ? .isSelected : [])
                            }
                        }
                    }
                    if !api.isSignedIn { Text("Sign in through your profile to publish a link. You can save an image without an account.").font(.caption).foregroundStyle(.secondary) }
                    Button { createLink() } label: { Label("Create recap link", systemImage: "link").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).disabled(busy || !api.isSignedIn || selected.count > 60)
                    if let shareLink, let url = URL(string: shareLink) { ShareLink(item: url) { Label("Share this link", systemImage: "square.and.arrow.up") } }
                    Button { createImage() } label: { Label("Share vertical image", systemImage: "photo").frame(maxWidth: .infinity) }.buttonStyle(.glass).disabled(busy)
                    if busy { ProgressView("Preparing your recap…") }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    if api.isSignedIn { Button("Revoke all recap links for this trip", role: .destructive) { revoke = true }.font(.caption).disabled(busy) }
                }.padding(22)
            }.background(Color.canvas).navigationTitle("Share recap").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
                .sheet(item: $export) { ActivityShareSheet(items: [$0.url]) }
                .confirmationDialog("Revoke this trip’s recap links?", isPresented: $revoke, titleVisibility: .visible) {
                    Button("Revoke links", role: .destructive) {
                        busy = true
                        Task { defer { busy = false }; do { try await api.revokeRecaps(document.id); shareLink = nil; message = "Recap links revoked." } catch { self.error = error.localizedDescription } }
                    }
                }
        }
    }
    private func createLink() {
        busy = true; error = nil; message = nil
        Task { defer { busy = false }
            do {
                let map = try await RecapArtwork.map(TripRecap(document: document))
                var safe = TripRecap(document: document).shareDocument(photoIDs: selected)
                for i in safe.places.indices { for j in safe.places[i].photos.indices {
                    safe.places[i].photos[j].jpeg = try RecapArtwork.compressed(safe.places[i].photos[j].jpeg)
                } }
                let link = try await api.recapLink(.init(document: safe, selectedPhotoIDs: selected.map { $0.uuidString }, mapJPEG: map?.jpegData(compressionQuality: 0.7)))
                shareLink = link.url; message = "Your recap link is ready. Later journal edits won’t change this snapshot."
            } catch { self.error = error.localizedDescription }
        }
    }
    private func createImage() {
        busy = true; error = nil
        Task { defer { busy = false }
            do {
                let recap = TripRecap(document: document), map = try await RecapArtwork.map(recap)
                let images = photos.filter { selected.contains($0.id) }.prefix(3).compactMap { UIImage(data: $0.jpeg) }
                let renderer = ImageRenderer(content: RecapPoster(recap: recap, map: map, photos: images).frame(width: 360, height: 640).environment(\.colorScheme, .light))
                renderer.scale = 3
                guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.95) else { throw JourneyError.message("The recap image could not be created.") }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Seur-recap-\(UUID().uuidString).jpg")
                try data.write(to: url, options: [.atomic, .completeFileProtection]); export = .init(url: url)
            } catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor enum RecapArtwork {
    static func compressed(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else { throw JourneyError.message("One of your journal photos could not be read.") }
        let scale = min(1, 800 / max(image.size.width, image.size.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let resized = UIGraphicsImageRenderer(size: .init(width: image.size.width * scale, height: image.size.height * scale), format: format).image { _ in image.draw(in: .init(origin: .zero, size: .init(width: image.size.width * scale, height: image.size.height * scale))) }
        guard let result = resized.jpegData(compressionQuality: 0.65), result.count <= 600_000 else { throw JourneyError.message("A photo is too large to share. Try a different photo.") }
        return result
    }
    static func map(_ recap: TripRecap) async throws -> UIImage? {
        guard !recap.mapPoints.isEmpty else { return nil }
        let options = MKMapSnapshotter.Options()
        options.region = RecapMapGeometry.region(recap.mapPoints); options.size = .init(width: 900, height: 550); options.scale = 1
        options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot
        do { snapshot = try await snapshotter.start() }
        catch { throw JourneyError.message("The route image needs a map connection. Your recap still works offline; try sharing again when you’re online.") }
        return UIGraphicsImageRenderer(size: options.size).image { ctx in
            snapshot.image.draw(at: .zero)
            ctx.cgContext.saveGState(); ctx.cgContext.clip(to: CGRect(origin: .zero, size: options.size))
            for leg in recap.legs {
                let polyline = RecapMapGeometry.polyline(leg)
                var coordinates = Array(repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
                polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
                let path = UIBezierPath(); var previous: CGPoint?
                for coordinate in coordinates {
                    let point = snapshot.point(for: coordinate)
                    if let p = previous, abs(point.x - p.x) < options.size.width * 0.7 { path.addLine(to: point) } else { path.move(to: point) }
                    previous = point
                }
                (leg.flight ? UIColor.systemTeal : UIColor.brown).setStroke(); path.lineWidth = 4; path.stroke()
            }
            for (i, stop) in recap.stops.enumerated() {
                let p = snapshot.point(for: stop.coordinate), r = CGRect(x: p.x-13, y: p.y-13, width: 26, height: 26)
                UIColor.brown.setFill(); UIBezierPath(ovalIn: r).fill()
                let text = "\(i+1)" as NSString, attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.white]
                let size = text.size(withAttributes: attributes)
                text.draw(at: .init(x: p.x-size.width/2, y: p.y-size.height/2), withAttributes: attributes)
            }
            ctx.cgContext.restoreGState()
            // Keep a legible attribution even when overlay strokes cross the map footer.
            let text = " Maps" as NSString, attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: UIColor.label, .backgroundColor: UIColor.white.withAlphaComponent(0.9)]
            text.draw(at: .init(x: 12, y: options.size.height - 25), withAttributes: attrs)
        }
    }
}

struct RecapPoster: View {
    let recap: TripRecap
    let map: UIImage?
    let photos: [UIImage]
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("S E U R  /  TRIP RECAP").font(.system(size: 10, weight: .semibold)).foregroundStyle(.brown)
            Text(recap.document.title).font(.system(size: 30, weight: .medium, design: .serif)).lineLimit(2).minimumScaleFactor(0.7)
            Text(recap.document.routeLabel).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            if let map { Image(uiImage: map).resizable().scaledToFit().clipShape(.rect(cornerRadius: 14)) }
            HStack {
                number("\(recap.document.nights)", "NIGHTS")
                Spacer(); number("\(recap.document.stops.count)", "CITY STOPS")
                Spacer(); number("\(recap.ratedCount)", "PLACES RATED")
            }
            if !photos.isEmpty {
                HStack(spacing: 7) { ForEach(photos.indices, id: \.self) { i in Image(uiImage: photos[i]).resizable().scaledToFill().frame(width: photos.count == 1 ? 316 : photos.count == 2 ? 154 : 100, height: 120).clipped().clipShape(.rect(cornerRadius: 10)) } }
            }
            Spacer(minLength: 0)
            Text("The places stay with you.").font(.system(size: 13, design: .serif)).foregroundStyle(.brown)
        }.padding(22).frame(width: 360, height: 640).background(Color(red: 0.97, green: 0.96, blue: 0.93)).foregroundStyle(.black)
    }
    private func number(_ value: String, _ label: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.system(size: 25, design: .serif)); Text(label).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary) } }
}
