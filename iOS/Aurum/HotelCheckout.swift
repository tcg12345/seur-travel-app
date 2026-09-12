import SwiftUI

struct HotelCheckoutGuest: Codable {
    var firstName = ""
    var lastName = ""
    var email = ""
    var phone = ""
    var valid: Bool {
        let names = [firstName, lastName].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 80 && $0.rangeOfCharacter(from: .controlCharacters) == nil && !$0.contains("<") && !$0.contains(">") }
        return names && email.count <= 254 && email.trimmingCharacters(in: .whitespaces).range(of: #"^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$"#, options: .regularExpression) != nil && phone.trimmingCharacters(in: .whitespaces).range(of: #"^\+[1-9][0-9]{6,14}$"#, options: .regularExpression) != nil
    }
}
struct HotelBookingReceipt: Codable { var id: String; var confirmationCode: String?; var hotelName: String; var confirmedAt: String }
struct HotelCancellationRequestState: Codable {
    var state: String
    var version: String
    var expiresAt: String
    var checkedAt: String
    var message: String? = nil
    var pending: Bool { ["queued", "submitting", "pending"].contains(state) }
    var canConfirm: Bool { state == "review" && (HotelRateClock.date(expiresAt) ?? .distantPast) > .now }
}
struct HotelCheckout: Codable, Identifiable {
    var id: String
    var state: String
    var environment: String
    var paymentState: String
    var quoteVersion: String
    var review: HotelQuoteReview
    var expiresAt: String
    var booking: HotelBookingReceipt?
    var createdAt: String
    var cancellation: HotelCancellationRequestState? = nil
    var expired: Bool { state == "expired" || (state == "review" && (HotelRateClock.date(expiresAt) ?? .distantPast) <= .now) }
    var confirming: Bool { ["queued", "submitting", "pending_confirmation"].contains(state) }
    var canPoll: Bool { confirming || state == "prebooking" }
    var confirmed: Bool { state == "confirmed" && booking != nil && environment == "sandbox" && paymentState == "test_no_charge" }
    var cancelled: Bool { state == "cancelled" && environment == "sandbox" && ["CANCELLED", "CANCELLED_WITH_CHARGES"].contains(review.providerStatus ?? "") && review.providerCheckedAt.flatMap(HotelRateClock.date) != nil }
    var title: String {
        if cancellation?.pending == true { return "Cancelling test booking" }
        if cancellation?.state == "needs_support" { return "Cancellation needs attention" }
        if confirmed { return "Test booking confirmed" }
        if cancelled { return "Test booking cancelled" }
        if expired { return "Price expired" }
        switch state {
        case "review": return "Review your stay"
        case "prebooking": return "Checking your room"
        case "queued", "submitting", "pending_confirmation": return "Confirming your test stay"
        case "prebook_unknown": return "Room check interrupted"
        default: return "Confirmation needs attention"
        }
    }
}
struct HotelCheckoutList: Decodable { var checkouts: [HotelCheckout]; var nextCursor: String? = nil }
struct HotelCheckoutRequest: Encodable { var id: String; var quote: String; var guest: HotelCheckoutGuest; var hotelName: String }

