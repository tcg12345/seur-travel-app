import SwiftUI
import PhotosUI

struct TripCreationView: View {
    var wishlist = false
    var initialDestination = ""
    var initialCity: ExploreCity? = nil
    var onCreated: (UUID) -> Void = { _ in }
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var nights = 3
    @State private var destination = ""
    @State private var selectedLocation: LocationSelection?
    @State private var departure = Calendar.current.startOfDay(for: .now)
    @State private var returnDate = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: .now))!
    @State private var error: String?
    private var earliestReturn: Date { Calendar.current.date(byAdding: .day, value: 1, to: departure)! }
    private var latestReturn: Date { Calendar.current.date(byAdding: .day, value: 365, to: departure)! }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LocationAutocompleteField("Where are you going?", text: $destination, kind: .destination, identifier: "trip-destination", onEdit: { selectedLocation = nil }) { selectedLocation = $0 }
                } header: { Text("Location") }
                if wishlist { Section("Length of stay") { Stepper("\(nights) nights", value: $nights, in: 1...365).accessibilityIdentifier("wishlist-trip-nights"); Text("Plan each day now. Choose travel dates when you’re ready.").font(.caption).foregroundStyle(.secondary) } } else { Section("Travel dates") {
                    DatePicker("Departure", selection: $departure, displayedComponents: .date).accessibilityIdentifier("trip-departure-date")
                    DatePicker("Return", selection: $returnDate, in: earliestReturn...latestReturn, displayedComponents: .date).accessibilityIdentifier("trip-return-date")
                }
                }
                Section {
                    SeasonalityCard(city: destination, countryCode: TravelStatistics.countryCode(selectedLocation?.countryCode) ?? TravelStatistics.countryCode(selectedLocation?.country), arrival: wishlist ? nil : TravelDay.key(departure), departure: wishlist ? nil : TravelDay.key(returnDate))
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Color.canvas)
                .navigationTitle(wishlist ? "Plan a wishlist trip" : "Create a trip").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { create() }.disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("journey-save")
                    }
                }
                .onChange(of: departure) { returnDate = min(max(returnDate, earliestReturn), latestReturn) }
                .onAppear {
                    guard destination.isEmpty else { return }; destination = initialDestination
                    if let city = initialCity {
                        destination = city.name
                        selectedLocation = LocationSelection(text: city.name, place: PlaceRecord(name: city.name, city: city.name, latitude: city.latitude, longitude: city.longitude), country: city.country)
                    }
                }
        }
    }
    private func create() {
        let location = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = wishlist ? "2000-01-01" : TravelDay.key(departure), end = wishlist ? TravelDay.adding(nights, to: "2000-01-01") : TravelDay.key(returnDate)
        guard !location.isEmpty else { return }
        let stop = JourneyStop(name: location, country: selectedLocation?.country ?? "", arrival: start, nights: TravelDay.distance(start, end), latitude: selectedLocation?.place.latitude, longitude: selectedLocation?.place.longitude, timeZone: selectedLocation?.timeZone, countryCode: TravelStatistics.countryCode(selectedLocation?.countryCode) ?? TravelStatistics.countryCode(selectedLocation?.country))
        let trip = JourneyDocument(title: "Trip to " + location, destination: location, dateMode: wishlist ? .nights : .dates, startDate: wishlist ? nil : start, endDate: wishlist ? nil : end, stops: [stop])
        if library.save(trip) { onCreated(trip.id); dismiss() } else { error = library.error }
    }
}

