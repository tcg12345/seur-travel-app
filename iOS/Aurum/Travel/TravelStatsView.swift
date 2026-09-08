import SwiftUI
import Charts
import MapKit

struct TravelStatsPreview: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelStore.self) private var store
    var compact = false
    var body: some View {
        let summary = TravelStatistics(documents: library.documents, catalog: store.hotels).summary()
        NavigationLink { TravelStatsView() } label: {
            VStack(alignment: .leading, spacing: compact ? 12 : 20) {
                HStack {
                    Text("Your travel").font(compact ? .subheadline.weight(.semibold) : .title2.weight(.semibold)).foregroundStyle(.primary)
                    Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Color.bronze)
                }
                HStack(alignment: .top, spacing: 8) {
                    number(summary.stars, "Michelin stars")
                    number(summary.countries.count, "Countries")
                    number(summary.cities.count, "Cities")
                    number(summary.nightsAway, summary.nightsLabel)
                }
                if !compact { Text("Based on your logged trips").font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, compact ? 10 : 14).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(compact ? "travel-stats-strip" : "profile-travel-stats")
            .task { await TravelStatsMetadata.shared.enrich(library, catalog: store.hotels) }
    }
    private func number(_ number: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(number.formatted()).font(.system(compact ? .title3 : .title2, design: .serif)).foregroundStyle(Color.bronze)
            Text(label).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TravelStatsView: View {
    @Environment(JourneyLibrary.self) private var library
    @Environment(TravelStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var year: Int?
    @State private var export: ExportedJourney?
    @State private var error: String?
    @AppStorage("seur.stats.distanceUnit") private var distanceUnit = "Miles"
    private var stats: TravelStatistics { .init(documents: library.documents, catalog: store.hotels) }
    var body: some View {
        let source = stats
        let summary = source.summary(year: year)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: year.map { "Your \($0), remembered" } ?? "A life in places")
                        Editorial("Your travel story.", size: 34)
                        Text("Based on your logged trips").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Menu {
                        Picker("Period", selection: $year) {
                            Text("All time").tag(Int?.none)
                            ForEach(source.years, id: \.self) { Text(String($0)).tag(Optional($0)) }
                        }
                    } label: { HStack(spacing: 4) { Text(year.map(String.init) ?? "All time"); Image(systemName: "chevron.down").font(.caption2) }.font(.caption.weight(.semibold)).frame(minHeight: 44) }
                    .accessibilityIdentifier("stats-year")
                }
                diningHeadline(summary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 24) {
                    metric(summary.countries.count.formatted(), "Countries visited", "globe.europe.africa")
                    metric(summary.cities.count.formatted(), "Cities visited", "building.2")
                    metric(summary.nightsAway.formatted(), summary.nightsLabel, "bed.double")
                    metric(Int(distanceUnit == "Miles" ? summary.miles : summary.kilometers).formatted(), distanceUnit == "Miles" ? "Miles flown" : "Kilometers flown", "airplane")
                }
                HStack {
                    Text("\(summary.trips) trips logged").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Distance unit", selection: $distanceUnit) { Text("Miles").tag("Miles"); Text("Kilometers").tag("Kilometers") }.pickerStyle(.menu).font(.caption)
                }
                if summary.otherNights > 0 { Text("\(summary.hotelNights) recorded hotel nights + \(summary.otherNights) nights away without hotel records.").font(.caption).foregroundStyle(.secondary) }
                TravelStatsMap(visits: summary.visits, planned: summary.planned)
                if !summary.countries.isEmpty {
                    Text(summary.countries.sorted().map { Locale.current.localizedString(forRegionCode: $0) ?? $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineSpacing(5)
                }
                if summary.unknownCountries > 0 { Text("\(summary.unknownCountries) visited stops still need a country. Add one to the destination to include it here.").font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 14) {
                    Image(systemName: "calendar").font(.title3).foregroundStyle(Color.bronze)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Upcoming").font(.subheadline.weight(.semibold))
                        Text("\(summary.upcomingTrips) trips · \(Set(summary.planned.map { TravelStatistics.normalized($0.city) }).count) planned cities").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(17).cardSurface(cornerRadius: 18)
                Text("Upcoming destinations are separate from your visited totals.").font(.caption2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 20) {
                    Text("The places you come back to").font(.title2.weight(.medium))
                    insight("Favorite hotel brand", value: summary.favoriteBrands.isEmpty ? "Not enough stays yet" : summary.favoriteBrands.joined(separator: " · "), detail: summary.favoriteBrands.isEmpty ? "Add brands to at least three hotel stays." : (summary.favoriteBrands.count > 1 ? "Joint favorites · " : "") + "\(summary.brandStays[summary.favoriteBrands[0]] ?? 0) stays per brand", symbol: "key")
                    Divider()
                    insight("Most-visited city", value: summary.favoriteCities.isEmpty ? "Still to discover" : summary.favoriteCities.joined(separator: " · "), detail: summary.favoriteCities.isEmpty ? "Your visited destinations appear here." : "\(summary.cityVisits[summary.favoriteCities[0]] ?? 0) recorded visits" + (summary.favoriteCities.count > 1 ? " each" : ""), symbol: "mappin.and.ellipse")
                    Divider()
                    insight("Longest completed trip", value: summary.longest?.title ?? "Your story is just beginning", detail: summary.longest.map { "\($0.nights) nights" } ?? "Completed trips will appear here.", symbol: "suitcase.rolling")
                    Divider()
                    insight("Average place score", value: summary.average.map { $0.formatted(.number.precision(.fractionLength(1))) + " / 10" } ?? "No ratings yet", detail: "\(summary.scores.count) recorded ratings", symbol: "star")
                }
                trends(source)
                if !summary.spend.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Recorded spending").font(.title2.weight(.medium))
                        ForEach(summary.spend.keys.sorted(), id: \.self) { currency in
                            HStack { Text(currency).font(.caption).foregroundStyle(.secondary); Spacer(); Text(summary.spend[currency]!.formatted(.currency(code: currency))).font(.system(.title3, design: .serif)) }
                        }
                        Text("Only costs you entered. Currencies stay separate; no exchange-rate estimates. Spending is never included on the shared image.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup("How your numbers are counted") {
                    Text("A trip contributes after it ends or you start its journal. On a trip in progress, a stop needs a matching journal visit before it counts. Future stops and flights stay out. Flights count only after their arrival day has passed; airport connections never add countries. Hotel nights are elapsed calendar nights, not rooms booked. Without hotel records, recorded stop nights are labelled nights away.\n\nThe year filter uses visit dates and splits hotel nights across years. Completed trips and longest trips belong to their end year. Undated memories with no finished-trip date appear only in All time. Country counts use recognized country codes; unknown countries are left out.\n\nStats use trips saved on this device, exclude templates, and deduplicate repeated document IDs. Restore your own saved cloud trips from Account after reinstalling to include them again.")
                        .font(.caption).foregroundStyle(.secondary).lineSpacing(5).padding(.top, 10)
                }.font(.subheadline)
                if year != nil && summary.undatedEntries > 0 { Text("\(summary.undatedEntries) undated journal entries appear only in All time. Add visit dates to include them in a year.").font(.caption).foregroundStyle(.secondary) }
                Button { share(summary) } label: { Label("Share your travel card", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.glassProminent).accessibilityIdentifier("stats-share")
            }.padding(24)
        }.background(Color.canvas).navigationTitle("Your travel").navigationBarTitleDisplayMode(.inline)
            .task { await TravelStatsMetadata.shared.enrich(library, catalog: store.hotels) }
            .sheet(item: $export) { ActivityShareSheet(items: [$0.url]) }
            .alert("Travel card", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func diningHeadline(_ summary: TravelStatistics.Summary) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "fork.knife").font(.title3).foregroundStyle(Color.bronze)
                Text(summary.stars.formatted()).font(.system(size: 64, weight: .regular, design: .serif)).foregroundStyle(Color.bronze)
                Text("Michelin stars, experienced").font(.headline)
                Text("Across \(summary.starredRestaurants) starred restaurants you logged").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "sparkle").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(Color.bronze.opacity(0.3)).accessibilityHidden(true)
        }.padding(.vertical, 12)
    }
    private func metric(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(Color.bronze)
            Text(value).font(.system(.largeTitle, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func insight(_ label: String, value: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).foregroundStyle(Color.bronze).frame(width: 22)
            VStack(alignment: .leading, spacing: 7) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(.title3, design: .serif))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func trends(_ source: TravelStatistics) -> some View {
        let current = Calendar.current.component(.year, from: .now)
        let data = source.years.filter { $0 <= current }.sorted().map { (year: $0, value: source.summary(year: $0)) }
        return VStack(alignment: .leading, spacing: 18) {
            Text("Through the years").font(.title2.weight(.medium))
            Text("Nights away").font(.caption).foregroundStyle(.secondary)
            Chart(data, id: \.year) { item in
                BarMark(x: .value("Year", String(item.year)), y: .value("Nights", item.value.nightsAway)).foregroundStyle(Color.bronze.gradient).cornerRadius(3)
            }.frame(height: 160).chartXAxis { AxisMarks { AxisValueLabel().font(.system(.caption2, design: .serif)) } }
                .accessibilityLabel("Nights away per year")
            Text("Countries visited in each year").font(.caption).foregroundStyle(.secondary)
            Chart(data, id: \.year) { item in
                BarMark(x: .value("Year", String(item.year)), y: .value("Countries", item.value.countries.count)).foregroundStyle(Color.teal.opacity(0.7).gradient).cornerRadius(3)
            }.frame(height: 130).chartXAxis { AxisMarks { AxisValueLabel().font(.system(.caption2, design: .serif)) } }
                .accessibilityLabel("Distinct countries per year")
        }
    }
    private func share(_ summary: TravelStatistics.Summary) {
        do {
            let renderer = ImageRenderer(content: TravelStatsCard(summary: summary, year: year, kilometers: distanceUnit != "Miles").frame(width: 360, height: 640).environment(\.colorScheme, .light))
            renderer.scale = 3
            guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.95) else { throw JourneyError.message("The image could not be created.") }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Seur-travel-\(UUID().uuidString).jpg")
            try data.write(to: url, options: [.atomic,.completeFileProtection]); export = .init(url:url)
        } catch { self.error = error.localizedDescription }
    }
}

struct TravelStatsMap: View {
    let visits: [TravelStatistics.Visit]
    let planned: [TravelStatistics.Visit]
    @State private var camera: MapCameraPosition = .camera(.init(centerCoordinate: .init(latitude: 24, longitude: 5), distance: 35_000_000))
    private var visited: [TravelStatistics.Visit] { var seen = Set<String>(); return visits.filter { $0.point != nil && seen.insert(TravelStatistics.normalized($0.city)).inserted } }
    private var future: [TravelStatistics.Visit] { var seen = Set(visited.map { TravelStatistics.normalized($0.city) }); return planned.filter { $0.point != nil && seen.insert(TravelStatistics.normalized($0.city)).inserted } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Map(position: $camera) {
                ForEach(visited) { visit in
                    Annotation(visit.city, coordinate: .init(latitude: visit.point!.latitude, longitude: visit.point!.longitude)) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).frame(width: 24, height: 24).background(Color.bronze, in: Circle()).accessibilityLabel(visit.city + ", visited")
                    }
                }
                ForEach(future) { visit in
                    Annotation(visit.city, coordinate: .init(latitude: visit.point!.latitude, longitude: visit.point!.longitude)) {
                        Circle().fill(Color.white.opacity(0.8)).frame(width: 16, height: 16).overlay(Circle().stroke(Color.bronze, lineWidth: 1)).accessibilityLabel(visit.city + ", planned")
                    }
                }
            }.mapStyle(.imagery(elevation: .realistic)).frame(height: 300).clipShape(.rect(cornerRadius: 22))
            HStack(spacing: 18) { Label("Visited", systemImage: "checkmark.circle.fill").foregroundStyle(Color.bronze); Label("Planned", systemImage: "circle").foregroundStyle(.secondary) }.font(.caption)
        }
    }
}

