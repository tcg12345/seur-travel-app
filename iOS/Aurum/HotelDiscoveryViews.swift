import SwiftUI
import MapKit
import ImageIO

/// Ephemeral media session: provider photos are not written into the app's disk cache.
private enum HotelMedia { static let session = URLSession(configuration: .ephemeral) }
struct LodgingImage: View {
    var url: String?
    var caption = "Hotel photo"
    var contentMode: ContentMode = .fill
    var maxPixelSize = 1400
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var image: UIImage?
    @State private var loading = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                StayStyle.surface
                if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode).frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                else { VStack(spacing: 9) { Image(systemName: "bed.double").font(.title); Text(loading ? "Loading photo" : "Photo unavailable").font(.caption) }.foregroundStyle(.secondary) }
            }
        }.clipped().contentShape(.rect).accessibilityElement(children: .ignore).accessibilityLabel(caption)
        .onDisappear { image = nil }
        .animation(StayStyle.motion(reduce), value: image != nil)
        .task(id: url) {
            image = nil
            #if DEBUG
            if HotelFixtures.enabled, url?.hasPrefix("fixture:") == true { image = UIImage(named: "london"); return }
            #endif
            guard !PlaceSearchTestPolicy.blocksPaidRequests, let url, let address = URL(string: url), address.scheme == "https", address.user == nil, address.password == nil else { return }
            loading = true; defer { loading = false }
            do {
                var request = URLRequest(url: address); request.timeoutInterval = 20
                let (data, response) = try await HotelMedia.session.data(for: request)
                try Task.checkCancellation()
                if (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 20_000_000,
                   let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixelSize] as CFDictionary) { image = UIImage(cgImage: thumbnail) }
            } catch { }
        }
    }
}
struct LodgingRating: View {
    let hotel: LodgingHotel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let rating = hotel.guestRating {
                Text(rating.formatted(.number.precision(.fractionLength(1))) + "/10 average guest rating").font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                if let count = hotel.reviewCount { Text("Based on \(count.formatted()) ratings & reviews").font(.caption).foregroundStyle(.secondary) }
                else { Text("Review count unavailable").font(.caption).foregroundStyle(.secondary) }
            } else { Text("Guest rating not available").font(.caption).foregroundStyle(.secondary) }
                    Text("LiteAPI / Nuitée").font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("hotel-average-rating")
    }
}
struct LodgingCard: View {
    let hotel: LodgingHotel
    var context = "hotel"
    var rate: HotelRateResult? = nil
    var dated = false
    var ratesLoading = false
    var ratesError: String? = nil
    @Environment(TravelStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Namespace private var transition
    var body: some View {
        NavigationLink {
            if reduce { LiveHotelDetailView(hotel: hotel) }
            else { LiveHotelDetailView(hotel: hotel).navigationTransition(.zoom(sourceID: hotel.id, in: transition)) }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                LodgingImage(url: hotel.photo, caption: hotel.name).aspectRatio(1.45, contentMode: .fit).clipShape(.rect(cornerRadius: 18)).matchedTransitionSource(id: hotel.id, in: transition)
                VStack(alignment: .leading, spacing: 6) {
                    Text(hotel.name).font(.title3.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                    HStack(alignment: .firstTextBaseline) {
                        Text(hotel.city + (hotel.stars.map { " · " + $0.formatted() + " star" } ?? "")).font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        if let rating = hotel.guestRating {
                            HStack(spacing: 4) { Image(systemName: "star.fill").font(.system(size: 9)); Text(rating.formatted(.number.precision(.fractionLength(1))) + "/10").fontWeight(.medium); if let count = hotel.reviewCount { Text("(\(count.formatted()))").foregroundStyle(.secondary) } }.font(.caption).foregroundStyle(.primary).accessibilityLabel("Guest score \(rating.formatted()) out of 10, \(hotel.reviewCount.map { String($0) + " ratings and reviews" } ?? "review count unavailable")")
                        }
                    }
                }
                if dated { HotelRateSummary(result: rate, loading: ratesLoading, error: ratesError) }
            }.contentShape(.rect)
        }.buttonStyle(StayPressStyle()).accessibilityIdentifier(context + "-open-" + hotel.id)
        .sensoryFeedback(.selection, trigger: store.isHotelSaved(hotel))
        .overlay(alignment: .topTrailing) {
            Button { withAnimation(StayStyle.motion(reduce)) { store.toggleHotelSave(hotel) } } label: {
                Image(systemName: store.isHotelSaved(hotel) ? "bookmark.fill" : "bookmark").font(.subheadline).contentTransition(reduce ? .identity : .symbolEffect(.replace)).frame(width: 44, height: 44).background(.regularMaterial, in: .circle)
            }.buttonStyle(StayPressStyle()).tint(.primary).padding(10).accessibilityLabel(store.isHotelSaved(hotel) ? "Unsave " + hotel.name : "Save " + hotel.name).accessibilityIdentifier(context + "-save-" + hotel.id)
        }
    }
}
struct HotelAccessNotice: View {
    @State private var account = false
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) { Text("More stays, one sign-in").font(.subheadline.weight(.medium)); Text("Explore hotels, photos and reviews.").font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            Button("Sign in") { account = true }.font(.subheadline.weight(.medium)).tint(.primary)
        }.padding(.vertical, 18)
        .fullScreenCover(isPresented: $account) { TravelAccountView() }
    }
}
struct HotelDiscoverySection: View {
    @Environment(TravelAPI.self) private var api
    @Environment(TravelStore.self) private var store
    @State private var model = HotelSearchModel()
    private var destinations: [ExploreCity] { ["Rome", "Kyoto", "Lisbon", "London", "Paris", "Bangkok"].compactMap { name in DestinationSuggestions.cities.first { $0.name == name } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) { Text("Stays to discover").font(.title3.weight(.semibold)); Spacer(); NavigationLink("See all") { HotelBookingFlow(city: model.destination) }.font(.subheadline) }
            ScrollView(.horizontal) { HStack(spacing: 9) { ForEach(destinations) { city in
                Button(city.name) { model.select(city, api: api) }.buttonStyle(.bordered).tint(model.destination?.id == city.id ? Color.bronze : .secondary)
            } } }.scrollIndicators(.hidden)
            if !api.hotelAccess {
                if let hotel = store.featured.first {
                    NavigationLink(value: hotel) {
                        ZStack(alignment: .bottomLeading) {
                            HotelPhoto(hotel: hotel).frame(height: 260)
                            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 6) { Text("FROM THE OFFLINE COLLECTION").font(.caption2).tracking(1.5); Editorial(hotel.shortName, size: 29); Text(hotel.city + " · Stay & dine").font(.subheadline) }.foregroundStyle(.white).padding(20)
                        }.clipShape(.rect(cornerRadius: 20))
                    }.buttonStyle(.plain).accessibilityIdentifier("hero-hotel")
                }
                HotelAccessNotice()
            }
            else if model.loading { ProgressView("Finding stays…").frame(maxWidth: .infinity, minHeight: 150) }
            else if let error = model.error { HotelRetry(message: error) { model.search(api: api) } }
            else if model.hotels.isEmpty { Text("No hotel information is available for this destination yet. Try another city.").foregroundStyle(.secondary) }
            else {
                if let hotel = model.hotels.first { LodgingCard(hotel: hotel, context: "home-hotel") }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 20) { ForEach(model.hotels.dropFirst().prefix(5)) { hotel in LodgingCard(hotel: hotel, context: "home-hotel").frame(width: 275) } }
                }.scrollIndicators(.hidden)
                Text("LiteAPI / Nuitée").font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                NavigationLink("Travel guides") { GuideHubView() }
                Spacer()
                NavigationLink("Stay & dine collection") { CollectionSearchView() }
            }.font(.subheadline)
        }
        .task(id: api.hotelAccess) {
            model.clear()
            if api.hotelAccess, let destination = model.destination ?? destinations.first { model.select(destination, api: api) }
        }
    }
}
struct HotelRetry: View {
    let message: String
    var retry: () -> Void
    var body: some View { VStack(alignment: .leading, spacing: 12) { Text(message).font(.subheadline).foregroundStyle(.secondary); Button("Try again", action: retry).buttonStyle(.bordered) }.padding(.vertical, 20).accessibilityIdentifier("hotel-error") }
}

