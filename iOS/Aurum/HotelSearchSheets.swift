import SwiftUI

// Restrained surfaces and motion shared by the entire hotel flow.
enum StayStyle {
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let ink = Color.primary
    static func motion(_ reduce: Bool) -> Animation? { reduce ? nil : .smooth(duration: 0.28, extraBounce: 0) }
}
struct StayPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reduce ? 0.985 : 1)
            .animation(StayStyle.motion(reduce), value: configuration.isPressed)
    }
}
struct StayBottomBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(.horizontal, 22).padding(.vertical, 14).frame(maxWidth: .infinity)
            .background(StayStyle.background.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Divider() }
    }
}
struct StayPrimaryButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).padding(.vertical, 12).padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(StayStyle.background).background(Color.primary, in: .rect(cornerRadius: 16)) }.buttonStyle(StayPressStyle())
    }
}
private struct StayFullPageKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var stayFullPage: Bool { get { self[StayFullPageKey.self] } set { self[StayFullPageKey.self] = newValue } }
}
extension View {
    func hotelFlowPage() -> some View {
        self.environment(\.stayFullPage, true).toolbar(.hidden, for: .navigationBar).toolbar(.hidden, for: .tabBar)
    }
}
struct StaySheetHeader: View {
    let title: String
    var back: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.stayFullPage) private var fullPage
    var body: some View {
        HStack(spacing: 12) {
            if fullPage || back != nil {
                Button { if let back { back() } else { dismiss() } } label: {
                    Image(systemName: "arrow.left").font(.body.weight(.medium)).frame(width: 44, height: 44)
                }.accessibilityLabel("Previous step").accessibilityIdentifier("hotel-step-back")
            }
            Text(title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !fullPage {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44).background(StayStyle.surface, in: .circle) }.accessibilityLabel("Close " + title)
            }
        }.dynamicTypeSize(...DynamicTypeSize.accessibility2).buttonStyle(StayPressStyle()).tint(.primary)
            .padding(.horizontal, fullPage ? 14 : 22).padding(.top, fullPage ? 6 : 18).padding(.bottom, 8)
    }
}

enum HotelSetupStep: String, Identifiable, Hashable {
    case destination, dates, guests
    var id: Self { self }
}

/// A single page with progressive inputs. Draft criteria only commit on completion.
struct HotelStaySetupPage: View {
    @Binding var selection: HotelStayPreferences
    var onComplete: (ExploreCity?) -> Void
    @Environment(TravelStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var draft: HotelStayPreferences
    @State private var city: ExploreCity?
    @State private var query = ""
    @State private var step: HotelSetupStep
    private let firstStep: HotelSetupStep
    init(selection: Binding<HotelStayPreferences>, city: ExploreCity? = nil, startingStep: HotelSetupStep? = nil, onComplete: @escaping (ExploreCity?) -> Void) {
        _selection = selection; self.onComplete = onComplete
        _draft = State(initialValue: selection.wrappedValue); _city = State(initialValue: city)
        let first = startingStep ?? (city == nil ? .destination : .dates)
        firstStep = first; _step = State(initialValue: first)
    }
    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .destination:
                    VStack(spacing: 0) {
                        StaySheetHeader(title: "Where are you staying?")
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                LocationAutocompleteField("Search a destination", text: $query, kind: .city, identifier: "hotel-destination", onSelect: { if let city = ExploreCity($0) { choose(city) } })
                                    .padding(18).background(StayStyle.surface, in: .rect(cornerRadius: 18))
                                NavigationLink { HotelNameSearchView() } label: {
                                    HStack { Label("Search a specific hotel", systemImage: "bed.double"); Spacer(); Image(systemName: "arrow.up.right") }.font(.subheadline.weight(.medium)).padding(.vertical, 10)
                                }.buttonStyle(StayPressStyle()).tint(.primary).accessibilityIdentifier("hotel-search-by-name")
                                if query.isEmpty {
                                    Text("Destinations").font(.subheadline.weight(.semibold))
                                    ForEach(Array((store.recentExploreCities.isEmpty ? DestinationSuggestions.cities.filter { ["Rome", "Kyoto", "Paris", "London", "Lisbon"].contains($0.name) } : store.recentExploreCities).prefix(6))) { city in
                                        HotelDestinationRow(city: city) { choose(city) }
                                    }
                                }
                            }.padding(22)
                        }.scrollDismissesKeyboard(.interactively)
                    }
                case .dates:
                    HotelDatesSheet(selection: $draft, dismissOnComplete: false, onComplete: { step = .guests }, onBack: firstStep == .destination ? { step = .destination } : nil)
                case .guests:
                    HotelGuestsSheet(selection: $draft, dismissOnComplete: false, onComplete: { selection = draft; onComplete(city) }, onBack: firstStep == .guests ? nil : { step = .dates })
                }
            }.id(step).transition(.opacity)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(StayStyle.background).hotelFlowPage()
            .animation(StayStyle.motion(reduce), value: step).sensoryFeedback(.selection, trigger: step)
    }
    private func choose(_ value: ExploreCity) { city = value; query = value.name; step = .dates }
}

