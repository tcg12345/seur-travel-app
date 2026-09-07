import SwiftUI
import MapKit
import Observation

enum PlaceSearchTestPolicy {
    static var blocksPaidRequests: Bool {
        let process = ProcessInfo.processInfo
        return process.arguments.contains("--ui-testing") || process.environment["XCTestConfigurationFilePath"] != nil || process.environment["XCTestBundlePath"] != nil || NSClassFromString("XCTestCase") != nil
    }
    static var usesFixtures: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && !args.contains("--live-apple-places")
    }
}

enum LocationSearchKind: Equatable {
    case destination, city, airport, place, address, country, timeZone
    var symbol: String {
        switch self { case .airport: "airplane"; case .place: "mappin.and.ellipse"; case .address: "location"; case .country: "globe.europe.africa"; case .timeZone: "clock"; default: "building.2" }
    }
    var isLocal: Bool { self == .country || self == .timeZone }
}

struct LocationSelection {
    var text: String
    var place: PlaceRecord
    var country = ""
    var timeZone = ""
}

struct LocationSuggestion: Identifiable {
    let title: String
    let subtitle: String
    var completion: MKLocalSearchCompletion?
    var localValue: String?
    var fixture: LocationSelection?
    var google: GooglePlaceSuggestion?
    var id: String { title + "|" + subtitle }
}

