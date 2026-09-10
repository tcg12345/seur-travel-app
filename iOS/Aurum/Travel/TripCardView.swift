import SwiftUI

struct CityPhotoResponse: Decodable {
    var photo: CityPhoto?
}
struct CityPhoto: Codable {
    struct Author: Codable {
        var name: String
        var url: URL?
        var avatarURL: URL?
    }
    var provider: String? = nil
    var isGoogle: Bool { provider == "google" }
    var isPexels: Bool { provider == "pexels" }
    var imageURL: URL
    var sourceURL: URL?
    var authors: [Author]
    var license: String
    var licenseURL: URL?
    var title: String
    var attribution: String
}

/// Original downloaded bytes and credits live in Application Support, not an evictable cache.
struct SavedTripCover: Codable {
    var photo: CityPhoto
    var data: Data
}

@MainActor final class TripCoverStore {
    static let shared = TripCoverStore()
    private let directory: URL
    private var pending: [UUID: Task<SavedTripCover?, Never>] = [:]
    private var decoded: [UUID: (image: UIImage, photo: CityPhoto)] = [:]
    private var inspected = Set<UUID>()
    /// Resolve retained covers before the first frame, without an asynchronous loading placeholder.
    func cached(for id: UUID) -> (image: UIImage, photo: CityPhoto)? {
        if let value = decoded[id] { return value }
        guard inspected.insert(id).inserted else { return nil }
        let file = directory.appendingPathComponent(id.uuidString + ".json")
        guard let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(SavedTripCover.self, from: data), saved.photo.isPexels, CityPhotoImage.allowed(saved.photo.imageURL), let image = UIImage(data: saved.data) else { return nil }
        let value = (image: image, photo: saved.photo); decoded[id] = value; return value
    }
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AurumTravel/PexelsDaytimeTripCovers-v1", isDirectory: true)
    }
    /// Claim on disk BEFORE requesting. Failed, cancelled and interrupted attempts never retry.
    /// The key deliberately excludes the city, server, layout and dates.
    func cover(for tripID: UUID, allowLookup: Bool = true, fetch: @escaping () async throws -> SavedTripCover?) async -> SavedTripCover? {
        if let task = pending[tripID] { return await task.value }
        let claim = directory.appendingPathComponent(tripID.uuidString + ".attempted")
        let file = directory.appendingPathComponent(tripID.uuidString + ".json")
        if FileManager.default.fileExists(atPath: claim.path) {
            return (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(SavedTripCover.self, from: $0) }
        }
        guard allowLookup else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Exclusive creation also prevents a second store instance from making another request.
            try Data([1]).write(to: claim, options: [.withoutOverwriting, .completeFileProtectionUnlessOpen])
        } catch { return nil } // Cannot prove the claim was saved: do not spend a request.
        let task = Task { () -> SavedTripCover? in
            guard let cover = try? await fetch(), cover.photo.isPexels, CityPhotoImage.allowed(cover.photo.imageURL), UIImage(data: cover.data) != nil else { return nil }
            // Preserve the claim even when the image cannot be saved, rather than refetching later.
            guard let encoded = try? JSONEncoder().encode(cover),
                  (try? encoded.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])) != nil else { return nil }
            if let image = UIImage(data: cover.data) { self.decoded[tripID] = (image, cover.photo) }
            return cover
        }
        pending[tripID] = task
        defer { pending[tripID] = nil }
        return await task.value
    }
}

enum CityPhotoImage {
    static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.port == nil &&
        ["images.pexels.com"].contains(url.host ?? "")
    }
    static func load(_ url: URL) async throws -> Data {
        guard allowed(url) else { throw URLError(.badURL) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let finalURL = response.url, allowed(finalURL),
              data.count <= 4_000_000, UIImage(data: data) != nil else { throw URLError(.cannotDecodeContentData) }
        return data
    }
}

/// The user's Tokyo photograph is an intentional exception to daytime Pexels covers.
enum SuppliedTokyoCover {
    static func matches(_ city: String) -> Bool {
        let parts = city.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let name = parts.first, ["tokyo", "tokyo prefecture", "tokyo metropolis", "東京都", "東京"].contains(name) else { return false }
        return parts.count == 1 || ["japan", "jp", "日本"].contains(parts.last!)
    }
    static let cover: (image: UIImage, photo: CityPhoto)? = {
        guard let image = UIImage(named: "TripCoverTokyo") else { return nil }
        return (image, CityPhoto(provider: "supplied", imageURL: URL(string: "seur://trip-cover/tokyo")!,
            sourceURL: nil, authors: [], license: "", licenseURL: nil,
            title: "Tokyo skyline", attribution: "Supplied photo"))
    }()
}

