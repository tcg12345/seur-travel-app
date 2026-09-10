import Foundation
import SwiftUI

struct TripCompanion: Codable, Hashable, Identifiable {
    var id: String
    var name: String
}
struct TripExchangeRates: Codable {
    var base: String
    var rates: [String: Decimal]
    var dates: [String: String]
    var fetchedAt: Double
    var stale: Bool
    func converted(_ totals: [String: Decimal], to home: String) -> Decimal? {
        var total: Decimal = 0
        for (currency, amount) in totals {
            if currency == home { total += amount; continue }
            guard let source = rates[currency], let target = rates[home],
                  !source.isNaN, !target.isNaN, source > 0, target > 0 else { return nil }
            total += amount / source * target
        }
        return total
    }
    var isCurrent: Bool { !stale && Self.day(Date(timeIntervalSince1970: fetchedAt)) == Self.day(.now) }
    static func day(_ date: Date) -> String { TodayPlanner.key(date, zone: TimeZone(secondsFromGMT: 0)!) }
}

@MainActor @Observable final class TripRatesStore {
    static let shared = TripRatesStore()
    private var values: [String: TripExchangeRates] = [:]
    private var pending: Set<String> = []
    var error: String?
    func value(server: String) -> TripExchangeRates? {
        if let value = values[server] { return value }
        guard let data = UserDefaults.standard.data(forKey: "seur.fx." + server), let value = try? JSONDecoder().decode(TripExchangeRates.self, from: data) else { return nil }
        return value
    }
    func refresh(api: TravelAPI) async {
        let server = api.baseURL
        guard api.isSignedIn, value(server: server)?.isCurrent != true, !pending.contains(server),
              !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        pending.insert(server); defer { pending.remove(server) }
        do {
            let value = try await api.exchangeRates()
            guard api.baseURL == server else { return }
            values[server] = value; error = nil
            if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "seur.fx." + server) }
        } catch { self.error = "Rates could not refresh. Saved rates remain available." }
    }
}

enum TripBudget {
    /// Saving budget settings opts in; prices alone never enable the trip summary.
    static func isConfigured(_ document: JourneyDocument) -> Bool {
        document.homeCurrency != nil || document.budgetTarget != nil || !(document.companions ?? []).isEmpty
    }

    struct Settlement: Identifiable, Equatable {
        var from: String
        var to: String
        var money: TravelMoney
        var id: String { money.currency + ":" + from + ":" + to }
    }
    static func actualCosts(_ document: JourneyDocument) -> [TravelMoney] {
        document.events.filter { $0.isDone == true }.compactMap(\.cost) +
        document.hotels.compactMap(\.cost).filter { $0.isPaid == true } +
        document.flights.compactMap(\.cost).filter { $0.isPaid == true }
    }
    static func spent(_ document: JourneyDocument) -> [String: Decimal] { JourneyDocument.totals(actualCosts(document)) }
    static func elapsedDays(_ document: JourneyDocument, now: Date = .now) -> Int? {
        guard document.dateMode == .dates,
              let start = document.startDate ?? document.stops.first?.arrival,
              let end = document.endDate ?? document.stops.last?.departure, end >= start else { return nil }
        let today = TodayPlanner.key(now, zone: TodayPlanner.context(document, now: now).zone)
        guard today >= start else { return nil }
        return max(1, TravelDay.distance(start, min(today, end)) + 1)
    }
    static func converted(_ totals: [String: Decimal], home: String, rates: TripExchangeRates?) -> Decimal? {
        if totals.keys.allSatisfy({ $0 == home }) { return totals[home] ?? 0 }
        return rates?.converted(totals, to: home)
    }
    static func minorScale(_ currency: String) -> Int64 {
        if ["BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"].contains(currency) { return 1 }
        if ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"].contains(currency) { return 1000 }
        if ["CLF", "UYW"].contains(currency) { return 10000 }
        return 100
    }
    static func settlements(_ document: JourneyDocument) -> [Settlement] {
        var balances: [String: [String: Int64]] = [:]
        let people = Set((document.companions ?? []).map(\.id))
        for cost in actualCosts(document) {
            guard let payer = cost.paidBy, people.contains(payer), let split = cost.splitBetween,
                  !split.isEmpty, Set(split).count == split.count, split.allSatisfy(people.contains),
                  !cost.amount.isNaN, cost.amount >= 0, cost.amount <= 1_000_000_000 else { continue }
            var raw = cost.amount * Decimal(minorScale(cost.currency)), rounded = Decimal()
            NSDecimalRound(&rounded, &raw, 0, .plain)
            let units = NSDecimalNumber(decimal: rounded).int64Value
            balances[cost.currency, default: [:]][payer, default: 0] += units
            let ids = split.sorted(), count = Int64(ids.count)
            for (index, id) in ids.enumerated() {
                balances[cost.currency, default: [:]][id, default: 0] -= units / count + (Int64(index) < units % count ? 1 : 0)
            }
        }
        var result: [Settlement] = []
        for currency in balances.keys.sorted() {
            let balance = balances[currency]!
            var debtors = balance.filter { $0.value < 0 }.sorted { $0.key < $1.key }.map { (id: $0.key, units: -$0.value) }
            var creditors = balance.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { (id: $0.key, units: $0.value) }
            var debit = 0, credit = 0
            while debit < debtors.count && credit < creditors.count {
                let units = min(debtors[debit].units, creditors[credit].units)
                result.append(Settlement(from: debtors[debit].id, to: creditors[credit].id,
                    money: TravelMoney(amount: Decimal(units) / Decimal(minorScale(currency)), currency: currency)))
                debtors[debit].units -= units; creditors[credit].units -= units
                if debtors[debit].units == 0 { debit += 1 }; if creditors[credit].units == 0 { credit += 1 }
            }
        }
        return result
    }
    static func validationError(_ document: JourneyDocument) -> String? {
        if let target = document.budgetTarget, target.isNaN || target < 0 || target > 1_000_000_000 { return "Enter a budget between zero and one billion." }
        if let home = document.homeCurrency, !TravelMoney.currencies.contains(home) { return "Choose a supported home currency." }
        let companions = document.companions ?? [], ids = Set(companions.map(\.id))
        if companions.count > 40 || ids.count != companions.count || companions.contains(where: { UUID(uuidString: $0.id) == nil || $0.id != $0.id.lowercased() || $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.name.count > 100 }) { return "Use up to 40 companions, each with a name and unique identity." }
        for cost in document.events.compactMap(\.cost) + document.hotels.compactMap(\.cost) + document.flights.compactMap(\.cost) {
            if cost.paidBy != nil || cost.splitBetween != nil {
                guard let payer = cost.paidBy, ids.contains(payer), let split = cost.splitBetween,
                      !split.isEmpty, Set(split).count == split.count, split.allSatisfy(ids.contains) else { return "Choose who paid and at least one companion to split each shared cost." }
            }
        }
        return nil
    }
}