/// Each query owns its completer and resolution task, so old responses cannot overwrite newer input.
@MainActor @Observable final class LocationAutocompleteModel: NSObject, @MainActor MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [LocationSuggestion] = []
    private(set) var loading = false
    private(set) var resolving = false
    private(set) var message: String?
    private var completer: MKLocalSearchCompleter?
    private var work: Task<Void, Never>?
    private var lookup: MKLocalSearch?
    private var revision = UUID()
    private(set) var query = ""
    private let fixtures: Bool
    private let appleSearch: ((String, LocationSearchKind) async throws -> [LocationSuggestion])?
    private var kind: LocationSearchKind = .destination
    private var context = ""
    private var requestedGoogle = false
    var canRequestGoogle: Bool { (kind == .place || kind == .address) && query.count >= 3 && !loading && !resolving && !requestedGoogle }
    init(fixtures: Bool = false, appleSearch: ((String, LocationSearchKind) async throws -> [LocationSuggestion])? = nil) {
        self.fixtures = fixtures; self.appleSearch = appleSearch; super.init()
    }
    private var contextualQuery: String {
        context.isEmpty || query.split(whereSeparator: { $0.isWhitespace }).count > 1 || query.localizedCaseInsensitiveContains(context) ? query : query + " " + context
    }

    func update(_ value: String, kind: LocationSearchKind, context: String = "") {
        let next = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let area = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let unchanged = query == next && self.kind == kind && self.context == area
        if unchanged && (loading || resolving || !suggestions.isEmpty) { return }
        stop()
        if !unchanged { requestedGoogle = false }
        query = next; self.kind = kind; self.context = area
        guard query.count >= 2 else { return }
        if kind.isLocal { suggestions = Self.localSuggestions(query, kind: kind); return }
        loading = true
        let current = revision; let fragment = query
        let contextual = contextualQuery
        work = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self, !Task.isCancelled, self.revision == current else { return }
            #if DEBUG
            if self.fixtures {
                self.suggestions = Self.testSuggestions(fragment, kind: kind); self.loading = false; return
            }
            #endif
            if let appleSearch = self.appleSearch {
                do {
                    let matches = try await appleSearch(contextual, kind)
                    guard !Task.isCancelled, self.revision == current else { return }
                    self.suggestions = matches; self.loading = false
                } catch {
                    guard !Task.isCancelled, self.revision == current else { return }
                    self.loading = false; self.message = "Suggestions are unavailable. You can still enter a location."
                }
                return
            }
            let engine = MKLocalSearchCompleter()
            engine.region = MKCoordinateRegion(.world)
            switch kind {
            case .destination: engine.resultTypes = .address; engine.addressFilter = MKAddressFilter(including: [.locality, .administrativeArea, .country])
            case .city: engine.resultTypes = .address; engine.addressFilter = MKAddressFilter(including: .locality)
            case .airport:
                engine.resultTypes = [.address, .pointOfInterest]
                engine.addressFilter = MKAddressFilter(including: .locality)
                engine.pointOfInterestFilter = MKPointOfInterestFilter(including: [.airport])
            case .address: engine.resultTypes = .address
            default: engine.resultTypes = [.pointOfInterest, .address]
            }
            self.completer = engine; engine.delegate = self; engine.queryFragment = contextual
        }
    }
    // Paid suggestions are requested only by an explicit tap, never by typing,
    // focus changes, automatic retries or an empty Apple response.
    func requestGoogle(search: @escaping (String) async throws -> [GooglePlaceSuggestion]) {
        guard canRequestGoogle else { return }
        let fallback = suggestions
        let contextual = contextualQuery
        stop(); requestedGoogle = true; loading = true
        let current = revision
        work = Task { [weak self] in
            do {
                let matches = try await search(contextual)
                guard let self, !Task.isCancelled, self.revision == current else { return }
                self.loading = false
                self.suggestions = matches.isEmpty ? fallback : matches.map { LocationSuggestion(title: $0.title, subtitle: $0.subtitle, google: $0) }
                if matches.isEmpty { self.message = "No additional suggestions. Try a more specific name." }
            } catch {
                guard let self, !Task.isCancelled, self.revision == current else { return }
                self.loading = false; self.suggestions = fallback
                self.message = "Google suggestions couldn’t load. You can use an existing match or refine your search."
            }
        }
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard completer === self.completer else { return }
        loading = false
        var seen = Set<String>()
        suggestions = completer.results.map { LocationSuggestion(title: $0.title, subtitle: $0.subtitle, completion: $0) }.filter { seen.insert($0.id).inserted }.prefix(5).map { $0 }
        message = suggestions.isEmpty ? "No suggestions. You can keep the location you typed." : nil
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard completer === self.completer else { return }
        loading = false; suggestions = []; message = "Suggestions are unavailable. You can still enter a location."
    }
    func select(_ suggestion: LocationSuggestion, kind: LocationSearchKind, category: PlaceCategory, completion: @escaping (LocationSelection) -> Void) {
        stop(); resolving = true
        let current = revision
        if let value = suggestion.localValue { resolving = false; completion(LocationSelection(text: value, place: PlaceRecord(name: value), country: kind == .country ? value : "", timeZone: kind == .timeZone ? value : "")); return }
        #if DEBUG
        if fixtures, let result = suggestion.fixture { resolving = false; completion(result); return }
        #endif
        let request: MKLocalSearch.Request
        if let item = suggestion.completion { request = MKLocalSearch.Request(completion: item) }
        else if suggestion.google != nil {
            // Google predictions are displayed with attribution, without a map. Resolve the
            // selected search independently in Apple Maps; stored details and pins come from Apple.
            request = MKLocalSearch.Request()
            request.naturalLanguageQuery = suggestion.title + " " + suggestion.subtitle
            request.resultTypes = [.pointOfInterest, .address]
        } else { resolving = false; return }
        let search = MKLocalSearch(request: request); lookup = search
        work = Task { [weak self] in
            do {
                let response = try await search.start()
                guard let self, !Task.isCancelled, self.revision == current else { return }
                guard let mapItem = response.mapItems.first else { self.resolving = false; self.message = "This place couldn’t be resolved. Try again or keep typing."; return }
                let place = ApplePlaceSearch.record(mapItem, fallbackName: suggestion.title, category: category)
                let text: String
                switch kind {
                case .destination: text = mapItem.addressRepresentations?.cityWithContext(.full) ?? place.name
                case .city: text = place.city.isEmpty ? place.name : place.city
                case .address: text = place.address.isEmpty ? place.name : place.address
                default: text = place.name
                }
                self.resolving = false
                completion(LocationSelection(text: text, place: place, country: mapItem.addressRepresentations?.regionName ?? "", timeZone: mapItem.timeZone?.identifier ?? ""))
            } catch {
                guard let self, !Task.isCancelled, self.revision == current else { return }
                self.resolving = false; self.message = "Couldn’t open that suggestion. Try again or enter the location manually."
            }
        }
    }
    func stop() {
        revision = UUID(); work?.cancel(); work = nil; completer?.delegate = nil; completer?.cancel(); completer = nil; lookup?.cancel(); lookup = nil
        suggestions = []; loading = false; resolving = false; message = nil
    }
    static func localSuggestions(_ query: String, kind: LocationSearchKind) -> [LocationSuggestion] {
        let fragment = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fragment.count >= 2 else { return [] }
        if kind == .country {
            return Locale.Region.isoRegions.compactMap { region -> LocationSuggestion? in
                guard let name = Locale.current.localizedString(forRegionCode: region.identifier), name.localizedCaseInsensitiveContains(fragment) || region.identifier.caseInsensitiveCompare(fragment) == .orderedSame else { return nil }
                return LocationSuggestion(title: name, subtitle: region.identifier, localValue: name)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.prefix(5).map { $0 }
        }
        return TimeZone.knownTimeZoneIdentifiers.filter { $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(fragment) || $0.localizedCaseInsensitiveContains(fragment) }.prefix(5).map { LocationSuggestion(title: $0.replacingOccurrences(of: "_", with: " "), subtitle: "Time zone", localValue: $0) }
    }
    #if DEBUG
    private static func testSuggestions(_ query: String, kind: LocationSearchKind) -> [LocationSuggestion] {
        if query.localizedCaseInsensitiveContains("lis") {
            let place = PlaceRecord(id: "ui-test-lisbon", name: "Lisbon", category: .other, city: "Lisbon", address: "Lisbon, Portugal", latitude: 38.7223, longitude: -9.1393, source: "UI test fixture")
            return [LocationSuggestion(title: "Lisbon", subtitle: "Portugal · UI test fixture", fixture: LocationSelection(text: kind == .destination ? "Lisbon, Portugal" : "Lisbon", place: place, country: "Portugal", timeZone: "Europe/Lisbon"))]
        }
        guard query.localizedCaseInsensitiveContains("par") || query.localizedCaseInsensitiveContains("cdg") else { return [] }
        let airport = kind == .airport
        let name = airport ? "Paris Charles de Gaulle Airport" : kind == .address ? "10 Avenue Example, Paris, France" : kind == .place ? "Paris Test Hotel" : "Paris"
        let place = PlaceRecord(id: "ui-test-paris", name: name, category: airport ? .other : .hotel, city: "Paris", address: "10 Avenue Example, Paris, France", latitude: 48.8566, longitude: 2.3522, source: "UI test fixture")
        let text = kind == .destination ? "Paris, France" : name
        return [LocationSuggestion(title: name, subtitle: "France · UI test fixture", fixture: LocationSelection(text: text, place: place, country: "France", timeZone: "Europe/Paris"))]
    }
    #endif
}

