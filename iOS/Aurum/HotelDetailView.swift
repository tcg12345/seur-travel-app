import SwiftUI

struct HotelDetailView: View {
    @Environment(TravelStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let hotel: Hotel
    @State private var booking = false
    @State private var browser: BrowserDestination?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HotelPhoto(hotel: hotel).frame(height: 330)
                    .overlay(alignment: .bottom) { LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom).frame(height: 120) }
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "\(hotel.city) · \(hotel.country)")
                        Editorial(hotel.name, size: 35)
                        Label(hotel.district == "n/a" ? hotel.city : hotel.district, systemImage: "mappin").font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 0) {
                        detailStat("\(hotel.venues.count)", "Dining options")
                        Divider().frame(height: 35)
                        detailStat(hotel.stars + " star", "Hotel category")
                        Divider().frame(height: 35)
                        detailStat(hotel.price.hasPrefix("$") ? hotel.price : "Luxury", "Price band")
                    }.padding(.vertical, 18).cardSurface(cornerRadius: 22)
                    Text(hotel.description).font(.body).foregroundStyle(.secondary).lineSpacing(5)
                    HStack(alignment: .top) {
                        SectionHeading(title: "A stay with great taste.", subtitle: "Restaurants, bars & places to linger.")
                        Image(systemName: "fork.knife").font(.title2).foregroundStyle(Color.bronze).padding(.top, 4)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(hotel.venues.enumerated()), id: \.offset) { index, item in
                            NavigationLink { RestaurantDetailView(place: RestaurantPlace(hotel: hotel, venue: item)) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: item.type.localizedCaseInsensitiveContains("bar") ? "wineglass" : "fork.knife")
                                        .font(.system(size: 20, weight: .light)).frame(width: 42, height: 48).foregroundStyle(Color.bronze)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.name).font(.system(.headline, design: .serif)).foregroundStyle(.primary)
                                        Text(item.cuisine).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        if item.price != "n/a" { Text(item.price).font(.caption2).foregroundStyle(Color.bronze) }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }.padding(.vertical, 17).padding(.horizontal, 14).contentShape(.rect)
                            }.buttonStyle(.plain).accessibilityIdentifier("venue-\(index)")
                            if index < hotel.venues.count - 1 { Divider().padding(.leading, 69) }
                        }
                    }.cardSurface(cornerRadius: 24)
                    SectionHeading(title: "The neighborhood")
                    VStack(alignment: .leading, spacing: 14) {
                        Label(hotel.address, systemImage: "mappin.and.ellipse")
                        if hotel.transit != "n/a" { Label(hotel.transit, systemImage: "tram") }
                        Button { openMap() } label: { Label("Explore in Maps", systemImage: "arrow.up.right") }.padding(.top, 4)
                    }.font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("From the hotel collection").font(.subheadline.weight(.medium))
                        Text("Dining details, awards, and venue openings may change. Check with the hotel for current menus and availability.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            ForEach(Array(hotel.sources.filter { validatedURL($0) != nil }.prefix(3).enumerated()), id: \.offset) { i, link in
                                Button("Source \(i + 1) ↗") { if let url = validatedURL(link) { browser = BrowserDestination(url: url) } }.font(.caption)
                            }
                        }
                    }.padding(.top, 6)
                }.padding(24).background(Color.canvas, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)).padding(.top, -28)
            }.padding(.bottom, 15)
        }.background(Color.canvas).ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.toggleSave(hotel) } label: { Image(systemName: store.saved.contains(hotel.id) ? "heart.fill" : "heart").contentTransition(.symbolEffect(.replace)) }
                        .sensoryFeedback(.selection, trigger: store.saved.contains(hotel.id)).accessibilityLabel(store.saved.contains(hotel.id) ? "Unsave hotel" : "Save hotel")
                        .accessibilityIdentifier("detail-save")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: hotel.name + "\n" + hotel.website) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share hotel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your next chapter").font(.subheadline.weight(.medium))
                        Text("Choose dates & plan your stay").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { booking = true } label: { HStack(spacing: 7) { Text("Plan a stay"); Image(systemName: "arrow.up.right") }.font(.subheadline.weight(.semibold)).padding(.vertical, 8) }
                        .buttonStyle(.glassProminent).accessibilityIdentifier("plan-stay")
                }.padding(14).glassEffect(.regular, in: .rect(cornerRadius: 27)).padding(.horizontal, 16).padding(.bottom, 8)
            }
            .sheet(isPresented: $booking) { StayPlanner(hotel: hotel) }
            .sheet(item: $browser) { InAppBrowser(url: $0.url).ignoresSafeArea() }
    }
    private func detailStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 5) { Text(value).font(.system(.headline, design: .serif)); Text(label).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }
    private func openMap() {
        var parts = URLComponents(string: "https://maps.apple.com/")!
        parts.queryItems = [URLQueryItem(name: "q", value: hotel.name + " " + hotel.address + " " + hotel.city)]
        if let url = parts.url { UIApplication.shared.open(url) }
    }
}

