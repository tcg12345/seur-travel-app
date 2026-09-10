import ActivityKit
import SwiftUI
import UserNotifications

struct FlightWatch: Codable, Identifiable {
    var id: String
    var flight_id: String
    var activity_id: String?
}
struct FlightWatchReply: Codable { var id: String }

final class SeurNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let value = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            FlightNotifications.shared.deviceToken = value
            #if DEBUG
            AppleFeatureCheck.record("deviceToken", value)
            #endif
        }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in FlightNotifications.shared.error = "This device couldn’t register for flight notifications. Check your connection and try again." }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { FlightNotifications.shared.openFlights = true }
    }
}

#if DEBUG
/// Opt-in terminal diagnostics on a developer-owned device. Never runs in normal use.
@MainActor enum AppleFeatureCheck {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--apple-service-check") }
    private static var values: [String: Any] = [:]
    static func record(_ key: String, _ value: Any) {
        guard enabled else { return }
        values[key] = value
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("seur-apple-check.json")
        if let bytes = try? JSONSerialization.data(withJSONObject: values) { try? bytes.write(to: path, options: [.atomic, .completeFileProtection]) }
    }
    static func run() async {
        if ProcessInfo.processInfo.arguments.contains("--apple-service-cleanup") {
            for activity in Activity<FlightActivityAttributes>.activities where activity.attributes.watchID == "seur-service-check" { await activity.end(nil, dismissalPolicy: .immediate) }
            let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("seur-apple-check.json")
            try? FileManager.default.removeItem(at: path)
            return
        }
        guard enabled else { return }
        for activity in Activity<FlightActivityAttributes>.activities where activity.attributes.watchID == "seur-service-check" { await activity.end(nil, dismissalPolicy: .immediate) }
        record("bundleID", Bundle.main.bundleIdentifier ?? "")
        let settings = await UNUserNotificationCenter.current().notificationSettings(); record("notificationAuthorization", settings.authorizationStatus.rawValue)
        UIApplication.shared.registerForRemoteNotifications()
        do {
            let now = Date.now.timeIntervalSince1970
            let state = FlightActivityAttributes.ContentState(status: "Connection test", departure: now + 3600, arrival: now + 7200, departureTime: "10:00", arrivalTime: "12:00", gate: "—", terminal: "", delayMinutes: 0, phase: "scheduled", updatedAt: now)
            let activity = try Activity.request(attributes: FlightActivityAttributes(watchID: "seur-service-check", flightNumber: "SEUR TEST", origin: "JFK", destination: "LHR"), content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(300)), pushType: .token)
            record("activityID", activity.id)
            Task { for await token in activity.pushTokenUpdates { record("activityToken", token.map { String(format: "%02x", $0) }.joined()); break } }
        } catch { record("activityError", error.localizedDescription) }
        do {
            let forecast = try await DestinationWeatherService.shared.forecast(city: "New York", latitude: 40.7128, longitude: -74.0060)
            record("weatherDays", forecast.days.count); record("weatherAttribution", forecast.attribution.serviceName)
        } catch { record("weatherError", error.localizedDescription) }
    }
}
#endif

