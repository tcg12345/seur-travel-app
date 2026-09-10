import SwiftUI

struct TripBudgetCard: View {
    let document: JourneyDocument
    var editable = true
    var initiallyExpanded = false
    @Environment(TravelAPI.self) private var api
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rates = TripRatesStore.shared
    @State private var editing = false
    @State private var expanded = false
    private var home: String { document.homeCurrency ?? "USD" }
    private var actual: Decimal? { TripBudget.converted(TripBudget.spent(document), home: home, rates: rates.value(server: api.baseURL)) }
    var body: some View {
        if TripBudget.isConfigured(document) {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "chart.pie").font(.system(size: 22, weight: .light)).foregroundStyle(Color.bronze)
                            .frame(width: 44, height: 44).background(Color.bronze.opacity(0.08), in: .circle)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trip budget").font(.system(.headline, design: .serif)).foregroundStyle(.primary)
                            Text(actual.map { money($0) + " spent" } ?? "View original amounts").font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold)).rotationEffect(.degrees(expanded ? 180 : 0)).foregroundStyle(Color.bronze)
                    }.padding(18).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("trip-budget-toggle").accessibilityValue(expanded ? "Expanded" : "Collapsed")
                if expanded {
                    VStack(alignment: .leading, spacing: 16) {
                        Divider()
                        if let target = document.budgetTarget, let actual {
                            HStack { Text(actual > target ? "Over target" : "Remaining").foregroundStyle(.secondary); Spacer(); Text(money(abs(target - actual))).fontWeight(.medium) }.font(.subheadline)
                            if target > 0 { ProgressView(value: min(1, max(0, NSDecimalNumber(decimal: actual / target).doubleValue))).tint(.bronze) }
                        }
                        HStack {
                            NavigationLink { TripBudgetDashboard(initial: document, editable: editable) } label: { Label("Open budget tracker", systemImage: "arrow.up.right").font(.subheadline.weight(.semibold)) }.accessibilityIdentifier("trip-budget-open")
                            Spacer()
                            if editable { Button("Edit") { editing = true }.font(.subheadline).accessibilityIdentifier("trip-budget-edit") }
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 18)
                }
            }.cardSurface(cornerRadius: 22)
                .sheet(isPresented: $editing) { TripBudgetEditor(documentID: document.id) }
                .onAppear { expanded = initiallyExpanded }
                .task(id: home + api.baseURL + String(api.isSignedIn) + document.totals.keys.sorted().joined()) { if document.totals.keys.contains(where: { $0 != home }) { await rates.refresh(api: api) } }
        }
    }
    private func money(_ value: Decimal) -> String { TravelMoney(amount: value, currency: home).formatted }
}