struct JourneyEditor: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State var document: JourneyDocument
    @State private var stop: JourneyStop?
    @State private var error: String?
    @State private var hasDates = false
    @State private var routing = false
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Journey title", text: $document.title).font(.system(.title2, design: .serif)).accessibilityIdentifier("journey-name"); TextField("A few words about this journey", text: $document.description, axis: .vertical).lineLimit(3...6) } header: { Text("Your journey") }
                if document.stops.isEmpty {
                    Section("Destination") {
                        LocationAutocompleteField("Destination", text: $document.destination, identifier: "trip-destination")
                        if document.dateMode == .dates {
                            DayField(title: "From", value: Binding(get: { document.startDate ?? TravelDay.key(.now) }, set: { document.startDate = $0 }))
                            DayField(title: "To", value: Binding(get: { document.endDate ?? TravelDay.key(.now) }, set: { document.endDate = $0 }))
                        }
                        SeasonalityCard(city: document.destination, arrival: document.dateMode == .dates ? document.startDate : nil, departure: document.dateMode == .dates ? document.endDate : nil)
                        Text("Start with a destination or a memory. Add route stops whenever you’re ready to plan individual days.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Group {
                    Section("Timing") {
                        Text(document.dateMode == .dates ? "Each destination has its own arrival and departure dates. Your overall dates follow the route." : "Choose nights in each destination. Days stay relative until you choose exact dates.").font(.caption).foregroundStyle(.secondary)
                        LabeledContent(document.dateMode == .dates ? "Total nights" : "Length of stay", value: "\(document.nights) nights")
                    }
                    Section {
                        ForEach(document.stops) { destination in
                            Button { stop = destination } label: {
                                HStack { Image(systemName: "mappin.and.ellipse").foregroundStyle(Color.bronze); VStack(alignment: .leading, spacing: 5) { Text(destination.name).foregroundStyle(.primary); Text(document.dateMode == .dates ? "\(TravelDay.label(destination.arrival)) – \(TravelDay.label(destination.departure))" : "\(destination.nights) nights").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption) }
                            }.accessibilityIdentifier("journey-stop-" + destination.id.uuidString)
                        }.onDelete { offsets in
                            let ids = Set(offsets.map { document.stops[$0].id })
                            if document.events.contains(where: { ids.contains($0.stopID) }) { error = "Remove or move this destination’s events before deleting it." }
                            else { document.stops.remove(atOffsets: offsets); clearRoutePlan() }
                        }.onMove { source, target in let start = document.stops.first?.arrival; document.stops.move(fromOffsets: source, toOffset: target); clearRoutePlan(); if document.dateMode == .dates { if let start { document.stops[0].arrival = start }; reflowDates() } }
                        Button { var next = JourneyStop(); if let last = document.stops.last { next.arrival = last.departure } else { next.name = document.destination; if let start = document.startDate { next.arrival = start }; if let start = document.startDate, let end = document.endDate { next.nights = max(1, TravelDay.distance(start, end)) } }; stop = next } label: { Label("Add destination", systemImage: "plus") }.accessibilityIdentifier("journey-add-stop")
                    } header: { HStack { Text("Your route"); Spacer(); EditButton().font(.caption) } } footer: { Text("Stops follow the order shown. Reordering a dated trip recalculates arrival and departure dates.") }
                }
                if document.stops.count > 1 {
                    Section { Button("Plan multi-city route", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { routing = true }.accessibilityIdentifier("editor-route-planner") }
                }
                Section { Label("Private until you choose to share", systemImage: "lock").font(.subheadline); Text("Visibility and sharing are managed from the journey’s Share button.").font(.caption).foregroundStyle(.secondary) }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Your trip").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityIdentifier("journey-save") }
                }
                .sheet(isPresented: $routing) { RoutePlannerView(document: document) { updated in document = updated; return nil } }
                .onAppear { hasDates = document.dateMode == .dates; if document.stops.isEmpty && hasDates { document.startDate = document.startDate ?? TravelDay.key(.now); document.endDate = document.endDate ?? TravelDay.adding(3, to: document.startDate!) } }
                .onChange(of: hasDates) { if hasDates { document.startDate = document.startDate ?? TravelDay.key(.now); document.endDate = document.endDate ?? document.startDate } }
                .navigationDestination(item: $stop) { value in StopEditor(stop: value, mode: document.dateMode) { edited in if let i = document.stops.firstIndex(where: { $0.id == edited.id }) { document.stops[i] = edited } else { document.stops.append(edited) }; clearRoutePlan() }.environment(\.tripEditorEmbedded, true) }
        }
    }
    private func clearRoutePlan() { document.routePlan = nil; document.events.removeAll { $0.routeLegID != nil } }
    private func reflowDates() { guard !document.stops.isEmpty else { return }; for i in document.stops.indices.dropFirst() { document.stops[i].arrival = document.stops[i - 1].departure } }
    private func save() {
        document.title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !document.stops.isEmpty { document.startDate = document.dateMode == .dates ? document.stops.first?.arrival : nil; document.endDate = document.dateMode == .dates ? document.stops.last?.departure : nil }
        else if !hasDates { document.startDate = nil; document.endDate = nil }
        if document.isWishlistTrip {
            do { try document.scheduleWishlist(from: library.documents.first(where: { $0.id == document.id })?.stops ?? document.stops, departure: "2000-01-01") }
            catch { self.error = error.localizedDescription; return }
        }
        if library.save(document) { dismiss() } else { error = library.error }
    }
}