struct HotelBookingFlow: View {
    var city: ExploreCity? = nil
    @Environment(TravelStore.self) private var store
    @Environment(TravelAPI.self) private var api
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var showingResults = false
    var body: some View {
        @Bindable var model = store.hotelSearch
        Group {
            if showingResults { HotelSearchView() }
            else {
                HotelStaySetupPage(selection: $model.stay, city: city) { selected in
                    guard let selected else { return }
                    model.clear(); model.filters = HotelResultFilters(); model.hotelName = ""; model.stars = ""; model.score = ""; model.sortByName = false; model.sortByPrice = false
                    store.rememberExploreCity(selected); model.select(selected, api: api); model.refreshRates(api: api)
                    showingResults = true
                }
            }
        }.hotelFlowPage().animation(StayStyle.motion(reduce), value: showingResults)
    }
}
struct StayChip: View {
    let title: String
    let symbol: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.caption.weight(.medium)).padding(.horizontal, 13).frame(minHeight: 40).background(selected ? Color.primary.opacity(0.09) : StayStyle.surface, in: .capsule) }.buttonStyle(StayPressStyle()).tint(.primary)
    }
}
struct HotelDatesSheet: View {
    @Binding var selection: HotelStayPreferences
    var dismissOnComplete = true
    var onComplete: () -> Void = {}
    var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var draft: HotelStayPreferences
    @State private var completion: Task<Void, Never>?
    @State private var finishing = false
    private let calendar = Calendar.current
    init(selection: Binding<HotelStayPreferences>, dismissOnComplete: Bool = true, onComplete: @escaping () -> Void = {}, onBack: (() -> Void)? = nil) { _selection = selection; self.dismissOnComplete = dismissOnComplete; self.onBack = onBack; self.onComplete = onComplete; _draft = State(initialValue: selection.wrappedValue) }
    private var months: [Date] {
        let month = calendar.dateInterval(of: .month, for: .now)!.start
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: month) }
    }
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: "Your dates", back: onBack.map { action in { action(); if dismissOnComplete { dismiss() } } })
            HStack(spacing: 0) {
                dateSummary("Check-in", draft.checkIn, active: draft.checkIn == nil || draft.checkOut != nil)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                dateSummary("Check-out", draft.checkOut, active: draft.checkIn != nil && draft.checkOut == nil)
            }.dynamicTypeSize(...DynamicTypeSize.accessibility1).padding(.horizontal, 22).padding(.vertical, 14)
            HStack(spacing: 0) { ForEach(0..<7) { offset in Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + offset) % 7]).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).padding(.horizontal, 22).padding(.vertical, 12)
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 26) { ForEach(months, id: \.self) { month in monthView(month).id(month) } }.padding(22)
                }.task { if let start = draft.checkIn, let month = calendar.dateInterval(of: .month, for: start)?.start { reader.scrollTo(month, anchor: .top) } }
            }
            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack { nightsLabel; Spacer(); clearButton }
                    VStack(alignment: .leading, spacing: 8) { nightsLabel; clearButton }
                }
                StayPrimaryButton(title: draft.checkIn == nil ? "Stay flexible" : "Apply dates") { apply() }.disabled(!draft.datesValid).opacity(draft.datesValid ? 1 : 0.4).accessibilityIdentifier("hotel-dates-apply")
            }.padding(22).background(StayStyle.background)
        }.background(StayStyle.background).presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(28)
        .sensoryFeedback(.selection, trigger: draft.checkIn)
        .sensoryFeedback(.success, trigger: draft.checkOut) { _, value in value != nil }
        .onDisappear { completion?.cancel() }
    }
    private var nightsLabel: some View {
        Text(draft.nights > 30 ? "Choose up to 30 nights" : draft.nights > 0 ? "\(draft.nights) \(draft.nights == 1 ? "night" : "nights")" : draft.checkIn != nil ? "Choose a check-out date" : "Dates flexible").font(.subheadline).foregroundStyle(.secondary)
    }
    private var clearButton: some View {
        Button("Clear") { withAnimation(StayStyle.motion(reduce)) { draft.checkIn = nil; draft.checkOut = nil } }.font(.subheadline).tint(.primary).accessibilityIdentifier("hotel-dates-clear")
    }
    private func apply() {
        guard draft.datesValid else { return }
        selection.checkIn = draft.checkIn; selection.checkOut = draft.checkOut; onComplete(); if dismissOnComplete { dismiss() }
    }
    private func select(_ date: Date) {
        guard !finishing else { return }
        withAnimation(StayStyle.motion(reduce)) { draft.select(date) }
        if draft.nights > 0 && draft.datesValid {
            finishing = true
            completion = Task { do { try await Task.sleep(for: .milliseconds(220)); try Task.checkCancellation(); apply() } catch { } }
        }
    }
    private func dateSummary(_ title: String, _ date: Date?, active: Bool) -> some View {
        VStack(spacing: 7) { Text(title).font(.caption).foregroundStyle(.secondary); Text(date?.formatted(.dateTime.month(.abbreviated).day()) ?? "Select date").font(.headline).fixedSize(horizontal: false, vertical: true); Capsule().fill(active ? Color.primary : .clear).frame(width: 28, height: 2) }.frame(maxWidth: .infinity)
    }
    private func monthView(_ month: Date) -> some View {
        let days = calendar.range(of: .day, in: .month, for: month)!.count
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        return VStack(alignment: .leading, spacing: 15) {
            Text(month.formatted(.dateTime.month(.wide).year())).font(.headline).dynamicTypeSize(...DynamicTypeSize.accessibility1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 5) {
                ForEach(0..<(leading + days), id: \.self) { i in
                    if i < leading { Color.clear.frame(height: 46) }
                    else { dayButton(calendar.date(byAdding: .day, value: i - leading, to: month)!) }
                }
            }
        }
    }
    private func dayButton(_ day: Date) -> some View {
        let selected = day == draft.checkIn || day == draft.checkOut
        let inRange = draft.checkIn.map { day > $0 } == true && draft.checkOut.map { day < $0 } == true
        let past = day < calendar.startOfDay(for: .now)
        return Button { select(day) } label: {
            Text(String(calendar.component(.day, from: day))).font(.subheadline.weight(selected ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(selected ? StayStyle.background : past ? Color.secondary.opacity(0.4) : Color.primary)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background { if selected { Circle().fill(Color.primary).padding(2) } else if inRange { Rectangle().fill(Color.primary.opacity(0.07)) } }
        }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).buttonStyle(StayPressStyle()).disabled(past).accessibilityLabel(day.formatted(date: .complete, time: .omitted)).accessibilityValue(day == draft.checkIn ? "Check-in" : day == draft.checkOut ? "Check-out" : "")
            .accessibilityIdentifier("hotel-date-" + TravelDay.key(day))
    }
}
struct HotelGuestsSheet: View {
    @Environment(TravelAPI.self) private var api
    @State private var travelerPicker = false
    @State private var travelerID: String?
    @State private var nationality: String
    @State private var travelerChosen = false
    @Binding var selection: HotelStayPreferences
    var dismissOnComplete = true
    var onComplete: () -> Void = {}
    var onBack: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var completed = false
    @Environment(\.stayFullPage) private var fullPage
    @Environment(\.dismiss) private var dismiss
    @State private var roomGuests: [HotelOccupancy]
    @State private var currency: String
    @State private var childAge: HotelChildAgeRoute?
    init(selection: Binding<HotelStayPreferences>, dismissOnComplete: Bool = true, onComplete: @escaping () -> Void = {}, onBack: (() -> Void)? = nil) {
        _selection = selection; self.dismissOnComplete = dismissOnComplete; self.onBack = onBack; self.onComplete = onComplete
        _roomGuests = State(initialValue: selection.wrappedValue.occupancies)
        _currency = State(initialValue: selection.wrappedValue.currency)
        _travelerID = State(initialValue: selection.wrappedValue.travelerID)
        _nationality = State(initialValue: selection.wrappedValue.guestNationality)
    }
    private var valid: Bool { roomGuests.allSatisfy(\.valid) && roomGuests.reduce(0) { $0 + $1.adults + $1.children.count } <= 24 }
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: "Who's coming?", back: onBack.map { action in { action(); if dismissOnComplete { dismiss() } } })
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if api.travelerAccess {
                        Button { travelerPicker = true } label: {
                            HStack { VStack(alignment: .leading, spacing: 5) { Text("Lead traveler").font(.caption).foregroundStyle(.secondary); Text(api.travelers.profiles.first(where: { $0.id == travelerID })?.name ?? "Choose a saved traveler").font(.subheadline.weight(.medium)) }; Spacer(); Image(systemName: "person.crop.circle").font(.title3) }.padding(18).background(StayStyle.surface, in: .rect(cornerRadius: 18))
                        }.buttonStyle(StayPressStyle()).tint(.primary).accessibilityIdentifier("hotel-saved-traveler")
                        if let error = api.travelers.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    }
                    ForEach($roomGuests) { $room in
                        let index = roomGuests.firstIndex(where: { $0.id == room.id }) ?? 0
                        VStack(alignment: .leading, spacing: 18) {
                            HStack { Text("Room \(index + 1)").font(.headline); Spacer(); if roomGuests.count > 1 { Button("Remove") { roomGuests.removeAll { $0.id == room.id } }.font(.caption).tint(.secondary).accessibilityIdentifier("hotel-remove-room-\(index)") } }
                            counter("Adults", value: $room.adults, bounds: 1...8, id: index == 0 ? "hotel-adults" : "hotel-adults-\(index)")
                            counter("Children", value: Binding(get: { room.children.count }, set: { count in if count > room.children.count { room.children.append(-1) } else { room.children.removeLast() } }), bounds: 0...4, id: "hotel-children-\(index)")
                            ForEach(0..<4, id: \.self) { child in
                                if child < room.children.count {
                                    if fullPage {
                                        Button { childAge = HotelChildAgeRoute(roomID: room.id, child: child) } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 5) { Text("Child \(child + 1) age at check-in").font(.caption).foregroundStyle(.secondary); Text(room.children[child] < 0 ? "Choose age" : room.children[child] == 0 ? "Under 1" : "\(room.children[child])").font(.subheadline) }
                                                Spacer(); Image(systemName: "chevron.right").font(.caption)
                                            }.frame(minHeight: 44).contentShape(.rect)
                                        }.buttonStyle(StayPressStyle()).tint(.primary).accessibilityIdentifier("hotel-child-age-\(index)-\(child)")
                                    } else {
                                        Picker("Child \(child + 1) age at check-in", selection: Binding(get: { room.children.indices.contains(child) ? room.children[child] : -1 }, set: { if room.children.indices.contains(child) { room.children[child] = $0 } })) {
                                            Text("Choose age").tag(-1)
                                            ForEach(0...17, id: \.self) { Text($0 == 0 ? "Under 1" : "\($0)").tag($0) }
                                        }.pickerStyle(.menu).font(.subheadline).tint(.primary).accessibilityIdentifier("hotel-child-age-\(index)-\(child)")
                                    }
                                }
                            }
                        }
                        Divider()
                    }
                    if roomGuests.count < 8 { Button("Add a room", systemImage: "plus") { roomGuests.append(HotelOccupancy()) }.font(.subheadline.weight(.medium)).tint(.primary).accessibilityIdentifier("hotel-add-room") }
                    HStack { Text("Currency").font(.subheadline); Spacer(); Picker("Currency", selection: $currency) { ForEach(["USD", "EUR", "GBP", "CAD", "AUD", "JPY", "CHF", "SGD", "THB", "AED", "HKD", "NZD", "INR", "KWD", "BHD"], id: \.self) { Text($0).tag($0) } }.labelsHidden().font(.subheadline).tint(.primary).accessibilityIdentifier("hotel-currency") }
                }.padding(.horizontal, 24).padding(.vertical, 18)
            }.scrollBounceBehavior(.basedOnSize)
            StayPrimaryButton(title: "Continue") {
                selection.adults = roomGuests.reduce(0) { $0 + $1.adults }; selection.rooms = roomGuests.count; selection.roomGuests = roomGuests; selection.travelerID = travelerID; selection.guestNationality = nationality.isEmpty ? "US" : nationality; selection.currency = currency
                completed = true; onComplete(); if dismissOnComplete { dismiss() }
            }.disabled(!valid || api.travelers.loading).opacity(valid ? 1 : 0.4).accessibilityIdentifier("hotel-guests-apply").padding(22)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(StayStyle.background).presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(28)
        .task {
            await api.loadTravelers()
            guard !travelerChosen else { return }
            let profile = travelerID.flatMap { id in api.travelers.profiles.first { $0.id == id } } ?? api.travelers.defaultProfile
            if let profile { travelerID = profile.id; nationality = profile.nationality }
        }
        .navigationDestination(isPresented: $travelerPicker) {
            TravelerProfilesPage(onSelect: { profile in travelerID = profile.id; nationality = profile.nationality; travelerChosen = true }).hotelFlowPage()
        }
        .navigationDestination(item: $childAge) { route in
            HotelChildAgePage(child: route.child, selected: selectedAge(route)) { age in
                guard let room = roomGuests.firstIndex(where: { $0.id == route.roomID }), roomGuests[room].children.indices.contains(route.child) else { return }
                roomGuests[room].children[route.child] = age
            }.hotelFlowPage()
        }
        .sensoryFeedback(.selection, trigger: travelerID)
        .sensoryFeedback(.success, trigger: completed)
        .sensoryFeedback(.selection, trigger: roomGuests)
        .animation(StayStyle.motion(reduce), value: roomGuests)
    }
    private func selectedAge(_ route: HotelChildAgeRoute) -> Int {
        guard let room = roomGuests.first(where: { $0.id == route.roomID }), room.children.indices.contains(route.child) else { return -1 }
        return room.children[route.child]
    }
    private func counter(_ title: String, value: Binding<Int>, bounds: ClosedRange<Int>, id: String) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout())
        return layout {
            Text(title).font(.body.weight(.medium))
            if !typeSize.isAccessibilitySize { Spacer() }
            HStack(spacing: 16) {
                Button { value.wrappedValue -= 1 } label: { Image(systemName: "minus").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44).background(StayStyle.surface, in: .circle) }.disabled(value.wrappedValue <= bounds.lowerBound).accessibilityLabel("Fewer " + title.lowercased()).accessibilityIdentifier(id + "-minus")
                Text(value.wrappedValue.formatted()).font(.headline.monospacedDigit()).frame(minWidth: 28).contentTransition(.numericText()).accessibilityIdentifier(id + "-count")
                Button { value.wrappedValue += 1 } label: { Image(systemName: "plus").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44).background(StayStyle.surface, in: .circle) }.disabled(value.wrappedValue >= bounds.upperBound).accessibilityLabel("More " + title.lowercased()).accessibilityIdentifier(id + "-plus")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).buttonStyle(StayPressStyle()).tint(.primary)
    }
}