struct HotelSearchView: View {
    @Environment(TravelAPI.self) private var api
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var editing: HotelSetupStep?
    @State private var filters = false
    @State private var checkouts = false
    @State private var map = false
    @State private var selectedHotel: LodgingHotel?
    @State private var mapSelection: String?
    private var model: HotelSearchModel { store.hotelSearch }
    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .bottom) {
            StayStyle.background.ignoresSafeArea()
            if map && !model.results.isEmpty {
                Map(selection: $mapSelection) {
                    ForEach(model.results.filter { $0.coordinate != nil }) { hotel in
                        Marker(hotel.name, systemImage: "bed.double.fill", coordinate: hotel.coordinate!).tint(Color.primary).tag(hotel.id)
                    }
                }.ignoresSafeArea(edges: .bottom).transition(.opacity)
                .onChange(of: mapSelection) { if let id = mapSelection { selectedHotel = model.hotels.first { $0.id == id }; mapSelection = nil } }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 25) {
                        if model.destination == nil { destinationList }
                        else if !api.hotelAccess { HotelAccessNotice() }
                        else if model.loading && model.hotels.isEmpty { HotelSearchSkeleton() }
                        else if model.error != nil && model.hotels.isEmpty {
                            quietState("Couldn't load hotels", detail: "Try again in a moment.", action: "Try again") { model.search(api: api) }
                        } else if model.searched && model.hotels.isEmpty {
                            quietState("No matches this time", detail: "Try another name or fewer filters.", action: "Reset filters") { model.filters = HotelResultFilters(); model.hotelName = ""; model.stars = ""; model.score = ""; model.search(api: api) }.accessibilityIdentifier("hotels-empty")
                        } else {
                            if model.results.isEmpty && !model.hotels.isEmpty {
                                if model.rates.loading { ProgressView("Checking prices…").frame(maxWidth: .infinity) }
                                else { quietState("No stays match these filters", detail: "Adjust your filters or load more stays.", action: "Edit filters") { filters = true }.accessibilityIdentifier("hotel-filtered-empty") }
                            }
                            ForEach(model.results) { hotel in LodgingCard(hotel: hotel, rate: model.matchingRate(for: hotel), dated: model.stay.ratesReady, ratesLoading: model.rates.loading, ratesError: model.rates.error) }
                            if let error = model.error { HotelRetry(message: error) { model.search(api: api, more: true) } }
                            if model.stay.ratesReady && !model.hotels.isEmpty { Button("Refresh prices") { model.refreshRates(api: api) }.font(.subheadline).tint(.primary) }
                            if model.nextOffset != nil {
                                Button { model.search(api: api, more: true) } label: { HStack { if model.loading { ProgressView() }; Text("More stays").font(.subheadline.weight(.medium)) }.frame(maxWidth: .infinity, minHeight: 48).background(StayStyle.surface, in: .capsule) }.buttonStyle(StayPressStyle()).tint(.primary).disabled(model.loading || model.rates.loading).accessibilityIdentifier("hotel-load-more")
                            }
                            Text("Hotel content via LiteAPI / Nuitée").font(.caption2).foregroundStyle(.tertiary)
                        }
                        if !api.hotelAccess || model.destination == nil { NavigationLink("Stay & dine collection") { CollectionSearchView() }.font(.footnote).tint(.secondary).accessibilityIdentifier("hotel-offline-collection") }
                    }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 22)
                }.scrollDismissesKeyboard(.interactively).transition(.opacity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.hotels.isEmpty {
                StayBottomBar {
                    HStack(spacing: 20) {
                        Text("\(model.results.count) of \(model.hotels.count) loaded").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { withAnimation(StayStyle.motion(reduce)) { map.toggle() } } label: { Label(map ? "Show list" : "Show map", systemImage: map ? "list.bullet" : "map").font(.subheadline.weight(.semibold)).frame(minHeight: 44) }.buttonStyle(StayPressStyle()).tint(.primary).accessibilityIdentifier("hotel-map-toggle")
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { searchHeader }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $editing) { step in
            HotelStaySetupPage(selection: $model.stay, city: model.destination, startingStep: step) { city in
                if let city, city.id != model.destination?.id {
                    model.clear(); model.filters = HotelResultFilters(); model.hotelName = ""; model.stars = ""; model.score = ""
                    store.rememberExploreCity(city); model.select(city, api: api)
                }
                model.refreshRates(api: api); editing = nil
            }
        }
        .navigationDestination(isPresented: $filters) { HotelFiltersSheet().hotelFlowPage() }
        .navigationDestination(isPresented: $checkouts) { HotelCheckoutsSheet().hotelFlowPage() }
        .navigationDestination(item: $selectedHotel) { LiveHotelDetailView(hotel: $0) }
        .onAppear { if model.stay.ratesReady && model.rates.criteria == nil && !model.hotels.isEmpty { model.refreshRates(api: api) } }
        .sensoryFeedback(.selection, trigger: map)
        .sensoryFeedback(.selection, trigger: model.destination?.id)
        .onChange(of: api.account?.id) { model.clear(); if api.hotelAccess && model.destination != nil { model.rateSearchEnabled = model.stay.ratesReady; model.search(api: api) } }
        .onChange(of: api.baseURL) { model.clear() }
    }
    private var searchHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { Image(systemName: "arrow.left").font(.body.weight(.medium)).frame(width: 44, height: 48) }.accessibilityLabel("Back to exploring").accessibilityIdentifier("hotel-search-close")
                Button { editing = .destination } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "magnifyingglass").font(.subheadline)
                        Text(model.destination?.name ?? "Where to?").font(.subheadline.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        if !model.hotelName.isEmpty { Text(model.hotelName).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }.padding(.horizontal, 16).frame(height: 50).background(StayStyle.surface, in: .capsule)
                }.accessibilityIdentifier("hotel-search-bar")
                Button { filters = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.body).frame(width: 44, height: 48)
                        .overlay(alignment: .topTrailing) { if model.filters.active || !model.hotelName.isEmpty { Circle().fill(Color.bronze).frame(width: 6, height: 6).padding(5) } }
                }.accessibilityLabel("Filters").accessibilityIdentifier("hotel-filters")
            }.buttonStyle(StayPressStyle()).tint(.primary)
            HStack(spacing: 8) {
                StayChip(title: model.stay.dateLabel, symbol: "calendar", selected: model.stay.checkIn != nil) { editing = .dates }.accessibilityIdentifier("hotel-dates")
                StayChip(title: model.stay.guestLabel, symbol: "person", selected: false) { editing = .guests }.accessibilityIdentifier("hotel-guests")
                Spacer(minLength: 0)
                Button { checkouts = true } label: { Image(systemName: "clock.arrow.circlepath").frame(width: 44, height: 44) }.tint(.primary).accessibilityLabel("Test bookings").accessibilityIdentifier("hotel-checkouts")
            }
            if model.destination != nil && api.hotelAccess {
                HStack {
                    Text(model.loading && model.hotels.isEmpty ? "Finding stays…" : model.hotels.isEmpty ? "Stays nearby" : "\(model.hotels.count) stays · " + (model.stay.ratesReady ? "test rates" : "choose dates for prices")).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("hotel-result-count")
                    Spacer()
                    if map && model.nextOffset != nil { Button("Load more") { model.search(api: api, more: true) }.disabled(model.loading || model.rates.loading).font(.caption.weight(.medium)).accessibilityIdentifier("hotel-map-more") }
                    else { Menu { Button("Recommended order") { model.sortByName = false; model.sortByPrice = false }; Button("Name A–Z · loaded stays") { model.sortByName = true; model.sortByPrice = false }; if model.stay.ratesReady { Button("Total price · checked stays") { model.sortByPrice = true; model.sortByName = false } } } label: { HStack(spacing: 5) { Text(model.sortByPrice ? "Price" : model.sortByName ? "Name" : "Sort"); Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }.font(.caption) } }
                }.tint(.primary).padding(.top, 2)
            }
        }.padding(.horizontal, 16).padding(.top, 5).padding(.bottom, 14).background(StayStyle.background)
            .overlay(alignment: .bottom) { Color.primary.opacity(0.06).frame(height: 0.5) }
    }
    private var destinationList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.recentExploreCities.isEmpty ? "Explore" : "Recent").font(.subheadline.weight(.semibold)).padding(.bottom, 8)
            ForEach(store.recentExploreCities.isEmpty ? Array(DestinationSuggestions.cities.filter { ["Rome", "Kyoto", "Lisbon", "Paris", "London", "Bangkok"].contains($0.name) }.prefix(6)) : store.recentExploreCities) { city in
                HotelDestinationRow(city: city) { model.destination = city; editing = .dates }
            }
        }
    }
    private func quietState(_ title: String, detail: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.tertiary).padding(.bottom, 6)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action, action: perform).font(.subheadline.weight(.medium)).tint(.primary).padding(.horizontal, 22).padding(.vertical, 12).background(StayStyle.surface, in: .capsule).padding(.top, 8)
        }.frame(maxWidth: .infinity).padding(.vertical, 65)
    }
}
struct HotelDestinationRow: View {
    let city: ExploreCity
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "location").font(.body).foregroundStyle(.secondary).frame(width: 46, height: 46).background(StayStyle.surface, in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) { Text(city.name).font(.subheadline.weight(.medium)); Text(city.country).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.tertiary)
            }.padding(.vertical, 8).contentShape(.rect)
        }.buttonStyle(StayPressStyle()).tint(.primary).accessibilityIdentifier("hotel-city-" + city.name)
    }
}
private struct HotelFiltersSheet: View {
    @Environment(TravelStore.self) private var store
    @Environment(TravelAPI.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var draft = HotelResultFilters()
    private var model: HotelSearchModel { store.hotelSearch }
    private var ceiling: Double {
        let values = model.rates.results.values.flatMap(\.offers).compactMap { $0.total?.decimal }.map { NSDecimalNumber(decimal: $0).doubleValue }
        return max(100, ceil(max(values.max() ?? 2000, draft.maximumPrice ?? 0, draft.minimumPrice ?? 0) / 100) * 100)
    }
    private func money(_ value: Double) -> String { value.formatted(.currency(code: model.stay.currency).precision(.fractionLength(0))) }
    var body: some View {
        VStack(spacing: 0) {
            StaySheetHeader(title: "Find your kind of stay")
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    TextField("Hotel name", text: $name).padding(16).background(StayStyle.surface, in: .rect(cornerRadius: 14)).accessibilityIdentifier("hotel-name")
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Total stay budget").font(.headline)
                        Text("All rooms · \(model.stay.currency) · includes known mandatory charges").font(.caption).foregroundStyle(.secondary)
                        HStack { Text("Minimum"); Spacer(); Text(draft.minimumPrice.map(money) ?? "Any") }.font(.subheadline)
                        Slider(value: Binding(get: { draft.minimumPrice ?? 0 }, set: { draft.minimumPrice = $0 == 0 ? nil : $0; if let high = draft.maximumPrice, high < $0 { draft.maximumPrice = $0 } }), in: 0...ceiling, step: 10).tint(.primary).accessibilityLabel("Minimum total stay price").accessibilityIdentifier("hotel-price-min")
                        HStack { Text("Maximum"); Spacer(); Text(draft.maximumPrice.map(money) ?? "Any") }.font(.subheadline)
                        Slider(value: Binding(get: { draft.maximumPrice ?? ceiling }, set: { draft.maximumPrice = $0 >= ceiling ? nil : $0; if let low = draft.minimumPrice, low > $0 { draft.minimumPrice = $0 } }), in: 0...ceiling, step: 10).tint(.primary).accessibilityLabel("Maximum total stay price").accessibilityIdentifier("hotel-price-max")
                        if !model.stay.ratesReady { Text("Choose dates to filter prices and room options.").font(.caption).foregroundStyle(.secondary) }
                    }.disabled(!model.stay.ratesReady)
                    Divider()
                    choices("Hotel category", values: [0, 3, 4, 5], selection: $draft.minimumStars) { $0 == 0 ? "Any" : "\($0)+ stars" }
                    choices("Average guest rating", values: [0, 7, 8, 9], selection: $draft.minimumRating) { $0 == 0 ? "Any" : "\($0)+ / 10" }
                    choices("Number of reviews", values: [0, 100, 500, 1000], selection: $draft.minimumReviews) { $0 == 0 ? "Any" : "\($0)+" }
                    choices("Distance from destination centre", values: [0, 1, 3, 5, 10], selection: $draft.maximumDistanceKM) { $0 == 0 ? "Any" : "\($0) km" }
                    Divider()
                    VStack(spacing: 20) {
                        Toggle("With photos", isOn: $draft.photosOnly).accessibilityIdentifier("hotel-filter-photos")
                        Toggle("With available test rates", isOn: $draft.availableOnly).disabled(!model.stay.ratesReady).accessibilityIdentifier("hotel-filter-available")
                        Toggle("Breakfast included", isOn: $draft.breakfast).disabled(!model.stay.ratesReady).accessibilityIdentifier("hotel-filter-breakfast")
                        Toggle("Free cancellation", isOn: $draft.freeCancellation).disabled(!model.stay.ratesReady).accessibilityIdentifier("hotel-filter-refundable")
                    }.font(.subheadline).tint(.primary)
                    Text("Filters apply to loaded stays. Price, breakfast and cancellation use each hotel's checked offer; other room packages may differ. Load more stays to widen your results.").font(.caption).foregroundStyle(.secondary)
                }.padding(22)
            }.scrollDismissesKeyboard(.interactively)
        }.background(StayStyle.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StayBottomBar {
                HStack(spacing: 24) {
                    Button("Reset") { name = ""; draft = HotelResultFilters() }.font(.subheadline).tint(.primary).accessibilityIdentifier("hotel-filters-reset")
                    StayPrimaryButton(title: "Show stays", action: apply).accessibilityIdentifier("hotel-filters-apply")
                }
            }
        }
        .onAppear { name = model.hotelName; draft = model.filters }
        .sensoryFeedback(.selection, trigger: draft)
    }
    private func apply() {
        let stars = draft.minimumStars >= 4 ? String(draft.minimumStars) : ""
        let score = draft.minimumRating >= 8 ? String(draft.minimumRating) : ""
        let reload = name != model.hotelName || stars != model.stars || score != model.score
        model.filters = draft; model.hotelName = name; model.stars = stars; model.score = score
        if reload { model.search(api: api) }
        dismiss()
    }
    private func choices(_ title: String, values: [Int], selection: Binding<Int>, label: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.subheadline.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { ForEach(values, id: \.self) { value in choice(value, label: label(value), selection: selection) } }
                VStack(alignment: .leading, spacing: 8) { ForEach(values, id: \.self) { value in choice(value, label: label(value), selection: selection) } }
            }
        }
    }
    private func choice(_ value: Int, label: String, selection: Binding<Int>) -> some View {
        Button { selection.wrappedValue = value } label: { Text(label).font(.caption.weight(.medium)).fixedSize().padding(.horizontal, 13).frame(minHeight: 44).foregroundStyle(selection.wrappedValue == value ? StayStyle.background : Color.primary).background(selection.wrappedValue == value ? Color.primary : StayStyle.surface, in: .capsule) }.buttonStyle(StayPressStyle()).accessibilityAddTraits(selection.wrappedValue == value ? .isSelected : [])
    }
}
private struct HotelSearchSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            RoundedRectangle(cornerRadius: 18).fill(StayStyle.surface).aspectRatio(1.45, contentMode: .fit)
            RoundedRectangle(cornerRadius: 4).fill(StayStyle.surface).frame(width: 180, height: 16)
            RoundedRectangle(cornerRadius: 4).fill(StayStyle.surface).frame(width: 120, height: 12)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Loading hotels").accessibilityIdentifier("hotels-loading")
    }
}

