import Foundation
import CoreLocation

/// Coalesced, once-per-coordinate country enrichment. No Google Places requests.
@MainActor final class TravelStatsMetadata {
    static let shared = TravelStatsMetadata()
    private var running = false
    private let defaults = UserDefaults.standard
    func enrich(_ library: JourneyLibrary, catalog: [Hotel]) async {
        guard !running else { return }
        running = true; defer { running = false }
        var cached = defaults.dictionary(forKey: "seur.stats.countryCache.v1") as? [String: String] ?? [:]
        var failures = defaults.dictionary(forKey: "seur.stats.countryAttempts.v1") as? [String: Double] ?? [:]
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        for id in library.documents.filter({ $0.isTemplate != true }).map(\.id) {
            guard !Task.isCancelled, var document = library.documents.first(where: { $0.id == id }) else { return }
            var changed = false
            for i in document.hotels.indices where document.hotels[i].place.brand == nil {
                if let brand = TravelStatistics.brand(for: document.hotels[i].place, catalog: catalog) { document.hotels[i].place.brand = brand; changed = true }
            }
            for i in document.stops.indices where document.stops[i].countryCode == nil {
                if let code = TravelStatistics.countryCode(document.stops[i].country) { document.stops[i].countryCode = code; changed = true }
            }
            if changed, !library.save(document) { return }
            for original in document.stops where original.countryCode == nil {
                guard !testing, !Task.isCancelled, let point = RoutePoint(original) else { continue }
                let key = String(format: "%.4f,%.4f", point.latitude, point.longitude)
                var code = cached[key]
                if code == nil {
                    if let last = failures[key], Date.now.timeIntervalSince1970 - last < 86400 { continue }
                    let geocoder = CLGeocoder()
                    do {
                        let marks = try await geocoder.reverseGeocodeLocation(.init(latitude: point.latitude, longitude: point.longitude))
                        guard !Task.isCancelled else { return }
                        code = marks.first?.isoCountryCode.flatMap(TravelStatistics.countryCode) ?? ""
                        cached[key] = code; defaults.set(cached, forKey: "seur.stats.countryCache.v1")
                    } catch {
                        failures[key] = Date.now.timeIntervalSince1970; defaults.set(failures, forKey: "seur.stats.countryAttempts.v1")
                        // Network failures are retried on a later day, never in a tight loop.
                    }
                    try? await Task.sleep(for: .milliseconds(1300))
                }
                guard !Task.isCancelled else { return }
                guard let code, !code.isEmpty, var latest = library.documents.first(where: { $0.id == id }),
                      let index = latest.stops.firstIndex(where: { $0.id == original.id }), latest.stops[index] == original else { continue }
                latest.stops[index].countryCode = code
                if !library.save(latest) { return }
            }
        }
    }
}