struct HotelCheckoutFlow: View {
    var hotelName: String
    var original: HotelQuoteReview? = nil
    var restored: HotelCheckout? = nil
    var preferredTravelerID: String? = nil
    @State private var travelerPicker = false
    @State private var appliedTraveler = false
    @State private var travelerMessage: String?
    @State private var travelerNeedsReprice = false
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.scenePhase) private var scene
    @State private var bookingDetails = false
    @State private var guest = HotelCheckoutGuest()
    @State private var requestID = UUID().uuidString.lowercased()
    @State private var checkout: HotelCheckout?
    @State private var busy = false
    @State private var error: String?
    @FocusState private var field: Field?
    private enum Field: Hashable { case first, last, email, phone }
    private var current: HotelCheckout? { checkout ?? restored }
    private var phase: String { current?.state ?? "guest" }
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: current?.title ?? "Guest details")
            HStack(spacing: 5) {
                ForEach(0..<3) { step in Capsule().fill(step <= (current == nil ? 0 : current?.state == "review" ? 1 : 2) ? Color.primary : Color.primary.opacity(0.1)).frame(height: 3) }
            }.padding(.horizontal, 22).padding(.vertical, 12).accessibilityHidden(true)
            Group {
                if let value = current {
                    if value.state == "review" && !value.expired { review(value) }
                    else { status(value) }
                } else { guestForm }
            }.id(phase).transition(.opacity.combined(with: .offset(y: reduce ? 0 : 8)))
            if let error { Text(error).font(.subheadline).foregroundStyle(.red).padding(.horizontal, 22).padding(.vertical, 8).accessibilityIdentifier("hotel-checkout-error") }
            if current == nil {
                StayPrimaryButton(title: busy ? "Checking your room…" : "Review test stay") { create() }
                    .disabled(!guest.valid || busy || travelerNeedsReprice).opacity(guest.valid ? 1 : 0.4).padding(22).accessibilityIdentifier("hotel-checkout-review")
            }
        }.background(StayStyle.background).animation(StayStyle.motion(reduce), value: phase)
            .sensoryFeedback(.selection, trigger: phase)
            .sensoryFeedback(.success, trigger: current?.confirmed == true)
            .sensoryFeedback(.error, trigger: error)
            .task(id: (current?.id ?? "") + phase + (scene == .active ? "active" : "inactive")) { await poll() }
            .onChange(of: api.account?.id) { dismiss() }
            .onChange(of: api.baseURL) { dismiss() }
            .navigationDestination(isPresented: $bookingDetails) { if let value = current { HotelBookingRecordView(initial: value).hotelFlowPage() } }
            .sensoryFeedback(.selection, trigger: travelerPicker)
            .navigationDestination(isPresented: $travelerPicker) {
                TravelerProfilesPage(onSelect: { useTraveler($0) }, requiredNationality: original?.criteria.guestNationality).hotelFlowPage()
            }
            .task {
                guard current == nil, !appliedTraveler else { return }
                await api.loadTravelers()
                guard !appliedTraveler, guest.firstName.isEmpty, guest.lastName.isEmpty, guest.email.isEmpty, guest.phone.isEmpty else { return }
                let profile = preferredTravelerID.flatMap { id in api.travelers.profiles.first { $0.id == id } } ?? (preferredTravelerID == nil ? api.travelers.defaultProfile : nil)
                if let profile { useTraveler(profile) }
            }
    }
    private func useTraveler(_ profile: SavedTravelerProfile) {
        guard let criteria = original?.criteria, profile.canUse(for: criteria) else {
            travelerNeedsReprice = true; travelerMessage = "This traveler has a different nationality. Return to guests, choose the traveler and refresh room prices first."; return
        }
        guest = profile.guest; appliedTraveler = true; travelerNeedsReprice = false; travelerMessage = "Details filled from " + profile.name + ". You can edit them for this booking."
    }
    private var guestForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) { Text(hotelName).font(.headline); Text("Lead guest · One room").font(.subheadline).foregroundStyle(.secondary) }
                Button { travelerPicker = true } label: { Label("Use a saved traveler", systemImage: "person.crop.rectangle.stack").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading).padding(16).background(StayStyle.surface, in: .rect(cornerRadius: 16)) }.buttonStyle(StayPressStyle()).tint(.primary).accessibilityIdentifier("checkout-saved-traveler")
                if let travelerMessage { Text(travelerMessage).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("checkout-traveler-message") }
                VStack(spacing: 0) {
                    TextField("First name", text: $guest.firstName).textContentType(.givenName).focused($field, equals: .first).submitLabel(.next).onSubmit { field = .last }.accessibilityIdentifier("hotel-checkout-first")
                    Divider().padding(.vertical, 14)
                    TextField("Last name", text: $guest.lastName).textContentType(.familyName).focused($field, equals: .last).submitLabel(.next).onSubmit { field = .email }.accessibilityIdentifier("hotel-checkout-last")
                    Divider().padding(.vertical, 14)
                    TextField("Email", text: $guest.email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().focused($field, equals: .email).submitLabel(.next).onSubmit { field = .phone }.accessibilityIdentifier("hotel-checkout-email")
                    Divider().padding(.vertical, 14)
                    TextField("Phone · +1 212 555 0123", text: $guest.phone).textContentType(.telephoneNumber).keyboardType(.phonePad).focused($field, equals: .phone).accessibilityIdentifier("hotel-checkout-phone")
                }.font(.body).padding(20).background(StayStyle.surface, in: .rect(cornerRadius: 18))
                Text("Use the lead guest’s name as shown on their ID. Enter the phone number with a country code and no spaces.").font(.caption).foregroundStyle(.secondary)
                Label("Test booking. No real reservation or charge.", systemImage: "testtube.2").font(.subheadline).foregroundStyle(.secondary)
            }.padding(22)
        }.scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { field = nil } } }
    }
    private func review(_ value: HotelCheckout) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                if value.review.changed == true {
                    Label("The price or terms changed. Review the updated details below.", systemImage: "arrow.triangle.2.circlepath").font(.subheadline).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(StayStyle.surface, in: .rect(cornerRadius: 14)).padding(.horizontal, 22).accessibilityIdentifier("hotel-checkout-changed")
                }
                HotelQuoteContent(hotelName: hotelName, review: value.review, prebooked: true)
                if let terms = value.review.terms, !terms.isEmpty { VStack(alignment: .leading, spacing: 8) { Text("Booking terms").font(.headline); Text(terms).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(22) }
            }
            TimelineView(.periodic(from: .now, by: 5)) { _ in
                VStack(spacing: 10) {
                    HStack { Text("Test total").font(.subheadline); Spacer(); Text(value.review.offer.price).font(.headline) }
                    Text("Confirming accepts the room, price and cancellation terms above. No card is charged.").font(.caption).foregroundStyle(.secondary)
                    StayPrimaryButton(title: value.expired ? "Price expired" : busy ? "Confirming…" : "Confirm test booking") { confirm(value) }
                        .disabled(busy || value.expired).accessibilityIdentifier("hotel-checkout-confirm")
                }.padding(22).background(StayStyle.background)
            }
        }
    }
    private func status(_ value: HotelCheckout) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                if value.canPoll { ProgressView().controlSize(.large).padding(28) }
                else { Image(systemName: value.confirmed ? "checkmark.circle" : "clock").font(.system(size: 52, weight: .ultraLight)).padding(.top, 26).accessibilityHidden(true) }
                Text(hotelName).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                Text(statusCopy(value)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let booking = value.booking, value.confirmed {
                    VStack(spacing: 14) {
                        receiptRow("Booking reference", booking.id)
                        if let code = booking.confirmationCode { receiptRow("Hotel confirmation", code) }
                        receiptRow("Test total", value.review.offer.price)
                        receiptRow("Charged", "Nothing · Sandbox")
                    }.padding(20).background(StayStyle.surface, in: .rect(cornerRadius: 18)).accessibilityIdentifier("hotel-booking-receipt")
                }
                if value.confirmed || value.state == "needs_support" { Button("View booking details") { bookingDetails = true }.font(.subheadline.weight(.medium)).tint(.primary).accessibilityIdentifier("hotel-checkout-details") }
                if value.state == "needs_support" {
                    Text("Reference: " + (value.review.supportReference ?? value.id)).font(.caption.monospaced()).textSelection(.enabled)
                }
                if value.canPoll || value.state == "needs_support" { Button("Check status") { Task { await refresh(value.id, provider: true) } }.tint(.primary).disabled(busy).accessibilityIdentifier("hotel-checkout-refresh") }
            }.padding(22)
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            StayBottomBar { StayPrimaryButton(title: "Done") { dismiss() }.accessibilityIdentifier("hotel-checkout-done") }
        }
    }
    private func receiptRow(_ label: String, _ value: String) -> some View { HStack(alignment: .top) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.subheadline) }
    private func statusCopy(_ value: HotelCheckout) -> String {
        if value.confirmed { return "Your test reservation is confirmed by LiteAPI. This is a sandbox booking; it cannot be used to check in." }
        if value.expired { return "This room price is no longer current. Return to room options to choose a fresh rate." }
        if value.state == "prebook_unknown" { return "The room check could not be completed. No booking was submitted and nothing was charged. Return to room options to try a fresh rate." }
        if value.canPoll { return value.confirming ? "We’re checking with LiteAPI. You can close this screen and return to My bookings. Please don’t start another booking for this stay." : "We’re checking availability and final pricing. You can return to this checkout from My bookings." }
        if let issue = value.review.issue { return issue + " This test booking needs support review. Please don’t make another booking for the same stay." }
        return "We couldn’t verify the provider’s final result. This test attempt needs support review. Keep this checkout and avoid starting another booking for the same stay."
    }
    private func create() {
        guard guest.valid, !busy, !travelerNeedsReprice, let original, let quote = original.offer.quote else { return }
        field = nil; busy = true; error = nil
        Task { defer { busy = false }; do { checkout = try await api.createHotelCheckout(.init(id: requestID, quote: quote, guest: guest, hotelName: hotelName), original: original) } catch { self.error = error.localizedDescription } }
    }
    private func confirm(_ value: HotelCheckout) {
        guard !busy, !value.expired else { return }; busy = true; error = nil
        Task { defer { busy = false }; do { checkout = try await api.confirmHotelCheckout(value) } catch { self.error = error.localizedDescription } }
    }
    private func refresh(_ id: String, provider: Bool = false) async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        do { let value = try await (provider ? api.syncHotelCheckout(id) : api.hotelCheckout(id)); try Task.checkCancellation(); checkout = value; error = nil } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func poll() async {
        guard scene == .active, let id = current?.id else { return }
        await refresh(id)
        for step in 0..<40 {
            guard current?.canPoll == true, !Task.isCancelled, scene == .active else { return }
            do { try await Task.sleep(for: .seconds(step == 0 ? 2 : step == 1 ? 5 : 15)) } catch { return }
            await refresh(id)
        }
    }
}
enum HotelBookingFilter: String, CaseIterable {
    case all = "All", upcoming = "Upcoming", past = "Past", attention = "Needs attention", pending = "In progress", confirmed = "Confirmed", expired = "Expired", cancelled = "Cancelled"
    func matches(_ value: HotelCheckout) -> Bool { matches(value, today: TravelDay.key(.now)) }
    func matches(_ value: HotelCheckout, today: String) -> Bool {
        switch self {
        case .all: return true
        case .upcoming: return value.stayPeriod(today: today) == .upcoming
        case .past: return value.stayPeriod(today: today) == .past
        case .confirmed: return value.confirmed
        case .cancelled: return value.cancelled
        case .pending: return value.cancellation?.pending == true || (!value.expired && (value.canPoll || value.state == "review"))
        case .attention: return value.cancellation?.state == "needs_support" || (!value.cancelled && !value.confirmed && !value.expired && !value.canPoll && value.state != "review")
        case .expired: return value.expired
        }
    }
    func results(_ values: [HotelCheckout], query: String, today: String) -> [HotelCheckout] {
        values.filter { matches($0, today: today) && $0.matchesBookingSearch(query) }.sorted { a, b in
            let ap = a.listPriority(today: today), bp = b.listPriority(today: today)
            if ap != bp { return ap < bp }
            if a.confirmed && b.confirmed, let period = a.stayPeriod(today: today), period == b.stayPeriod(today: today) {
                let ad = period == .past ? a.review.criteria.checkout : a.review.criteria.checkin
                let bd = period == .past ? b.review.criteria.checkout : b.review.criteria.checkin
                if ad != bd { return period == .past ? ad > bd : ad < bd }
            }
            let ac = HotelRateClock.date(a.createdAt) ?? .distantPast, bc = HotelRateClock.date(b.createdAt) ?? .distantPast
            return ac == bc ? a.id < b.id : ac > bc
        }
    }
}
enum HotelStayPeriod: String { case upcoming = "Upcoming", current = "Stay dates in progress", past = "Past stay" }
extension HotelCheckout {
    /// Date buckets describe the recorded stay dates, never confirmation or payment status.
    func stayPeriod(today: String) -> HotelStayPeriod? {
        guard confirmed,
              [review.criteria.checkin, review.criteria.checkout, today].allSatisfy({ $0.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil }),
              let checkin = TravelDay.date(review.criteria.checkin), let checkout = TravelDay.date(review.criteria.checkout),
              let day = TravelDay.date(today), checkout > checkin else { return nil }
        if day < checkin { return .upcoming }
        return day >= checkout ? .past : .current
    }
    fileprivate func listPriority(today: String) -> Int {
        if HotelBookingFilter.attention.matches(self) { return 0 }
        if HotelBookingFilter.pending.matches(self) { return 1 }
        switch stayPeriod(today: today) {
        case .current: return 2
        case .upcoming: return 3
        case .past: return 4
        case nil: return confirmed ? 5 : 6
        }
    }
    var paymentDescription: String { environment == "sandbox" && paymentState == "test_no_charge" ? "Nothing · Sandbox" : "Payment status not verified" }
    var displayHotelName: String { review.hotelName ?? booking?.hotelName ?? "Hotel stay" }
    var stayLabel: String { TravelDay.localDate(review.criteria.checkin).formatted(.dateTime.month(.abbreviated).day()) + " → " + TravelDay.localDate(review.criteria.checkout).formatted(.dateTime.month(.abbreviated).day().year()) }
    func matchesBookingSearch(_ query: String) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace })
        let value = [displayHotelName, id, booking?.id ?? "", booking?.confirmationCode ?? "", review.criteria.checkin, review.criteria.checkout, stayLabel].joined(separator: " ")
        return words.allSatisfy { value.localizedCaseInsensitiveContains($0) }
    }
    /// Deliberately export a whitelist, never the encoded checkout or guest payload.
    var shareSummary: String {
        guard environment == "sandbox", paymentState == "test_no_charge" else { return "SEUR · UNVERIFIED BOOKING RECORD\nReference: " + id + "\nBooking and payment status could not be verified. Contact support." }
        var lines = [confirmed ? "SEUR · SANDBOX TEST RECEIPT" : "SEUR · TEST BOOKING SUPPORT SUMMARY",
                     "Not valid for travel. No real stay or payment.", "", displayHotelName,
                     "Status: " + title, "Seur reference: " + id, "Check-in: " + review.criteria.checkin, "Check-out: " + review.criteria.checkout]
        if (confirmed || cancelled), let booking {
            lines += ["Provider booking: " + booking.id, "Hotel confirmation: " + (booking.confirmationCode?.isEmpty == false ? booking.confirmationCode! : "Not supplied"), "Confirmed at: " + booking.confirmedAt]
        } else if !cancelled {
            lines += ["Confirmation has not been verified. Do not use the quoted terms as a confirmed reservation."]
        }
        lines += ["", confirmed ? "Recorded stay details" : "Requested stay details"]
        for room in review.offer.rooms {
            lines += ["Room \(room.number): " + room.name, "Adults: \(room.adults) · Children: \(room.children.count)", "Meal plan: " + room.board]
            if room.cancellation.nonrefundable { lines.append("Recorded cancellation terms: nonrefundable") }
            if let end = room.cancellation.freeUntil { lines.append("Recorded free-cancellation deadline: " + end) }
            for penalty in room.cancellation.penalties {
                lines.append("Penalty from " + (penalty.from ?? penalty.text) + ": " + (penalty.charge?.label ?? "Amount not supplied"))
            }
            lines += room.cancellation.remarks
        }
        lines += ["", "Room subtotal: " + review.offer.base.label]
        for fee in review.offer.fees {
            let timing = fee.included == true ? "included in subtotal" : fee.included == false ? "at property" : "timing not supplied"
            lines.append(fee.description + ": " + (fee.charge?.label ?? "Amount not supplied") + " · " + timing)
        }
        lines += [(review.offer.total == nil ? "Quoted subtotal: " : "Test total: ") + review.offer.price,
                  "Charged: nothing · sandbox", "This is not a payment receipt or a cancellation/refund quote."]
        if !confirmed {
            lines += ["", "Support reference: " + (review.supportReference ?? id)]
            if let issue = review.issue { lines.append("Issue: " + issue) }
            lines.append("Do not submit another booking while this attempt is unresolved.")
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor @Observable final class HotelBookingsModel {
    var rows: [HotelCheckout] = []
    var error: String?
    var loading = false
    var loadingMore = false
    var moreError: String?
    private(set) var nextCursor: String?
    private var generation = UUID()
    private var visited = Set<String>()
    func clear() { generation = UUID(); rows = []; nextCursor = nil; visited = []; error = nil; moreError = nil; loading = false; loadingMore = false }
    func load(using fetch: () async throws -> HotelCheckoutList) async {
        let request = UUID(); generation = request; loading = true; loadingMore = false; error = nil; moreError = nil
        defer { if generation == request { loading = false } }
        do {
            let result = try await fetch(); try Task.checkCancellation()
            guard generation == request else { return }
            var seen = Set<String>(); rows = result.checkouts.filter { seen.insert($0.id).inserted }
            nextCursor = result.nextCursor; visited = []
        } catch { if generation == request && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func loadMore(using fetch: (String) async throws -> HotelCheckoutList) async {
        guard !loading, !loadingMore, let cursor = nextCursor else { return }
        let request = generation; loadingMore = true; moreError = nil
        defer { if generation == request { loadingMore = false } }
        do {
            let result = try await fetch(cursor); try Task.checkCancellation()
            guard generation == request, nextCursor == cursor else { return }
            if let next = result.nextCursor, next == cursor || visited.contains(next) { throw JourneyError.message("Booking history changed. Pull down to refresh.") }
            var seen = Set(rows.map(\.id)); rows += result.checkouts.filter { seen.insert($0.id).inserted }
            visited.insert(cursor); nextCursor = result.nextCursor
        } catch { if generation == request && !Task.isCancelled { moreError = error.localizedDescription } }
    }
    func refreshRecord(_ id: String, using fetch: () async throws -> HotelCheckout) async {
        let request = generation
        do {
            let value = try await fetch(); try Task.checkCancellation()
            guard generation == request, value.id == id, let index = rows.firstIndex(where: { $0.id == id }) else { return }
            rows[index] = value
        } catch { if generation == request && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct HotelCheckoutsSheet: View {
    @Environment(TravelAPI.self) private var api
    @Environment(\.scenePhase) private var scene
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var today = TravelDay.key(.now)
    @State private var model = HotelBookingsModel()
    @State private var loadedIdentity: String?
    @State private var selected: HotelCheckout?
    @State private var filter = HotelBookingFilter.all
    @State private var query = ""
    private var identity: String { (api.account?.id ?? "signed-out") + "|" + api.baseURL }
    private var rows: [HotelCheckout] { filter.results(model.rows, query: query, today: today) }
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: "My bookings")
            VStack(spacing: 14) {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Hotel or booking reference", text: $query).autocorrectionDisabled().accessibilityIdentifier("hotel-bookings-search") }.padding(15).background(StayStyle.surface, in: .rect(cornerRadius: 15))
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { ForEach(HotelBookingFilter.allCases, id: \.self) { value in
                        Button { withAnimation(StayStyle.motion(reduce)) { filter = value } } label: { Text(value.rawValue).font(.caption.weight(.medium)).padding(.horizontal, 15).frame(minHeight: 44).foregroundStyle(filter == value ? StayStyle.background : Color.primary).background(filter == value ? Color.primary : StayStyle.surface, in: .capsule) }.buttonStyle(StayPressStyle()).accessibilityIdentifier("hotel-bookings-filter-" + value.rawValue).accessibilityAddTraits(filter == value ? .isSelected : [])
                    } }
                }.scrollIndicators(.hidden)
            }.padding(.horizontal, 22).padding(.vertical, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Label("Sandbox test bookings · No real stays or charges", systemImage: "testtube.2").font(.caption).foregroundStyle(.secondary)
                    if !api.hotelAccess { HotelAccessNotice() }
                    else {
                        if model.loading && model.rows.isEmpty { ProgressView("Loading your bookings…").frame(maxWidth: .infinity).padding(30) }
                        if let error = model.error { HotelRetry(message: error) { Task { await load() } } }
                        if rows.isEmpty && !model.loading && model.error == nil {
                            ContentUnavailableView(model.rows.isEmpty ? "No bookings yet" : "No matching bookings", systemImage: "bed.double", description: Text(model.rows.isEmpty ? "Saved checkouts and test confirmations appear here, independently of your trips." : "Try another hotel name, booking reference or filter."))
                            if !model.rows.isEmpty && (filter != .all || !query.isEmpty) {
                                Button("Show all loaded bookings") { withAnimation(StayStyle.motion(reduce)) { filter = .all; query = "" } }.font(.subheadline.weight(.medium)).tint(.primary).frame(maxWidth: .infinity).accessibilityIdentifier("hotel-bookings-reset")
                            }
                        }
                        ForEach(rows) { value in
                            Button { selected = value } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top) { Text(value.displayHotelName).font(.headline); Spacer(minLength: 12); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                                    Text(value.stayLabel).font(.subheadline).foregroundStyle(.secondary)
                                    if let period = value.stayPeriod(today: today) { Text(period.rawValue).font(.caption.weight(.medium)).accessibilityIdentifier("hotel-booking-period-" + value.id) }
                                    HStack { Text(value.title).font(.caption.weight(.medium)); Spacer(); Text(value.review.offer.price).font(.subheadline.weight(.medium)) }
                                    if let reference = value.booking?.id, value.confirmed { Text(reference).font(.caption.monospaced()).foregroundStyle(.secondary) }
                                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(StayStyle.surface, in: .rect(cornerRadius: 18))
                            }.buttonStyle(StayPressStyle()).tint(.primary).accessibilityIdentifier("hotel-saved-checkout-" + value.id)
                        }
                        if let error = model.moreError { Text(error).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("hotel-bookings-more-error") }
                        if model.nextCursor != nil {
                            VStack(spacing: 10) {
                                Text("Search and filters apply to loaded bookings.").font(.caption).foregroundStyle(.secondary)
                                Button { Task { await model.loadMore { try await api.hotelCheckouts(cursor: $0) } } } label: {
                                    HStack(spacing: 10) { if model.loadingMore { ProgressView() }; Text(model.loadingMore ? "Loading older bookings…" : model.moreError == nil ? "Load older bookings" : "Retry older bookings") }.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 50).background(StayStyle.surface, in: .rect(cornerRadius: 16))
                                }.buttonStyle(StayPressStyle()).tint(.primary).disabled(model.loading || model.loadingMore).accessibilityIdentifier("hotel-bookings-load-more")
                            }
                        }
                        if !model.rows.isEmpty {
                            Text(model.nextCursor == nil ? "All \(model.rows.count) booking records loaded" : "\(model.rows.count) booking records loaded · More available").font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("hotel-bookings-loaded-count")
                            if filter == .upcoming || filter == .past { Text("Stay dates are grouped using your current time zone.").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }.padding(22)
            }.refreshable { await load() }.scrollDismissesKeyboard(.interactively)
        }.background(StayStyle.background)
        .task(id: identity) {
            guard loadedIdentity != identity else { return }
            loadedIdentity = identity; model.clear(); selected = nil; await load()
        }
        .navigationDestination(isPresented: Binding(get: { selected != nil }, set: { if !$0 {
            let previous = selected; selected = nil
            if let previous { Task { await model.refreshRecord(previous.id) { try await api.hotelCheckout(previous.id) } } }
        } })) {
            if let value = selected {
                if value.confirmed || value.cancelled || value.expired || HotelBookingFilter.attention.matches(value) { HotelBookingRecordView(initial: value).hotelFlowPage() }
                else { HotelCheckoutFlow(hotelName: value.displayHotelName, restored: value).hotelFlowPage() }
            }
        }
        .sensoryFeedback(.selection, trigger: selected?.id).sensoryFeedback(.selection, trigger: filter)
        .sensoryFeedback(.selection, trigger: model.rows.count)
        .onChange(of: api.account?.id) { model.clear(); selected = nil }
        .onChange(of: api.baseURL) { model.clear(); selected = nil }
        .onChange(of: scene) { if scene == .active { today = TravelDay.key(.now); if selected == nil { Task { await load() } } } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = TravelDay.key(.now) }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in today = TravelDay.key(.now) }
    }
    private func load() async { today = TravelDay.key(.now); guard api.hotelAccess else { model.clear(); return }; await model.load { try await api.hotelCheckouts() } }
}

struct HotelBookingRecordView: View {
    let initial: HotelCheckout
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var value: HotelCheckout?
    @State private var error: String?
    @State private var loading = false
    @State private var support = false
    @State private var cancelling = false
    @State private var valid = true
    private var current: HotelCheckout { value ?? initial }
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: current.confirmed ? "Booking details" : "Booking status")
            ScrollView {
                if valid {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(current.displayHotelName).font(.title2.weight(.semibold))
                            Text(current.title).font(.subheadline.weight(.medium)).accessibilityIdentifier("hotel-record-status")
                            Text("Sandbox test · Not valid for travel").font(.caption).foregroundStyle(.secondary)
                        }
                        if current.cancelled { Text("LiteAPI has confirmed that this test booking is cancelled.").font(.subheadline).foregroundStyle(.secondary) }
                        if let checked = current.review.providerCheckedAt.flatMap(HotelRateClock.date) { Text("Checked with LiteAPI " + checked.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("hotel-provider-checked") }
                        if loading { ProgressView("Updating status…") }
                        if let error { HotelRetry(message: error) { Task { await refresh(provider: true) } } }
                        if !current.confirmed && !current.cancelled {
                            Text(current.expired ? "This checkout expired. No confirmed reservation is recorded here." : "The provider result has not been verified. These are the requested terms. Keep this reference and avoid a second booking for the same stay.").font(.subheadline).foregroundStyle(.secondary)
                            if let issue = current.review.issue { Text(issue).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        VStack(spacing: 13) {
                            recordRow("Seur reference", current.id)
                            if current.confirmed || current.cancelled, let booking = current.booking {
                                recordRow("Booking reference", booking.id)
                                recordRow("Hotel confirmation", booking.confirmationCode?.isEmpty == false ? booking.confirmationCode! : "Not supplied")
                            }
                            recordRow("Check-in", TravelDay.localDate(current.review.criteria.checkin).formatted(date: .abbreviated, time: .omitted))
                            recordRow("Check-out", TravelDay.localDate(current.review.criteria.checkout).formatted(date: .abbreviated, time: .omitted))
                            recordRow("Charged", current.paymentDescription)
                        }.padding(18).background(StayStyle.surface, in: .rect(cornerRadius: 18))
                    }.padding(22)
                    HotelQuoteContent(hotelName: current.displayHotelName, review: current.review, prebooked: true, recorded: true)
                    VStack(alignment: .leading, spacing: 12) {
                        if let terms = current.review.terms, !terms.isEmpty { Text("Recorded terms").font(.headline); Text(terms).font(.caption).foregroundStyle(.secondary) }
                        Text("Sandbox cancellations never charge a card. Recorded policies describe the test rate; they do not establish a refund.").font(.caption).foregroundStyle(.secondary)
                        if (api.hotelCancellationAccess || current.cancellation != nil) && current.confirmed && !current.cancelled { Button(current.cancellation?.pending == true || current.cancellation?.state == "needs_support" ? "View cancellation" : "Cancel test booking") { cancelling = true }.font(.subheadline.weight(.medium)).tint(.primary).accessibilityIdentifier("hotel-cancel-open") }
                        Button("Support details") { support = true }.font(.subheadline.weight(.medium)).tint(.primary).accessibilityIdentifier("hotel-record-support")
                    }.padding(22)
                }
            }.refreshable { await refresh(provider: true) }
        }.background(StayStyle.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if valid {
                StayBottomBar {
                    HStack(spacing: 22) {
                        Button { Task { await refresh(provider: true) } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.disabled(loading).tint(.primary).accessibilityLabel("Refresh booking")
                        ShareLink(item: current.shareSummary) {
                            Label(current.confirmed ? "Share test receipt" : "Share support summary", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(StayStyle.background).background(Color.primary, in: .rect(cornerRadius: 16))
                        }.accessibilityIdentifier("hotel-record-share")
                    }
                }
            }
        }
        .task { await refresh() }
        .onChange(of: api.account?.id) { valid = false; value = nil; dismiss() }
        .onChange(of: api.baseURL) { valid = false; value = nil; dismiss() }
        .navigationDestination(isPresented: $support) { HotelBookingSupportView(value: current).hotelFlowPage() }
        .navigationDestination(isPresented: $cancelling) { HotelCancellationFlow(initial: current).hotelFlowPage() }
        .onChange(of: cancelling) { if !cancelling { Task { await refresh() } } }
        .sensoryFeedback(.selection, trigger: cancelling)
        .sensoryFeedback(.selection, trigger: support)
    }
    private func recordRow(_ label: String, _ value: String) -> some View { HStack(alignment: .top) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).font(label == "Seur reference" ? .caption.monospaced() : .subheadline).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.subheadline) }
    private func refresh(provider: Bool = false) async {
        guard !loading, valid else { return }; loading = true
        let owner = api.account?.id, endpoint = api.baseURL
        defer { loading = false }
        do {
            let latest = try await (provider ? api.syncHotelCheckout(initial.id) : api.hotelCheckout(initial.id)); try Task.checkCancellation()
            guard valid, owner == api.account?.id, endpoint == api.baseURL else { return }
            value = latest; error = nil
        } catch { if valid && owner == api.account?.id && endpoint == api.baseURL && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
private struct HotelBookingSupportView: View {
    let value: HotelCheckout
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: "Support details")
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Keep these details with your support request.").font(.title3.weight(.semibold))
                    Text("Nothing is sent automatically. This summary includes booking references and stay details, with no guest contact information or payment credentials.").font(.subheadline).foregroundStyle(.secondary)
                    Text(value.shareSummary).font(.callout.monospaced()).textSelection(.enabled).accessibilityIdentifier("hotel-support-summary")
                }.padding(22)
            }
        }.background(StayStyle.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StayBottomBar { ShareLink(item: value.shareSummary) { Label("Share summary", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(StayStyle.background).background(Color.primary, in: .rect(cornerRadius: 16)) }.accessibilityIdentifier("hotel-support-share") }
        }
        .onChange(of: api.account?.id) { dismiss() }.onChange(of: api.baseURL) { dismiss() }
    }
}

