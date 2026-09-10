import SwiftUI

struct RoutePlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let document: JourneyDocument
    var onSave: (JourneyDocument) -> String?
    @State private var stops: [JourneyStop]
    @State private var plan: JourneyRoutePlan
    @State private var message: String?
    @State private var error: String?
    @State private var editingLeg: JourneyRouteLeg?
    @State private var locating: JourneyStop?
    @State private var choosingHome = false
    @State private var suggesting = false
    @State private var suggestionTask: Task<Void, Never>?
    @State private var editMode: EditMode = .inactive
    init(document: JourneyDocument, onSave: @escaping (JourneyDocument) -> String?) {
        self.document = document; self.onSave = onSave
        _stops = State(initialValue: document.stops)
        _plan = State(initialValue: document.routePlan.flatMap { $0.valid ? $0 : nil } ?? JourneyRoutePlan())
    }
    private var legs: [JourneyRouteLeg] { MultiCityRouting.legs(stops, plan: plan) }
    private var baseline: [JourneyRouteLeg] { MultiCityRouting.legs(document.stops, plan: plan) }
    private var ready: Bool { stops.count > 1 && stops.allSatisfy { RoutePoint($0) != nil } }
    private var preview: JourneyDocument? { try? MultiCityRouting.applying(stops, plan: plan, to: document) }
    private var changedDates: Int { guard let preview else { return 0 }; return preview.stops.filter { stop in document.stops.first { $0.id == stop.id }?.arrival != stop.arrival }.count }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("A better way between places").font(.title2.weight(.semibold))
                        Text("Arrange your cities, compare transfers and leave room for travel days.").font(.subheadline).foregroundStyle(.secondary)
                        if ready { summary }
                        if let message { Text(message).font(.caption).foregroundStyle(Color.bronze).accessibilityIdentifier("route-suggestion-message") }
                    }.padding(.vertical, 8)
                }.listRowBackground(Color.clear)
                Section("Planning choices") {
                    Picker("Optimize for", selection: $plan.objective) { ForEach(RouteObjective.allCases) { Text($0.title).tag($0) } }
                    Toggle("Prefer train when times are close", isOn: $plan.preferTrain)
                    Toggle("Keep first city fixed", isOn: $plan.keepFirst).accessibilityIdentifier("route-keep-first")
                    Toggle("Keep last city fixed", isOn: $plan.keepLast)
                    Button { choosingHome = true } label: {
                        HStack { Label("Starting from", systemImage: "house"); Spacer(); Text(plan.home?.name ?? "Add home or another city").foregroundStyle(.secondary) }
                    }.accessibilityIdentifier("route-home")
                    if plan.home != nil {
                        Toggle("Return to this city", isOn: $plan.returnHome)
                        Button("Remove starting city", role: .destructive) { plan.home = nil }
                    }
                }
                Section {
                    if let home = plan.home {
                        Label(home.name + " · start", systemImage: "house").font(.subheadline).foregroundStyle(.secondary)
                            .moveDisabled(true)
                    }
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Text("\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(Color.bronze).frame(width: 25, height: 25).background(Color.bronze.opacity(0.10), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stop.name).font(.headline)
                                    if let projected = preview?.stops.first(where: { $0.id == stop.id }), document.dateMode == .dates {
                                        Text(TravelDay.label(projected.arrival) + " – " + TravelDay.label(projected.departure) + " · \(stop.nights) nights").font(.caption).foregroundStyle(.secondary)
                                    } else { Text("\(stop.nights) nights").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Menu {
                                    Button("Move earlier", systemImage: "arrow.up") { move(index, by: -1) }.disabled(index == 0)
                                    Button("Move later", systemImage: "arrow.down") { move(index, by: 1) }.disabled(index == stops.count - 1)
                                    Button("Change location", systemImage: "mappin") { locating = stop }
                                } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 35, height: 40) }.accessibilityLabel("Move " + stop.name).accessibilityIdentifier("route-move-\(index)")
                            }
                            if let projected = preview?.stops.first(where: { $0.id == stop.id }) {
                                SeasonalityCard(city: projected.name, countryCode: projected.countryCode ?? TravelStatistics.countryCode(projected.country), arrival: document.dateMode == .dates ? projected.arrival : nil, departure: document.dateMode == .dates ? projected.departure : nil, compact: true)
                            } else {
                                SeasonalityCard(city: stop.name, countryCode: stop.countryCode ?? TravelStatistics.countryCode(stop.country), compact: true)
                            }
                            if RoutePoint(stop) == nil {
                                Button("Choose this city on the map", systemImage: "mappin.and.ellipse") { locating = stop }.font(.caption).accessibilityIdentifier("route-locate-\(index)")
                            }
                        }.padding(.vertical, 5).accessibilityElement(children: .contain).accessibilityIdentifier("route-stop-\(index)")
                    }.onMove { offsets, destination in stops.move(fromOffsets: offsets, toOffset: destination); message = "Your order. Transfer estimates have been updated." }
                    if let home = plan.home, plan.returnHome { Label(home.name + " · return", systemImage: "house.fill").font(.subheadline).foregroundStyle(.secondary).moveDisabled(true) }
                } header: {
                    HStack { Text("Stop order"); Spacer(); Button(editMode == .active ? "Done" : "Reorder") { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { editMode = editMode == .active ? .inactive : .active } }.font(.caption).accessibilityIdentifier("route-reorder") }
                } footer: { Text("Drag to reorder, or use the arrows beside a city. Fixed first/last cities constrain suggestions; you can still move them yourself. Seasonality follows the proposed dates; suggestions optimize transfers.") }
                Section {
                    Button(suggesting ? "Finding a route…" : "Suggest an order", systemImage: "sparkles") { suggest() }.disabled(!ready || suggesting).accessibilityIdentifier("route-suggest")
                    Button("Restore current trip order", systemImage: "arrow.uturn.backward") {
                        let resolved = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0) })
                        stops = document.stops.map { resolved[$0.id] ?? $0 }; message = "Current trip order restored."
                    }.accessibilityIdentifier("route-restore")
                    if !ready { Text("Choose a map location for each city to calculate the route. You can still rearrange the list.").font(.caption).foregroundStyle(.secondary) }
                }
                if !legs.isEmpty {
                    Section {
                        ForEach(legs) { leg in legRow(leg) }
                    } header: { Text("Between destinations") } footer: { Text("Planning estimates, not bookable departures. Check services for your dates, then adjust each allowance for connections, traffic or overnight travel.") }
                }
                Section("Apply to your plan") {
                    Toggle("Reserve transfer time in itinerary", isOn: $plan.reserveTransfers).accessibilityIdentifier("route-reserve")
                    Text("Transfer blocks are added to travel days. Applying again updates these blocks without duplicating them. Their 09:00 times are placeholders until you book.").font(.caption).foregroundStyle(.secondary)
                    if document.dateMode == .dates {
                        Text(changedDates == 0 ? "Your destination dates stay the same." : "\(changedDates) destination arrival dates will change. Nights and city plans stay together.").font(.subheadline).accessibilityIdentifier("route-date-impact")
                        if let preview, let end = preview.endDate { LabeledContent("Trip ends", value: TravelDay.label(end)).font(.caption) }
                    } else { Text("Your trip stays flexible. Nights remain attached to each city.").font(.caption).foregroundStyle(.secondary) }
                    if !document.hotels.isEmpty || !document.flights.isEmpty {
                        Label("Review your bookings", systemImage: "calendar.badge.exclamationmark").foregroundStyle(Color.bronze)
                        Text("Existing hotel and flight bookings keep their original dates. Check them against the proposed route before applying.").font(.caption).foregroundStyle(.secondary)
                    }
                    if !document.events.filter({ $0.routeLegID == nil }).isEmpty {
                        Text("Existing activities move with their city. Check timed plans on transfer days for overlaps.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
                }
            }.environment(\.editMode, $editMode)
                .scrollContentBackground(.hidden).background(Color.canvas)
                .navigationTitle("Plan your route").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    Button { apply() } label: { Text("Use this route").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9) }
                        .buttonStyle(.glassProminent).disabled(!ready || preview == nil).padding(.horizontal, 20).padding(.vertical, 10).background(.regularMaterial).accessibilityIdentifier("route-apply")
                }
                .sheet(item: $editingLeg) { leg in RouteLegEditor(leg: leg) { choice in plan.choices.removeAll { $0.key == leg.id }; if let choice { plan.choices.append(choice) } } }
                .sheet(item: $locating) { stop in RouteLocationPicker(title: "Locate " + stop.name, initial: stop.name) { point in
                    if let i = stops.firstIndex(where: { $0.id == stop.id }) { stops[i].name = point.name; stops[i].latitude = point.latitude; stops[i].longitude = point.longitude; stops[i].timeZone = point.timeZone; stops[i].countryCode = point.countryCode ?? stops[i].countryCode }
                } }
                .sheet(isPresented: $choosingHome) { RouteLocationPicker(title: "Starting city", initial: plan.home?.name ?? "") { point in var home = point; home.id = "route-home"; plan.home = home } }
                .onAppear { if document.routePlan == nil && message == nil && ready { suggest() } }
                .onDisappear { suggestionTask?.cancel() }
        }
    }
    private var summary: some View {
        let km = legs.reduce(0) { $0 + $1.distance }, originalKM = baseline.reduce(0) { $0 + $1.distance }
        let minutes = legs.reduce(0) { $0 + $1.selected.total }, originalMinutes = baseline.reduce(0) { $0 + $1.selected.total }
        return VStack(alignment: .leading, spacing: 7) {
            Text("~" + RouteEstimate.duration(minutes) + " total transfer time").font(.headline).foregroundStyle(Color.bronze).accessibilityIdentifier("route-total")
            Text(Int(km).formatted() + " km between cities · " + "\(legs.filter(\.isTravelDay).count) substantial travel days").font(.caption).foregroundStyle(.secondary)
            if !baseline.isEmpty && abs(originalKM - km) >= 1 {
                Text(Int(abs(originalKM - km)).formatted() + (km < originalKM ? " km less" : " km more") + " than your current route").font(.caption)
            }
            if !baseline.isEmpty && abs(originalMinutes - minutes) >= 5 { Text(RouteEstimate.duration(abs(originalMinutes - minutes)) + (minutes < originalMinutes ? " less" : " more") + " estimated travel time").font(.caption) }
        }.padding(.vertical, 8)
    }
    private func legRow(_ leg: JourneyRouteLeg) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: leg.selected.mode.symbol).foregroundStyle(leg.selected.mode == .train ? Color.teal : Color.blue).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(leg.from.name + " → " + leg.to.name).font(.subheadline.weight(.semibold))
                    Text(leg.selected.mode.title + " · ~" + RouteEstimate.duration(leg.selected.total) + " total").font(.subheadline).foregroundStyle(Color.bronze)
                }
                Spacer()
                Button { editingLeg = leg } label: { Image(systemName: "slider.horizontal.3").frame(width: 40, height: 40) }.accessibilityLabel("Adjust transfer to " + leg.to.name)
            }
            if !leg.customized {
                Text(RouteEstimate.duration(leg.selected.rideMinutes) + " travelling + " + RouteEstimate.duration(leg.selected.bufferMinutes) + " allowance").font(.caption).foregroundStyle(.secondary)
            }
            Text(leg.selected.explanation).font(.caption).foregroundStyle(.secondary)
            HStack {
                Label(leg.isTravelDay ? "Leave this day light" : "Part-day transfer", systemImage: leg.isTravelDay ? "sun.max" : "clock").font(.caption).foregroundStyle(Color.bronze)
                if leg.extraDays > 0 { Text("+\(leg.extraDays) travel day(s)").font(.caption) }
            }
            if let d = preview, d.dateMode == .dates {
                if let dates = MultiCityRouting.transferDates(leg, stops: d.stops) {
                    Text("Transfer · " + TravelDay.label(dates.departure) + (dates.arrival == dates.departure ? "" : " – " + TravelDay.label(dates.arrival))).font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Link("Check trains", destination: leg.mapsURL).font(.caption)
                Spacer()
                Link("Check flights", destination: flightSearchURL(leg)).font(.caption)
                if let source = leg.selected.source, let url = validatedURL(source) { Link("Operator", destination: url).font(.caption) }
            }
        }.padding(.vertical, 8)
    }
    private func flightSearchURL(_ leg: JourneyRouteLeg) -> URL {
        var components = URLComponents(string: "https://www.google.com/travel/flights")!
        let day = preview.flatMap { MultiCityRouting.transferDates(leg, stops: $0.stops)?.departure }
        components.queryItems = [URLQueryItem(name: "q", value: "Flights from " + leg.from.name + " to " + leg.to.name + (document.dateMode == .dates ? day.map { " on " + $0 } ?? "" : ""))]
        return components.url!
    }
    private func suggest() {
        guard !suggesting else { return }
        let input = stops, settings = plan
        suggesting = true
        suggestionTask = Task {
            let route = await Task.detached(priority: .userInitiated) { MultiCityRouting.suggest(input, plan: settings) }.value
            suggesting = false
            guard !Task.isCancelled, stops == input, plan == settings, let route else { return }
            let changed = route.map(\.id) != stops.map(\.id)
            stops = route
            message = changed ? "Suggested order ready. Review transfers and dates below." : "This order already fits your current choices."
            if stops.count > 11 { message = (message ?? "") + " This is an improved route, not a guaranteed optimum." }
        }
    }
    private func move(_ index: Int, by offset: Int) {
        guard stops.indices.contains(index + offset) else { return }
        stops.swapAt(index, index + offset); message = "Your order. Transfer estimates have been updated."
    }
    private func apply() {
        do { let updated = try MultiCityRouting.applying(stops, plan: plan, to: document); if let issue = onSave(updated) { error = issue } else { dismiss() } }
        catch { self.error = error.localizedDescription }
    }
}

