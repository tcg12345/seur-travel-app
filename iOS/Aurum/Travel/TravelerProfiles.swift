import SwiftUI
import UIKit

struct SavedTravelerProfile: Codable, Identifiable, Hashable {
    var id = UUID().uuidString.lowercased()
    var version = 0
    var isDefault = false
    var firstName = ""
    var lastName = ""
    var email = ""
    var phone = ""
    var nationality = ""
    var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
    var countryName: String { Locale.current.localizedString(forRegionCode: nationality) ?? nationality }
    var guest: HotelCheckoutGuest { .init(firstName: firstName, lastName: lastName, email: email, phone: phone) }
    var valid: Bool { guest.valid && TravelerNationality.codes.contains(nationality) }
    func canUse(for criteria: HotelRateCriteria) -> Bool { valid && nationality == criteria.guestNationality }
}
struct TravelerProfileList: Codable { var profiles: [SavedTravelerProfile] }
struct TravelerProfileWrite: Encodable {
    var expectedVersion: Int; var isDefault: Bool; var firstName: String; var lastName: String; var email: String; var phone: String; var nationality: String
    init(_ p: SavedTravelerProfile) { expectedVersion = p.version; isDefault = p.isDefault; firstName = p.firstName; lastName = p.lastName; email = p.email; phone = p.phone; nationality = p.nationality }
}
@MainActor @Observable final class TravelerProfilesStore {
    private(set) var profiles: [SavedTravelerProfile] = []
    var loading = false
    var error: String?
    private var generation = UUID()
    var defaultProfile: SavedTravelerProfile? { profiles.first(where: \.isDefault) }
    func clear() { generation = UUID(); profiles = []; loading = false; error = nil }
    func replace(_ values: [SavedTravelerProfile]) { generation = UUID(); profiles = values; loading = false; error = nil }
    func load(using fetch: () async throws -> TravelerProfileList) async {
        let request = UUID(); generation = request; loading = true; error = nil
        defer { if generation == request { loading = false } }
        do {
            let result = try await fetch(); try Task.checkCancellation()
            guard request == generation else { return }; profiles = result.profiles
        } catch { if request == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
enum TravelerNationality {
    static let codes = "AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW".split(separator: " ").map(String.init)
}
struct TravelerProfilesPage: View {
    var onSelect: ((SavedTravelerProfile) -> Void)? = nil
    var requiredNationality: String? = nil
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var editing: SavedTravelerProfile?
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: onSelect == nil ? "Saved travelers" : "Choose a traveler")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Save details once for quicker booking. Use names as they appear on ID.").font(.subheadline).foregroundStyle(.secondary)
                    if api.travelers.loading { ProgressView("Loading travelers…") }
                    if let error = api.travelers.error { HotelRetry(message: error) { Task { await api.loadTravelers() } } }
                    if api.travelers.profiles.isEmpty && !api.travelers.loading && api.travelers.error == nil { ContentUnavailableView("Your travel companions", systemImage: "person.crop.rectangle.stack", description: Text("Add yourself or someone you book for.")) }
                    ForEach(api.travelers.profiles) { profile in
                        HStack(spacing: 16) {
                            Button {
                                if let onSelect { onSelect(profile); dismiss() } else { editing = profile }
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack { Text(profile.name).font(.headline); if profile.isDefault { Text("Default").font(.caption).foregroundStyle(.secondary) } }
                                    Text(profile.countryName).font(.subheadline).foregroundStyle(.secondary)
                                    if let requiredNationality, requiredNationality != profile.nationality { Text("Refresh prices with this traveler’s nationality first.").font(.caption).foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                            }.buttonStyle(StayPressStyle()).tint(.primary).disabled(onSelect != nil && requiredNationality != nil && requiredNationality != profile.nationality).accessibilityIdentifier("traveler-select-" + profile.id)
                            if onSelect != nil { Button { editing = profile } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }.tint(.primary).accessibilityLabel("Edit " + profile.name) }
                            else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true) }
                        }.padding(18).background(StayStyle.surface, in: .rect(cornerRadius: 18))
                    }
                }.padding(22)
            }.refreshable { await api.loadTravelers() }
        }.background(StayStyle.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { StayBottomBar { StayPrimaryButton(title: "Add traveler") { editing = SavedTravelerProfile(isDefault: api.travelers.profiles.isEmpty) }.disabled(api.travelers.profiles.count >= 20).accessibilityIdentifier("traveler-add") } }
            .navigationDestination(item: $editing) { profile in TravelerProfileEditor(profile: profile).hotelFlowPage() }
            .task { await api.loadTravelers() }
            .onChange(of: api.account?.id) { dismiss() }
            .onChange(of: api.baseURL) { dismiss() }
            .sensoryFeedback(.selection, trigger: editing?.id)
    }
}
struct TravelerProfileEditor: View {
    @State var profile: SavedTravelerProfile
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var nationality = false
    @State private var deleting = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case first, last, email, phone }
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: profile.version == 0 ? "New traveler" : "Edit traveler")
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 16) {
                        TextField("First name", text: $profile.firstName).textContentType(.givenName).focused($focus, equals: .first).submitLabel(.next).onSubmit { focus = .last }.accessibilityIdentifier("traveler-first")
                        Divider()
                        TextField("Last name", text: $profile.lastName).textContentType(.familyName).focused($focus, equals: .last).submitLabel(.next).onSubmit { focus = .email }.accessibilityIdentifier("traveler-last")
                        Divider()
                        TextField("Email", text: $profile.email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus, equals: .email).submitLabel(.next).onSubmit { focus = .phone }.accessibilityIdentifier("traveler-email")
                        Divider()
                        TextField("Phone · +12125550123", text: $profile.phone).textContentType(.telephoneNumber).keyboardType(.phonePad).focused($focus, equals: .phone).accessibilityIdentifier("traveler-phone")
                    }.padding(20).background(StayStyle.surface, in: .rect(cornerRadius: 18))
                    Button { focus = nil; nationality = true } label: {
                        HStack { VStack(alignment: .leading, spacing: 6) { Text("Nationality").font(.caption).foregroundStyle(.secondary); Text(profile.nationality.isEmpty ? "Choose nationality" : profile.countryName).font(.subheadline.weight(.medium)) }; Spacer(); Image(systemName: "chevron.right").font(.caption) }.frame(minHeight: 44)
                    }.tint(.primary).accessibilityIdentifier("traveler-nationality")
                    Text("Nationality can affect hotel rates. We’ll use it when checking prices.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Default traveler", isOn: $profile.isDefault).tint(.primary).disabled(api.travelers.profiles.first(where: { $0.id == profile.id })?.isDefault == true).accessibilityIdentifier("traveler-default")
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("traveler-error") }
                    if profile.version > 0 { Button("Delete traveler", role: .destructive) { deleting = true }.disabled(busy).accessibilityIdentifier("traveler-delete") }
                    Text("Saved to your private account. Updating or deleting a profile won’t change an existing booking.").font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }.scrollDismissesKeyboard(.interactively)
        }.background(StayStyle.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { StayBottomBar { StayPrimaryButton(title: busy ? "Saving…" : "Save traveler") { save() }.disabled(busy || !profile.valid).accessibilityIdentifier("traveler-save") } }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focus = nil } } }
            .navigationDestination(isPresented: $nationality) { TravelerNationalityPage(selection: $profile.nationality).hotelFlowPage() }
            .confirmationDialog("Delete this saved traveler?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete traveler", role: .destructive) { remove() } } message: { Text("Existing bookings will remain unchanged.") }
            .onChange(of: api.account?.id) { dismiss() }.onChange(of: api.baseURL) { dismiss() }
            .sensoryFeedback(.selection, trigger: nationality).sensoryFeedback(.error, trigger: error)
    }
    private func save() { busy = true; error = nil; focus = nil; Task { defer { busy = false }; do { try await api.saveTraveler(profile); UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() } catch { self.error = error.localizedDescription } } }
    private func remove() { busy = true; error = nil; Task { defer { busy = false }; do { try await api.deleteTraveler(profile); UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() } catch { self.error = error.localizedDescription } } }
}
struct TravelerNationalityPage: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var countries: [(code: String, name: String)] { TravelerNationality.codes.map { ($0, Locale.current.localizedString(forRegionCode: $0) ?? $0) }.filter { query.isEmpty || $0.1.localizedCaseInsensitiveContains(query) || $0.0.caseInsensitiveCompare(query) == .orderedSame }.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending } }
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: "Nationality")
            TextField("Search countries", text: $query).autocorrectionDisabled().padding(16).background(StayStyle.surface, in: .rect(cornerRadius: 16)).padding(.horizontal, 22).accessibilityIdentifier("traveler-country-query")
            List(countries, id: \.code) { country in Button { selection = country.code; dismiss() } label: { HStack { Text(country.name); Spacer(); if selection == country.code { Image(systemName: "checkmark") } }.frame(minHeight: 44) }.tint(.primary).accessibilityIdentifier("traveler-country-" + country.code) }.listStyle(.plain)
        }.background(StayStyle.background)
    }
}
#if DEBUG
@MainActor enum TravelerFixtures {
    static var profiles: [SavedTravelerProfile] = []
    static func save(_ profile: SavedTravelerProfile) -> TravelerProfileList {
        var value = profile; value.version += 1
        if profiles.isEmpty { value.isDefault = true }
        if value.isDefault { for i in profiles.indices where profiles[i].id != value.id && profiles[i].isDefault { profiles[i].isDefault = false; profiles[i].version += 1 } }
        profiles.removeAll { $0.id == value.id }; profiles.append(value)
        profiles.sort { $0.isDefault && !$1.isDefault }; return .init(profiles: profiles)
    }
    static func delete(_ profile: SavedTravelerProfile) -> TravelerProfileList {
        profiles.removeAll { $0.id == profile.id }
        if !profiles.isEmpty && !profiles.contains(where: \.isDefault) { profiles[0].isDefault = true; profiles[0].version += 1 }
        return .init(profiles: profiles)
    }
}
#endif