struct LiveHotelDetailView: View {
    let hotel: LodgingHotel
    var legacy: Hotel? = nil
    @Environment(TravelAPI.self) private var api
    @Environment(TravelStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var detail: LodgingDetail?
    @State private var loading = false
    @State private var error: String?
    @State private var reload = 0
    @State private var gallery = false
    @State private var planning = false
    @State private var setup: HotelSetupStep?
    @State private var rateScroll = 0
    @State private var selectedRoom: LodgingRoom?
    @State private var aboutExpanded = false
    @State private var allRooms = false
    @State private var planningRoom = ""
    private var current: LodgingHotel { detail?.hotel ?? hotel }
    var body: some View {
        @Bindable var model = store.hotelSearch
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 0) {
                    Button { gallery = true } label: {
                        ZStack(alignment: .bottomTrailing) {
                            LodgingImage(url: detail?.photos.first?.url ?? current.photo, caption: current.name).frame(height: 310)
                            if let photos = detail?.photos, !photos.isEmpty { Label("\(photos.count) photos", systemImage: "square.on.square").font(.caption.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 11).background(.regularMaterial, in: .capsule).padding(20) }
                        }
                    }.buttonStyle(.plain).disabled(detail?.photos.isEmpty != false).accessibilityIdentifier("hotel-gallery")
                    VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(current.city + (current.stars.map { " · " + $0.formatted() + " star hotel" } ?? "")).font(.subheadline).foregroundStyle(.secondary)
                        Text(current.name).font(.title2.weight(.semibold)).accessibilityIdentifier("hotel-detail-title")
                        LodgingRating(hotel: current)
                    }
                    HStack(spacing: 24) {
                        ForEach(["Overview", "Rooms", "Reviews"], id: \.self) { title in Button(title) { withAnimation(StayStyle.motion(reduce)) { reader.scrollTo(title == "Rooms" ? "Room prices" : title, anchor: .top) } }.font(.subheadline.weight(.medium)).tint(.primary) }
                    }.padding(.vertical, 8)
                    if !api.hotelAccess { HotelAccessNotice() }
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if let error { HotelRetry(message: error) { reload += 1 } }
                    if let detail {
                        VStack(alignment: .leading, spacing: 15) {
                            if !detail.description.isEmpty {
                                Text(detail.description).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4).lineLimit(aboutExpanded ? nil : 4)
                                Button(aboutExpanded ? "Less" : "About this hotel") { withAnimation(StayStyle.motion(reduce)) { aboutExpanded.toggle() } }.font(.subheadline.weight(.medium)).tint(.primary)
                            }
                            if !detail.facilities.isEmpty { HotelFacilities(values: detail.facilities) }
                        }.id("Overview")
                        section("Your stay") {
                            HStack(spacing: 8) {
                                StayChip(title: model.stay.dateLabel, symbol: "calendar") { setup = .dates }.accessibilityIdentifier("hotel-detail-dates")
                                StayChip(title: model.stay.guestLabel, symbol: "person") { setup = .guests }
                            }
                        }
                        HotelRoomOffersView(hotel: current, detail: detail).id("Room prices")
                        if !detail.rooms.isEmpty {
                            section("Rooms") {
                                ForEach(allRooms ? detail.rooms : Array(detail.rooms.prefix(3))) { room in
                                    Button { planningRoom = ""; selectedRoom = room } label: {
                                        HStack(spacing: 15) {
                                            LodgingImage(url: room.photos.first?.url, caption: room.name).frame(width: 82, height: 88).clipShape(.rect(cornerRadius: 13))
                                            VStack(alignment: .leading, spacing: 6) { Text(room.name).font(.subheadline.weight(.medium)); if let size = room.size { Text(size.formatted() + " " + room.sizeUnit).font(.caption).foregroundStyle(.secondary) }; if let guests = room.maxOccupancy { Text("Up to \(guests) guests").font(.caption).foregroundStyle(.secondary) } }
                                            Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                        }.contentShape(.rect)
                                    }.buttonStyle(StayPressStyle()).tint(.primary).accessibilityIdentifier("hotel-room-details-" + room.id)
                                }
                                if detail.rooms.count > 3 { Button(allRooms ? "Show fewer rooms" : "All \(detail.rooms.count) room types") { withAnimation(StayStyle.motion(reduce)) { allRooms.toggle() } }.font(.subheadline.weight(.medium)).tint(.primary) }
                            }.id("Rooms")
                        }
                    }
                    section("Guest reviews") { HotelReviewsView(hotelID: hotel.id) }.id("Reviews")
                    if !current.address.isEmpty {
                        section("Location") {
                            if let coordinate = current.coordinate { Map { Marker(current.name, coordinate: coordinate).tint(Color.primary) }.frame(height: 180).clipShape(.rect(cornerRadius: 16)) }
                            Text(current.address).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let detail, !detail.importantInformation.isEmpty { DisclosureGroup("Good to know") { Text(detail.importantInformation).font(.subheadline).foregroundStyle(.secondary).padding(.top, 12) }.font(.subheadline.weight(.medium)).tint(.primary) }
                    if let legacy, !legacy.venues.isEmpty { NavigationLink("Dining at this hotel") { CollectionHotelDetailView(hotel: legacy) }.font(.subheadline).tint(.primary) }
                    Text("Hotel content via LiteAPI / Nuitée").font(.caption2).foregroundStyle(.tertiary)
                    }.padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 24)
                }
            }.onChange(of: rateScroll) { withAnimation(StayStyle.motion(reduce)) { reader.scrollTo("Room prices", anchor: .top) } }.background(StayStyle.background).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { withAnimation(StayStyle.motion(reduce)) { store.toggleHotelSave(current) } } label: { Image(systemName: store.isHotelSaved(current) ? "bookmark.fill" : "bookmark").contentTransition(reduce ? .identity : .symbolEffect(.replace)) }.tint(.primary).accessibilityLabel(store.isHotelSaved(current) ? "Unsave hotel" : "Save hotel").accessibilityIdentifier("hotel-detail-save")
            } }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StayBottomBar {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) { Text(model.stay.nights > 0 ? "\(model.stay.nights) nights" : "Your next stay").font(.subheadline.weight(.medium)); Button("Plan stay") { planningRoom = ""; planning = true }.font(.caption).tint(.secondary).accessibilityIdentifier("hotel-plan-stay") }.frame(maxWidth: .infinity, alignment: .leading)
                    StayPrimaryButton(title: "View rooms") { if !model.stay.ratesReady { setup = model.stay.checkIn == nil ? .dates : .guests } else { withAnimation(StayStyle.motion(reduce)) { reader.scrollTo("Room prices", anchor: .top) } } }.frame(maxWidth: 170).accessibilityIdentifier("hotel-view-rooms")
                }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: store.isHotelSaved(current))
        .sheet(isPresented: $planning) { HotelStayPlanner(hotel: current, roomName: planningRoom) }
        .navigationDestination(item: $setup) { step in
            HotelStaySetupPage(selection: $model.stay, city: model.destination, startingStep: step) { _ in
                model.refreshRates(api: api); setup = nil; rateScroll += 1
            }
        }
        .navigationDestination(isPresented: Binding(get: { selectedRoom != nil }, set: { if !$0 { selectedRoom = nil } })) {
            if let room = selectedRoom { HotelRoomSheet(hotel: current, room: room).hotelFlowPage() }
        }
        .fullScreenCover(isPresented: $gallery) { HotelPhotoGallery(photos: detail?.photos ?? []) }
        .task(id: "\(reload)-\(api.hotelAccess)") {
            guard api.hotelAccess else { detail = nil; error = nil; return }
            loading = true; error = nil; defer { loading = false }
            do { detail = try await api.hotelDetail(hotel.id) } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) { Divider().padding(.bottom, 4); Text(title).font(.headline); content() }
    }
}
private struct HotelFacilities: View {
    let values: [String]
    @State private var all = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 18) {
                ForEach(Array(values.prefix(4).enumerated()), id: \.offset) { _, value in Label(value, systemImage: symbol(value)).font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, 10)
            Button("All amenities") { all = true }.font(.subheadline.weight(.medium)).tint(.primary)
        }.navigationDestination(isPresented: $all) {
            VStack(spacing: 0) { StaySheetHeader(title: "Amenities"); List(Array(values.enumerated()), id: \.offset) { _, value in Label(value, systemImage: symbol(value)).font(.subheadline).listRowSeparator(.hidden).padding(.vertical, 7) }.listStyle(.plain) }.background(StayStyle.background).hotelFlowPage()
        }
    }
    private func symbol(_ text: String) -> String {
        let value = text.lowercased()
        if value.contains("wifi") { return "wifi" }; if value.contains("pool") { return "water.waves" }; if value.contains("fitness") { return "dumbbell" }; if value.contains("restaurant") { return "fork.knife" }; if value.contains("park") { return "car" }; return "checkmark"
    }
}
private struct HotelRoomSheet: View {
    let hotel: LodgingHotel
    let room: LodgingRoom
    @Environment(\.dismiss) private var dismiss
    @State private var photos = false
    @State private var planning = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !room.photos.isEmpty {
                        Button { photos = true } label: {
                            ZStack(alignment: .bottomTrailing) {
                                LodgingImage(url: room.photos.first?.url, caption: room.name)
                                    .frame(height: min(420, max(300, geometry.size.width * 0.82)) + geometry.safeAreaInsets.top)
                                    .overlay(alignment: .top) {
                                        LinearGradient(colors: [StayStyle.background.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                                            .frame(height: geometry.safeAreaInsets.top + 60).allowsHitTesting(false)
                                    }
                                Label("\(room.photos.count) photos", systemImage: "square.on.square").font(.caption.weight(.medium)).padding(13).background(.regularMaterial, in: .capsule).padding(20)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("hotel-room-photos")
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        Text(room.name).font(.title2.weight(.semibold))
                        if let size = room.size { Text(size.formatted() + " " + room.sizeUnit).font(.subheadline).foregroundStyle(.secondary) }
                        if let count = room.maxOccupancy { Label("Up to \(count) guests", systemImage: "person.2").font(.subheadline).foregroundStyle(.secondary) }
                        if !room.description.isEmpty { Text(room.description).font(.subheadline).lineSpacing(4) }
                        Text("Room availability hasn't been checked.").font(.caption).foregroundStyle(.secondary)
                    }.padding(22)
                }.padding(.top, room.photos.isEmpty ? 64 : 0)
            }.ignoresSafeArea(.container, edges: room.photos.isEmpty ? [] : .top)
        }.background(StayStyle.background)
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.black).frame(width: 46, height: 46)
                    .background(.white.opacity(0.94), in: .circle)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            }.buttonStyle(StayPressStyle()).padding(.leading, 22).padding(.top, 8)
                .accessibilityLabel("Back to hotel").accessibilityIdentifier("hotel-room-back")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StayBottomBar { StayPrimaryButton(title: "Plan this room") { planning = true }.accessibilityIdentifier("hotel-plan-room") }
        }
        .fullScreenCover(isPresented: $photos) { HotelPhotoGallery(photos: room.photos) }
        .sheet(isPresented: $planning) { HotelStayPlanner(hotel: hotel, roomName: room.name).environment(\.stayFullPage, false) }
        .sensoryFeedback(.selection, trigger: photos)
    }
}
private enum HotelPhotoMode: String, CaseIterable { case individual = "Individual", gallery = "Gallery" }
private struct HotelPhotoGallery: View {
    let photos: [LodgingPhoto]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var index = 0
    @State private var mode = HotelPhotoMode.individual
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Photos").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close photos").accessibilityIdentifier("hotel-gallery-done")
            }.padding(.horizontal, 22)
            Picker("Photo view", selection: $mode) { ForEach(HotelPhotoMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 22).padding(.bottom, 16).accessibilityIdentifier("hotel-photo-mode")
            if photos.isEmpty { ContentUnavailableView("No photos available", systemImage: "photo") }
            else if mode == .individual {
                TabView(selection: $index) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { i, photo in
                        Group {
                            // Only decode the visible image and its immediate neighbours.
                            if abs(i - index) <= 1 { LodgingImage(url: photo.url, caption: photo.caption, contentMode: .fit, maxPixelSize: 1800) }
                            else { StayStyle.background }
                        }.tag(i)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never)).accessibilityIdentifier("hotel-photo-individual")
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                            ForEach(Array(photos.enumerated()), id: \.offset) { i, photo in
                                Button { index = i; withAnimation(StayStyle.motion(reduce)) { mode = .individual } } label: {
                                    LodgingImage(url: photo.url, caption: photo.caption, maxPixelSize: 480).aspectRatio(1, contentMode: .fit)
                                }.buttonStyle(.plain).id(i).accessibilityLabel("Photo \(i + 1): " + photo.caption).accessibilityIdentifier("hotel-photo-thumb-\(i)")
                            }
                        }
                    }.onAppear { reader.scrollTo(index, anchor: .center) }
                }.accessibilityIdentifier("hotel-photo-grid")
            }
        }.background(StayStyle.background).tint(.primary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StayBottomBar {
                VStack(spacing: 8) {
                    if mode == .individual && photos.indices.contains(index) {
                        HStack {
                            Button { index = max(0, index - 1) } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }.disabled(index == 0).accessibilityLabel("Previous photo").accessibilityIdentifier("hotel-photo-previous")
                            Spacer()
                            Text("\(index + 1) / \(photos.count)").font(.subheadline.monospacedDigit()).accessibilityIdentifier("hotel-photo-count")
                            Spacer()
                            Button { index = min(photos.count - 1, index + 1) } label: { Image(systemName: "arrow.right").frame(width: 44, height: 44) }.disabled(index == photos.count - 1).accessibilityLabel("Next photo").accessibilityIdentifier("hotel-photo-next")
                        }
                        Text(photos[index].caption).font(.caption).multilineTextAlignment(.center).lineLimit(3)
                    }
                    Text("LiteAPI / Nuitée").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: index).sensoryFeedback(.selection, trigger: mode)
    }
}

