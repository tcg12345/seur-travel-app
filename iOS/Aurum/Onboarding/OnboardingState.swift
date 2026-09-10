import Foundation
import Observation

struct TravelerProfile: Codable, Equatable {
    var completed = false
    var step = 0
    var interests: Set<String> = []
    var cuisines: Set<String> = []
    var destination = ""
    var previewPlan: PreviewPlan?
    var hasPreferences: Bool { !interests.isEmpty || !cuisines.isEmpty || !destination.isEmpty }
}

enum PreviewPlan: String, Codable, CaseIterable, Identifiable {
    case annual, monthly
    var id: String { rawValue }
    var title: String { self == .annual ? "Annual" : "Monthly" }
    var price: String { self == .annual ? "$79.99" : "$9.99" }
    var interval: String { self == .annual ? "per year" : "per month" }
    var detail: String { self == .annual ? "Equivalent to $6.67 / month" : "A month at a time" }
}

@Observable final class OnboardingStore {
    static let key = "aurum.travelerProfile.v1"
    static let interests = ["Exceptional stays", "Memorable dining", "Art & culture", "Rest & relaxation"]
    static let cuisines = ["French", "Japanese", "Italian", "Thai", "Chinese", "Indian"]
    private let defaults: UserDefaults
    private(set) var profile: TravelerProfile
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), var saved = try? JSONDecoder().decode(TravelerProfile.self, from: data) {
            saved.step = min(max(saved.step, 0), 6)
            saved.interests.formIntersection(Self.interests)
            saved.cuisines.formIntersection(Self.cuisines)
            if !TravelStore.cities.contains(saved.destination) { saved.destination = "" }
            profile = saved
        } else { profile = TravelerProfile() }
    }
    func move(to step: Int) { profile.step = min(max(step, 0), 6); save() }
    func toggleInterest(_ value: String) {
        guard Self.interests.contains(value) else { return }
        if !profile.interests.insert(value).inserted { profile.interests.remove(value) }
        save()
    }
    func toggleCuisine(_ value: String) {
        guard Self.cuisines.contains(value) else { return }
        if !profile.cuisines.insert(value).inserted { profile.cuisines.remove(value) }
        save()
    }
    func chooseDestination(_ value: String) {
        guard value.isEmpty || TravelStore.cities.contains(value) else { return }
        profile.destination = value; save()
    }
    func selectPreview(_ plan: PreviewPlan?) { profile.previewPlan = plan; save() }
    func complete() { profile.completed = true; profile.step = 6; save() }
    private func save() { if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: Self.key) } }
}