@MainActor @Observable final class FlightNotifications {
    static let shared = FlightNotifications()
    var deviceToken: String?
    var error: String?
    var openFlights = false
    private(set) var followed: [FlightWatch] = []
    private var tokenTasks: [String: Task<Void, Never>] = [:]
    private var owner: String?
    let installationID: String
    static var testing: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
    static var environment: String { Bundle.main.object(forInfoDictionaryKey: "APNSEnvironment") as? String == "production" ? "production" : "sandbox" }
    private init() {
        let existing = UserDefaults.standard.string(forKey: "seur.push.installation")
        installationID = existing ?? UUID().uuidString.lowercased()
        if existing == nil { UserDefaults.standard.set(installationID, forKey: "seur.push.installation") }
    }
    func watch(for flight: FlightSnapshot?) -> FlightWatch? { followed.first { $0.flight_id == flight?.id } }
    func restore(api: TravelAPI) async {
        guard !Self.testing else { return }
        if owner != api.account?.id { followed = []; tokenTasks.values.forEach { $0.cancel() }; tokenTasks = [:]; owner = api.account?.id }
        guard api.isSignedIn else { return }
        do {
            followed = try await api.flightWatches(installationID)
            await syncDeviceToken(api: api)
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional { UIApplication.shared.registerForRemoteNotifications() }
            for activity in Activity<FlightActivityAttributes>.activities where followed.contains(where: { $0.id == activity.attributes.watchID }) { observe(activity, api: api) }
        } catch { self.error = error.localizedDescription }
    }
    func syncDeviceToken(api: TravelAPI) async {
        guard !Self.testing, api.isSignedIn, let deviceToken else { return }
        for watch in followed {
            do {
                _ = try await api.followFlight(["id": watch.id, "installationID": installationID, "deviceToken": deviceToken, "environment": Self.environment], update: true)
            } catch { self.error = "Couldn’t refresh flight alerts on this device. " + error.localizedDescription }
        }
    }
    private func registration() async throws -> String {
        guard !Self.testing else { throw JourneyError.message("Live push registration is disabled during automated tests.") }
        let permitted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        guard permitted else { throw JourneyError.message("Allow notifications for Seur in iPhone Settings to receive flight alerts.") }
        error = nil; UIApplication.shared.registerForRemoteNotifications()
        for _ in 0..<100 {
            if let deviceToken { return deviceToken }
            if let error { throw JourneyError.message(error) }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw JourneyError.message("Still waiting for Apple to register this device. Try again shortly.")
    }
    func follow(_ flight: FlightSnapshot, day: String, api: TravelAPI) async throws {
        let device = try await registration()
        let reply = try await api.followFlight(["installationID": installationID, "deviceToken": device, "environment": Self.environment, "flightID": flight.id, "ident": flight.ident, "day": day])
        followed.removeAll { $0.flight_id == flight.id }; followed.append(FlightWatch(id: reply.id, flight_id: flight.id))
    }
    func startActivity(_ flight: FlightSnapshot, api: TravelAPI) async throws {
        guard let watch = watch(for: flight) else { throw JourneyError.message("Follow this flight first.") }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw JourneyError.message("Enable Live Activities for Seur in iPhone Settings.") }
        guard !Activity<FlightActivityAttributes>.activities.contains(where: { $0.attributes.watchID == watch.id }) else { return }
        let departure = FlightSnapshot.date(flight.estimatedOut ?? flight.scheduledOut) ?? .now
        guard departure.timeIntervalSinceNow < 8 * 3600 else { throw JourneyError.message("Start the Live Activity within eight hours of departure. Flight alerts are already enabled.") }
        let state = Self.state(flight)
        let activity = try Activity.request(attributes: FlightActivityAttributes(watchID: watch.id, flightNumber: flight.ident, origin: flight.origin, destination: flight.destination), content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(20 * 60)), pushType: .token)
        observe(activity, api: api)
    }
    private func observe(_ activity: Activity<FlightActivityAttributes>, api: TravelAPI) {
        guard tokenTasks[activity.id] == nil else { return }
        tokenTasks[activity.id] = Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                guard let self, !Task.isCancelled else { return }
                do {
                    let device = try await registration()
                    _ = try await api.followFlight(["id": activity.attributes.watchID, "installationID": installationID, "deviceToken": device, "environment": Self.environment, "activityToken": token.map { String(format: "%02x", $0) }.joined(), "activityID": activity.id], update: true)
                } catch { self.error = "Live Activity is showing its last update. " + error.localizedDescription }
            }
        }
    }
    func stop(_ watch: FlightWatch, api: TravelAPI) async throws {
        try await api.stopFlightNotifications(installationID, id: watch.id)
        for activity in Activity<FlightActivityAttributes>.activities where activity.attributes.watchID == watch.id {
            tokenTasks.removeValue(forKey: activity.id)?.cancel(); await activity.end(nil, dismissalPolicy: .immediate)
        }
        followed.removeAll { $0.id == watch.id }
    }
    func clearLocalActivities() async {
        guard !Self.testing else { return }
        tokenTasks.values.forEach { $0.cancel() }; tokenTasks = [:]
        for activity in Activity<FlightActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        followed = []; owner = nil
    }
    static func state(_ flight: FlightSnapshot, now: Date = .now) -> FlightActivityAttributes.ContentState {
        let departure = flight.actualOut ?? flight.estimatedOut ?? flight.scheduledOut, arrival = flight.actualIn ?? flight.estimatedIn ?? flight.scheduledIn
        return .init(status: flight.status, departure: FlightSnapshot.date(departure)?.timeIntervalSince1970 ?? 0, arrival: FlightSnapshot.date(arrival)?.timeIntervalSince1970 ?? 0,
                     departureTime: FlightDisplay.clock(departure, zone: flight.originZone), arrivalTime: FlightDisplay.clock(arrival, zone: flight.destinationZone), gate: flight.gateOrigin ?? "", terminal: flight.terminalOrigin ?? "", delayMinutes: max(0, Int(((flight.departureDelay ?? 0) / 60).rounded())), phase: flight.cancelled ? "cancelled" : flight.actualIn != nil ? "arrived" : flight.actualOut != nil ? "departed" : "scheduled", updatedAt: now.timeIntervalSince1970)
    }
}