struct TripBudgetEditor: View {
    let documentID: UUID
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var home = "USD"
    @State private var target: Decimal = 0
    @State private var hasTarget = false
    @State private var companions: [TripCompanion] = []
    @State private var name = ""
    @State private var friends: [TravelFriend] = []
    @State private var groups: [TravelConversation] = []
    @State private var error: String?
    @State private var peopleError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Budget") {
                    Picker("Home currency", selection: $home) { ForEach(TravelMoney.currencies, id: \.self) { Text($0).tag($0) } }
                    Toggle("Set a target", isOn: $hasTarget).accessibilityIdentifier("budget-target-toggle")
                    if hasTarget { TextField("Target in " + home, value: $target, format: .number).keyboardType(.decimalPad).accessibilityIdentifier("budget-target") }
                    Text("Your target is entered in the selected home currency. Conversion estimates refresh daily; original costs are unchanged.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Companions") {
                    ForEach(companions) { person in
                        HStack { Text(person.name); Spacer(); Button(role: .destructive) { remove(person) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove " + person.name) }
                    }
                    HStack { TextField("Companion name", text: $name).accessibilityIdentifier("budget-companion-name"); Button("Add") { add(.init(id: UUID().uuidString.lowercased(), name: name.trimmingCharacters(in: .whitespacesAndNewlines))); name = "" }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 100 || companions.count >= 40) }
                    if let account = api.account { Button("Add me · " + account.name) { add(.init(id: account.id.lowercased(), name: account.name)) }.disabled(companions.contains { $0.id == account.id.lowercased() }) }
                    Text("Set who paid and who shares each cost in its price fields. Companions and splits are included when you explicitly save or share this trip.").font(.caption).foregroundStyle(.secondary)
                }
                if api.isSignedIn {
                    Section("From friends & conversations") {
                        ForEach(friends.filter { $0.status == "accepted" }) { friend in
                            Button(friend.name + " · @" + friend.handle) { add(.init(id: friend.id.lowercased(), name: friend.name)) }.disabled(companions.contains { $0.id == friend.id.lowercased() })
                        }
                        ForEach(groups) { group in
                            Button("Add members · " + group.name) { for member in group.members { add(.init(id: member.id.lowercased(), name: member.name)) } }
                        }
                        if let peopleError { Text(peopleError).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("Budget & companions").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).accessibilityIdentifier("budget-save") } }
                .onAppear {
                    guard let document = library.documents.first(where: { $0.id == documentID }) else { return }
                    home = document.homeCurrency ?? "USD"; target = document.budgetTarget ?? 0; hasTarget = document.budgetTarget != nil || !TripBudget.isConfigured(document); companions = document.companions ?? []
                }
                .task {
                    guard api.isSignedIn else { return }
                    do { async let f = api.friends(); async let g = api.conversations(); (friends, groups) = try await (f, g) }
                    catch { peopleError = "Friends could not load. You can still add companions by name." }
                }
        }
    }
    private func add(_ person: TripCompanion) {
        guard !companions.contains(where: { $0.id == person.id }) else { return }
        guard companions.count < 40 else { error = "A trip supports up to 40 companions."; return }
        companions.append(person)
    }
    private func remove(_ person: TripCompanion) {
        guard let document = library.documents.first(where: { $0.id == documentID }) else { return }
        let costs = document.events.compactMap(\.cost) + document.hotels.compactMap(\.cost) + document.flights.compactMap(\.cost)
        guard !costs.contains(where: { $0.paidBy == person.id || $0.splitBetween?.contains(person.id) == true }) else { error = "Remove this companion from existing cost splits first."; return }
        companions.removeAll { $0.id == person.id }
    }
    private func save() {
        guard var document = library.documents.first(where: { $0.id == documentID }) else { return }
        document.homeCurrency = home; document.budgetTarget = hasTarget ? target : nil; document.companions = companions
        if library.save(document) { dismiss() } else { error = library.error }
    }
}

