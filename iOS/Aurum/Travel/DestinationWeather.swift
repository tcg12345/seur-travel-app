import SwiftUI
import WeatherKit
import MapKit

struct DestinationForecast {
    var days: [DayWeather]
    var zone: TimeZone
    var attribution: WeatherAttribution
    var fetchedAt: Date
    func day(_ key: String) -> DayWeather? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd"
        return days.first { formatter.string(from: $0.date) == key }
    }
}
@MainActor final class DestinationWeatherService {
    static let shared = DestinationWeatherService()
    private var cache: [String: DestinationForecast] = [:]
    private var pending: [String: Task<DestinationForecast, Error>] = [:]
    func forecast(city: String, latitude: Double?, longitude: Double?) async throws -> DestinationForecast {
        guard !FlightNotifications.testing else { throw JourneyError.message("Weather is disabled during automated tests.") }
        let key = city.lowercased() + "|" + String(latitude ?? 999) + "|" + String(longitude ?? 999)
        if let value = cache[key], value.fetchedAt.timeIntervalSinceNow > -1800 { return value }
        if let task = pending[key] { return try await task.value }
        let task = Task<DestinationForecast, Error> {
            let request = MKLocalSearch.Request(); request.naturalLanguageQuery = city; request.resultTypes = .address
            if let latitude, let longitude { request.region = MKCoordinateRegion(center: .init(latitude: latitude, longitude: longitude), latitudinalMeters: 50000, longitudinalMeters: 50000) }
            let result = try await MKLocalSearch(request: request).start()
            guard let place = result.mapItems.first, let zone = place.timeZone else { throw JourneyError.message("Weather isn’t available for this destination yet.") }
            let location = latitude.flatMap { lat in longitude.map { CLLocation(latitude: lat, longitude: $0) } } ?? place.location
            let forecast = try await WeatherService.shared.weather(for: location, including: .daily)
            let attribution = try await WeatherService.shared.attribution
            return DestinationForecast(days: Array(forecast), zone: zone, attribution: attribution, fetchedAt: .now)
        }
        pending[key] = task
        defer { pending[key] = nil }
        let value = try await task.value
        if cache.count >= 30 { cache.removeAll() }
        cache[key] = value; return value
    }
    static func canForecast(day: String?, now: Date = .now) -> Bool {
        guard let day, TravelDay.date(day) != nil else { return false }
        let distance = TravelDay.distance(TravelDay.key(now), day)
        return (-1...10).contains(distance)
    }
}

struct DestinationWeatherRow: View {
    @Environment(TravelStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let city: String
    let day: String?
    var tripID: UUID?
    var latitude: Double?
    var longitude: Double?
    @State private var forecast: DestinationForecast?
    @State private var error: String?
    @State private var loading = false
    private var weather: DayWeather? { day.flatMap { forecast?.day($0) } }
    var body: some View {
        if !FlightNotifications.testing {
            VStack(alignment: .leading, spacing: 8) {
                if let weather, let forecast {
                    HStack(spacing: 9) {
                        Image(systemName: weather.symbolName).symbolRenderingMode(.multicolor)
                        Text(weather.condition.description).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(weather.highTemperature.formatted(.measurement(width: .narrow, usage: .weather)) + " / " + weather.lowTemperature.formatted(.measurement(width: .narrow, usage: .weather))).monospacedDigit()
                    }.font(.caption)
                    HStack {
                        Label("\(Int((weather.precipitationChance * 100).rounded()))% rain", systemImage: "drop")
                        Spacer()
                        Link(destination: forecast.attribution.legalPageURL) {
                            AsyncImage(url: scheme == .dark ? forecast.attribution.combinedMarkLightURL : forecast.attribution.combinedMarkDarkURL) { image in image.resizable().scaledToFit() } placeholder: { Text("Apple Weather") }.frame(width: 82, height: 14)
                        }.accessibilityLabel("Apple Weather attribution")
                    }.font(.caption2).foregroundStyle(.secondary)
                    if weather.precipitationChance >= 0.5 {
                        Button("Plan an indoor alternative", systemImage: "sparkles") {
                            store.concierge.selectedTripID = tripID
                            store.concierge.reference = "Apple Weather forecast fetched \(forecast.fetchedAt.formatted()): \(city), \(day ?? ""), \(weather.condition.description), rain chance \(Int(weather.precipitationChance * 100))%. Forecasts can change."
                            store.concierge.pendingInput = "Suggest an indoor alternative in \(city) for \(day ?? "this day") based on this weather forecast."
                            store.selectedTab = 4
                        }.font(.caption)
                    }
                } else if loading { HStack { ProgressView().controlSize(.mini); Text("Checking weather…").font(.caption2).foregroundStyle(.secondary) } }
                else if let error { HStack { Text(error).font(.caption2).foregroundStyle(.secondary); Button("Retry") { Task { await load() } }.font(.caption2) } }
                else if day == nil { Text("Choose dates to see the forecast").font(.caption2).foregroundStyle(.secondary) }
                else if let day, day >= TravelDay.key(.now) { Text("Forecast available closer to your trip").font(.caption2).foregroundStyle(.secondary) }
            }.task(id: city + (day ?? "")) { await load() }
        }
    }
    private func load() async {
        guard DestinationWeatherService.canForecast(day: day) else { return }
        loading = true; error = nil
        defer { loading = false }
        do { forecast = try await DestinationWeatherService.shared.forecast(city: city, latitude: latitude, longitude: longitude) }
        catch { self.error = "Weather unavailable right now." }
    }
}
