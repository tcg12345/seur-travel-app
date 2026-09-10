import Foundation
import SwiftUI
import CryptoKit

struct GuidePlace: Codable, Hashable, Identifiable {
    var id = UUID()
    var place = PlaceRecord(category: .attraction)
    var note = ""
    var photoJPEG: Data?
}
struct GuideSection: Codable, Hashable, Identifiable {
    var id = UUID()
    var title = ""
    var note = ""
    var places: [GuidePlace] = []
}
struct TravelGuide: Codable, Hashable, Identifiable {
    var id = UUID()
    var title = ""
    var destination = ""
    var introduction = ""
    var tags: [String] = []
    var sections: [GuideSection] = []
    var coverJPEG: Data?
    var thumbnailJPEG: Data?
    static let themes = ["Food & drink", "Art & culture", "Design", "Outdoors", "Hidden gems", "Family", "Weekend", "Luxury"]
    var places: [GuidePlace] { sections.flatMap(\.places) }
    var publicationIssue: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give your guide a title." }
        if destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Choose a destination." }
        if introduction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add a short introduction for your readers." }
        if title.count > 100 || destination.count > 150 || introduction.count > 5000 { return "Shorten your title, destination or introduction." }
        if sections.isEmpty || sections.count > 20 { return "Add between 1 and 20 sections." }
        if places.isEmpty || places.count > 100 { return "Add between 1 and 100 recommended places." }
        if tags.count > 3 || tags.contains(where: { !Self.themes.contains($0) }) { return "Choose up to three themes." }
        for section in sections {
            if section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || section.title.count > 80 { return "Give each section a short title." }
            if section.places.isEmpty && section.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add a note or place to each section." }
            if section.places.count > 50 || section.note.count > 3000 { return "Shorten a section or split it in two." }
            for item in section.places {
                if item.place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.place.name.count > 200 || item.note.count > 3000 { return "Give each place a name and a note under 3,000 characters." }
                if !item.place.website.isEmpty && validatedURL(item.place.website) == nil { return "Check your place website links." }
            }
        }
        if (try? JSONEncoder().encode(self).count).map({ $0 > 5_000_000 }) == true { return "Remove a photo to keep this guide easy to download." }
        return nil
    }
    var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: (try? encoder.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
    /// Copy only location facts. Personal bookings, notes, ratings, costs and attendees stay in the trip.
    static func fromTrip(_ trip: JourneyDocument) -> TravelGuide {
        var guide = TravelGuide(title: trip.title, destination: trip.stops.first?.name ?? trip.destination)
        let locations = trip.events.filter { ($0.kind ?? .place) == .place }.map(\.place) + trip.hotels.map(\.place) + trip.places.map(\.place)
        var seen = Set<String>()
        let items = locations.filter { !$0.name.isEmpty }.compactMap { place -> GuidePlace? in
            let key = (place.name + "|" + place.city).lowercased()
            guard seen.insert(key).inserted else { return nil }
            return GuidePlace(place: place.guideLocation)
        }
        let selected = Array(items.prefix(100))
        guide.sections = [GuideSection(title: "My recommendations", places: Array(selected.prefix(50)))]
        if selected.count > 50 { guide.sections.append(GuideSection(title: "More places to explore", places: Array(selected.dropFirst(50)))) }
        return guide
    }
}
extension PlaceRecord {
    var guideLocation: PlaceRecord {
        PlaceRecord(id: id, name: name, category: category, city: city, address: address, website: website,
            latitude: hasCoordinate ? latitude : nil, longitude: hasCoordinate ? longitude : nil, source: "Traveler guide")
    }
}
struct PublishedGuide: Codable, Identifiable {
    var guide: TravelGuide
    var author: TravelAccount
    var revision: Int
    var isPublished: Bool
    var isSummary: Bool
    var updatedAt: Double
    var placeCount: Int
    var id: UUID { guide.id }
}
struct GuideDraft: Codable, Identifiable {
    var guide: TravelGuide
    var ownerID: String?
    var server: String?
    var revision = 0
    var isPublished = false
    var publishedFingerprint: String?
    var updatedAt = Date.now.timeIntervalSince1970
    var id: UUID { guide.id }
    var hasChanges: Bool { isPublished && guide.fingerprint != publishedFingerprint }
    var status: String { hasChanges ? "Unpublished changes" : isPublished ? "Published" : "Private draft" }
}
@MainActor @Observable final class GuideLibrary {
    private(set) var drafts: [GuideDraft] = []
    private(set) var saved: [PublishedGuide] = []
    private(set) var blockedAuthors: Set<String> = []
    private(set) var hiddenGuides: Set<UUID> = []
    var error: String?
    private let url: URL
    private var unreadable = false
    private struct Archive: Codable { var version = 1; var drafts: [GuideDraft]; var saved: [PublishedGuide]; var blockedAuthors: Set<String>; var hiddenGuides: Set<UUID> }
    init(url: URL? = nil) {
        let args = ProcessInfo.processInfo.arguments, testing = args.contains("--ui-testing")
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(testing ? "AurumUITestTravel/guides.json" : "AurumTravel/guides.json")
        if url == nil && testing && !args.contains("--preserve-state") { try? FileManager.default.removeItem(at: self.url) }
        guard FileManager.default.fileExists(atPath: self.url.path) else { return }
        do { let value = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: self.url)); guard value.version == 1 else { throw CocoaError(.coderReadCorrupt) }; drafts = value.drafts; saved = value.saved; blockedAuthors = value.blockedAuthors; hiddenGuides = value.hiddenGuides }
        catch { unreadable = true; self.error = "Your guides couldn’t be loaded. The original file has been kept." }
    }
    private func persist(_ next: Archive) -> Bool {
        guard !unreadable else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            drafts = next.drafts; saved = next.saved; blockedAuthors = next.blockedAuthors; hiddenGuides = next.hiddenGuides; error = nil; return true
        } catch { self.error = "Your guide couldn’t be saved. Free up storage and try again."; return false }
    }
    private var archive: Archive { Archive(drafts: drafts, saved: saved, blockedAuthors: blockedAuthors, hiddenGuides: hiddenGuides) }
    @discardableResult func save(_ guide: TravelGuide) -> Bool {
        var next = archive
        if let i = next.drafts.firstIndex(where: { $0.id == guide.id }) { next.drafts[i].guide = guide; next.drafts[i].updatedAt = Date.now.timeIntervalSince1970 }
        else { next.drafts.insert(GuideDraft(guide: guide), at: 0) }
        return persist(next)
    }
    @discardableResult func accept(_ remote: PublishedGuide, server: String, replaceDraft: Bool = true) -> Bool {
        guard !remote.isSummary else { error = "Open the full guide before restoring it."; return false }
        var next = archive
        let current = next.drafts.first { $0.id == remote.id }
        let draft = GuideDraft(guide: replaceDraft ? remote.guide : current?.guide ?? remote.guide, ownerID: remote.author.id, server: server, revision: remote.revision,
            isPublished: remote.isPublished, publishedFingerprint: remote.guide.fingerprint)
        next.drafts.removeAll { $0.id == remote.id }; next.drafts.insert(draft, at: 0)
        return persist(next)
    }
    @discardableResult func remove(_ id: UUID) -> Bool { var next = archive; next.drafts.removeAll { $0.id == id }; return persist(next) }
    @discardableResult func bookmark(_ remote: PublishedGuide) -> Bool {
        guard !remote.isSummary else { error = "Open the full guide before saving it."; return false }
        var next = archive
        if next.saved.contains(where: { $0.id == remote.id }) { next.saved.removeAll { $0.id == remote.id } }
        else { next.saved.insert(remote, at: 0) }
        return persist(next)
    }
    @discardableResult func hide(_ id: UUID) -> Bool { var next = archive; next.hiddenGuides.insert(id); next.saved.removeAll { $0.id == id }; return persist(next) }
    @discardableResult func block(_ author: String, blocked: Bool) -> Bool {
        var next = archive
        if blocked { next.blockedAuthors.insert(author); next.saved.removeAll { $0.author.id == author } } else { next.blockedAuthors.remove(author) }
        return persist(next)
    }
    func visible(_ guide: PublishedGuide) -> Bool { !blockedAuthors.contains(guide.author.id) && !hiddenGuides.contains(guide.id) }
}