/// Supplied catalog assets take priority; missing/invalid images permit the Pexels fallback.
enum BundledDestinationCover {
    private struct Entry: Decodable {
        var asset: String; var cities: [String]; var countries: [String]; var regions: [String]; var photo: CityPhoto
    }
    private static let catalog: [Entry] = {
        guard let data = NSDataAsset(name: "DestinationCoverCatalog")?.data else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }()
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    private static let byName: [String: [Entry]] = {
        var result: [String: [Entry]] = [:]
        for entry in catalog {
            for name in Set(entry.cities.map(normalized)) { result[name, default: []].append(entry) }
        }
        return result
    }()
    static var destinations: [String] { catalog.compactMap { $0.cities.first } }
    static func cover(city: String) -> (image: UIImage, photo: CityPhoto)? {
        // Preserve the separately requested Tokyo Tower/Mount Fuji photograph.
        if SuppliedTokyoCover.matches(city), let cover = SuppliedTokyoCover.cover { return cover }
        let parts = city.split(separator: ",").map(String.init)
        for count in stride(from: parts.count, through: 1, by: -1) {
            guard let entries = byName[normalized(parts.prefix(count).joined(separator: ","))] else { continue }
            let suffix = parts.dropFirst(count).map(normalized)
            for entry in entries where suffix.isEmpty || entry.countries.map(normalized).contains(suffix.last!) ||
                (suffix.count == 1 && entry.regions.map(normalized).contains(suffix[0])) {
                if let image = UIImage(named: entry.asset) { return (image, entry.photo) }
            }
        }
        return nil
    }
}

struct JourneyCard: View {
    let document: JourneyDocument
    var compact = false
    @Environment(TravelAPI.self) private var api
    @State private var photo: CityPhoto?
    @State private var image: UIImage?
    @State private var loadedCity: String?
    @State private var showingPhoto = false
    @State private var isVisible = false
    private var city: String {
        let stop = document.stops.first
        let name = (stop?.name.isEmpty == false ? stop!.name : document.destination).trimmingCharacters(in: .whitespacesAndNewlines)
        if let country = stop?.country, !country.isEmpty, !name.localizedCaseInsensitiveContains(country) { return name + ", " + country }
        return name
    }
    private var displayedCover: (image: UIImage, photo: CityPhoto)? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--trip-card-testing") { return TripCardFixtures.cover }
        #endif
        if let cover = BundledDestinationCover.cover(city: city) { return cover }
        if loadedCity == city, let image, let photo { return (image, photo) }
        return TripCoverStore.shared.cached(for: document.id)
    }
    private var dates: String {
        guard let start = document.startDate else { return "Dates to come" }
        return TravelDay.label(start) + (document.endDate.map { " – " + TravelDay.label($0) } ?? "")
    }
    private var detail: String {
        var parts: [String] = []
        if document.planCount > 0 { parts.append("\(document.planCount) \(document.planCount == 1 ? "plan" : "plans")") }
        if !document.places.isEmpty { parts.append("\(document.places.count) \(document.places.count == 1 ? "memory" : "memories")") }
        return parts.isEmpty ? "Start planning" : parts.joined(separator: " · ")
    }
    var body: some View {
        VStack(spacing: 0) {
            NavigationLink { JourneyDetailView(id: document.id) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        GeometryReader { geometry in
                            Group {
                                if let cover = displayedCover {
                                    Image(uiImage: cover.image).resizable().scaledToFit()
                                }
                                else {
                                    ZStack {
                                        LinearGradient(colors: [Color(red: 0.24, green: 0.29, blue: 0.30), Color(red: 0.10, green: 0.13, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        Circle().stroke(.white.opacity(0.12), lineWidth: 1).frame(width: 240, height: 240).offset(x: 75, y: -20)
                                        Circle().stroke(.white.opacity(0.08), lineWidth: 1).frame(width: 180, height: 180).offset(x: 75, y: -20)
                                        Text(String(city.prefix(1)).uppercased()).font(.system(size: 150, weight: .regular, design: .serif)).foregroundStyle(.white.opacity(0.10)).offset(x: 65, y: -10)
                                    }
                                }
                            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top).clipped()
                        }.accessibilityHidden(true).allowsHitTesting(false)
                    }.aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .accessibilityIdentifier("trip-cover-image")
                        .overlay(alignment: .topLeading) {
                            if document.nights > 0 {
                                Text("\(document.nights) \(document.nights == 1 ? "night" : "nights")").font(.caption.weight(.medium)).foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 6).background(.black.opacity(0.38), in: .capsule).padding(14)
                            }
                        }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(document.title).font(.system(compact ? .headline : .title2, design: .serif))
                            .fontWeight(.medium).foregroundStyle(.primary)
                            .lineLimit(compact ? 3 : nil).fixedSize(horizontal: false, vertical: true)
                        if document.stops.count > 1 && !compact {
                            Text(document.routeLabel).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Text(dates).font(.subheadline.weight(.medium)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: document.visibility == .private ? "lock" : document.visibility == .friends ? "person.2" : "globe")
                                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 3).accessibilityLabel(document.visibility.title)
                        }
                        HStack {
                            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.bronze).accessibilityHidden(true)
                        }
                    }.padding(compact ? 15 : 18)
                }
            }.contentShape(Rectangle()).buttonStyle(.plain).accessibilityIdentifier("trip-card-" + document.id.uuidString)
            if let cover = displayedCover, let source = cover.photo.sourceURL {
                Link(destination: source) {
                    Text("Photo by \(cover.photo.authors.first?.name ?? "Photographer") · \(cover.photo.isPexels ? "Pexels" : "Wikimedia Commons")")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, compact ? 15 : 18).padding(.bottom, 14)
                }.accessibilityLabel(cover.photo.attribution)
            }
        }.background(Color.cardSurface).clipShape(.rect(cornerRadius: compact ? 22 : 26))
            .overlay { RoundedRectangle(cornerRadius: compact ? 22 : 26).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.75).allowsHitTesting(false) }
            .overlay(alignment: .topTrailing) {
                if displayedCover != nil {
                    Button { showingPhoto = true } label: {
                        Image(systemName: "info.circle").font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white).padding(8).background(.black.opacity(0.65), in: .circle)
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(10).accessibilityLabel(displayedCover?.photo.provider == "supplied" ? "Photo information" : "Photo credits, " + (displayedCover?.photo.isPexels == true ? "Pexels" : "Wikimedia Commons")).accessibilityIdentifier("trip-photo-credits")
                }
            }
            .onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }
            .task(id: document.id.uuidString + "|" + String(api.status?.pexelsCityPhotos == true) + "|" + String(isVisible)) {
                guard isVisible, city.count >= 2, BundledDestinationCover.cover(city: city) == nil, !PlaceSearchTestPolicy.blocksPaidRequests else { return }
                let requestedCity = city
                guard let result = await TripCoverStore.shared.cover(for: document.id,
                    allowLookup: api.status?.pexelsCityPhotos == true, fetch: {
                        guard let photo = try await api.pexelsCityPhoto(requestedCity).photo, photo.isPexels else { return nil }
                        return SavedTripCover(photo: photo, data: try await CityPhotoImage.load(photo.imageURL))
                    }) else { return }
                photo = result.photo; image = UIImage(data: result.data); loadedCity = requestedCity
            }
            .sheet(isPresented: $showingPhoto) {
                if let cover = displayedCover { TripPhotoCredits(photo: cover.photo, image: cover.image, city: city) }
            }
    }
}

