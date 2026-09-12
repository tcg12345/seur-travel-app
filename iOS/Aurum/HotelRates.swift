import SwiftUI
import Observation

struct HotelOccupancy: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var adults = 2
    var children: [Int] = []
    enum CodingKeys: String, CodingKey { case adults, children }
    var valid: Bool { (1...8).contains(adults) && children.count <= 4 && children.allSatisfy { (0...17).contains($0) } }
}
struct HotelRateCriteria: Codable, Equatable {
    var checkin: String
    var checkout: String
    var currency: String
    var guestNationality: String
    var occupancies: [HotelOccupancy]
    init?(_ stay: HotelStayPreferences) {
        guard stay.ratesReady, let start = stay.checkIn, let end = stay.checkOut else { return nil }
        checkin = TravelDay.key(start); checkout = TravelDay.key(end); currency = stay.currency; guestNationality = stay.guestNationality; occupancies = stay.occupancies
    }
    // Local room IDs are presentation identity, not search criteria.
    static func ==(a: Self, b: Self) -> Bool { a.checkin == b.checkin && a.checkout == b.checkout && a.currency == b.currency && a.guestNationality == b.guestNationality && a.occupancies.map { [$0.adults] + $0.children } == b.occupancies.map { [$0.adults] + $0.children } }
}
struct HotelMoney: Codable, Equatable {
    var amount: String
    var currency: String
    var decimal: Decimal? { Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) }
    var label: String { decimal?.formatted(.currency(code: currency)) ?? currency + " " + amount }
}
struct HotelPenalty: Codable { var from: String?; var charge: HotelMoney?; var text: String }
struct HotelCancellation: Codable { var nonrefundable: Bool; var freeUntil: String?; var penalties: [HotelPenalty]; var remarks: [String] }
struct HotelRateRoom: Codable, Identifiable {
    var number: Int
    var name: String
    var mappedRoomId: String?
    var adults: Int
    var children: [Int]
    var board: String
    var breakfast: Bool
    var paymentTypes: [String]
    var cancellation: HotelCancellation
    var remarks: String
    var perks: [String]
    var id: Int { number }
    var cancellationLabel: String {
        if cancellation.nonrefundable { return "Nonrefundable" }
        if let end = cancellation.freeUntil, let date = HotelRateClock.date( end), date > .now { return "Free cancellation until " + HotelRateClock.label(date) }
        return "See cancellation terms"
    }
}
struct HotelRateFee: Codable { var description: String; var included: Bool?; var charge: HotelMoney?; var room: Int }
struct HotelRateOffer: Codable, Identifiable {
    var id: String
    var hotelId: String
    var rooms: [HotelRateRoom]
    var base: HotelMoney
    var total: HotelMoney?
    var fees: [HotelRateFee]
    var publicPriceEligible: Bool
    var publicPriceFloor: HotelMoney?
    var breakfast: Bool
    var freeCancellationUntil: String?
    var expiresAt: String
    var quote: String?
    var expired: Bool { (HotelRateClock.date( expiresAt) ?? .distantPast) <= .now }
    var title: String { rooms.count == 1 ? rooms[0].name : "\(rooms.count)-room package" }
    var freeCancellationAvailable: Bool { freeCancellationUntil.flatMap(HotelRateClock.date).map { $0 > .now } ?? false }
    var cancellationLabel: String {
        if rooms.allSatisfy({ $0.cancellation.nonrefundable }) { return "Nonrefundable" }
        if let end = freeCancellationUntil, let date = HotelRateClock.date(end), date > .now { return "Free cancellation until " + HotelRateClock.label(date) }
        return rooms.count == 1 ? rooms[0].cancellationLabel : "See cancellation terms for each room"
    }
    var price: String { (total ?? base).label }
}
struct HotelRateResult: Codable { var hotelId: String; var offers: [HotelRateOffer]; var status: String }
struct HotelRatePage: Codable { var hotels: [HotelRateResult]; var criteria: HotelRateCriteria; var environment: String; var expiresAt: String; var checkoutEnabled: Bool }
struct HotelQuoteReview: Codable { var offer: HotelRateOffer; var criteria: HotelRateCriteria; var environment: String; var checkoutEnabled: Bool; var terms: String? = nil; var changed: Bool? = nil; var hotelName: String? = nil; var issue: String? = nil; var supportReference: String? = nil; var providerStatus: String? = nil; var providerCheckedAt: String? = nil }
struct HotelRatesRequest: Encodable {
    var hotelIds: [String]; var detail: Bool; var criteria: HotelRateCriteria
    func encode(to encoder: Encoder) throws {
        try criteria.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self); try c.encode(hotelIds, forKey: .hotelIds); try c.encode(detail, forKey: .detail)
    }
    enum Keys: String, CodingKey { case hotelIds, detail }
}
@MainActor @Observable final class HotelRateModel {
    var results: [String: HotelRateResult] = [:]
    var criteria: HotelRateCriteria?
    var loading = false
    var error: String?
    var expiresAt: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    var expired: Bool { expiresAt.map { (HotelRateClock.date( $0) ?? .distantPast) <= .now } ?? false }
    func clear() { task?.cancel(); generation = UUID(); results = [:]; criteria = nil; error = nil; loading = false; expiresAt = nil }
    func load(hotelIDs: [String], stay: HotelStayPreferences, api: TravelAPI, detail: Bool = false, more: Bool = false) {
        guard let context = HotelRateCriteria(stay), !hotelIDs.isEmpty else { clear(); return }
        task?.cancel(); let id = UUID(); generation = id
        if !more || criteria != context || expired { results = [:]; expiresAt = nil }
        criteria = context; loading = true; error = nil
        task = Task {
            defer { if generation == id { loading = false } }
            do {
                let page = try await api.hotelRates(hotelIDs: Array(hotelIDs.prefix(20)), criteria: context, detail: detail)
                try Task.checkCancellation(); guard generation == id, page.criteria == context else { return }
                for result in page.hotels { results[result.hotelId] = result }
                expiresAt = page.expiresAt
            } catch { if generation == id && !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
struct HotelRateSummary: View {
    let result: HotelRateResult?
    var loading = false
    var error: String?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            if let offer = result?.offers.first, !offer.expired {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) { Text(offer.price).font(.headline); Text(offer.total == nil ? "stay + hotel charges" : "total stay").font(.caption).foregroundStyle(.secondary) }
                    Text("Test rate" + (offer.breakfast ? " · Breakfast included" : "") + (offer.freeCancellationAvailable ? " · Refundable" : "")).font(.caption2).foregroundStyle(.secondary)
                }.accessibilityIdentifier("hotel-rate-price")
            } else if loading { Text("Checking prices…").font(.caption).foregroundStyle(.secondary) }
            else { Text(error != nil ? "Prices temporarily unavailable" : result?.offers.first?.expired == true ? "Refresh for current prices" : result?.status == "unavailable" ? "No rooms for these dates" : result == nil ? "Open hotel for room prices" : "No eligible room prices").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
struct HotelRoomOffersView: View {
    let hotel: LodgingHotel
    let detail: LodgingDetail?
    @Environment(TravelAPI.self) private var api
    @Environment(TravelStore.self) private var store
    @State private var model = HotelRateModel()
    @State private var selected: HotelRateOffer?
    @State private var review: HotelQuoteReview?
    @State private var inspecting = false
    @State private var error: String?
    @State private var refundable = false
    @State private var breakfast = false
    @State private var initialized = false
    private var offers: [HotelRateOffer] {
        var filters = store.hotelSearch.filters; filters.breakfast = breakfast; filters.freeCancellation = refundable
        return (model.results[hotel.id]?.offers ?? []).filter { filters.matches($0, currency: store.hotelSearch.stay.currency) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Available rooms").font(.headline); Spacer(); Text("Test rates").font(.caption).foregroundStyle(.secondary) }.accessibilityIdentifier("hotel-available-rooms")
            if !store.hotelSearch.stay.ratesReady { Text("Choose dates and complete guest details to see room prices.").font(.subheadline).foregroundStyle(.secondary) }
            else {
                ScrollView(.horizontal) { HStack { StayChip(title: "Breakfast", symbol: "cup.and.saucer", selected: breakfast) { breakfast.toggle() }; StayChip(title: "Free cancellation", symbol: "arrow.uturn.backward", selected: refundable) { refundable.toggle() } } }.scrollIndicators(.hidden)
                if model.loading { ProgressView("Checking room options…").font(.subheadline) }
                if let message = model.error { HotelRetry(message: message) { refresh() } }
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    if model.expired { Text("These prices have expired. Refresh to see current options.").font(.subheadline).foregroundStyle(.secondary) }
                    else {
                        ForEach(offers) { offer in
                            Button { inspect(offer) } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    if let roomID = offer.rooms.first?.mappedRoomId, let room = detail?.rooms.first(where: { $0.id == roomID }), let photo = room.photos.first { LodgingImage(url: photo.url, caption: room.name).frame(height: 170).clipShape(.rect(cornerRadius: 14)) }
                                    Text(offer.title).font(.subheadline.weight(.semibold))
                                    if offer.rooms.count > 1 { Text(offer.rooms.map { "Room \($0.number) · " + $0.name }.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary) }
                                    Text(offer.rooms.map(\.board).filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                    Text(offer.cancellationLabel).font(.caption).foregroundStyle(.secondary)
                                    HStack { Text(offer.price).font(.headline); Text(offer.total == nil ? "+ hotel charges" : "total stay").font(.caption).foregroundStyle(.secondary); Spacer(); Image(systemName: "arrow.right").font(.subheadline) }
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(StayStyle.surface, in: .rect(cornerRadius: 18))
                            }.buttonStyle(StayPressStyle()).tint(.primary).disabled(inspecting).accessibilityIdentifier("hotel-room-offer-" + offer.id)
                        }
                    }
                }
                if offers.isEmpty && !model.loading && model.error == nil && !model.expired { Text(model.results[hotel.id]?.status == "unavailable" ? "No rooms available for these dates." : "No matching room options. Try different dates or fewer filters.").font(.subheadline).foregroundStyle(.secondary) }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                if inspecting { ProgressView("Opening rate details…") }
                Button("Refresh prices") { refresh() }.font(.subheadline).tint(.primary).disabled(model.loading).accessibilityIdentifier("hotel-rates-refresh")
            }
        }.task(id: HotelRateCriteria(store.hotelSearch.stay)) { if !initialized { breakfast = store.hotelSearch.filters.breakfast; refundable = store.hotelSearch.filters.freeCancellation; initialized = true }; if model.criteria != HotelRateCriteria(store.hotelSearch.stay) { refresh() } }
        .navigationDestination(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) { if let review { HotelRateReviewSheet(hotel: hotel, review: review).hotelFlowPage() } }
        .sensoryFeedback(.selection, trigger: breakfast).sensoryFeedback(.selection, trigger: refundable)
        .sensoryFeedback(.selection, trigger: selected?.id)
    }
    private func refresh() { guard api.hotelAccess else { return }; selected = nil; review = nil; error = nil; model.load(hotelIDs: [hotel.id], stay: store.hotelSearch.stay, api: api, detail: true) }
    private func inspect(_ offer: HotelRateOffer) {
        guard !offer.expired else { error = "This price has expired. Refresh room options."; return }
        inspecting = true; error = nil
        Task { defer { inspecting = false }; do { let value = try await api.hotelQuote(offer); guard value.criteria == HotelRateCriteria(store.hotelSearch.stay) else { return }; review = value; selected = offer } catch { self.error = error.localizedDescription } }
    }
}
struct HotelRateReviewSheet: View {
    @Environment(TravelStore.self) private var store
    let hotel: LodgingHotel
    let review: HotelQuoteReview
    @State private var checkout = false
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: "Your room option")
            ScrollView { HotelQuoteContent(hotelName: hotel.name, review: review) }
            TimelineView(.periodic(from: .now, by: 10)) { _ in
                VStack(spacing: 10) {
                    if review.checkoutEnabled {
                        StayPrimaryButton(title: "Continue to test booking") { checkout = true }
                            .disabled(review.offer.expired).accessibilityIdentifier("hotel-checkout-start")
                    }
                    Text(review.offer.expired ? "Price expired. Refresh room options." : review.checkoutEnabled ? "No card needed. You won’t be charged." : "Test booking supports one room with a complete price.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(22).background(StayStyle.background)
            }
        }.background(StayStyle.background).presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(28)
            .navigationDestination(isPresented: $checkout) { HotelCheckoutFlow(hotelName: hotel.name, original: review, preferredTravelerID: store.hotelSearch.stay.travelerID).hotelFlowPage() }
            .sensoryFeedback(.selection, trigger: checkout)
    }
}
struct HotelQuoteContent: View {
    let hotelName: String
    let review: HotelQuoteReview
    var prebooked = false
    var recorded = false
    var body: some View {
                VStack(alignment: .leading, spacing: 22) {
                    if !recorded {
                        Text(hotelName).font(.headline)
                        Text(TravelDay.localDate(review.criteria.checkin).formatted(.dateTime.month(.abbreviated).day()) + " → " + TravelDay.localDate(review.criteria.checkout).formatted(.dateTime.month(.abbreviated).day().year())).font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(review.offer.rooms) { room in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Room \(room.number) · " + room.name).font(.headline)
                            Text("\(room.adults) adults" + (room.children.isEmpty ? "" : " · \(room.children.count) children")).font(.subheadline)
                            Text(room.board).font(.subheadline).foregroundStyle(.secondary)
                            if !recorded { Text(room.paymentTypes.contains("NUITEE_PAY") ? "Online payment offered" : "Pay at the hotel").font(.caption).foregroundStyle(.secondary) }
                            if recorded {
                                Text("Recorded cancellation terms").font(.subheadline.weight(.medium))
                                if room.cancellation.nonrefundable { Text("Nonrefundable").font(.subheadline) }
                                if let end = room.cancellation.freeUntil, let date = HotelRateClock.date(end) { Text("Free-cancellation deadline: " + HotelRateClock.label(date)).font(.caption).foregroundStyle(.secondary) }
                            } else { Text(room.cancellationLabel).font(.subheadline) }
                            ForEach(Array(room.cancellation.penalties.enumerated()), id: \.offset) { _, p in
                                Text((p.from.flatMap { HotelRateClock.date( $0) }.map(HotelRateClock.label) ?? p.text) + " · " + (p.charge?.label ?? "Penalty details need confirmation")).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(room.perks, id: \.self) { Text($0).font(.caption) }
                            if !room.remarks.isEmpty { Text(room.remarks).font(.caption).foregroundStyle(.secondary) }
                            ForEach(room.cancellation.remarks, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        }
                        Divider()
                    }
                    HStack { Text("Room subtotal"); Spacer(); Text(review.offer.base.label) }.font(.subheadline)
                    ForEach(Array(review.offer.fees.enumerated()), id: \.offset) { _, fee in
                        HStack(alignment: .top) { VStack(alignment: .leading, spacing: 4) { Text(fee.description); Text(fee.included == true ? "Included in subtotal" : fee.included == false ? "Pay at hotel · Room \(fee.room)" : "Payment timing not supplied").foregroundStyle(.secondary) }; Spacer(); Text(fee.charge?.label ?? "Amount not supplied") }.font(.caption)
                    }
                    HStack { Text(review.offer.total == nil ? "Subtotal + hotel charges" : "Total stay"); Spacer(); Text(review.offer.price) }.font(.headline).accessibilityIdentifier("hotel-quote-total")
                    if review.offer.total == nil { Text("Hotel charges are separate; currencies have not been converted.").font(.caption).foregroundStyle(.secondary) }
                    Text(prebooked ? "Test booking · No real stay or charge." : "Test rate · No reservation has been made.").font(.caption).foregroundStyle(.secondary)

                }.padding(22)
    }
}

// Supplier instants include milliseconds; accept both ISO-8601 representations.
enum HotelRateClock {
    static func label(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) + " " + (TimeZone.current.abbreviation(for: date) ?? TimeZone.current.identifier) }
    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

@MainActor enum HotelRateFixtures {
    static var lastCriteria: HotelRateCriteria?
    static func page(ids: [String], criteria: HotelRateCriteria, detail: Bool) throws -> HotelRatePage {
        lastCriteria = criteria
        if ProcessInfo.processInfo.arguments.contains("--hotel-rates-error") { throw JourneyError.message("Prices are temporarily unavailable. Try again.") }
        let expired = ProcessInfo.processInfo.arguments.contains("--hotel-rates-expired")
        let expiry = ISO8601DateFormatter().string(from: .now.addingTimeInterval(expired ? -10 : 300))
        let hotels = ids.map { hotelId in
            let offers = (0..<(detail ? 2 : 1)).map { index in
                let base = 500 + index * 100, total = base * criteria.occupancies.count
                let rooms = criteria.occupancies.enumerated().map { n, occupancy in
                    HotelRateRoom(number: n + 1, name: index == 0 ? "Deluxe double room" : "Deluxe king · breakfast", mappedRoomId: "room1", adults: occupancy.adults, children: occupancy.children, board: index == 0 ? "Room only" : "Breakfast included", breakfast: index == 1, paymentTypes: ["NUITEE_PAY"], cancellation: HotelCancellation(nonrefundable: index == 0, freeUntil: index == 1 ? ISO8601DateFormatter().string(from: .now.addingTimeInterval(86400)) : nil, penalties: [], remarks: []), remarks: "Test rate details.", perks: [])
                }
                return HotelRateOffer(id: "rate-" + hotelId.replacingOccurrences(of: ":", with: "-") + "-\(index)", hotelId: hotelId, rooms: rooms, base: .init(amount: "\(total).00", currency: criteria.currency), total: .init(amount: "\(total + 40).00", currency: criteria.currency), fees: [.init(description: "City tax", included: false, charge: .init(amount: "40.00", currency: criteria.currency), room: 1)], publicPriceEligible: true, publicPriceFloor: nil, breakfast: index == 1, freeCancellationUntil: rooms.first?.cancellation.freeUntil, expiresAt: expiry, quote: "fixture-only")
            }
            let empty = ProcessInfo.processInfo.arguments.contains("--hotel-rates-empty")
            return HotelRateResult(hotelId: hotelId, offers: empty ? [] : offers, status: empty ? "unavailable" : "available")
        }
        return .init(hotels: hotels, criteria: criteria, environment: "sandbox", expiresAt: expiry, checkoutEnabled: false)
    }
}