#if DEBUG
/// Explicit UI-test backend; never enabled in ordinary simulator or device runs.
@MainActor enum GuideTestBackend {
    static var enabled: Bool { let args = ProcessInfo.processInfo.arguments; return args.contains("--ui-testing") && args.contains("--guide-publishing-testing") }
    static let author = TravelAccount(id: "22222222-2222-4222-8222-222222222222", handle: "guide_tester", name: "Guide Tester")
    private static var publications: [UUID: PublishedGuide] = [:]
    static func response(path: String, method: String, data: Data?) throws -> Data? {
        let encoder = JSONEncoder()
        if path == "/v1/status" { return try JSONSerialization.data(withJSONObject: ["tripadvisor": false, "ai": false, "publicSharing": true, "travelGuides": true]) }
        if path == "/v1/me" { return try encoder.encode(author) }
        if path == "/v1/guides" { return try encoder.encode(Array(publications.values.filter(\.isPublished))) }
        guard path.hasPrefix("/v1/guides/"), let id = UUID(uuidString: String(path.split(separator: "/")[2])) else { return nil }
        if method == "PUT", let data {
            struct Body: Decodable { var guide: TravelGuide; var expectedRevision: Int }
            let body = try JSONDecoder().decode(Body.self, from: data)
            guard body.expectedRevision == publications[id]?.revision ?? 0 else { throw JourneyError.message("Guide version changed.") }
            let remote = PublishedGuide(guide: body.guide, author: author, revision: body.expectedRevision + 1, isPublished: true, isSummary: false, updatedAt: Date.now.timeIntervalSince1970, placeCount: body.guide.places.count)
            publications[id] = remote; return try encoder.encode(remote)
        }
        if method == "POST" && path.hasSuffix("/unpublish"), var remote = publications[id] { remote.isPublished = false; remote.revision += 1; publications[id] = remote; return try encoder.encode(remote) }
        if let remote = publications[id] { return try encoder.encode(remote) }
        return nil
    }
}
#endif