private struct TripPhotoCredits: View {
    let photo: CityPhoto
    let image: UIImage
    let city: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Photo of " + city)
                    VStack(alignment: .leading, spacing: 16) {
                        Text(photo.title).font(.headline)
                        ForEach(Array(photo.authors.enumerated()), id: \.offset) { _, author in
                            HStack(spacing: 12) {
                                if let url = author.url { Link(author.name, destination: url) }
                                else { Text(author.name) }
                            }.font(.subheadline)
                        }
                        if !photo.attribution.isEmpty { Text(photo.attribution).font(.system(size: photo.isGoogle ? 14 : 12)).foregroundStyle(.primary) }
                        if let url = photo.licenseURL, !photo.license.isEmpty { Link(photo.license, destination: url).font(.subheadline) }
                        Text("Landscape cover prepared in 16:9 for Seur.").font(.caption).foregroundStyle(.secondary)
                        if let url = photo.sourceURL { Link(photo.isPexels ? "View photo on Pexels" : "View photo on Wikimedia Commons", destination: url).font(.subheadline) }
                    }.padding(.horizontal, 20)
                }.padding(.bottom, 24)
            }.background(Color.canvas).navigationTitle("Destination photo").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
#if DEBUG
enum TripCardFixtures {
    // Deterministic UI fixture; tests never spend photo-provider quota.
    static let cover: (image: UIImage, photo: CityPhoto) = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180)).image { context in
            UIColor(red: 0.28, green: 0.37, blue: 0.41, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        }
        return (image, CityPhoto(provider: "pexels", imageURL: URL(string: "https://images.pexels.com/test.jpeg")!,
            sourceURL: URL(string: "https://www.pexels.com"), authors: [.init(name: "Seur test fixture")],
            license: "Pexels License", licenseURL: URL(string: "https://www.pexels.com/license/"),
            title: "Test destination cover", attribution: "Photo by Seur test fixture on Pexels"))
    }()

    static var documents: [JourneyDocument] {
        var paris = JourneyDocument(title: "Trip to Paris, France", destination: "Paris, France", startDate: "2026-10-12", endDate: "2026-10-15")
        paris.stops = [.init(name: "Paris, France", arrival: "2026-10-12", nights: 3)]
        var athens = JourneyDocument(title: "An Athenian autumn", destination: "Athens, Greece", startDate: "2026-11-02", endDate: "2026-11-06")
        athens.stops = [.init(name: "Athens, Greece", arrival: "2026-11-02", nights: 4)]
        var newYork = JourneyDocument(title: "Trip to New York, NY, United States", destination: "New York, NY, United States", startDate: "2026-10-20", endDate: "2026-10-23")
        newYork.stops = [.init(name: "New York, NY, United States", country: "United States", arrival: "2026-10-20", nights: 3)]
        paris.updatedAt = 3; newYork.updatedAt = 2; athens.updatedAt = 1
        return [paris, newYork, athens]
    }
}
#endif
