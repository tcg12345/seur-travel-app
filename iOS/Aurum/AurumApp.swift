import SwiftUI

@main struct AurumApp: App {
    @UIApplicationDelegateAdaptor(SeurNotificationDelegate.self) private var notificationsDelegate
    @AppStorage("aurum.appearance") private var appearance = "System"
    @State private var library = JourneyLibrary()
    @State private var api = TravelAPI()
    @State private var store: TravelStore
    @State private var onboarding: OnboardingStore
    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let defaults = UserDefaults(suiteName: "com.aurum.travel.uitests")!
            if !ProcessInfo.processInfo.arguments.contains("--preserve-state") { defaults.removePersistentDomain(forName: "com.aurum.travel.uitests") }
            _store = State(initialValue: TravelStore(defaults: defaults))
            _onboarding = State(initialValue: OnboardingStore(defaults: defaults))
        } else { _store = State(initialValue: TravelStore()); _onboarding = State(initialValue: OnboardingStore()) }
    }
    var body: some Scene {
        WindowGroup { AppEntryView().environment(onboarding).environment(store).environment(library).environment(api).tint(.bronze).preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light)
            .task {
                #if DEBUG
                await AppleFeatureCheck.run()
                #endif
            }
        }
    }
}

struct RootView: View {
    @Environment(TravelAPI.self) private var api
    @Environment(TravelStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            Tab("Discover", systemImage: "safari", value: 0) { NavigationStack { DiscoverView() } }
            // Reset nested map navigation only for an explicit city-guide handoff.
            // Normal tab/section switching keeps the same map instance.
            Tab("Map", systemImage: "globe.europe.africa", value: 1) { NavigationStack { WorldMapView(request: store.cityMapRequest) }.id(store.cityMapRequest?.id) }
            Tab("Travel", systemImage: "suitcase.rolling", value: 2) { NavigationStack { TravelHubView() } }
            Tab("Friends", systemImage: "person.2", value: 5) { NavigationStack { FriendsHubView() } }
            Tab("Concierge", systemImage: "sparkles", value: 4) { NavigationStack { ConciergeView() } }
        }
        .tabBarMinimizeBehavior(.never)
        .sheet(isPresented: $store.searchPresented) {
            NavigationStack { SearchView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { store.searchPresented = false } } } }
                .presentationDetents([.large])
        }
        .task { try? await api.refresh() }
        .task(id: api.account?.id) { await FlightNotifications.shared.restore(api: api) }
        .task(id: FlightNotifications.shared.deviceToken) { await FlightNotifications.shared.syncDeviceToken(api: api) }
        .onOpenURL { url in if url.scheme == "seur" && url.host == "flights" { FlightNotifications.shared.openFlights = true; store.selectedTab = 1 } }
        .onChange(of: FlightNotifications.shared.openFlights) { if FlightNotifications.shared.openFlights { store.selectedTab = 1 } }
        .overlay(alignment: .top) {
            if let message = store.message {
                Label(message, systemImage: "checkmark.circle.fill").font(.subheadline)
                    .padding(16).glassEffect(.regular, in: .rect(cornerRadius: 22)).padding(.horizontal, 20).padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("toast").allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: store.message)
    }
}