struct TravelStatsCard: View {
    let summary: TravelStatistics.Summary
    let year: Int?
    var kilometers = false
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack { Text("S E U R").font(.system(size: 13, weight: .medium)); Spacer(); Text(year.map(String.init) ?? "ALL TIME").font(.system(size: 12, weight: .semibold)) }.foregroundStyle(Color(red:0.55,green:0.4,blue:0.24))
            Text("A life\nin places.").font(.system(size: 48, design: .serif)).lineSpacing(-3)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(summary.stars)").font(.system(size: 68, design: .serif))
                Text("Michelin stars\nexperienced").font(.system(size: 15)).lineSpacing(4)
            }.foregroundStyle(Color(red:0.55,green:0.4,blue:0.24))
            Rectangle().fill(Color.brown.opacity(0.2)).frame(height:1)
            HStack { number(summary.countries.count.formatted(),"COUNTRIES"); Spacer(); number(summary.cities.count.formatted(),"CITIES") }
            HStack { number(summary.nightsAway.formatted(),summary.nightsLabel.uppercased()); Spacer(); number(Int(kilometers ? summary.kilometers : summary.miles).formatted(),kilometers ? "KILOMETERS FLOWN" : "MILES FLOWN") }
            Spacer(minLength: 0)
            Text("Based on my logged trips.").font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Well planned. Beautifully remembered.").font(.system(size: 13, design: .serif)).foregroundStyle(Color(red:0.55,green:0.4,blue:0.24))
        }.padding(28).frame(width: 360, height: 640).background(Color(red:0.97,green:0.96,blue:0.93)).foregroundStyle(Color(red:0.16,green:0.21,blue:0.17))
    }
    private func number(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(value).font(.system(size: 31, design: .serif)).lineLimit(1).minimumScaleFactor(0.6); Text(label).font(.system(size: 9)).foregroundStyle(.secondary) }.frame(width: 140, alignment: .leading)
    }
}