// Isolated test data: production requests never fall back to this implementation.
@MainActor enum HotelCheckoutFixtures {
    private static let defaults = UserDefaults(suiteName: "SeurHotelCheckoutUITests")!
    static var rows: [HotelCheckout] {
        get { (try? JSONDecoder().decode([HotelCheckout].self, from: defaults.data(forKey: "checkouts") ?? Data())) ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "checkouts") }
    }
    static func servicingExamples() throws -> [HotelCheckout] {
        var stay = HotelStayPreferences(); stay.guestNationality = "US"
        stay.checkIn = Calendar.current.date(byAdding: .day, value: 10, to: Calendar.current.startOfDay(for: .now))
        stay.checkOut = Calendar.current.date(byAdding: .day, value: 3, to: stay.checkIn!)
        let criteria = HotelRateCriteria(stay)!
        let offer = try HotelRateFixtures.page(ids: ["liteapi:lpfixture0"], criteria: criteria, detail: true).hotels[0].offers[1]
        var review = HotelQuoteReview(offer: offer, criteria: criteria, environment: "sandbox", checkoutEnabled: true, hotelName: "Palazzo Testa · Test hotel")
        review.offer.quote = nil
        let confirmed = HotelCheckout(id: "10000000-0000-4000-8000-000000000001", state: "confirmed", environment: "sandbox", paymentState: "test_no_charge", quoteVersion: UUID().uuidString, review: review, expiresAt: offer.expiresAt, booking: .init(id: "TEST-SEUR-001", confirmationCode: "TEST-ONLY", hotelName: review.hotelName!, confirmedAt: ISO8601DateFormatter().string(from: .now)), createdAt: ISO8601DateFormatter().string(from: .now))
        var pending = confirmed; pending.id = "10000000-0000-4000-8000-000000000002"; pending.state = "pending_confirmation"; pending.booking = nil
        var attention = pending; attention.id = "10000000-0000-4000-8000-000000000003"; attention.state = "needs_support"; attention.review.issue = "The provider returned different room terms."; attention.review.supportReference = "TEST-SUPPORT-003"
        var expired = pending; expired.id = "10000000-0000-4000-8000-000000000004"; expired.state = "expired"
        var past = confirmed; past.id = "10000000-0000-4000-8000-000000000005"; past.review.hotelName = "The Archive · Test hotel"; past.booking?.id = "TEST-SEUR-PAST"
        past.review.criteria.checkin = TravelDay.adding(-10, to: TravelDay.key(.now)); past.review.criteria.checkout = TravelDay.adding(-7, to: TravelDay.key(.now))
        var current = confirmed; current.id = "10000000-0000-4000-8000-000000000006"; current.review.hotelName = "The Present · Test hotel"; current.booking?.id = "TEST-SEUR-CURRENT"
        current.review.criteria.checkin = TravelDay.adding(-1, to: TravelDay.key(.now)); current.review.criteria.checkout = TravelDay.adding(2, to: TravelDay.key(.now))
        return [confirmed, pending, attention, expired, past, current]
    }
    static func historyPage(cursor: String?) throws -> HotelCheckoutList {
        let offset = cursor.flatMap(Int.init) ?? 0
        let values = rows
        guard offset >= 0, offset <= values.count else { throw JourneyError.message("Refresh booking history.") }
        if offset > 0 && ProcessInfo.processInfo.arguments.contains("--hotel-history-retry") && !defaults.bool(forKey: "history-page-failed") {
            defaults.set(true, forKey: "history-page-failed"); throw JourneyError.message("Could not load older bookings. Try again.")
        }
        let end = min(offset + 30, values.count)
        return .init(checkouts: Array(values[offset..<end]), nextCursor: end < values.count ? String(end) : nil)
    }
    static func paginatedExamples() throws -> [HotelCheckout] {
        defaults.removeObject(forKey: "history-page-failed")
        let base = try servicingExamples()[0]
        return (0..<65).map { index in
            var value = base
            value.id = String(format: "20000000-0000-4000-8000-%012d", index)
            value.review.hotelName = index == 64 ? "Older Harbor Hotel" : "History hotel \(index + 1)"
            value.booking?.id = "TEST-HISTORY-\(index)"
            if index < 60 { value.state = "expired"; value.booking = nil }
            else { value.review.criteria.checkin = TravelDay.adding(-12, to: TravelDay.key(.now)); value.review.criteria.checkout = TravelDay.adding(-9, to: TravelDay.key(.now)) }
            return value
        }
    }
    static func create(_ request: HotelCheckoutRequest, original: HotelQuoteReview) throws -> HotelCheckout {
        if ProcessInfo.processInfo.arguments.contains("--hotel-checkout-error") { throw JourneyError.message("Room check interrupted. Try again to recover this checkout.") }
        if let old = rows.first(where: { $0.id == request.id }) { return old }
        var review = original; review.offer.quote = nil; review.hotelName = request.hotelName; review.terms = "Sandbox terms. This test reservation is not valid for travel."
        review.changed = ProcessInfo.processInfo.arguments.contains("--hotel-checkout-changed")
        if review.changed == true { review.offer.base.amount = "550.00"; review.offer.total?.amount = "590.00" }
        let value = HotelCheckout(id: request.id, state: "review", environment: "sandbox", paymentState: "test_no_charge", quoteVersion: UUID().uuidString, review: review, expiresAt: review.offer.expiresAt, createdAt: ISO8601DateFormatter().string(from: .now))
        rows = [value]; return value
    }
    static func get(_ id: String) throws -> HotelCheckout { guard let value = rows.first(where: { $0.id == id }) else { throw JourneyError.message("Checkout unavailable.") }; return value }
    static func confirm(_ value: HotelCheckout) -> HotelCheckout {
        var result = value
        if ProcessInfo.processInfo.arguments.contains("--hotel-checkout-pending") { result.state = "pending_confirmation" }
        else { result.state = "confirmed"; result.booking = .init(id: "TEST-SEUR-001", confirmationCode: "TEST-ONLY", hotelName: value.review.hotelName ?? "Hotel", confirmedAt: ISO8601DateFormatter().string(from: .now)) }
        rows = [result]; return result
    }
}