struct TripBudgetDashboard: View {
    let initial: JourneyDocument
    var editable = true
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rates = TripRatesStore.shared
    @State private var settings = false
    @State private var adding = false
    @State private var selected: BudgetLedger.Entry?
    @State private var filter = "All"
    @State private var search = ""
    private var document: JourneyDocument { editable ? (library.documents.first { $0.id == initial.id } ?? initial) : initial }
    private var canEdit: Bool { editable && library.documents.contains { $0.id == initial.id } }
    private var home: String { document.homeCurrency ?? "USD" }
    private var quote: TripExchangeRates? { rates.value(server: api.baseURL) }
    private var entries: [BudgetLedger.Entry] { BudgetLedger.entries(document) }
    private var paid: [BudgetLedger.Entry] { entries.filter(\.spent) }
    private var actual: Decimal? { convert(BudgetLedger.totals(paid)) }
    private var planned: Decimal? { convert(document.totals) }
    private var filtered: [BudgetLedger.Entry] { entries.filter { (filter == "All" || ($0.spent ? filter == "Spent" : filter == "Planned")) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) } }
    private var taskKey: String { [home, api.baseURL, String(api.isSignedIn), String(describing: scenePhase), document.totals.keys.sorted().joined()].joined(separator: "|") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.routeLabel.isEmpty ? document.title : document.routeLabel).font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Color.bronze).lineLimit(2)
                    Text("A little clarity.\nMore room to explore.").font(.system(size: 31, weight: .regular, design: .serif))
                }
                overview
                breakdown
                if !paid.isEmpty && document.dateMode == .dates { dailySpending }
                if !(document.companions ?? []).isEmpty { companions }
                history
                details
            }.padding(22)
        }.accessibilityIdentifier("budget-dashboard").background(Color.canvas).navigationTitle("Trip budget").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { if canEdit { Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Budget settings").accessibilityIdentifier("budget-dashboard-settings") } } }
            .safeAreaInset(edge: .bottom) {
                if canEdit {
                    HStack {
                        Spacer(minLength: 0)
                        Button { adding = true } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                                    .symbolEffect(.bounce, value: adding && !reduceMotion)
                                Text("Add expense").font(.subheadline.weight(.semibold))
                            }.foregroundStyle(colorScheme == .dark ? Color(red: 0.12, green: 0.15, blue: 0.14) : Color.white)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                        }.buttonStyle(.glassProminent).controlSize(.regular).frame(minHeight: 44)
                            .sensoryFeedback(.impact(weight: .light), trigger: adding) { _, value in value }
                            .accessibilityIdentifier("budget-add-expense")
                    }.padding(.horizontal, 22).padding(.bottom, 10)
                }
            }
            .sheet(isPresented: $settings) { TripBudgetEditor(documentID: document.id) }
            .sheet(isPresented: $adding) { BudgetExpenseEditor(documentID: document.id) }
            .sheet(item: $selected) { BudgetExpenseEditor(documentID: document.id, initial: $0) }
            .task(id: taskKey) { if scenePhase == .active && entries.contains(where: { $0.money.currency != home }) { await rates.refresh(api: api) } }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) { heroNumbers; Spacer(minLength: 0); BudgetProgressRing(spent: actual, target: document.budgetTarget) }
                VStack(alignment: .leading, spacing: 18) { heroNumbers; BudgetProgressRing(spent: actual, target: document.budgetTarget) }
            }
            Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
            HStack(alignment: .top, spacing: 20) {
                heroMetric("Total planned", value: planned.map(money) ?? "Unavailable")
                if let days = TripBudget.elapsedDays(document) { heroMetric("Spent per day", value: actual.map { money($0 / Decimal(days)) } ?? "Unavailable") }
                else { heroMetric("Daily pace", value: "Starts with your trip") }
            }
        }.padding(24).foregroundStyle(.white).background {
            RoundedRectangle(cornerRadius: 28).fill(Color(red: 0.12, green: 0.17, blue: 0.17))
                .overlay(alignment: .topTrailing) { Circle().stroke(.white.opacity(0.035), lineWidth: 40).frame(width: 230, height: 230).offset(x: 60, y: -90).clipped() }
        }.clipShape(.rect(cornerRadius: 28))
    }
    private var heroNumbers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SPENT SO FAR · " + home).font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.65))
            Text(actual.map(money) ?? "—").font(.system(size: 37, weight: .regular, design: .serif)).minimumScaleFactor(0.7).lineLimit(1).accessibilityIdentifier("budget-spent-total")
            if let target = document.budgetTarget, let actual {
                Text(money(abs(target - actual)) + (actual > target ? " over target" : " left to enjoy")).font(.subheadline).foregroundStyle(actual > target ? Color(red: 0.96, green: 0.70, blue: 0.59) : Color(red: 0.80, green: 0.86, blue: 0.74))
                Text("of " + money(target) + " budget").font(.caption).foregroundStyle(.white.opacity(0.6))
            } else { Text(actual == nil ? "Original amounts below" : "No target set").font(.caption).foregroundStyle(.white.opacity(0.65)) }
        }.frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
    }
    private func heroMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption).foregroundStyle(.white.opacity(0.62)); Text(value).font(.system(.title3, design: .serif)).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("Where it goes", subtitle: "Recorded spending")
            if paid.isEmpty { empty("Your spending story starts here.", detail: "Add an expense, mark an activity done, or mark a booking paid.") }
            else {
                VStack(spacing: 18) {
                    ForEach(BudgetLedger.Category.allCases.filter { category in paid.contains { $0.category == category } }) { category in
                        categoryRow(category)
                    }
                }.padding(20).cardSurface(cornerRadius: 23)
            }
        }
    }
    private func categoryRow(_ category: BudgetLedger.Category) -> some View {
        let totals = BudgetLedger.totals(paid.filter { $0.category == category })
        let amount = convert(totals)
        return VStack(spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: category.symbol).foregroundStyle(category.tint).frame(width: 20)
                Text(category.rawValue).font(.subheadline)
                Spacer(minLength: 6)
                Text(amount.map(money) ?? original(totals)).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing)
            }
            if let actual, actual > 0, let amount {
                GeometryReader { geometry in
                    Capsule().fill(category.tint.opacity(0.1))
                    Capsule().fill(category.tint).frame(width: geometry.size.width * min(1, max(0, NSDecimalNumber(decimal: amount / actual).doubleValue)))
                }.frame(height: 5).accessibilityHidden(true)
            }
        }
    }
    private var dailySpending: some View {
        let dates = Array(Set(paid.compactMap(\.date))).sorted().suffix(14)
        let values = dates.map { date in (date: date, value: convert(BudgetLedger.totals(paid.filter { $0.date == date }))) }
        let maxValue = values.compactMap(\.value).max() ?? 0
        return VStack(alignment: .leading, spacing: 16) {
            sectionHeading("The rhythm of your trip", subtitle: "By itinerary day")
            VStack(alignment: .leading, spacing: 12) {
                if values.allSatisfy({ $0.value != nil }) {
                    HStack(alignment: .bottom, spacing: 7) {
                        ForEach(values, id: \.date) { day in
                            VStack(spacing: 7) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 5).fill(Color.bronze.opacity(day.value == maxValue ? 0.9 : 0.35)).frame(height: maxValue > 0 ? max(3, NSDecimalNumber(decimal: (day.value ?? 0) / maxValue).doubleValue * 65) : 3).frame(maxWidth: 28)
                                Text(String(day.date.suffix(2))).font(.system(size: 9)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore).accessibilityLabel(TravelDay.label(day.date) + ": " + money(day.value ?? 0))
                        }
                    }.frame(height: 95)
                    if let first = dates.first, let last = dates.last { Text(TravelDay.label(first) + " – " + TravelDay.label(last)).font(.caption).foregroundStyle(.secondary) }
                } else { Text("The chart appears when all conversion rates are available.").font(.caption).foregroundStyle(.secondary) }
                Text("Done activities and paid bookings, shown on their itinerary dates. Up to 14 spending days.").font(.caption2).foregroundStyle(.secondary)
            }.padding(20).cardSurface(cornerRadius: 23)
        }
    }
    private var companions: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Shared adventures", subtitle: "Who paid, who’s owed")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(document.companions ?? []) { person in companionCard(person) }
            }
            DisclosureGroup("Settle up") {
                let transfers = TripBudget.settlements(document)
                if transfers.isEmpty { Text("All square for recorded splits.").font(.subheadline).padding(.top, 10) }
                ForEach(transfers) { transfer in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) { Text(name(transfer.from) + " owes " + name(transfer.to)).font(.subheadline); Text("Suggested transfer").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Text(transfer.money.formatted).font(.subheadline.weight(.semibold))
                    }.padding(.vertical, 10)
                }
                Text("Equal splits of done or paid costs. Original currencies are preserved. This does not send money.").font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline.weight(.medium)).tint(.bronze).padding(20).cardSurface(cornerRadius: 23).accessibilityIdentifier("trip-settlement")
        }
    }
    private func companionCard(_ person: TripCompanion) -> some View {
        let balances = BudgetLedger.balance(person.id, in: document)
        let paidTotals = BudgetLedger.totals(paid.filter { $0.money.paidBy == person.id })
        return VStack(alignment: .leading, spacing: 12) {
            Text(String(person.name.prefix(1)).uppercased()).font(.system(.title3, design: .serif)).foregroundStyle(Color.bronze).frame(width: 36, height: 36).background(Color.bronze.opacity(0.09), in: .circle)
            Text(person.name).font(.headline)
            if balances.isEmpty { Text("All square").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(balances.keys.sorted(), id: \.self) { currency in
                let value = balances[currency] ?? 0
                VStack(alignment: .leading, spacing: 3) {
                    Text(TravelMoney(amount: abs(value), currency: currency).formatted).font(.system(.title3, design: .serif)).foregroundStyle(value > 0 ? Color.bronze : Color.primary)
                    Text(value > 0 ? "Gets back" : "Owes").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(paidTotals.isEmpty ? "No shared payments" : "Paid " + original(paidTotals)).font(.caption2).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).cardSurface(cornerRadius: 22)
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Every little detail", subtitle: "Expense history · \(entries.count)")
            HStack(spacing: 8) {
                ForEach(["All", "Spent", "Planned"], id: \.self) { value in
                    Button { filter = value } label: { Text(value).font(.subheadline.weight(.medium)).padding(.horizontal, 17).padding(.vertical, 10).background(filter == value ? Color.bronze.opacity(0.14) : Color.cardSurface, in: .capsule) }.buttonStyle(.plain).accessibilityIdentifier("budget-filter-" + value).accessibilityAddTraits(filter == value ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            if !entries.isEmpty { HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Find an expense", text: $search).font(.subheadline).accessibilityIdentifier("budget-expense-search") }.padding(15).cardSurface(cornerRadius: 16) }
            if filtered.isEmpty { Text(entries.isEmpty ? "Your expenses will appear here." : "No expenses match this view.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 14) }
            LazyVStack(spacing: 0) {
                ForEach(filtered) { entry in
                    Button { selected = entry } label: { expenseRow(entry) }.buttonStyle(.plain).disabled(!canEdit).accessibilityIdentifier("budget-expense-" + entry.id)
                    if entry.id != filtered.last?.id { Divider().padding(.leading, 53) }
                }
            }
        }
    }
    private func expenseRow(_ entry: BudgetLedger.Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.category.symbol).font(.system(size: 16, weight: .light)).foregroundStyle(entry.category.tint).frame(width: 40, height: 40).background(entry.category.tint.opacity(0.08), in: .rect(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text([entry.date.map(TravelDay.label), entry.money.paidBy.map(name)].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                Text(entry.money.formatted).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(entry.spent ? "Spent" : "Planned").font(.caption2).foregroundStyle(entry.spent ? Color.bronze : Color.secondary)
            }
        }.padding(.vertical, 16).contentShape(Rectangle())
    }
    private var details: some View {
        DisclosureGroup("About these totals") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Spent includes done activities and bookings marked paid. Planned includes all recorded prices. Unpriced items are excluded.").font(.caption)
                ForEach(document.totals.keys.sorted(), id: \.self) { currency in Text(currency + " · Spent " + TravelMoney(amount: TripBudget.spent(document)[currency] ?? 0, currency: currency).formatted + " · Planned " + TravelMoney(amount: document.totals[currency] ?? 0, currency: currency).formatted).font(.caption) }
                if entries.contains(where: { $0.money.currency != home }) {
                    Text(quote == nil ? "Sign in and connect to load currency estimates. Original amounts are always shown in history." : "Estimated in " + home + " using Frankfurter reference rates · " + (quote!.isCurrent ? "Daily rates" : "Saved rates; refresh needed")).font(.caption)
                    if let quote { Text(Set(quote.dates.values).sorted().joined(separator: ", ")).font(.caption2) }
                    if let error = rates.error { Text(error).font(.caption) }
                    Button("Refresh rates") { Task { await rates.refresh(api: api) } }.disabled(!api.isSignedIn).font(.caption)
                }
            }.foregroundStyle(.secondary).padding(.top, 12)
        }.font(.caption).tint(.bronze)
    }
    private func convert(_ totals: [String: Decimal]) -> Decimal? { TripBudget.converted(totals, home: home, rates: quote) }
    private func money(_ value: Decimal) -> String { TravelMoney(amount: value, currency: home).formatted }
    private func original(_ totals: [String: Decimal]) -> String { totals.keys.sorted().map { TravelMoney(amount: totals[$0] ?? 0, currency: $0).formatted }.joined(separator: " · ") }
    private func name(_ id: String) -> String { document.companions?.first { $0.id == id }?.name ?? "Companion" }
    private func sectionHeading(_ title: String, subtitle: String) -> some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(.title2, design: .serif)); Text(subtitle).font(.caption).foregroundStyle(.secondary) } }
    private func empty(_ title: String, detail: String) -> some View { VStack(alignment: .leading, spacing: 10) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }.padding(20).frame(maxWidth: .infinity, alignment: .leading).cardSurface(cornerRadius: 23) }
}

private struct BudgetProgressRing: View {
    let spent: Decimal?
    let target: Decimal?
    private var fraction: Double { guard let spent, let target else { return 0 }; return target > 0 ? min(1, max(0, NSDecimalNumber(decimal: spent / target).doubleValue)) : spent > 0 ? 1 : 0 }
    private var percentage: String {
        guard let spent, let target else { return "—" }
        guard target > 0 else { return spent > 0 ? "Over" : "0%" }
        let ratio = NSDecimalNumber(decimal: spent / target).doubleValue
        return ratio > 9.99 ? "999%+" : ratio.formatted(.percent.precision(.fractionLength(0)))
    }
    private var caption: String { target == nil ? "no target" : spent == nil ? "rates needed" : "of budget" }
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.09), lineWidth: 9)
            Circle().trim(from: 0, to: fraction).stroke(AngularGradient(colors: [Color(red: 0.66, green: 0.51, blue: 0.32), Color(red: 0.90, green: 0.80, blue: 0.60)], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)), style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 4) { Text(percentage).font(.system(.title3, design: .serif)); Text(caption).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)) }
        }.frame(width: 100, height: 100).padding(5).accessibilityElement(children: .ignore).accessibilityLabel(percentage + " " + caption + (spent == nil || target == nil ? "" : " spent"))
    }
}
private extension BudgetLedger.Category {
    var tint: Color { switch self { case .stays: Color.bronze; case .transport: Color(red: 0.43, green: 0.55, blue: 0.57); case .dining: Color(red: 0.65, green: 0.49, blue: 0.37); case .experiences: Color(red: 0.48, green: 0.57, blue: 0.45); case .shopping: Color(red: 0.57, green: 0.51, blue: 0.61); case .other: Color.secondary } }
}