struct LocationAutocompleteField: View {
    @Environment(TravelAPI.self) private var api
    let title: String
    @Binding var text: String
    var kind: LocationSearchKind = .destination
    var identifier = "location-field"
    var category: PlaceCategory = .other
    var searchContext = ""
    var suggestionSymbol: String?
    private var resultSymbol: String {
        suggestionSymbol ?? (kind == .place && category != .other ? category.symbol : kind.symbol)
    }
    var onEdit: (() -> Void)?
    var onSelect: ((LocationSelection) -> Void)?
    @State private var model: LocationAutocompleteModel
    @FocusState private var focused: Bool
    init(_ title: String, text: Binding<String>, kind: LocationSearchKind = .destination, identifier: String = "location-field", category: PlaceCategory = .other, searchContext: String = "", suggestionSymbol: String? = nil, onEdit: (() -> Void)? = nil, onSelect: ((LocationSelection) -> Void)? = nil) {
        self.title = title; _text = text; self.kind = kind; self.identifier = identifier; self.category = category; self.searchContext = searchContext; self.suggestionSymbol = suggestionSymbol; self.onEdit = onEdit; self.onSelect = onSelect
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        _model = State(initialValue: LocationAutocompleteModel(fixtures: PlaceSearchTestPolicy.usesFixtures || (args.contains("--ui-testing") && args.contains("--location-testing"))))
        #else
        _model = State(initialValue: LocationAutocompleteModel())
        #endif
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(title, text: Binding(get: { text }, set: { value in guard value != text else { return }; text = value; onEdit?() }))
                .focused($focused).autocorrectionDisabled().textInputAutocapitalization(.words).submitLabel(.done)
                .onSubmit { focused = false; model.stop() }.accessibilityIdentifier(identifier)
            if focused && text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                VStack(alignment: .leading, spacing: 0) {
                    if model.loading || model.resolving { HStack(spacing: 8) { ProgressView(); Text(model.resolving ? "Finding this place…" : "Finding suggestions…").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 12) }
                    ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            model.select(suggestion, kind: kind, category: category) { result in
                                text = result.text; focused = false; model.stop(); onSelect?(result)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: resultSymbol).font(.system(size: 16, weight: .regular)).foregroundStyle(Color.bronze).frame(width: 21).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    if !suggestion.subtitle.isEmpty { Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.up.left").font(.caption2).foregroundStyle(.secondary)
                            }.padding(.vertical, 12).contentShape(.rect)
                        }.buttonStyle(.plain).accessibilityIdentifier("\(identifier)-suggestion-\(index)")
                        if index < model.suggestions.count - 1 { Divider() }
                    }
                    if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary).padding(.vertical, 10) }
                    if model.canRequestGoogle && !PlaceSearchTestPolicy.blocksPaidRequests && api.isSignedIn && api.status?.googlePlaces != false {
                        Button("Try Google suggestions") { model.requestGoogle { try await api.autocompletePlaces($0) } }
                            .font(.caption).padding(.vertical, 10).accessibilityIdentifier(identifier + "-google-fallback")
                    }
                    if !model.suggestions.isEmpty { Text(kind.isLocal ? "Suggested matches" : model.suggestions.contains(where: { $0.google != nil }) ? "Google Maps" : "Apple Maps suggestions").font(.caption).foregroundStyle(.secondary).padding(.bottom, 5) }
                }.padding(.top, 6)
            }
        }
        .onChange(of: text) { if focused { model.update(text, kind: kind, context: searchContext) } }
        .onChange(of: focused) { if focused { model.update(text, kind: kind, context: searchContext) } else { model.stop() } }
        .onChange(of: kind) { if focused { model.update(text, kind: kind, context: searchContext) } }
        .onChange(of: searchContext) { if focused { model.update(text, kind: kind, context: searchContext) } }
        .onDisappear { model.stop() }
    }
}