struct FlightNotificationControls: View {
    @Environment(TravelAPI.self) private var api
    let flight: FlightSnapshot?
    let day: String
    @State private var busy = false
    private var notifications: FlightNotifications { .shared }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let watch = notifications.watch(for: flight), let flight {
                HStack { Label("Flight alerts on", systemImage: "bell.badge"); Spacer(); Button("Turn off") { run { try await notifications.stop(watch, api: api) } } }.font(.subheadline)
                Button("Show on Lock Screen", systemImage: "rectangle.inset.filled") { run { try await notifications.startActivity(flight, api: api) } }.font(.subheadline)
            } else {
                Button("Follow flight", systemImage: "bell") { if let flight { run { try await notifications.follow(flight, day: day, api: api) } } }.font(.subheadline).disabled(flight == nil || !api.isSignedIn)
                Text(api.isSignedIn ? "Get gate changes, delays and a departure reminder. Choose a live departure above to begin." : "Sign in to enable flight alerts.").font(.caption).foregroundStyle(.secondary)
            }
            if busy { ProgressView().controlSize(.small) }
            if let error = notifications.error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }.disabled(busy).padding(.vertical, 14).task { await notifications.restore(api: api) }
    }
    private func run(_ action: @escaping () async throws -> Void) {
        busy = true; notifications.error = nil
        Task { defer { busy = false }; do { try await action() } catch { notifications.error = error.localizedDescription } }
    }
}


/// Permission alone does not follow flights or subscribe the traveler to alerts.
@MainActor @Observable final class OnboardingNotificationPermission {
    private(set) var status: UNAuthorizationStatus?
    private(set) var busy = false
    private(set) var error: String?
    private let readStatus: () async -> UNAuthorizationStatus
    private let request: () async throws -> Bool
    private let register: @MainActor () -> Void
    var isAllowed: Bool { status == .authorized || status == .provisional || status == .ephemeral }
    init(
        readStatus: @escaping () async -> UNAuthorizationStatus = { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
        request: @escaping () async throws -> Bool = { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) },
        register: @escaping @MainActor () -> Void = { if !FlightNotifications.testing { UIApplication.shared.registerForRemoteNotifications() } }
    ) {
        self.readStatus = readStatus; self.request = request; self.register = register
    }
    func requestOnArrival() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        status = await readStatus()
        guard !Task.isCancelled else { return }
        if status == .notDetermined {
            do { _ = try await request(); status = await readStatus() }
            catch { self.error = "Permission couldn’t be requested. Try again, or continue without notifications." }
        }
        if isAllowed { register() }
    }
    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        status = await readStatus()
        if isAllowed { error = nil; register() }
    }
}