private struct BudgetExpenseEditor: View {
    let documentID: UUID
    var initial: BudgetLedger.Entry?
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amount: Decimal = 0
    @State private var currency = "USD"
    @State private var category: BudgetLedger.Category = .other
    @State private var dayID = ""
    @State private var spent = true
    @State private var split = false
    @State private var payer = ""
    @State private var people: Set<String> = []
    @State private var error: String?
    @State private var loaded = false
    private var document: JourneyDocument? { library.documents.first { $0.id == documentID } }
    private var companions: [TripCompanion] { document?.companions ?? [] }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(initial == nil ? "Make room for the memories." : title).font(.system(.title2, design: .serif))
                        Text(initial == nil ? "A quick note of what you spent, or what you’re planning." : "Update the price and payment details of this itinerary item.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8).listRowBackground(Color.clear)
                }
                if initial == nil {
                    Section {
                        TextField("What was it for?", text: $title).accessibilityIdentifier("budget-expense-title")
                        Picker("Category", selection: $category) { ForEach(BudgetLedger.Category.allCases) { Text($0.rawValue).tag($0) } }
                        Picker("Trip day", selection: $dayID) { ForEach(document?.days ?? []) { day in Text(day.label + " · " + day.city).tag(day.id) } }
                    } header: { Text("The details") } footer: { Text("This expense also appears on the selected day’s itinerary.") }
                }
                Section {
                    HStack {
                        TextField("Amount", value: $amount, format: .number).font(.system(.title, design: .serif)).keyboardType(.decimalPad).accessibilityIdentifier("budget-expense-amount")
                        Picker("Currency", selection: $currency) { ForEach(TravelMoney.currencies, id: \.self) { Text($0).tag($0) } }.labelsHidden()
                    }
                    Toggle("Include in spent", isOn: $spent).accessibilityIdentifier("budget-expense-paid")
                } header: { Text("Amount") } footer: { Text("Spent marks an activity done or a booking paid. Turn it off to keep the cost planned.") }
                if !companions.isEmpty {
                    Section("Share the cost") {
                        Toggle("Split with companions", isOn: $split).accessibilityIdentifier("budget-expense-split")
                        if split {
                            Picker("Who paid", selection: $payer) { ForEach(companions) { Text($0.name).tag($0.id) } }
                            ForEach(companions) { person in
                                Toggle(person.name, isOn: Binding(get: { people.contains(person.id) }, set: { if $0 { people.insert(person.id) } else { people.remove(person.id) } }))
                            }
                            Text("Split equally between the selected companions.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(Color.canvas).tint(.bronze)
                .navigationTitle(initial == nil ? "Add expense" : "Edit expense").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold).accessibilityIdentifier("budget-expense-save") }
                }
                .alert("Check this expense", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
                .onAppear {
                    guard !loaded, let document else { return }; loaded = true
                    currency = initial?.money.currency ?? document.homeCurrency ?? "USD"
                    title = initial?.title ?? ""; amount = initial?.money.amount ?? 0; spent = initial?.spent ?? true
                    split = initial?.money.paidBy != nil; payer = initial?.money.paidBy ?? companions.first?.id ?? ""
                    people = Set(initial?.money.splitBetween ?? companions.map(\.id))
                    dayID = document.days.first(where: { $0.date == TravelDay.key(.now) })?.id ?? document.days.first?.id ?? ""
                }
        }
    }
    private func save() {
        guard var document else { error = "This trip is no longer available."; return }
        guard !amount.isNaN, amount >= 0, amount <= 1_000_000_000 else { error = "Enter an amount between 0 and 1 billion."; return }
        guard !split || (!people.isEmpty && companions.contains { $0.id == payer }) else { error = "Choose who paid and at least one person to split with."; return }
        let money = TravelMoney(amount: amount, currency: currency, paidBy: split ? payer : nil, splitBetween: split ? people.sorted() : nil, isPaid: spent)
        if let initial {
            switch initial.source {
            case .event(let id):
                guard let index = document.events.firstIndex(where: { $0.id == id }) else { error = "This expense was removed."; return }
                document.events[index].cost = money; document.events[index].isDone = spent
            case .hotel(let id):
                guard let index = document.hotels.firstIndex(where: { $0.id == id }) else { error = "This booking was removed."; return }
                document.hotels[index].cost = money
            case .flight(let id):
                guard let index = document.flights.firstIndex(where: { $0.id == id }) else { error = "This booking was removed."; return }
                document.flights[index].cost = money
            }
        } else {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 200 else { error = "Add a short expense name (up to 200 characters)."; return }
            guard let day = document.days.first(where: { $0.id == dayID }) else { error = "Choose an available trip day."; return }
            var event = JourneyEvent(stopID: day.stopID, day: day.localDay)
            event.kind = category == .transport ? .transfer : category == .shopping ? .shopping : .custom
            event.title = trimmed; event.allDay = true; event.place.category = category.placeCategory
            event.cost = money; event.isDone = spent
            document.events.append(event)
        }
        if library.save(document) { dismiss() } else { error = library.error ?? "The expense could not be saved." }
    }
}
