import Foundation
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

// Usage: swift import_16x9_covers.swift <source-folder> <asset-catalog> <selection-json> [credits-output]
// selection-json is an explicit array of destination names; originals are never changed.
struct Source: Decodable {
    var id: Int; var destination: String; var country_or_territory: String
    var filename: String; var width: Int; var height: Int; var photographer: String
    var attribution: String?; var photo_title: String?; var license: String
    var license_url: String; var source_page: String; var original_url: String; var sha256: String
    var download_url: String?; var source_caption: String?; var landmark: String?; var restrictions: String?
    var title: String { photo_title ?? source_caption ?? landmark ?? destination }
    var imageURL: String { original_url.isEmpty ? (download_url ?? source_page) : original_url }
    var credit: String { attribution.flatMap { $0.isEmpty ? nil : $0 } ?? "Photo by " + photographer + " · " + license }
}
func normalize(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
}
let args = CommandLine.arguments
precondition((4...5).contains(args.count), "Supply source, asset catalog, explicit selection JSON, and optional credits output")
let source = URL(fileURLWithPath: args[1]), assets = URL(fileURLWithPath: args[2])
let selected = Set(try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: args[3]))))
let manifest = source.appendingPathComponent(FileManager.default.fileExists(atPath: source.appendingPathComponent("manifest.json").path) ? "manifest.json" : "index.json")
let entries = try JSONDecoder().decode([Source].self, from: Data(contentsOf: manifest))
precondition(Set(entries.map(\.id)).count == entries.count, "Duplicate destination IDs")
precondition(selected.isSubset(of: Set(entries.map(\.destination))), "Unknown destination in selection")
let locale = Locale(identifier: "en_US")
var countryCodes: [String: String] = [:]
for region in Locale.Region.isoRegions {
    if let name = locale.localizedString(forRegionCode: region.identifier) { countryCodes[normalize(name)] = region.identifier }
}
let specialCountries: [String: [String]] = [
    "China": ["CN", "China mainland"], "Bosnia and Herzegovina": ["BA", "Bosnia & Herzegovina"], "Saint Lucia": ["LC", "St. Lucia"],
    "United States": ["USA", "US", "United States of America"], "United Kingdom": ["UK", "GB", "England", "Scotland", "Wales"],
    "Türkiye": ["Turkey", "TR"], "South Korea": ["Korea", "KR"], "Czechia": ["Czech Republic", "CZ"],
    "Japan": ["JP", "日本"],
    "Hong Kong SAR, China": ["Hong Kong", "HK", "China", "CN"], "Macao SAR, China": ["Macau", "Macao", "MO", "China", "CN"],
    "United Arab Emirates": ["UAE", "AE"], "Israel / Palestinian territories": ["Israel", "IL", "Palestine", "PS"],
    "Turks and Caicos Islands": ["Turks & Caicos Islands", "TC"]
]
let aliases: [String: [String]] = [
    "New York City": ["New York", "NYC"], "Washington DC": ["Washington, D.C.", "Washington D.C.", "Washington"],
    "Florence": ["Firenze"], "Venice": ["Venezia"], "Rome": ["Roma"], "Naples": ["Napoli"],
    "Tokyo": ["Tokyo Prefecture", "Tokyo Metropolis", "東京", "東京都"], "Macau": ["Macao"], "Macao": ["Macau"],
    "Ho Chi Minh City": ["Saigon"], "Mexico City": ["Ciudad de México", "CDMX"], "Mumbai": ["Bombay"],
    "Marrakesh": ["Marrakech"], "Xian": ["Xi'an", "Xi’an"], "Quebec City": ["Québec City", "Quebec", "Québec"],
    "Cairo and Giza": ["Cairo", "Giza"], "Oahu": ["Honolulu"], "Honolulu and Oahu": ["Honolulu", "Oahu"]
]
let regions: [String: [String]] = ["New York City": ["NY", "New York"], "Paris": ["Île-de-France"], "London": ["Greater London"], "Athens": ["Attica"]]
var catalog: [[String: Any]] = []; var bytes = 0
var credits = "PHOTO CREDITS AND SOURCE LICENSE METADATA\nSupplied metadata is preserved; inclusion does not establish reuse rights.\nApp copies: 1280×720 JPEG, quality 0.72; proportional downsampling with at most one output pixel trimmed for source aspect-ratio rounding.\n"
for entry in entries where selected.contains(entry.destination) {
    try autoreleasepool {
        let original = try Data(contentsOf: source.appendingPathComponent(entry.filename))
        let hash = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        precondition(hash == entry.sha256, "Checksum mismatch: \(entry.destination)")
        guard let decoded = CGImageSourceCreateWithData(original as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int else { fatalError("Invalid JPEG") }
        precondition(w == entry.width && h == entry.height, "Dimensions differ from manifest: \(entry.destination)")
        precondition(abs(Double(h) - Double(w) * 9 / 16) <= 1 && w >= 1280, "Expected near-16:9 image: \(entry.destination)")
        precondition((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1, "Unexpected image orientation: \(entry.destination)")
        guard let originalImage = CGImageSourceCreateImageAtIndex(decoded, 0, nil),
              let context = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Cannot decode image") }
        // Rendering at an explicit size avoids ImageIO thumbnail rounding (e.g. 1280×719).
        // Aspect fill only trims the subpixel difference in the two rounded source images.
        let scale = max(1280.0 / Double(w), 720.0 / Double(h))
        let outputWidth = Double(w) * scale, outputHeight = Double(h) * scale
        context.interpolationQuality = .high
        context.draw(originalImage, in: CGRect(x: (1280 - outputWidth) / 2, y: (720 - outputHeight) / 2, width: outputWidth, height: outputHeight))
        guard let image = context.makeImage() else { fatalError("Cannot resize image") }
        let asset = String(format: "DestinationCover%03d", entry.id), folder = assets.appendingPathComponent(asset + ".imageset")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent("cover.jpg")
        guard let encoder = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { fatalError("Cannot encode") }
        CGImageDestinationAddImage(encoder, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        precondition(CGImageDestinationFinalize(encoder))
        bytes += (try Data(contentsOf: output)).count
        let contents: [String: Any] = ["images": [["filename": "cover.jpg", "idiom": "universal"]], "info": ["author": "xcode", "version": 1]]
        try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
        let countryNames = entry.country_or_territory.components(separatedBy: " / ")
        let countries = Set([entry.country_or_territory] + countryNames + countryNames.compactMap { countryCodes[normalize($0)] } + (specialCountries[entry.country_or_territory] ?? []))
        var photo: [String: Any] = ["provider": "bundled", "imageURL": entry.imageURL, "sourceURL": entry.source_page,
            "authors": [["name": entry.photographer]], "license": entry.license,
            "title": entry.title, "attribution": entry.credit]
        if !entry.license_url.isEmpty { photo["licenseURL"] = entry.license_url }
        catalog.append(["asset": asset, "cities": [entry.destination] + (aliases[entry.destination] ?? []), "countries": countries.sorted(),
            "regions": regions[entry.destination] ?? [], "sourceSHA256": entry.sha256, "photo": photo])
        credits += "\n\(entry.id) | \(entry.destination) | \(entry.title)\nPhotographer: \(entry.photographer)\nAttribution: \(entry.credit)\nLicense: \(entry.license)\nLicense URL: \(entry.license_url)\nSource: \(entry.source_page)\nOriginal image: \(entry.imageURL)\nRestrictions: \(entry.restrictions ?? "None supplied beyond license metadata")\nSource SHA-256: \(entry.sha256)\n"
    }
}
let folder = assets.appendingPathComponent("DestinationCoverCatalog.dataset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("catalog.json"))
try JSONSerialization.data(withJSONObject: ["data": [["filename": "catalog.json", "idiom": "universal"]], "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
print("Imported \(catalog.count) covers; \(bytes) JPEG bytes; 1280×720 each.")
if args.count == 5 {
    let cleanCredits = credits.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    try cleanCredits.write(toFile: args[4], atomically: true, encoding: .utf8)
}
