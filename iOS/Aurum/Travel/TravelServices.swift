import SwiftUI
import MapKit
import Security

struct TravelAccount: Codable, Identifiable { var id: String; var handle: String; var name: String }
struct TravelAuthResponse: Codable { var token: String; var user: TravelAccount }
struct TravelServiceStatus: Codable { var tripadvisor: Bool; var ai: Bool; var publicSharing: Bool; var googlePlaces: Bool?; var flightTracking: Bool?; var flightHistory: Bool? }
struct GooglePlaceSuggestion: Codable, Identifiable { var id: String; var title: String; var subtitle: String }
struct TravelFriend: Codable, Identifiable { var id: String; var handle: String; var name: String; var status: String; var incoming: Bool }
struct RemoteJourney: Codable, Identifiable { var id: String; var owner: TravelAccount; var document: JourneyDocument; var revision: Int }
struct TravelConversation: Codable, Identifiable { var id: String; var name: String; var members: [TravelAccount] }
struct TravelChatMessage: Codable, Identifiable { var id: String; var sender: TravelAccount; var text: String; var documentID: String?; var createdAt: Double; var timestamp: String { Date(timeIntervalSince1970: createdAt).formatted(date: .abbreviated, time: .shortened) } }
struct TravelLink: Codable { var url: String }
struct AITravelResponse: Codable { var text: String; var places: [PlaceRecord] }
private struct APIProblem: Codable { var error: String }
private struct EmptyReply: Codable { var ok: Bool }

@MainActor @Observable final class TravelAPI {
    var baseURL: String { didSet { if oldValue != baseURL { defaults.set(baseURL, forKey: "aurum.backendURL"); account = nil; token = nil } } }
    private(set) var account: TravelAccount?
    private(set) var status: TravelServiceStatus?
    private var token: String?
    private let defaults = UserDefaults.standard
    init() {
        #if DEBUG
        let fallback = "http://localhost:8787"
        #else
        let fallback = ""
        #endif
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        if args.contains("--ui-testing"), let index = args.firstIndex(of: "--travel-test-server"), args.indices.contains(index + 1) {
            baseURL = args[index + 1]
        } else { baseURL = defaults.string(forKey: "aurum.backendURL") ?? fallback }
        #else
        baseURL = defaults.string(forKey: "aurum.backendURL") ?? fallback
        #endif
        token = Self.readToken(for: baseURL)
    }
    var isSignedIn: Bool { account != nil && token != nil }
    func refresh() async throws { status = try await request("/v1/status"); if token != nil { account = try await request("/v1/me") } }
    func authenticate(handle: String, name: String, password: String, register: Bool) async throws {
        let response: TravelAuthResponse = try await request(register ? "/v1/auth/register" : "/v1/auth/login", method: "POST", body: ["handle": handle, "name": name, "password": password])
        try Self.writeToken(response.token, for: baseURL)
        token = response.token; account = response.user
    }
    func logout() async {
        if token != nil { let _: EmptyReply? = try? await request("/v1/auth/logout", method: "POST", body: [:]) }
        Self.deleteToken(for: baseURL); token = nil; account = nil
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
        try await perform("/v1/locations/autocomplete", method: "GET", data: nil, query: ["q": query], timeout: 5)
    }
    func searchPlaces(_ query: String, category: PlaceCategory) async throws -> [PlaceRecord] {
        try await request("/v1/places/search", query: ["q": query, "category": category == .hotel ? "hotels" : category == .restaurant || category == .bar || category == .cafe ? "restaurants" : "attractions"])
    }
    func placeDetails(_ id: String) async throws -> PlaceRecord { try await request("/v1/places/\(id)") }
    func recommendations(city: String, interests: String) async throws -> AITravelResponse { try await request("/v1/ai/activities", method: "POST", body: ["city": city, "interests": interests]) }
    func hotelOverview(_ place: PlaceRecord) async throws -> AITravelResponse { try await request("/v1/ai/hotel", method: "POST", encodable: place) }
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
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else { throw JourneyError.message("Set your HTTPS backend address in Travel → Account. Simulator development can use http://localhost:8787.") }
        url.path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")); url.path = (url.path.isEmpty ? "" : "/" + url.path) + path
        if !query.isEmpty { url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let address = url.url else { throw JourneyError.message("Invalid backend address.") }
        var request = URLRequest(url: address); request.httpMethod = method; request.httpBody = data; request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw JourneyError.message("The server did not return an HTTP response.") }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 { account = nil }
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
