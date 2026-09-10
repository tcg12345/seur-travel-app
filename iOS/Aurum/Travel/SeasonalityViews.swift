import SwiftUI

/// Embeddable in Forms and route rows; no network requests or itinerary mutations.
struct SeasonalityCard: View {
    var city: String
    var countryCode: String? = nil
    var arrival: String? = nil
    var departure: String? = nil
    var compact = false
    @State private var calendarPresented = false
    private var catalog: SeasonalityCatalog? { .shared }
    private var destination: CitySeasonality? { catalog?.city(named: city, countryCode: countryCode) }
    var body: some View {
        if let destination {
            let assessment = destination.assessment(arrival: arrival, departure: departure)
            VStack(alignment: .leading, spacing: 10) {
                Label(destination.name + " · Seasonality", systemImage: "sun.max").font(.subheadline.weight(.semibold))
                if let assessment {
                    ForEach(assessment.months) { month in
                        Text(month.name + " · " + month.season.title + " · " + month.weather + " · " + month.rain).font(.caption).accessibilityIdentifier("seasonality-selected-" + destination.id + "-\(month.month)")
                    }
                    ForEach(assessment.advisories) { advisory in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(advisory.notice.title, systemImage: advisory.calendarPrompt == nil ? "calendar.badge.exclamationmark" : "calendar.badge.questionmark").font(.caption.weight(.semibold)).foregroundStyle(Color.bronze)
                            if let prompt = advisory.calendarPrompt { Text(prompt).font(.caption).foregroundStyle(.secondary) }
                            if !compact { Text(advisory.notice.detail).font(.caption).foregroundStyle(.secondary) }
                        }.accessibilityIdentifier("seasonality-notice-" + advisory.id)
                    }
                } else {
                    Text("Compare peak and shoulder months before choosing dates.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Compare months & holidays") { calendarPresented = true }
                    .font(.caption.weight(.semibold)).buttonStyle(.borderless).accessibilityIdentifier("seasonality-calendar-" + destination.id)
                if !compact { Text("Typical seasons, not a weather forecast. Venue hours and holiday crowds vary.").font(.caption2).foregroundStyle(.secondary) }
            }.padding(.vertical, 5).accessibilityElement(children: .contain).accessibilityIdentifier("seasonality-" + destination.id)
                .sheet(isPresented: $calendarPresented) { SeasonalityCalendar(city: destination, selectedMonths: Set(assessment?.months.map(\.month) ?? []), reviewedOn: catalog?.reviewedOn ?? "") }
        }
    }
}
private struct SeasonalityCalendar: View {
    let city: CitySeasonality
    let selectedMonths: Set<Int>
    let reviewedOn: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Peak usually means more visitors. Shoulder balances weather and crowds. Quieter months may bring tougher weather. These are editorial patterns; events can change demand.").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(city.months) { month in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(month.name).font(.headline)
                                Spacer()
                                Text(month.season.title).font(.subheadline).foregroundStyle(month.season == .shoulder ? Color.teal : Color.bronze)
                                if selectedMonths.contains(month.month) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.teal).accessibilityLabel("In your dates") }
                            }
                            Text(month.weather + " · " + month.rain).font(.caption).foregroundStyle(.secondary)
                        }.accessibilityIdentifier("seasonality-month-\(month.month)")
                    }
                } header: { Text("Month by month") } footer: { Text("Broad daytime weather bands, not temperature limits or a forecast. Rain is possible in every month.") }
                Section("Holidays & possible closures") {
                    ForEach(city.notices) { notice in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(notice.title).font(.headline)
                            Text(notice.schedule).font(.caption).foregroundStyle(Color.bronze)
                            Text(notice.detail).font(.subheadline)
                            Link("Check local guidance", destination: notice.source).font(.caption)
                        }
                    }
                    Text("This is a curated selection, not a complete public-holiday calendar. Dated entries apply only to the years shown; observed days and opening hours need confirmation.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Sources") {
                    ForEach(city.sources) { source in Link(source.title, destination: source.url) }
                    Text("Reviewed " + reviewedOn + ". Available offline; source links require a connection.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle(city.name + " by season").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("seasonality-calendar-done") } }
        }
    }
}