private struct RouteLocationPicker: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    @State var text: String
    @State private var point: RoutePoint?
    var save: (RoutePoint) -> Void
    init(title: String, initial: String, save: @escaping (RoutePoint) -> Void) { self.title = title; _text = State(initialValue: initial); self.save = save }
    var body: some View {
        NavigationStack {
            Form {
                LocationAutocompleteField("Search city", text: $text, kind: .city, identifier: "route-city-query", onEdit: { point = nil }) { location in
                    if let lat = location.place.latitude, let lon = location.place.longitude { point = RoutePoint(id: "", name: location.text, latitude: lat, longitude: lon, timeZone: location.timeZone, countryCode: TravelStatistics.countryCode(location.countryCode) ?? TravelStatistics.countryCode(location.country)) }
                }
                Text("Select a city result so its location can be used in your route.").font(.caption).foregroundStyle(.secondary)
            }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Use city") { if let point { save(point); dismiss() } }.disabled(point?.valid != true).accessibilityIdentifier("route-city-save") }
                }
        }
    }
}
private struct RouteLegEditor: View {
    @Environment(\.dismiss) private var dismiss
    let leg: JourneyRouteLeg
    var save: (RouteLegChoice?) -> Void
    @State private var mode: RouteMode
    @State private var minutes: Int
    @State private var extraDays: Int
    init(leg: JourneyRouteLeg, save: @escaping (RouteLegChoice?) -> Void) {
        self.leg = leg; self.save = save
        _mode = State(initialValue: leg.selected.mode); _minutes = State(initialValue: leg.selected.total); _extraDays = State(initialValue: leg.extraDays)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(leg.from.name + " → " + leg.to.name).font(.headline) }
                Section("Planning estimates") {
                    ForEach(leg.options, id: \.mode) { option in
                        Button { mode = option.mode; minutes = option.total } label: { Label(option.mode.title + " · ~" + RouteEstimate.duration(option.total), systemImage: option.mode.symbol) }
                    }
                    Text("Train durations are shown only where a rail baseline is available. For other routes, check services and enter your own allowance.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Your transfer allowance") {
                    Picker("Travel by", selection: $mode) { ForEach(RouteMode.allCases) { Text($0.title).tag($0) } }
                    Stepper("Total: " + RouteEstimate.duration(minutes), value: $minutes, in: 15...4320, step: 15).accessibilityIdentifier("route-leg-duration")
                    Stepper("Additional travel days: \(extraDays)", value: $extraDays, in: max(0, minutes / 1440)...3)
                    Text("Include connections and time at the station or airport. Additional days shift the next destination’s arrival while preserving its nights. Home legs extend the trip’s departure or return date; review these allowances against your bookings.").font(.caption).foregroundStyle(.secondary)
                }
                Section { Button("Use automatic estimate") { save(nil); dismiss() } }
            }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Transfer details").navigationBarTitleDisplayMode(.inline)
                .onChange(of: minutes) { extraDays = max(extraDays, minutes / 1440) }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(.init(key: leg.id, mode: mode, minutes: minutes, extraDays: extraDays)); dismiss() }.accessibilityIdentifier("route-leg-save") }
                }
        }
    }
}