private struct HotelChildAgeRoute: Hashable, Identifiable {
    var roomID: UUID
    var child: Int
    var id: String { roomID.uuidString + "-\(child)" }
}
private struct HotelChildAgePage: View {
    let child: Int
    let selected: Int
    var onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: "Child \(child + 1)'s age")
            Text("Age at check-in").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.bottom, 16)
            List(0...17, id: \.self) { age in
                Button { onSelect(age); dismiss() } label: {
                    HStack { Text(age == 0 ? "Under 1" : "\(age)"); Spacer(); if selected == age { Image(systemName: "checkmark") } }.frame(minHeight: 44).contentShape(.rect)
                }.buttonStyle(.plain).accessibilityIdentifier("hotel-child-age-option-\(age)")
            }.listStyle(.plain)
        }.background(StayStyle.background)
    }
}

/// A planning review, not a simulated checkout or reservation confirmation.
struct HotelStayPlanner: View {
    let hotel: LodgingHotel
    var roomName = ""
    @Environment(TravelStore.self) private var store
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var stay = HotelStayPreferences()
    @State private var tripID: UUID?
    @State private var dates = false
    @State private var guests = false
    @State private var choosingTrip = false
    @State private var error: String?
    @State private var initialized = false
    @State private var advanceGuests = false
    @State private var advanceTrip = false
    @State private var completed = false
    private var trip: JourneyDocument? { library.documents.first { $0.id == tripID } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StaySheetHeader(title: "Plan your stay")
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        HStack(spacing: 16) {
                            LodgingImage(url: hotel.photo, caption: hotel.name).frame(width: 78, height: 90).clipShape(.rect(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 7) { Text(hotel.name).font(.headline); Text(roomName.isEmpty ? hotel.city : roomName).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        VStack(spacing: 0) {
                            planningRow("Dates", value: trip?.isWishlistTrip == true ? "Flexible" : stay.dateLabel, symbol: "calendar") { dates = true }.disabled(trip?.isWishlistTrip == true).accessibilityIdentifier("hotel-plan-dates")
                            Divider()
                            planningRow("Guests", value: stay.guestLabel, symbol: "person") { guests = true }.accessibilityIdentifier("hotel-plan-guests")
                            Divider()
                            planningRow("Trip", value: trip?.title ?? "Choose a trip", symbol: "suitcase.rolling") { choosingTrip = true }.accessibilityIdentifier("hotel-plan-trip")
                        }
                        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    }.padding(22)
                }
                VStack(spacing: 12) {
                    Text("A plan, not a reservation. Availability hasn't been checked.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    StayPrimaryButton(title: "Save to trip", action: save).disabled(trip == nil || (trip?.isWishlistTrip != true && (stay.nights == 0 || !stay.datesValid))).opacity(trip == nil ? 0.4 : 1).accessibilityIdentifier("hotel-plan-save")
                }.padding(22)
            }.background(StayStyle.background).toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $choosingTrip) { HotelPlanTripPicker(selected: $tripID) }
        }.presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(28)
        .sheet(isPresented: $dates, onDismiss: { if advanceGuests { advanceGuests = false; guests = true } }) { HotelDatesSheet(selection: $stay, onComplete: { advanceGuests = true }) }
        .sheet(isPresented: $guests, onDismiss: { if advanceTrip { advanceTrip = false; choosingTrip = true } }) { HotelGuestsSheet(selection: $stay, onComplete: { advanceTrip = true }) }
        .onAppear { guard !initialized else { return }; initialized = true; stay = store.hotelSearch.stay; if stay.nights == 0 { dates = true } else { choosingTrip = true } }
        .sensoryFeedback(.success, trigger: completed)
        .onChange(of: tripID) {
            error = nil
            if stay.checkIn == nil, let trip, !trip.isWishlistTrip, let stop = trip.stops.first {
                stay.checkIn = TravelDay.localDate(stop.arrival); stay.checkOut = TravelDay.localDate(stop.departure)
            }
        }
    }
    private func planningRow(_ title: String, value: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 15) { Image(systemName: symbol).font(.body).frame(width: 22); VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.medium)) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }.padding(.vertical, 20).contentShape(.rect)
        }.buttonStyle(StayPressStyle()).tint(.primary)
    }
    private func save() {
        guard var trip else { return }
        guard !trip.hotels.contains(where: { $0.place.id == hotel.id && $0.place.source == hotel.source }) else { error = "This hotel is already in your trip."; return }
        _ = trip.preparePlanningRoute()
        let start: String, end: String
        if trip.isWishlistTrip {
            guard let stop = trip.stops.first(where: { $0.name.localizedCaseInsensitiveContains(hotel.city) }) ?? trip.stops.first else { error = "Add a destination to this trip first."; return }
            start = stop.arrival; end = stop.departure
        } else {
            guard stay.datesValid, let checkIn = stay.checkIn, let checkOut = stay.checkOut else { error = "Choose your stay dates."; return }
            start = TravelDay.key(checkIn); end = TravelDay.key(checkOut)
        }
        trip.hotels.append(HotelReservation(place: hotel.place, checkIn: start, checkOut: end, guests: stay.adults + stay.childCount, rooms: stay.rooms, roomType: roomName, notes: "Planned stay. Reservation required."))
        if library.save(trip) { store.hotelSearch.stay = stay; store.showMessage("Stay added to " + trip.title); completed = true; dismiss() }
        else { error = library.error ?? "Couldn't save your stay. Please try again." }
    }
}
private struct HotelPlanTripPicker: View {
    @Binding var selected: UUID?
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var create = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(library.documents.filter { $0.isTemplate != true }.sorted { $0.updatedAt > $1.updatedAt }) { trip in
                    Button { if selected == trip.id { dismiss() } else { selected = trip.id } } label: {
                        HStack(spacing: 15) { Image(systemName: "suitcase.rolling").frame(width: 26); VStack(alignment: .leading, spacing: 6) { Text(trip.title).font(.subheadline.weight(.medium)); Text(trip.isWishlistTrip ? "Dates flexible" : trip.routeLabel).font(.caption).foregroundStyle(.secondary) }; Spacer(); if selected == trip.id { Image(systemName: "checkmark") } }.padding(.vertical, 14).contentShape(.rect)
                    }.buttonStyle(StayPressStyle()).tint(.primary).accessibilityIdentifier("hotel-plan-trip-" + trip.id.uuidString)
                }
                Button("Create a trip", systemImage: "plus") { create = true }.font(.subheadline.weight(.medium)).tint(.primary).padding(.vertical, 18)
            }.padding(22)
        }.background(StayStyle.background).navigationTitle("Choose a trip").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $create) { TripCreationView(onCreated: { selected = $0; create = false }) }
        .onChange(of: selected) { if selected != nil { dismiss() } }
    }
}