private struct StopEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var stop: JourneyStop
    let mode: JourneyDateMode
    var save: (JourneyStop) -> Void
    var body: some View {
        TripEditorNavigation {
            Form {
                Section {
                    LocationAutocompleteField("City or destination", text: $stop.name, kind: .city, identifier: "stop-name", onEdit: { stop.latitude = nil; stop.longitude = nil; stop.timeZone = nil; stop.country = ""; stop.countryCode = nil; stop.code = "" }) { selected in
                        stop.code = ""; stop.country = selected.country; stop.countryCode = TravelStatistics.countryCode(selected.countryCode) ?? TravelStatistics.countryCode(selected.country); stop.latitude = selected.place.latitude; stop.longitude = selected.place.longitude; stop.timeZone = selected.timeZone
                    }
                    LocationAutocompleteField("City / airport code or name (optional)", text: $stop.code, kind: .airport, identifier: "stop-airport")
                    LocationAutocompleteField("Country (optional)", text: $stop.country, kind: .country, identifier: "stop-country", onEdit: { stop.countryCode = nil; stop.latitude = nil; stop.longitude = nil; stop.timeZone = nil }, onSelect: { selection in stop.countryCode = TravelStatistics.countryCode(selection.country); stop.latitude = nil; stop.longitude = nil; stop.timeZone = nil })
                }
                Section(mode == .dates ? "Travel dates" : "Length of stay") {
                    if mode == .dates {
                        DayField(title: "Arrival", value: $stop.arrival)
                        DayField(title: "Departure", value: Binding(get: { stop.departure }, set: { stop.nights = max(1, TravelDay.distance(stop.arrival, $0)) }))
                    } else {
                        Stepper("\(stop.nights) nights", value: $stop.nights, in: 1...365).accessibilityIdentifier("stop-nights")
                    }
                }
                Section {
                    SeasonalityCard(city: stop.name, countryCode: stop.countryCode ?? TravelStatistics.countryCode(stop.country), arrival: mode == .dates ? stop.arrival : nil, departure: mode == .dates ? stop.departure : nil)
                }
            }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("A place to linger").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { TripEditorBackButton() }; ToolbarItem(placement: .confirmationAction) { Button("Add to route") { save(stop); dismiss() }.disabled(stop.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("stop-save") } }
        }
    }
}

struct JourneyEventEditor: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    @State var event: JourneyEvent
    var onSaved: () -> Void = {}
    @State private var days: Set<Int> = []
    @State private var links = ""
    @State private var moreDetails = false
    @State private var initialized = false
    @State private var error: String?
    @State private var delete = false
    private var document: JourneyDocument? { library.documents.first { $0.id == documentID } }
    var body: some View {
        TripEditorNavigation {
            Form {
                if event.isPlaceVisit { PlaceFields(place: $event.place, fixedCategory: event.place.category == .restaurant ? .restaurant : nil, context: document?.stops.first(where: { $0.id == event.stopID })?.name ?? "") }
                else {
                    Section(event.kind?.title ?? "Your event") {
                        Picker("Event type", selection: Binding(get: { event.kind ?? .custom }, set: { event.kind = $0 })) {
                            ForEach(ItineraryItemKind.allCases.filter { $0 != .place }) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }.pickerStyle(.menu)
                        TextField(event.kind?.titlePrompt ?? "Event title", text: Binding(get: { event.title ?? "" }, set: { event.title = $0 })).accessibilityIdentifier("event-title")
                    }
                    PlaceFields(place: $event.place, fixedCategory: .other, context: document?.stops.first(where: { $0.id == event.stopID })?.name ?? "", optional: true, identifier: "event-location", suggestionSymbol: event.symbol)
                }
                if let document {
                    Section("When") {
                        if document.stops.count > 1 { Picker("In", selection: $event.stopID) { ForEach(document.stops) { Text($0.name).tag($0.id) } }.pickerStyle(.menu) }
                        if let stop = document.stops.first(where: { $0.id == event.stopID }) {
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 8) {
                                    ForEach(0...stop.nights, id: \.self) { day in
                                        Button { if days.contains(day) { days.remove(day) } else { days.insert(day) } } label: {
                                            VStack(spacing: 7) {
                                                Text("Day \(day + 1)").font(.caption.weight(.semibold))
                                                Text(document.dateMode == .dates ? TravelDay.localDate(TravelDay.adding(day, to: stop.arrival)).formatted(.dateTime.month(.abbreviated).day()) : stop.name).font(.caption2).lineLimit(1)
                                                Image(systemName: days.contains(day) ? "checkmark.circle.fill" : "circle").font(.subheadline)
                                            }.foregroundStyle(days.contains(day) ? Color.white : Color.primary).frame(width: 76).padding(.vertical, 12)
                                                .background(days.contains(day) ? Color.bronze : Color.primary.opacity(0.04), in: .rect(cornerRadius: 17))
                                        }.buttonStyle(.plain).accessibilityIdentifier("event-day-\(day)").accessibilityValue(days.contains(day) ? "Selected" : "Not selected")
                                    }
                                }
                            }.scrollIndicators(.hidden).padding(.vertical, 5)
                            Text(days.count > 1 ? "Repeats on \(days.count) selected days" : "Select one or more days in \(stop.name)").font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("All day", isOn: Binding(get: { event.allDay ?? false }, set: { event.allDay = $0 })).accessibilityIdentifier("event-all-day")
                        if event.allDay != true {
                            DatePicker("Time", selection: Binding(get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(event.minute * 60)) }, set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); event.minute = (c.hour ?? 0) * 60 + (c.minute ?? 0) }), displayedComponents: .hourAndMinute)
                        }
                    }
                }
                Section {
                    DisclosureGroup("More details", isExpanded: $moreDetails) {
                        TextField("Notes or special requests", text: $event.description, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("event-notes")
                        TextField("People or guests", text: Binding(get: { event.attendees ?? "" }, set: { event.attendees = $0 }))
                        TextField("Booking or meeting links · one per line", text: $links, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        if event.allDay != true {
                            Toggle("Set duration", isOn: Binding(get: { event.durationMinutes != nil }, set: { event.durationMinutes = $0 ? 60 : nil })).accessibilityIdentifier("event-duration-toggle")
                            if event.durationMinutes != nil { Stepper("\(event.durationMinutes ?? 60) minutes", value: Binding(get: { event.durationMinutes ?? 60 }, set: { event.durationMinutes = $0 }), in: 1...1440, step: 15); if let end = event.endTimeLabel { LabeledContent("Ends", value: end).foregroundStyle(.secondary) } }
                        }
                        MoneyFields(cost: $event.cost, companions: document?.companions ?? [], showsPaid: false)
                        if event.cost != nil && days.count > 1 { Text("This price is counted once for each selected day.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section { Toggle("Done · include in spent", isOn: Binding(get: { event.isDone == true }, set: { event.isDone = $0 })).accessibilityIdentifier("event-done") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if document?.events.contains(where: { $0.id == event.id }) == true { Section { Button("Delete this occurrence", role: .destructive) { delete = true } } }
            }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Color.canvas).navigationTitle(event.isPlaceVisit ? (event.place.category == .restaurant ? "Your restaurant visit" : "Your activity") : event.categoryTitle).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { TripEditorBackButton() }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityIdentifier("event-save") } }
                .onAppear { guard !initialized else { return }; initialized = true; days = [event.day]; links = event.links.joined(separator: "\n"); moreDetails = !event.description.isEmpty || !event.links.isEmpty || event.cost != nil || event.durationMinutes != nil || event.attendees?.isEmpty == false }
                .onChange(of: event.stopID) { days = [0] }
                .confirmationDialog("Delete this event?", isPresented: $delete, titleVisibility: .visible) { Button("Delete occurrence", role: .destructive) { guard var d = document else { return }; d.events.removeAll { $0.id == event.id }; if library.save(d) { onSaved(); dismiss() } } }
        }
    }
    private func save() {
        guard var d = document, !days.isEmpty else { error = "Select at least one day."; return }
        event.links = links.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        d.putEvent(event, on: days)
        if library.save(d) { onSaved(); dismiss() } else { error = library.error }
    }
}

