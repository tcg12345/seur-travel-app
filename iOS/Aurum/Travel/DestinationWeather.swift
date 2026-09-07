import SwiftUI
import WeatherKit
import MapKit

enum WeatherPreferences {
    static let key = "seur.weather.enabled"
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
}

enum WeatherDisplay {
    static func temperature(_ value: Measurement<UnitTemperature>, locale: Locale = .current) -> String {
        value.formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }
}

struct WeatherSettingsToggle: View {
    @AppStorage(WeatherPreferences.key) private var weatherEnabled = true
    var body: some View {
        Toggle(isOn: $weatherEnabled) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Trip weather", systemImage: "cloud.sun")
                Text("Show daily forecasts and rain-aware suggestions in your trips.").font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("settings-trip-weather")
            .onChange(of: weatherEnabled) { if !weatherEnabled { DestinationWeatherService.shared.clear() } }
    }
}

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
    func clear() {
        pending.values.forEach { $0.cancel() }; pending = [:]; cache = [:]
    }
    func forecast(city: String, latitude: Double?, longitude: Double?) async throws -> DestinationForecast {
        guard WeatherPreferences.isEnabled() else { throw JourneyError.message("Trip weather is turned off.") }
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
            try Task.checkCancellation()
            guard WeatherPreferences.isEnabled() else { throw CancellationError() }
            let forecast = try await WeatherService.shared.weather(for: location, including: .daily)
            try Task.checkCancellation()
            let attribution = try await WeatherService.shared.attribution
            return DestinationForecast(days: Array(forecast), zone: zone, attribution: attribution, fetchedAt: .now)
        }
        pending[key] = task
        defer { pending[key] = nil }
        let value = try await task.value
        if cache.count >= 30 { cache.removeAll() }
        try Task.checkCancellation()
        guard WeatherPreferences.isEnabled() else { throw CancellationError() }
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
    @AppStorage(WeatherPreferences.key) private var weatherEnabled = true
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
        if weatherEnabled && !FlightNotifications.testing {
            VStack(alignment: .leading, spacing: 8) {
                if let weather, let forecast {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: weather.symbolName).symbolRenderingMode(.multicolor)
                            .font(.system(size: 24, weight: .medium)).frame(width: 30).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(weather.condition.description).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                            Label("\(Int((weather.precipitationChance * 100).rounded()))% chance of rain", systemImage: "drop")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("High").font(.caption).foregroundStyle(.secondary)
                                Text(WeatherDisplay.temperature(weather.highTemperature)).font(.headline).foregroundStyle(Color.bronze)
                            }.accessibilityElement(children: .combine)
                            HStack(spacing: 6) {
                                Text("Low").font(.caption).foregroundStyle(.secondary)
                                Text(WeatherDisplay.temperature(weather.lowTemperature)).font(.headline).foregroundStyle(FlightDisplay.blue)
                            }.accessibilityElement(children: .combine)
                        }.monospacedDigit().fixedSize()
                    }
                    HStack {
                        Spacer()
                        Link(destination: forecast.attribution.legalPageURL) {
                            AsyncImage(url: scheme == .dark ? forecast.attribution.combinedMarkLightURL : forecast.attribution.combinedMarkDarkURL) { image in
                                image.renderingMode(.template).resizable().scaledToFit()
                            } placeholder: { Text("Apple Weather").font(.caption2) }
                                .foregroundStyle(.secondary).frame(width: 72, height: 12).padding(.vertical, 6)
                        }.buttonStyle(.plain).accessibilityLabel("Apple Weather data sources")
                    }
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
            }.padding(.leading, 12).padding(.vertical, 6)
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(FlightDisplay.blue.opacity(0.4)).frame(width: 2).padding(.vertical, 6) }
                .task(id: city + (day ?? "")) { await load() }
        }
    }
    private func load() async {
        guard weatherEnabled, DestinationWeatherService.canForecast(day: day) else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let value = try await DestinationWeatherService.shared.forecast(city: city, latitude: latitude, longitude: longitude)
            guard !Task.isCancelled, weatherEnabled else { return }
            forecast = value
        } catch { if !Task.isCancelled, weatherEnabled { self.error = "Weather unavailable right now." } }
    }
}