private struct HotelReviewsView: View {
    let hotelID: String
    @Environment(TravelAPI.self) private var api
    @State private var reviews: [LodgingReview] = []
    @State private var nextOffset: Int? = 0
    @State private var loading = false
    @State private var error: String?
    @State private var requested = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Guest scores may include ratings without written comments.").font(.caption).foregroundStyle(.secondary)
            ForEach(reviews) { review in
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(review.name.isEmpty ? "Guest" : review.name).font(.subheadline.weight(.semibold)); Spacer(); if let rating = review.rating { Text(rating.formatted() + "/10").foregroundStyle(Color.primary) } }
                    Text([String(review.date.prefix(10)), review.source].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    if !review.headline.isEmpty { Text(review.headline).font(.headline) }
                    if !review.pros.isEmpty { Text(review.pros).font(.subheadline) }
                    if !review.cons.isEmpty { VStack(alignment: .leading, spacing: 5) { Text("Could be better").font(.caption.weight(.medium)).foregroundStyle(.secondary); Text(review.cons).font(.subheadline) } }
                    Divider()
                }.textSelection(.enabled)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if requested && reviews.isEmpty && !loading && error == nil { Text(nextOffset == nil ? "No written reviews are available." : "This page contains ratings without written comments. Continue to the next page.").font(.subheadline).foregroundStyle(.secondary) }
            if nextOffset != nil {
                Button { Task { await load() } } label: { HStack { if loading { ProgressView() }; Text(!requested ? "Read guest reviews" : error != nil ? "Retry reviews" : "Load more reviews") } }.buttonStyle(.bordered).disabled(loading).accessibilityIdentifier("hotel-load-reviews")
            }
        }
    }
    private func load() async {
        guard !loading, let offset = nextOffset else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            let page = try await api.hotelReviews(hotelID, offset: offset); try Task.checkCancellation()
            var seen = Set(reviews.map(\.id)); reviews += page.reviews.filter { seen.insert($0.id).inserted }; nextOffset = page.nextOffset; requested = true
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}