/// A read-only projection of existing trip costs; each event or booking appears exactly once.
enum BudgetLedger {
    enum Category: String, CaseIterable, Identifiable {
        case stays = "Stays", transport = "Transport", dining = "Food & drink", experiences = "Experiences", shopping = "Shopping", other = "Other"
        var id: String { rawValue }
        var symbol: String { switch self { case .stays: "bed.double"; case .transport: "airplane"; case .dining: "fork.knife"; case .experiences: "sparkles"; case .shopping: "bag"; case .other: "creditcard" } }
        var placeCategory: PlaceCategory { switch self { case .stays: .hotel; case .dining: .restaurant; case .experiences: .attraction; case .shopping: .shopping; default: .other } }
    }
    enum Source: Hashable { case event(UUID), hotel(UUID), flight(UUID) }
    struct Entry: Identifiable {
        var source: Source
        var title: String
        var category: Category
        var date: String?
        var money: TravelMoney
        var spent: Bool
        var id: String { switch source { case .event(let id): "event-\(id)"; case .hotel(let id): "hotel-\(id)"; case .flight(let id): "flight-\(id)" } }
    }
    static func category(_ event: JourneyEvent) -> Category {
        if event.routeLegID != nil || [.transfer, .train, .ferry].contains(event.kind) { return .transport }
        if event.kind == .shopping { return .shopping }
        switch event.place.category {
        case .restaurant, .bar, .cafe: return .dining
        case .hotel: return .stays
        case .shopping: return .shopping
        case .other: return .other
        default: return .experiences
        }
    }
    static func entries(_ document: JourneyDocument) -> [Entry] {
        let events = document.events.compactMap { event -> Entry? in
            guard let cost = event.cost else { return nil }
            return Entry(source: .event(event.id), title: event.displayTitle.isEmpty ? "Trip expense" : event.displayTitle, category: category(event), date: document.date(for: event), money: cost, spent: event.isDone == true)
        }
        let hotels = document.hotels.compactMap { item -> Entry? in
            guard let cost = item.cost else { return nil }
            return Entry(source: .hotel(item.id), title: item.place.name.isEmpty ? "Hotel stay" : item.place.name, category: .stays, date: document.dateMode == .dates ? item.checkIn : nil, money: cost, spent: cost.isPaid == true)
        }
        let flights = document.flights.compactMap { item -> Entry? in
            guard let cost = item.cost else { return nil }
            let title = [item.airline, item.flightNumber].filter { !$0.isEmpty }.joined(separator: " ")
            return Entry(source: .flight(item.id), title: title.isEmpty ? "Flight" : title, category: .transport, date: document.dateMode == .dates ? item.departureDay : nil, money: cost, spent: cost.isPaid == true)
        }
        return (events + hotels + flights).sorted { ($0.date ?? "", $0.id) > ($1.date ?? "", $1.id) }
    }
    static func totals(_ entries: [Entry]) -> [String: Decimal] { JourneyDocument.totals(entries.map(\.money)) }
    static func balance(_ person: String, in document: JourneyDocument) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        for transfer in TripBudget.settlements(document) {
            if transfer.to == person { result[transfer.money.currency, default: 0] += transfer.money.amount }
            if transfer.from == person { result[transfer.money.currency, default: 0] -= transfer.money.amount }
        }
        return result.filter { $0.value != 0 }
    }
}