struct HotelReservationEditor: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    private var wishlistDocument: JourneyDocument? { library.wishlistTrips.first { $0.id == documentID } }
    private var wishlistStop: JourneyStop? { wishlistDocument?.stops.first { $0.arrival <= reservation.checkIn && reservation.checkIn < $0.departure } }
    let documentID: UUID
    @State var reservation: HotelReservation
    @Environment(TravelStore.self) private var catalog
    var onSaved: () -> Void = {}
    @State private var error: String?
    @State private var loading = false
    @State private var bookingDetails = false
    @State private var delete = false
    var body: some View {
        TripEditorNavigation {
            Form {
                PlaceFields(place: $reservation.place, fixedCategory: .hotel, context: reservation.place.city)
                Section("Hotel brand") {
                    TextField("Brand or collection (optional)", text: Binding(get: { reservation.place.brand ?? "" }, set: { reservation.place.brand = $0 })).accessibilityIdentifier("hotel-brand")
                }
                Section("Your stay") {
                    if let document = wishlistDocument {
                        Picker("Check-in day", selection: $reservation.checkIn) {
                            ForEach(document.stops) { stop in
                                ForEach(0..<stop.nights, id: \.self) { day in
                                    Text("\(stop.name) · Day \(TravelDay.distance(document.stops[0].arrival, stop.arrival) + day + 1)").tag(TravelDay.adding(day, to: stop.arrival))
                                }
                            }
                        }.accessibilityIdentifier("wishlist-hotel-checkin")
                        if let stop = wishlistStop {
                            Picker("Check-out day", selection: $reservation.checkOut) {
                                ForEach((TravelDay.distance(stop.arrival, reservation.checkIn) + 1)...stop.nights, id: \.self) { day in
                                    Text("Day \(TravelDay.distance(document.stops[0].arrival, stop.arrival) + day + 1)").tag(TravelDay.adding(day, to: stop.arrival))
                                }
                            }.accessibilityIdentifier("wishlist-hotel-checkout")
                        }
                    } else {
                        DayField(title: "Check-in", value: $reservation.checkIn)
                        DayField(title: "Check-out", value: $reservation.checkOut)
                    }
                    Toggle("Set planned checkout time", isOn: Binding(get: { reservation.checkOutTime != nil }, set: { reservation.checkOutTime = $0 ? "11:00" : nil }))
                    if reservation.checkOutTime != nil {
                        DatePicker("Leave hotel at", selection: Binding(get: { TodayPlanner.date("2000-01-01", minute: JourneyConflicts.minute(reservation.checkOutTime) ?? 660, zone: .current) ?? .now }, set: { reservation.checkOutTime = TodayPlanner.clock($0, zone: .current) }), displayedComponents: .hourAndMinute)
                        Text("Your planned departure from the hotel, in local time. Used to check your flight timing.").font(.caption).foregroundStyle(.secondary)
                    }
                    Stepper("\(reservation.guests) \(reservation.guests == 1 ? "guest" : "guests")", value: $reservation.guests, in: 1...99)
                    Stepper("\(reservation.rooms) \(reservation.rooms == 1 ? "room" : "rooms")", value: $reservation.rooms, in: 1...50)
                }
                Section {
                    DisclosureGroup("Booking details", isExpanded: $bookingDetails) {
                        TextField("Room or suite type", text: $reservation.roomType)
                        TextField("Confirmation number", text: $reservation.confirmation).textInputAutocapitalization(.characters)
                        MoneyFields(cost: $reservation.cost, companions: library.documents.first { $0.id == documentID }?.companions ?? [])
                        TextField("Special requests or booking notes", text: $reservation.notes, axis: .vertical).lineLimit(2...6)
                    }
                } footer: { Text("Save the stay now. You can add your confirmation and other booking details later.") }
                if !reservation.place.name.isEmpty {
                    Section {
                        DisclosureGroup("About this hotel") {
                            if !reservation.overview.isEmpty { Text(reservation.overview).font(.subheadline).textSelection(.enabled); Text("AI overview · verify important details with the hotel.").font(.caption).foregroundStyle(.secondary) }
                            Button { Task { loading = true; defer { loading = false }; do { reservation.overview = try await api.hotelOverview(reservation.place).text } catch { self.error = error.localizedDescription } } } label: { Label(loading ? "Preparing overview…" : "Ask concierge for an overview", systemImage: "sparkles") }.disabled(loading)
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if library.documents.first(where: { $0.id == documentID })?.hotels.contains(where: { $0.id == reservation.id }) == true { Section { Button("Remove hotel record", role: .destructive) { delete = true } } }
            }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Your stay").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { TripEditorBackButton() }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityIdentifier("hotel-record-save") } }
                .confirmationDialog("Remove this hotel record?", isPresented: $delete, titleVisibility: .visible) { Button("Remove record", role: .destructive) { save(remove: true) } }
            .onAppear { if reservation.place.brand == nil { reservation.place.brand = TravelStatistics.brand(for: reservation.place, catalog: catalog.hotels) }; bookingDetails = !reservation.roomType.isEmpty || !reservation.confirmation.isEmpty || !reservation.notes.isEmpty || reservation.cost != nil }
            .onChange(of: reservation.place.id) { _, _ in if reservation.place.brand == nil { reservation.place.brand = TravelStatistics.brand(for: reservation.place, catalog: catalog.hotels) } }
            .onChange(of: reservation.checkIn) { if reservation.checkOut <= reservation.checkIn || (wishlistStop.map { reservation.checkOut > $0.departure } ?? false) { reservation.checkOut = TravelDay.adding(1, to: reservation.checkIn) } }
        }
    }
    private func save(remove: Bool = false) { guard var d = library.documents.first(where: { $0.id == documentID }) else { return }; d.hotels.removeAll { $0.id == reservation.id }; if !remove { d.hotels.append(reservation) }; if library.save(d) { onSaved(); dismiss() } else { error = library.error } }
}

struct FlightReservationEditor: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tripEditorEmbedded) private var embedded
    let documentID: UUID?
    @State var reservation: FlightReservation
    var onCancel: (() -> Void)? = nil
    var onSaved: () -> Void = {}
    @State private var error: String?
    @State private var delete = false
    @State private var saving = false
    var body: some View {
        TripEditorNavigation {
            Form {
                Section("Flight") { TextField("Airline", text: $reservation.airline).accessibilityIdentifier("booking-airline"); TextField("Flight number · e.g. BA178", text: $reservation.flightNumber).textInputAutocapitalization(.characters); InlineFlightSchedule(reservation: $reservation) }
                Section("Departure · airport local time") { LocationAutocompleteField("Departure airport / code", text: $reservation.departureAirport, kind: .airport, identifier: "booking-departure", onEdit: { reservation.departureLatitude = nil; reservation.departureLongitude = nil; reservation.departureZone = "" }) { selected in reservation.departureLatitude = selected.place.latitude; reservation.departureLongitude = selected.place.longitude; reservation.departureZone = selected.timeZone }; DayField(title: "Date", value: $reservation.departureDay); LocalTimeField(title: "Departure time", value: $reservation.departureTime) }
                Section("Arrival · airport local time") { LocationAutocompleteField("Arrival airport / code", text: $reservation.arrivalAirport, kind: .airport, identifier: "booking-arrival", onEdit: { reservation.arrivalLatitude = nil; reservation.arrivalLongitude = nil; reservation.arrivalZone = "" }) { selected in reservation.arrivalLatitude = selected.place.latitude; reservation.arrivalLongitude = selected.place.longitude; reservation.arrivalZone = selected.timeZone }; DayField(title: "Date", value: $reservation.arrivalDay); LocalTimeField(title: "Arrival time", value: $reservation.arrivalTime) }
                Section("Booking") { MoneyFields(cost: $reservation.cost, companions: library.documents.first { $0.id == documentID }?.companions ?? []); TextField("Booking link", text: $reservation.bookingLink).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled(); TextField("Notes", text: $reservation.notes, axis: .vertical).lineLimit(3...6) }
                Section { Text("Times are stored exactly as airport-local values, including overnight and date-line crossings. Confirm them against your airline booking.").font(.caption).foregroundStyle(.secondary) }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if library.documents.first(where: { $0.id == documentID })?.flights.contains(where: { $0.id == reservation.id }) == true || (documentID == nil && api.savedFlights.contains(where: { $0.id == reservation.id })) { Section { Button("Remove flight record", role: .destructive) { delete = true } } }
            }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Color.canvas).navigationTitle(documentID == nil ? "Review flight" : "Your flight booking").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(onCancel == nil && !embedded ? "Cancel" : "Back") { if let onCancel { onCancel() } else { dismiss() } }.disabled(saving) }; ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { save() }.disabled(saving).accessibilityIdentifier("flight-record-save") } }
                .confirmationDialog("Remove this flight record?", isPresented: $delete, titleVisibility: .visible) { Button("Remove record", role: .destructive) { save(remove: true) } }
        }
    }
    private func save(remove: Bool = false) {
        guard !saving else { return }
        if let documentID {
            guard var d = library.documents.first(where: { $0.id == documentID }) else { error = "This trip is no longer available."; return }
            d.flights.removeAll { $0.id == reservation.id }; if !remove { d.flights.append(reservation) }
            if library.save(d) { onSaved(); dismiss() } else { error = library.error }
        } else {
            var validation = JourneyDocument(title: "Flight"); validation.flights = [reservation]
            if !remove, let problem = validation.validationError() { error = problem; return }
            saving = true
            Task {
                do { if remove { try await api.removeFlight(reservation.id) } else { try await api.saveFlight(reservation) }; onSaved(); dismiss() }
                catch { self.error = error.localizedDescription }
                saving = false
            }
        }
    }
}