/// Resolve a named place first, then let the traveler choose its supplier listing.
/// An Apple Maps suggestion is never treated as a LiteAPI booking identifier.
struct HotelNameSearchView: View {
    var isGlobalSearch = false
    @Environment(TravelAPI.self) private var api
    @Environment(TravelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var lookup = HotelSearchModel()
    @State private var selected: LodgingHotel?
    @State private var location: LocationSelection?
    @State private var error: String?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let error { Text(error).font(.subheadline).foregroundStyle(.secondary) }
                if let location {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Matching hotels").font(.headline)
                        Text(location.place.address).font(.caption).foregroundStyle(.secondary)
                    }
                    if !api.hotelAccess { HotelAccessNotice() }
                    else if lookup.loading && lookup.hotels.isEmpty { ProgressView("Finding hotel listings…").frame(maxWidth: .infinity).padding(.vertical, 35) }
                    else if let message = lookup.error { HotelRetry(message: message) { lookup.search(api: api, more: !lookup.hotels.isEmpty) } }
                    else if lookup.searched && lookup.hotels.isEmpty {
                        ContentUnavailableView("No matching listing", systemImage: "bed.double", description: Text("Try another spelling or add the city to the hotel name. This property may not be in our hotel inventory."))
                    }
                    ForEach(lookup.hotels) { hotel in
                        Button { open(hotel) } label: {
                            HStack(alignment: .top, spacing: 15) {
                                LodgingImage(url: hotel.photo, caption: hotel.name).frame(width: 88, height: 100).clipShape(.rect(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(hotel.name).font(.subheadline.weight(.semibold))
                                    Text([hotel.city, hotel.country].filter { !$0.isEmpty }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                    Text(hotel.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    if let rating = hotel.guestRating { Text(rating.formatted(.number.precision(.fractionLength(1))) + "/10").font(.caption.weight(.medium)) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 3)
                            }.contentShape(.rect)
                        }.buttonStyle(StayPressStyle()).tint(.primary).accessibilityIdentifier("hotel-name-result-" + hotel.id)
                        Divider()
                    }
                    if lookup.nextOffset != nil {
                        Button("More matches") { lookup.search(api: api, more: true) }.disabled(lookup.loading).font(.subheadline.weight(.medium)).tint(.primary)
                    }
                    if !lookup.hotels.isEmpty { Text("Hotel listings via LiteAPI / Nuitée. Choose the matching name and address.").font(.caption).foregroundStyle(.secondary) }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Have a hotel in mind?").font(.title3.weight(.semibold))
                        Text("Search its name and choose a suggestion. Add a city if several hotels share the name.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 12)
                }
            }.padding(22)
        }.scrollDismissesKeyboard(.interactively).background(StayStyle.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).padding(.top, 2)
                LocationAutocompleteField("Search hotel name", text: $query, kind: .hotel, identifier: "hotel-name-query", category: .hotel, onEdit: {
                    lookup.clear(); location = nil; error = nil
                }, onSelect: { value in
                    guard let city = ExploreCity(value) else { error = "Choose a hotel suggestion with an address."; return }
                    location = value; error = nil; lookup.hotelName = String(value.place.name.prefix(100)); lookup.select(city, api: api)
                })
            }.padding(17).background(StayStyle.surface, in: .rect(cornerRadius: 19)).padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 12).background(StayStyle.background)
        }
        .navigationTitle(isGlobalSearch ? "Explore" : "Find a hotel").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .toolbar {
            if isGlobalSearch { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "arrow.left") }.accessibilityLabel("Close search").accessibilityIdentifier("explore-search-close") } }
        }
        .navigationDestination(item: $selected) { hotel in LiveHotelDetailView(hotel: hotel) }
        .onChange(of: api.hotelAccess) { if location != nil { lookup.search(api: api) } }
        .sensoryFeedback(.selection, trigger: selected?.id)
    }
    private func open(_ hotel: LodgingHotel) {
        let model = store.hotelSearch
        model.clear(); model.filters = HotelResultFilters(); model.hotelName = ""; model.stars = ""; model.score = ""; model.sortByName = false; model.sortByPrice = false
        model.destination = hotel.coordinate.map { ExploreCity(name: hotel.city, country: hotel.country, latitude: $0.latitude, longitude: $0.longitude) } ?? lookup.destination
        selected = hotel
    }
}