struct HotelCancellationFlow: View {
    let initial: HotelCheckout
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    @State private var value: HotelCheckout?
    @State private var busy = false
    @State private var error: String?
    private var current: HotelCheckout { value ?? initial }
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: current.cancelled ? "Booking cancelled" : "Cancel test booking")
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(current.displayHotelName).font(.title2.weight(.semibold))
                    Text(current.stayLabel).font(.subheadline).foregroundStyle(.secondary)
                    if busy { ProgressView("Checking cancellation…") }
                    if current.cancelled {
                        Label("Test booking cancelled", systemImage: "checkmark.circle").font(.headline).accessibilityIdentifier("hotel-cancel-success")
                        Text("LiteAPI has confirmed the cancellation. No real payment was made for this test stay.").font(.subheadline).foregroundStyle(.secondary)
                    } else if current.cancellation?.pending == true {
                        ProgressView("Waiting for confirmation")
                        Text("You can leave this page. We’ll keep checking the original cancellation request.").font(.subheadline).foregroundStyle(.secondary)
                    } else if current.cancellation?.state == "needs_support" {
                        Text("Cancellation needs attention").font(.headline)
                        Text("Keep this booking reference and contact support. A cancellation has not been verified; please don’t submit another request.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Review before cancelling").font(.headline)
                        Text("This cancels a sandbox test reservation. You won’t be charged. Your booking stays active until the provider confirms cancellation.").font(.subheadline).foregroundStyle(.secondary)
                        ForEach(current.review.offer.rooms, id: \.number) { room in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(room.name).font(.headline)
                                Text(room.cancellationLabel).font(.subheadline)
                                ForEach(Array(room.cancellation.penalties.enumerated()), id: \.offset) { _, penalty in
                                    Text((penalty.charge?.label ?? "Amount not supplied") + (penalty.from.flatMap(HotelRateClock.date).map { " from " + HotelRateClock.label($0) } ?? " · Timing not supplied")).font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(StayStyle.surface, in: .rect(cornerRadius: 18))
                        }
                        if let message = current.cancellation?.message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    if let error { HotelRetry(message: error) { Task { await prepare() } } }
                }.padding(22)
            }
        }.background(StayStyle.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { TimelineView(.periodic(from: .now, by: 1)) { _ in StayBottomBar {
            if current.cancelled { StayPrimaryButton(title: "Done") { dismiss() }.accessibilityIdentifier("hotel-cancel-done") }
            else if current.cancellation?.pending == true || current.cancellation?.state == "needs_support" { StayPrimaryButton(title: "Back to booking") { dismiss() } }
            else if current.cancellation?.canConfirm == true { StayPrimaryButton(title: "Confirm test cancellation") { Task { await confirm() } }.disabled(busy).accessibilityIdentifier("hotel-cancel-confirm") }
            else { StayPrimaryButton(title: "Check cancellation terms") { Task { await prepare() } }.disabled(busy).accessibilityIdentifier("hotel-cancel-check") }
        } } }
        .task { if current.cancellation == nil { await prepare() } }
        .task(id: (current.cancellation?.state ?? "") + String(scene == .active)) {
            guard scene == .active else { return }
            for _ in 0..<40 {
                guard current.cancellation?.pending == true, !Task.isCancelled else { return }
                do { try await Task.sleep(for: .seconds(5)); value = try await api.hotelCheckout(initial.id); try Task.checkCancellation() }
                catch { if !Task.isCancelled { self.error = error.localizedDescription }; return }
            }
        }
        .onChange(of: api.account?.id) { dismiss() }.onChange(of: api.baseURL) { dismiss() }
        .sensoryFeedback(.success, trigger: current.cancelled).sensoryFeedback(.error, trigger: error)
    }
    private func prepare() async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do { value = try await api.prepareHotelCancellation(initial.id) } catch { self.error = error.localizedDescription }
    }
    private func confirm() async {
        guard !busy, current.cancellation?.canConfirm == true else { return }; busy = true; error = nil
        defer { busy = false }
        do { value = try await api.confirmHotelCancellation(current) } catch { self.error = error.localizedDescription }
    }
}
#if DEBUG
extension HotelCheckoutFixtures {
    static func prepareCancellation(_ id: String) throws -> HotelCheckout {
        var value = try get(id)
        if value.cancellation?.pending == true || value.cancelled { return value }
        value.cancellation = .init(state: "review", version: UUID().uuidString, expiresAt: Date().addingTimeInterval(300).ISO8601Format(), checkedAt: Date().ISO8601Format())
        rows.removeAll { $0.id == id }; rows.append(value); return value
    }
    static func confirmCancellation(_ input: HotelCheckout) throws -> HotelCheckout {
        var value = try get(input.id)
        guard value.cancellation?.version == input.cancellation?.version else { throw JourneyError.message("Review cancellation again.") }
        if ProcessInfo.processInfo.arguments.contains("--hotel-cancel-pending") { value.cancellation?.state = "pending" }
        else { value.state = "cancelled"; value.review.providerStatus = "CANCELLED"; value.review.providerCheckedAt = Date().ISO8601Format(); value.cancellation?.state = "cancelled" }
        rows.removeAll { $0.id == value.id }; rows.append(value); return value
    }
}
#endif
