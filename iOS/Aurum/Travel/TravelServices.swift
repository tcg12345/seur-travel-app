import SwiftUI
import MapKit
import Security

struct TravelAccount: Codable, Identifiable { var id: String; var handle: String; var name: String }
struct TravelAuthResponse: Codable { var token: String; var user: TravelAccount }
struct TravelServiceStatus: Codable { var tripadvisor: Bool; var ai: Bool; var publicSharing: Bool; var googlePlaces: Bool?; var flightTracking: Bool?; var flightHistory: Bool? }
struct GooglePlaceSuggestion: Codable, Identifiable { var id: String; var title: String; var subtitle: String }
struct TravelFriend: Codable, Identifiable { var id: String; var handle: String; var name: String; var status: String; var incoming: Bool }
struct RemoteJourney: Codable, Identifiable { var id: String; var owner: TravelAccount; var document: JourneyDocument; var revision: Int; var isSummary: Bool? }
struct TravelConversation: Codable, Identifiable { var id: String; var name: String; var members: [TravelAccount] }
struct TravelChatMessage: Codable, Identifiable { var id: String; var sender: TravelAccount; var text: String; var documentID: String?; var createdAt: Double; var timestamp: String { Date(timeIntervalSince1970: createdAt).formatted(date: .abbreviated, time: .shortened) } }
struct TravelLink: Codable { var url: String }
struct AITravelResponse: Codable { var text: String; var places: [PlaceRecord] }
private struct APIProblem: Codable { var error: String }
private struct EmptyReply: Codable { var ok: Bool }

/// Coalesce only requests that are still running. Google prediction content is
/// not persisted, prefetched or retained as a reusable response cache.
@MainActor final class GoogleAutocompleteRequests {
    private var pending: [String: Task<[GooglePlaceSuggestion], Error>] = [:]
    func fetch(_ query: String, server: String, request: @escaping (String) async throws -> [GooglePlaceSuggestion]) async throws -> [GooglePlaceSuggestion] {
        let normalized = query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard (3...200).contains(normalized.count) else { return [] }
        try Task.checkCancellation()
        let key = server + "|" + normalized.lowercased()
        if let task = pending[key] { return try await task.value }
        let task = Task { try await request(normalized) }
        pending[key] = task
        defer { pending[key] = nil }
        return try await task.value
    }
}