struct StayPlanner: View {
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let hotel: Hotel
    @State private var dates = BookingDates()
    @State private var browser: BrowserDestination?
    @State private var added = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    HotelRow(hotel: hotel, showsChevron: false)
                    SectionHeading(title: "Make yourself at home.", subtitle: "A few details for your next escape.")
                    dateControls
                    HStack {
                        Label("\(dates.nights) nights", systemImage: "moon.stars")
                        Spacer(); Text("\(dates.guests) adults")
                    }.font(.subheadline).foregroundStyle(.secondary)
                    if !dates.isValid { Label("Check-out must be after check-in.", systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red) }
                    VStack(spacing: 12) {
                        if let url = hotel.officialURL {
                            Button { browser = BrowserDestination(url: url) } label: { Label("Check hotel availability", systemImage: "arrow.up.right").frame(maxWidth: .infinity).padding(.vertical, 12) }
                                .buttonStyle(.glassProminent).disabled(!dates.isValid).accessibilityIdentifier("check-hotel-availability")
                        }
                        Button {
                            added = store.addPlan(name: hotel.name, city: hotel.city, kind: "Stay", hotelID: hotel.id, dates: dates)
                        } label: { Label(added ? "Added to itinerary" : "Add to my itinerary", systemImage: added ? "checkmark" : "plus").frame(maxWidth: .infinity).padding(.vertical, 11) }
                            .buttonStyle(.glass).disabled(!dates.isValid || added).accessibilityIdentifier("add-stay")
                    }
                    Text("Reservations are completed with the hotel. Confirm your dates, travelers, price, and cancellation terms on its website. Adding a stay to your itinerary does not make a booking.")
                        .font(.footnote).foregroundStyle(.secondary).lineSpacing(4)
                }.padding(22)
            }.background(Color.canvas).navigationTitle("Your stay").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear { dates = store.dates }
                .onChange(of: dates.start) { _, newValue in
                    if dates.end <= newValue { dates.end = Calendar.current.date(byAdding: .day, value: 1, to: newValue)! }
                    added = false
                }
                .onChange(of: dates.end) { added = false }
                .onChange(of: dates.guests) { added = false }
                .onDisappear { store.dates = dates }
                .sheet(item: $browser) { InAppBrowser(url: $0.url).ignoresSafeArea() }
        }
    }
    private var dateControls: some View {
        VStack(spacing: 0) {
            DatePicker("Check-in", selection: $dates.start, in: Date.now..., displayedComponents: .date).padding(18)
            Divider().padding(.horizontal, 18)
            DatePicker("Check-out", selection: $dates.end, in: dates.start..., displayedComponents: .date).padding(18)
            Divider().padding(.horizontal, 18)
            Stepper("\(dates.guests) adults", value: $dates.guests, in: 1...9).padding(18)
        }.cardSurface(cornerRadius: 23)
    }
}

struct DiningVisitPlanner: View {
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let hotel: Hotel
    let venue: DiningVenue
    @State private var browser: BrowserDestination?
    @State private var date = Date.now.addingTimeInterval(86400 * 14)
    @State private var guests = 2
    @State private var added = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Eyebrow(text: hotel.name)
                    Editorial(venue.name, size: 34)
                    Label(venue.cuisine, systemImage: "fork.knife").font(.subheadline).foregroundStyle(Color.bronze)
                    Text(venue.description).font(.body).foregroundStyle(.secondary).lineSpacing(4)
                    HStack { if venue.location != "n/a" { Label(venue.location, systemImage: "mappin") }; Spacer(); Text(venue.price) }.font(.caption).foregroundStyle(.secondary)
                    DatePicker("Dining date", selection: $date, in: Date.now..., displayedComponents: .date)
                    Stepper("\(guests) guests", value: $guests, in: 1...9)
                    if let url = hotel.officialURL {
                        Button { browser = BrowserDestination(url: url) } label: { Label("Visit hotel for reservations", systemImage: "arrow.up.right").frame(maxWidth: .infinity).padding(.vertical, 9) }.buttonStyle(.glassProminent)
                    }
                    Button {
                        var dates = BookingDates(); dates.start = date; dates.end = Calendar.current.date(byAdding: .day, value: 1, to: date)!; dates.guests = guests
                        added = store.addPlan(name: venue.name, city: hotel.city, kind: "Dining", hotelID: hotel.id, dates: dates)
                    } label: { Label(added ? "Added to itinerary" : "Add dining plan", systemImage: added ? "checkmark" : "plus").frame(maxWidth: .infinity).padding(.vertical, 9) }.buttonStyle(.glass).disabled(added).accessibilityIdentifier("add-dining")
                    Text("Plans are saved on this device. Contact the hotel to confirm opening hours and reserve a table.").font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.background(Color.canvas).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onChange(of: date) { added = false }.onChange(of: guests) { added = false }
                .sheet(item: $browser) { InAppBrowser(url: $0.url).ignoresSafeArea() }
        }
    }
}

struct ComparisonView: View {
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(store.hotels.filter { store.compared.contains($0.id) }) { hotel in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                HotelPhoto(hotel: hotel).frame(height: 160).clipShape(.rect(cornerRadius: 24))
                                Editorial(hotel.name, size: 25)
                                Text(hotel.city).font(.subheadline).foregroundStyle(.secondary)
                                Label("\(hotel.venues.count) dining options", systemImage: "fork.knife").font(.headline).foregroundStyle(Color.bronze)
                                Text("Hotel price band: \(hotel.price)").font(.caption)
                                Divider()
                                ForEach(Array(hotel.venues.enumerated()), id: \.offset) { _, venue in
                                    NavigationLink { RestaurantDetailView(place: RestaurantPlace(hotel: hotel, venue: venue)) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(venue.name).font(.headline).foregroundStyle(.primary)
                                            Text(venue.cuisine).font(.subheadline).foregroundStyle(.secondary)
                                            Text(venue.price).font(.caption).foregroundStyle(Color.bronze)
                                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                                    }.buttonStyle(.plain)
                                }
                            }.padding(18)
                        }.frame(width: 270).cardSurface(cornerRadius: 28)
                    }
                }.padding(20)
            }.background(Color.canvas).navigationTitle("Compare the tables").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .safeAreaInset(edge: .bottom) { Text("Dining counts reflect variety, not a quality rating.").font(.caption).foregroundStyle(.secondary).padding(12) }
        }
    }
}