struct RatedPlaceEditor: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    @State var rated: RatedPlace
    var onSaved: () -> Void = {}
    @State private var hasDate = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var processing = false
    @State private var error: String?
    @State private var delete = false
    @State private var moreDetails = false
    private var existingEntry: Bool { library.documents.first(where: { $0.id == documentID })?.places.contains(where: { $0.id == rated.id }) == true }
    var body: some View {
        TripEditorNavigation {
            Form {
                Section {
                    Text(existingEntry ? "Update your memories here. Save entry keeps your changes." : "Start with the place you visited. The details below are optional, so you can add more later.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                PlaceFields(place: $rated.place, context: library.documents.first(where: { $0.id == documentID })?.destination ?? "", journalEntry: true)
                Section("Your visit · optional") {
                    Toggle("Add a visit date", isOn: $hasDate).accessibilityIdentifier("rated-has-date")
                    if hasDate { DayField(title: "Visited on", value: Binding(get: { rated.visitedOn ?? TravelDay.key(.now) }, set: { rated.visitedOn = $0 })).accessibilityIdentifier("rated-visit-date") }
                    TextField("What did you love? What would you remember for next time?", text: $rated.notes, axis: .vertical)
                        .lineLimit(3...8).accessibilityLabel("Visit notes").accessibilityIdentifier("rated-notes")
                }
                Section {
                    scoreControl("Overall", score: $rated.overall)
                } header: { Text("Your rating · optional") }
                footer: { Text("Rate your experience out of 10. Leave it unrated if you prefer.") }
                Section("Photos · optional") {
                    if !rated.photos.isEmpty { ScrollView(.horizontal) { HStack { ForEach(rated.photos) { photo in
                        if let image = UIImage(data: photo.jpeg) { Image(uiImage: image).resizable().scaledToFill().frame(width: 110, height: 110).clipped().clipShape(.rect(cornerRadius: 16)).overlay(alignment: .topTrailing) { Button { rated.photos.removeAll { $0.id == photo.id } } label: { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7)).padding(5) }.buttonStyle(.plain).accessibilityLabel("Remove photo") } }
                    } } } }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: max(0, 6 - rated.photos.count), matching: .images) { Label(processing ? "Preparing photos…" : "Choose photos", systemImage: "photo.badge.plus") }.disabled(processing || rated.photos.count >= 6).accessibilityIdentifier("rated-add-photos")
                    Text("Up to six photos per place. Photos are included when you explicitly share this journal.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup("Detailed ratings & more", isExpanded: $moreDetails) {
                        ForEach(rated.place.category.scoreCategories, id: \.self) { category in
                            scoreControl(category, score: Binding(get: { rated.scores[category] ?? 0 }, set: { rated.scores[category] = $0 }))
                        }
                        Picker("Price range", selection: $rated.priceRange) { Text("Not specified").tag(""); ForEach(["$", "$$", "$$$", "$$$$"], id: \.self) { Text($0) } }
                        if rated.place.category == .restaurant {
                            Picker("Michelin stars at time of visit", selection: Binding(get: { rated.michelinStars ?? -1 }, set: { rated.michelinStars = $0 < 0 ? nil : $0 })) {
                                Text("Not recorded").tag(-1); ForEach(0...3, id: \.self) { Text("\($0) stars").tag($0) }
                            }
                            Text("Your personal record, not a verified current award.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("rated-more-details")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if existingEntry { Section { Button("Delete journal entry", role: .destructive) { delete = true } } }
            }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Color.canvas)
                .navigationTitle(existingEntry ? "Edit journal entry" : "New journal entry").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { TripEditorBackButton() }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save entry") { save() }
                            .disabled(processing || rated.place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("rated-save")
                    }
                }
                .onAppear { hasDate = rated.visitedOn != nil }
                .onChange(of: hasDate) { if hasDate { rated.visitedOn = rated.visitedOn ?? TravelDay.key(.now) } }
                .onChange(of: photoItems) { Task { await importPhotos() } }
                .onChange(of: rated.place.category) { rated.scores = [:]; rated.michelinStars = nil }
                .confirmationDialog("Delete this journal entry and its photos?", isPresented: $delete, titleVisibility: .visible) { Button("Delete entry", role: .destructive) { save(remove: true) } }
        }
    }
    private func scoreControl(_ title: String, score: Binding<Double>) -> some View { VStack(alignment: .leading, spacing: 8) { HStack { Text(title); Spacer(); Text(score.wrappedValue == 0 ? "To rate" : String(format: "%.1f / 10", score.wrappedValue)).foregroundStyle(Color.bronze).monospacedDigit(); Stepper("Adjust " + title, value: score, in: 0...10, step: 0.1).labelsHidden().fixedSize().accessibilityIdentifier(title + "-stepper") }; Slider(value: score, in: 0...10, step: 0.1).accessibilityLabel(title + " rating").accessibilityValue(String(format: "%.1f", score.wrappedValue)) } }
    private func save(remove: Bool = false) { guard var d = library.documents.first(where: { $0.id == documentID }) else { error = "This trip is no longer available."; return }; if !hasDate { rated.visitedOn = nil }; d.places.removeAll { $0.id == rated.id }; if !remove { d.places.append(rated) }; if library.save(d) { onSaved(); dismiss() } else { error = library.error } }
    private func importPhotos() async {
        guard !photoItems.isEmpty else { return }; processing = true; defer { processing = false; photoItems = [] }
        do { for item in photoItems.prefix(6 - rated.photos.count) {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw JourneyError.message("This photo couldn’t be opened.") }
            let ratio = min(1, 1500 / max(image.size.width, image.size.height)); let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            guard let jpeg = resized.jpegData(compressionQuality: 0.7), jpeg.count <= 1_500_000 else { throw JourneyError.message("Choose a smaller photo.") }
            rated.photos.append(JournalPhoto(jpeg: jpeg))
        } } catch { self.error = error.localizedDescription }
    }
}