@MainActor @Observable final class TravelAPI {
    var baseURL: String { didSet { if oldValue != baseURL { defaults.set(baseURL, forKey: "aurum.backendURL"); account = nil; token = nil; savedFlights = [] } } }
    private(set) var account: TravelAccount?
    private(set) var status: TravelServiceStatus?
    private(set) var savedFlights: [FlightReservation] = []
    var savedFlightsError: String?
    private var token: String?
    private let googleAutocomplete = GoogleAutocompleteRequests()
    private let defaults = UserDefaults.standard
    init() {
        let fallback = "https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api"
        let saved = defaults.string(forKey: "aurum.backendURL") ?? ""
        // Move existing simulator installs to the cloud while retaining local journeys.
        let previousHost = URL(string: saved)?.host ?? ""
        let configured = saved.isEmpty || ["localhost", "127.0.0.1", "::1"].contains(previousHost) ? fallback : saved
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        if args.contains("--ui-testing"), let index = args.firstIndex(of: "--travel-test-server"), args.indices.contains(index + 1) {
            baseURL = args[index + 1]
        } else { baseURL = configured }
        #else
        baseURL = configured
        #endif
        token = Self.readToken(for: baseURL)
    }
    var isSignedIn: Bool { account != nil && token != nil }
    func refresh() async throws {
        let server = baseURL, sessionToken = token
        let value: TravelServiceStatus = try await request("/v1/status")
        guard baseURL == server else { return }
        status = value
        if sessionToken != nil && token == sessionToken {
            let user: TravelAccount = try await request("/v1/me")
            guard baseURL == server && token == sessionToken else { return }
            account = user
        }
    }
    func authenticate(handle: String, name: String, password: String, register: Bool) async throws {
        let response: TravelAuthResponse = try await request(register ? "/v1/auth/register" : "/v1/auth/login", method: "POST", body: ["handle": handle, "name": name, "password": password])
        try Self.writeToken(response.token, for: baseURL)
        token = response.token; account = response.user
    }
    func deleteAccount() async throws {
        let _: EmptyReply = try await request("/v1/account", method: "DELETE", body: [:])
        await FlightNotifications.shared.clearLocalActivities()
        Self.deleteToken(for: baseURL); token = nil; account = nil; savedFlights = []; savedFlightsError = nil
    }
    func logout() async throws {
        if token != nil { let _: EmptyReply = try await request("/v1/auth/logout", method: "POST", body: [:]) }
        await FlightNotifications.shared.clearLocalActivities()
        Self.deleteToken(for: baseURL); token = nil; account = nil; savedFlights = []; savedFlightsError = nil
    }
    func loadSavedFlights() async {
        #if DEBUG
        if FlightMapFixtures.enabled { return }
        #endif
        guard isSignedIn else { savedFlights = []; return }
        let user = account?.id
        do {
            let values: [FlightReservation] = try await request("/v1/my-flights")
            guard account?.id == user else { return }
            savedFlights = values; savedFlightsError = nil
        } catch { if account?.id == user { savedFlightsError = error.localizedDescription } }
    }
    func flightWatches(_ installation: String) async throws -> [FlightWatch] {
        try await request("/v1/flight-notifications", query: ["installationID": installation])
    }
    func followFlight(_ body: [String: String], update: Bool = false) async throws -> FlightWatchReply {
        try await request("/v1/flight-notifications", method: update ? "PUT" : "POST", body: body)
    }
    func stopFlightNotifications(_ installation: String, id: String? = nil) async throws {
        var body = ["installationID": installation]; if let id { body["id"] = id }
        let _: EmptyReply = try await request("/v1/flight-notifications", method: "DELETE", body: body)
    }
    func saveFlight(_ flight: FlightReservation) async throws {
        let user = account?.id, server = baseURL
        let saved: FlightReservation
        #if DEBUG
        if FlightMapFixtures.enabled { saved = flight }
        else { saved = try await request("/v1/my-flights/" + flight.id.uuidString, method: "PUT", encodable: flight) }
        #else
        saved = try await request("/v1/my-flights/" + flight.id.uuidString, method: "PUT", encodable: flight)
        #endif
        guard user == account?.id && server == baseURL else { return }
        savedFlights.removeAll { $0.id == saved.id }; savedFlights.insert(saved, at: 0); savedFlightsError = nil
    }
    func removeFlight(_ id: UUID) async throws {
        let user = account?.id, server = baseURL
        #if DEBUG
        if !FlightMapFixtures.enabled { let _: EmptyReply = try await request("/v1/my-flights/" + id.uuidString, method: "DELETE") }
        #else
        let _: EmptyReply = try await request("/v1/my-flights/" + id.uuidString, method: "DELETE")
        #endif
        guard user == account?.id && server == baseURL else { return }
        savedFlights.removeAll { $0.id == id }
    }
    func flightRoute(origin: String, destination: String, day: String) async throws -> FlightFeed {
        #if DEBUG
        if FlightMapFixtures.enabled { return FlightMapFixtures.feed }
        #endif
        return try await request("/v1/flights/route", query: ["origin": origin, "destination": destination, "date": day])
    }
    func nearbyFlightAirport(latitude: Double, longitude: Double) async throws -> FlightAirport {
        #if DEBUG
        if FlightMapFixtures.enabled { return .init(code: "CDG", name: "Paris Charles de Gaulle", latitude: 49.0097, longitude: 2.5479, timeZone: "Europe/Paris") }
        #endif
        return try await request("/v1/flights/airport-nearby", query: ["latitude": String(latitude), "longitude": String(longitude)])
    }
    func flightAirport(_ code: String) async throws -> FlightAirport {
        #if DEBUG
        if FlightMapFixtures.enabled { return code == "JFK" ? .init(code: "JFK", name: "John F. Kennedy International", latitude: 40.6413, longitude: -73.7781, timeZone: "America/New_York") : .init(code: "LHR", name: "London Heathrow", latitude: 51.47, longitude: -0.4543, timeZone: "Europe/London") }
        #endif
        return try await request("/v1/flights/airport", query: ["code": code])
    }
    func flightStatus(_ ident: String, day: String) async throws -> FlightFeed {
        #if DEBUG
        if FlightMapFixtures.enabled { return FlightMapFixtures.feed }
        #endif
        return try await request("/v1/flights/status", query: ["q": ident, "date": day])
    }
    func flightHistory(_ ident: String, day: String) async throws -> FlightFeed {
        #if DEBUG
        if FlightMapFixtures.enabled { return FlightMapFixtures.history }
        #endif
        return try await request("/v1/flights/history", query: ["q": ident, "date": day])
    }
    func flightPosition(_ id: String) async throws -> FlightPosition {
        #if DEBUG
        if FlightMapFixtures.enabled { return FlightPosition(latitude: 48.5, longitude: -35, timestamp: "2026-09-07T01:00:00Z", altitude: 350, groundspeed: 470, heading: 75) }
        #endif
        return try await request("/v1/flights/position", query: ["id": id])
    }
    func autocompletePlaces(_ query: String) async throws -> [GooglePlaceSuggestion] {
        guard !PlaceSearchTestPolicy.blocksPaidRequests else { throw JourneyError.message("Live Google Places requests are disabled during automated tests.") }
        guard isSignedIn, status?.googlePlaces != false else { return [] }
        return try await googleAutocomplete.fetch(query, server: baseURL) { [self] value in
            try await perform("/v1/locations/autocomplete", method: "GET", data: nil, query: ["q": value], timeout: 5)
        }
    }
    func searchPlaces(_ query: String, category: PlaceCategory) async throws -> [PlaceRecord] {
        try requirePaidProviderAccess()
        return try await request("/v1/places/search", query: ["q": query, "category": category == .hotel ? "hotels" : category == .restaurant || category == .bar || category == .cafe ? "restaurants" : "attractions"])
    }
    func placeDetails(_ id: String) async throws -> PlaceRecord { try requirePaidProviderAccess(); return try await request("/v1/places/\(id)") }
    func recommendations(city: String, interests: String) async throws -> AITravelResponse {
        try requirePaidProviderAccess()
        let payload = try await AppleActivityIdeas.prepare(city: city, interests: interests)
        try Task.checkCancellation()
        guard !payload.candidates.isEmpty else { return AITravelResponse(text: "No places were found in Apple Maps. Try another destination or different interests.", places: []) }
        return try await request("/v1/ai/activities", method: "POST", encodable: payload)
    }
    func conciergeReply(_ payload: ConciergeRequest) async throws -> ConciergeReply {
        #if DEBUG
        if ConciergeFixtures.enabled {
            try await Task.sleep(for: .milliseconds(80))
            return ConciergeReply(text: "## A plan shaped around you\n\nHere is a flexible two-day plan for Paris, with time for exploring and a slower afternoon. You can review each activity before saving it.\n\nTell me what you would like to change and I’ll refine the plan.", suggestions: ["Make the pace slower", "Add more restaurant ideas"], searches: [], itinerary: ConciergeFixtures.plan)
        }
        #endif
        try requirePaidProviderAccess()
        return try await perform("/v1/ai/concierge", method: "POST", data: JSONEncoder().encode(payload), timeout: 90)
    }
    func conciergeSearch(_ query: ConciergeSearch) async throws -> [PlaceRecord] {
        try Task.checkCancellation()
        let destinations = try await ApplePlaceSearch.search(query.city, citiesOnly: true)
        guard let destination = destinations.first(where: \.hasCoordinate) else { return [] }
        let city = ExploreCity(name: query.city, country: "", latitude: destination.latitude!, longitude: destination.longitude!)
        let results = try await CityExploreSearch.search(city: city, interest: .highlights, term: query.query, wider: false)
        try Task.checkCancellation()
        return Array(results.prefix(8).map(\.record))
    }
    private func requirePaidProviderAccess() throws {
        guard !PlaceSearchTestPolicy.blocksPaidRequests else { throw JourneyError.message("Live paid place and AI requests are disabled during automated tests.") }
        guard isSignedIn else { throw JourneyError.message("Sign in to your travel account to use this feature.") }
    }
    func hotelOverview(_ place: PlaceRecord) async throws -> AITravelResponse { try requirePaidProviderAccess(); return try await request("/v1/ai/hotel", method: "POST", encodable: place) }
    func friends() async throws -> [TravelFriend] { try await request("/v1/friends") }
    func requestFriend(_ handle: String) async throws { let _: EmptyReply = try await request("/v1/friends", method: "POST", body: ["handle": handle]) }
    func respondFriend(_ id: String, accept: Bool) async throws { let _: EmptyReply = try await request("/v1/friends/\(id)", method: accept ? "PUT" : "DELETE", body: [:]) }
    func documents(feed: Bool = false) async throws -> [RemoteJourney] { try await request(feed ? "/v1/feed" : "/v1/documents") }
    func document(_ id: String) async throws -> RemoteJourney { try await request("/v1/documents/\(id)") }
    func upload(_ document: JourneyDocument) async throws -> RemoteJourney { try await request("/v1/documents/\(document.id.uuidString)", method: "PUT", encodable: document) }
    func deleteDocument(_ id: String) async throws { let _: EmptyReply = try await request("/v1/documents/\(id)", method: "DELETE") }
    func link(_ id: UUID) async throws -> TravelLink { try await request("/v1/documents/\(id.uuidString)/link", method: "POST", body: [:]) }
    func revoke(_ id: UUID) async throws { let _: EmptyReply = try await request("/v1/documents/\(id.uuidString)/revoke", method: "POST", body: [:]) }
    func conversations() async throws -> [TravelConversation] { try await request("/v1/conversations") }
    func createConversation(name: String, members: [String]) async throws -> TravelConversation { try await request("/v1/conversations", method: "POST", body: ["name": name, "members": members]) }
    func messages(_ conversation: String) async throws -> [TravelChatMessage] { try await request("/v1/conversations/\(conversation)/messages") }
    func send(_ conversation: String, text: String, documentID: String?) async throws -> TravelChatMessage {
        var body: [String: Any] = ["text": text]; if let documentID { body["documentID"] = documentID }
        return try await request("/v1/conversations/\(conversation)/messages", method: "POST", body: body)
    }
    private func request<T: Decodable, Body: Encodable>(_ path: String, method: String, encodable: Body) async throws -> T {
        try await perform(path, method: method, data: JSONEncoder().encode(encodable))
    }
    private func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, query: [String: String] = [:]) async throws -> T {
        try await perform(path, method: method, data: body.map { try JSONSerialization.data(withJSONObject: $0) }, query: query)
    }
    private func perform<T: Decodable>(_ path: String, method: String, data: Data?, query: [String: String] = [:], timeout: TimeInterval = 40) async throws -> T {
        guard var url = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else { throw JourneyError.message("The cloud service address is invalid. Check the server setting in Travel → Account.") }
        url.path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")); url.path = (url.path.isEmpty ? "" : "/" + url.path) + path
        if !query.isEmpty { url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let address = url.url else { throw JourneyError.message("Invalid backend address.") }
        let requestToken = token, requestServer = baseURL
        var request = URLRequest(url: address); request.httpMethod = method; request.httpBody = data; request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let requestToken { request.setValue("Bearer " + requestToken, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw JourneyError.message("The server did not return an HTTP response.") }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 && token == requestToken && baseURL == requestServer {
                Self.deleteToken(for: requestServer); token = nil; account = nil; savedFlights = []; savedFlightsError = nil
            }
            throw JourneyError.message((try? JSONDecoder().decode(APIProblem.self, from: data))?.error ?? "Request failed (\(response.statusCode)).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private static func key(_ server: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.aurum.travel.session", kSecAttrAccount as String: server] }
    private static func readToken(for server: String) -> String? {
        var query = key(server); query[kSecReturnData as String] = true
        var result: CFTypeRef?; guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }; return String(data: data, encoding: .utf8)
    }
    private static func writeToken(_ token: String, for server: String) throws {
        deleteToken(for: server)
        var query = key(server); query[kSecValueData as String] = Data(token.utf8); query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw JourneyError.message("Couldn’t securely save the session in Keychain.") }
    }
    private static func deleteToken(for server: String) { SecItemDelete(key(server) as CFDictionary) }
}