struct DayField: View {
    var title: String
    @Binding var value: String
    var body: some View { DatePicker(title, selection: Binding(get: { TravelDay.localDate(value) }, set: { value = TravelDay.key($0) }), displayedComponents: .date) }
}
struct MoneyFields: View {
    @Binding var cost: TravelMoney?
    var companions: [TripCompanion] = []
    var showsPaid = true
    var body: some View {
        Toggle("Include a price", isOn: Binding(get: { cost != nil }, set: { cost = $0 ? TravelMoney() : nil }))
        if cost != nil {
            TextField("Amount", value: Binding(get: { cost?.amount ?? 0 }, set: { cost?.amount = $0 }), format: .number).keyboardType(.decimalPad).accessibilityIdentifier("money-amount")
            Picker("Currency", selection: Binding(get: { cost?.currency ?? "USD" }, set: { cost?.currency = $0 })) { ForEach(TravelMoney.currencies, id: \.self) { Text($0) } }.pickerStyle(.menu)
            if showsPaid { Toggle("Paid · include in spent", isOn: Binding(get: { cost?.isPaid == true }, set: { cost?.isPaid = $0 })).accessibilityIdentifier("cost-paid") }
            if !companions.isEmpty {
                Toggle("Split with companions", isOn: Binding(get: { cost?.paidBy != nil }, set: { enabled in
                    cost?.paidBy = enabled ? companions.first?.id : nil
                    cost?.splitBetween = enabled ? companions.map(\.id) : nil
                })).accessibilityIdentifier("cost-split")
                if cost?.paidBy != nil {
                    Picker("Who paid", selection: Binding(get: { cost?.paidBy ?? "" }, set: { cost?.paidBy = $0 })) { ForEach(companions) { Text($0.name).tag($0.id) } }
                    ForEach(companions) { person in
                        Toggle("Split between · " + person.name, isOn: Binding(get: { cost?.splitBetween?.contains(person.id) == true }, set: { included in
                            var ids = cost?.splitBetween ?? []
                            if included { if !ids.contains(person.id) { ids.append(person.id) } }
                            else if ids.count > 1 { ids.removeAll { $0 == person.id } }
                            cost?.splitBetween = ids
                        }))
                    }
                    Text("Split equally. Included in settlement once this event is done or this booking is paid.").font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("Add companions in the trip budget to split this cost.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct LocalTimeField: View {
    let title: String
    @Binding var value: String
    var body: some View {
        DatePicker(title, selection: Binding(get: {
            let parts = value.split(separator: ":").compactMap { Int($0) }
            return Calendar.current.startOfDay(for: .now).addingTimeInterval(Double((parts.first ?? 9) * 3600 + (parts.count > 1 ? parts[1] : 0) * 60))
        }, set: {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
            value = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }), displayedComponents: .hourAndMinute)
    }
}

/// Schedule lookup stays inside the booking form and preserves the user's booking notes.
struct InlineFlightSchedule: View {
    @Environment(TravelAPI.self) private var api
    @Binding var reservation: FlightReservation
    @State private var feed: FlightFeed?
    @State private var loading = false
    @State private var message: String?
    private var ident: String {
        let number = reservation.flightNumber.replacingOccurrences(of: " ", with: "").uppercased()
        if number.first?.isNumber == true, let airline = FlightAirline.collection.first(where: { $0.name.localizedCaseInsensitiveCompare(reservation.airline) == .orderedSame || $0.code.localizedCaseInsensitiveCompare(reservation.airline) == .orderedSame }) { return airline.code + number }
        return number
    }
    var body: some View {
        DisclosureGroup("Find this flight’s schedule") {
            Button { Task { await lookup() } } label: { Label(loading ? "Finding your flight…" : "Look up flight", systemImage: "magnifyingglass") }.disabled(loading || ident.isEmpty).accessibilityIdentifier("booking-lookup-flight")
            Text("Enter the airline, flight number and departure date. Choose a departure to fill its airports and local times.").font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let feed {
                ForEach(feed.flights) { flight in
                    Button { Task { await select(flight) } } label: {
                        VStack(alignment: .leading, spacing: 5) { Text(flight.ident + " · " + flight.origin + " → " + flight.destination); Text(FlightSnapshot.time(flight.scheduledOut ?? flight.scheduledOff, zone: flight.originZone)).font(.caption).foregroundStyle(.secondary) }
                    }.disabled(loading)
                }
                if !feed.message.isEmpty { Text(feed.message).font(.caption).foregroundStyle(.secondary) }
            }
        }.onChange(of: reservation.flightNumber) { feed = nil }.onChange(of: reservation.departureDay) { feed = nil }
    }
    private func lookup() async {
        loading = true; message = nil; feed = nil; defer { loading = false }
        let number = ident, day = reservation.departureDay
        do { let value = try await api.flightStatus(number, day: day); if ident == number && reservation.departureDay == day { feed = value } }
        catch { message = error.localizedDescription }
    }
    private func select(_ flight: FlightSnapshot) async {
        loading = true; message = nil; defer { loading = false }
        let original = reservation
        do {
            async let departure = api.flightAirport(flight.origin)
            async let arrival = api.flightAirport(flight.destination)
            let (a, b) = try await (departure, arrival)
            guard reservation == original else { return }
            var value = flight.reservation(airline: FlightAirline.identified(by: flight.ident)?.name ?? reservation.airline)
            value.id = reservation.id; value.cost = reservation.cost; value.notes = reservation.notes; value.bookingLink = reservation.bookingLink
            value.departureLatitude = a.latitude; value.departureLongitude = a.longitude; value.arrivalLatitude = b.latitude; value.arrivalLongitude = b.longitude
            reservation = value; feed = nil; message = "Schedule added. Review the details before saving."
        } catch { message = error.localizedDescription }
    }
}