@MainActor enum ApplePlaceSearch {
    static func search(_ text: String, category: PlaceCategory = .other, citiesOnly: Bool = false) async throws -> [PlaceRecord] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = citiesOnly ? [.address, .pointOfInterest] : [.pointOfInterest, .address]
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { record($0, fallbackName: text, category: category) }
    }
    static func record(_ item: MKMapItem, fallbackName: String, category: PlaceCategory = .other) -> PlaceRecord {
        PlaceRecord(id: item.identifier?.rawValue ?? UUID().uuidString, name: item.name ?? fallbackName, category: category, city: item.addressRepresentations?.cityName ?? "", address: item.address?.fullAddress ?? item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true) ?? "", phone: item.phoneNumber ?? "", website: item.url?.absoluteString ?? "", latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude, source: "Apple Maps")
    }
}


struct ActivityIdeasRequest: Encodable {
    let city: String
    let interests: String
    let candidates: [PlaceRecord]
}

@MainActor enum AppleActivityIdeas {
    typealias Search = (String, String) async throws -> [PlaceRecord]
    static func prepare(city: String, interests: String, search: Search = findPlaces) async throws -> ActivityIdeasRequest {
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let interests = interests.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...100).contains(city.count), interests.count <= 1000 else { throw JourneyError.message("Enter a destination and up to 1,000 characters of interests.") }
        try Task.checkCancellation()
        let found = try await search(city, interests)
        try Task.checkCancellation()
        var seen = Set<String>()
        let candidates = found.filter { $0.source == "Apple Maps" && $0.hasCoordinate && !$0.name.isEmpty && seen.insert($0.id).inserted }.prefix(8)
        return ActivityIdeasRequest(city: city, interests: interests, candidates: Array(candidates))
    }
    private static func findPlaces(city: String, interests: String) async throws -> [PlaceRecord] {
        let destinations = try await ApplePlaceSearch.search(city, citiesOnly: true)
        try Task.checkCancellation()
        guard let destination = destinations.first(where: \.hasCoordinate) else { return [] }
        let region = ExploreCity(name: city, country: "", latitude: destination.latitude!, longitude: destination.longitude!)
        // At most two regional searches; no search-per-keystroke or paid fallback.
        let preferred = try await CityExploreSearch.search(city: region, interest: .attractions, term: interests.isEmpty ? "attractions" : interests, wider: false)
        try Task.checkCancellation()
        if preferred.count >= 8 || interests.isEmpty { return preferred.map(\.record) }
        let highlights = try await CityExploreSearch.search(city: region, interest: .attractions, term: "", wider: false)
        return (preferred + highlights).map(\.record)
    }
}
