import SwiftUI
import WidgetKit

// Shared, offline artwork: typography and vector details stay crisp at every size.
private func widgetColor(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
}
private struct WidgetPalette {
    let start, end, ink, muted, accent: Color
    init(dark: Bool) {
        start = widgetColor(dark ? 0x201F1D : 0xF5F2EC)
        end = widgetColor(dark ? 0x2B2925 : 0xEBE7DF)
        ink = widgetColor(dark ? 0xF3EFE7 : 0x292621)
        muted = widgetColor(dark ? 0xBBB5AA : 0x686158)
        accent = widgetColor(dark ? 0xC8B38A : 0x806B49)
    }
}

struct JourneyWidgetContent: View {
    let snapshot: JourneyWidgetSnapshot?
    let date: Date
    let kind: JourneyWidgetKind
    var previewFamily: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.colorScheme) private var scheme
    private var family: WidgetFamily { previewFamily ?? environmentFamily }
    private var small: Bool { family == .systemSmall }
    private var large: Bool { family == .systemLarge }
    private var palette: WidgetPalette { WidgetPalette(dark: scheme == .dark) }
    private var fullColor: Bool { renderingMode == .fullColor && (previewFamily != nil || showsBackground) }
    private var ink: Color { fullColor ? palette.ink : .primary }
    private var muted: Color { fullColor ? palette.muted : .secondary }
    private var accent: Color { fullColor ? palette.accent : .primary }
    private var active: JourneyWidgetTrip? { snapshot?.active(at: date) }
    private var trip: JourneyWidgetTrip? { kind == .nextTrip ? snapshot?.upcoming(at: date) ?? active : active ?? snapshot?.upcoming(at: date) }
    private var expired: Bool { snapshot.map { date >= $0.expiresAt } == true }
    private var heading: String { switch kind { case .today: "Today"; case .nextTrip: "Next trip"; case .budget: "Trip budget"; case .profile: "Travel profile" } }
    private var symbol: String { switch kind { case .today: "sun.max"; case .nextTrip: "airplane"; case .budget: "chart.pie"; case .profile: "globe.europe.africa" } }
    var link: URL { if kind == .profile { return JourneyWidgetProfile.url }; return trip.map { JourneyWidgetLink(tripID: $0.id, kind: kind).url } ?? URL(string: "seur://travel")! }

    var body: some View {
        Group {
            if family == .accessoryInline || family == .accessoryCircular || family == .accessoryRectangular {
                accessory
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    masthead
                    if kind == .profile { profileContent }
                    else if let trip {
                        switch kind {
                        case .today: today(trip)
                        case .nextTrip: countdown(trip)
                        case .budget: budget(trip)
                        case .profile: EmptyView()
                        }
                    } else { emptyContent }
                }.foregroundStyle(ink).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }.privacySensitive().widgetURL(link)
    }
    private var masthead: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium)).widgetAccentable()
            Text(small && kind == .profile ? "PASSPORT" : small && kind == .budget ? "BUDGET" : heading.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(1.3).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            if !small { Text("SEUR").font(.system(size: 9, weight: .medium)).tracking(2.5) }
            else { Image(systemName: "sparkle").font(.system(size: 9)).accessibilityHidden(true) }
        }.foregroundStyle(accent)
    }
    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1.1).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.8)
    }
    private func footer(_ text: String) -> some View {
        Text(text).font(.system(size: 9)).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.85)
    }
    private var rule: some View { Rectangle().fill(accent.opacity(0.3)).frame(height: 0.5).accessibilityHidden(true) }

    @ViewBuilder private func today(_ trip: JourneyWidgetTrip) -> some View {
        if trip.isActive(at: date) {
            let items = trip.remaining(at: date)
            let limit = large ? 5 : small ? 1 : 2
            if family == .systemMedium {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(trip.stop(at: date)?.name ?? trip.title).font(.system(size: 27, design: .serif)).lineLimit(2).minimumScaleFactor(0.7)
                        dateBadge(zone: trip.zone(at: date))
                    }.frame(width: 112, alignment: .leading)
                    Rectangle().fill(accent.opacity(0.3)).frame(width: 0.5).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 10) {
                        if items.isEmpty {
                            Text("Room to wander").font(.system(size: 19, design: .serif)).lineLimit(2)
                            footer("No remaining plans today")
                        } else {
                            ForEach(Array(items.prefix(2))) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    Text(item.schedule + " · " + item.zoneLabel(at: date)).font(.system(size: 9)).foregroundStyle(muted).lineLimit(1)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: .infinity, alignment: .top)
                footer("Saved itinerary" + (items.count > limit ? " · +\(items.count - limit) more" : ""))
            } else {
            HStack(alignment: .center) {
                Text(trip.stop(at: date)?.name ?? trip.title)
                    .font(.system(size: large ? 34 : small ? 25 : 29, weight: .regular, design: .serif))
                    .lineLimit(1).minimumScaleFactor(0.65)
                Spacer(minLength: 3)
                if !small { dateBadge(zone: trip.zone(at: date)) }
            }
            if !small { rule }
            if items.isEmpty {
                Spacer(minLength: 0)
                Text("Room to wander").font(.system(size: small ? 14 : 19, weight: .medium, design: .serif)).lineLimit(2)
                footer("No remaining plans today")
            } else {
                if small { eyebrow("Next in your day") }
                ForEach(Array(items.prefix(limit).enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 9) {
                        if !small {
                            VStack(spacing: 4) {
                                Circle().fill(index == 0 ? accent : accent.opacity(0.35)).frame(width: 5, height: 5)
                                if large && index < min(items.count, limit) - 1 { Rectangle().fill(accent.opacity(0.25)).frame(width: 1, height: 23) }
                            }.frame(width: 8).padding(.top, 5).accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.system(size: small ? 13 : large ? 16 : 13, weight: .medium)).lineLimit(small ? 2 : 1)
                            Text(item.schedule + " · " + item.zoneLabel(at: date)).font(.system(size: 9, weight: .medium)).foregroundStyle(muted).lineLimit(1)
                        }
                        if large { Spacer(minLength: 4); Image(systemName: item.symbol).font(.caption).foregroundStyle(accent).accessibilityHidden(true) }
                    }
                }
            }
            Spacer(minLength: 0)
            if large {
                rule
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        eyebrow("The journey")
                        Text(trip.title).font(.system(size: 17, design: .serif)).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    footer(trip.dateLabel)
                }
            }
            footer("Saved itinerary" + (items.count > limit ? " · +\(items.count - limit) more" : ""))
            }
        } else {
            Text("Your next chapter").font(.system(size: small ? 23 : 29, design: .serif)).lineLimit(2)
            Spacer(minLength: 0)
            Text(trip.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
            footer("No trip today · Starts in \(trip.daysUntil(date)) days")
        }
    }
    private func dateBadge(zone: String) -> some View {
        let calendar = WidgetCalendar.calendar(zone)
        let formatter = DateFormatter(); formatter.timeZone = calendar.timeZone; formatter.setLocalizedDateFormatFromTemplate("EEE")
        return VStack(spacing: 1) {
            Text(formatter.string(from: date).uppercased()).font(.system(size: 7, weight: .bold)).tracking(1)
            Text(String(calendar.component(.day, from: date))).font(.system(size: 20, weight: .medium, design: .serif))
        }.foregroundStyle(accent).frame(width: 34, height: 36)
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.4), lineWidth: 0.7) }
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func countdown(_ trip: JourneyWidgetTrip) -> some View {
        if small {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(trip.isActive(at: date) ? "Now" : String(trip.daysUntil(date)))
                    .font(.system(size: 46, weight: .regular, design: .serif)).lineLimit(1).minimumScaleFactor(0.65)
                if !trip.isActive(at: date) { Text("DAYS").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(muted) }
            }.widgetAccentable()
            Text(trip.title).font(.system(size: 15, weight: .medium, design: .serif)).lineLimit(2)
            Spacer(minLength: 0)
            footer(trip.dateLabel)
        } else {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(trip.isActive(at: date) ? "Now" : String(trip.daysUntil(date)))
                        .font(.system(size: 58, weight: .regular, design: .serif)).lineLimit(1).minimumScaleFactor(0.55)
                    eyebrow(trip.isActive(at: date) ? "Bon voyage" : "Days to go")
                }.frame(width: 84, alignment: .leading).widgetAccentable()
                WidgetPerforation().stroke(accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 4])).frame(width: 1).padding(.vertical, 4).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(trip.title).font(.system(size: 24, weight: .regular, design: .serif)).lineLimit(2).minimumScaleFactor(0.8)
                    Text(trip.destination).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
                    HStack(spacing: 5) { Image(systemName: "airplane.departure"); Text(trip.dateLabel) }.font(.system(size: 9, weight: .medium)).foregroundStyle(accent).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: .infinity)
            footer(trip.isActive(at: date) ? "Your journey is underway" : "A little closer to somewhere new")
        }
    }

    @ViewBuilder private func budget(_ trip: JourneyWidgetTrip) -> some View {
        Text(trip.title).font(.system(size: 11, weight: .medium)).foregroundStyle(muted).lineLimit(1)
        if let spent = trip.spent {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(spent.formatted(.currency(code: trip.currency)))
                        .font(.system(size: small ? 29 : 33, weight: .regular, design: .serif)).lineLimit(1).minimumScaleFactor(0.55)
                    footer(trip.target.map { "of " + $0.formatted(.currency(code: trip.currency)) + " target" } ?? "Spent so far")
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !small, let target = trip.target, target > 0 {
                    WidgetBudgetDial(fraction: NSDecimalNumber(decimal: spent / target).doubleValue, color: accent, ink: ink, track: accent.opacity(0.18))
                        .frame(width: 60, height: 60)
                }
            }
            if small, let target = trip.target, target > 0 {
                WidgetBudgetSegments(fraction: NSDecimalNumber(decimal: spent / target).doubleValue, color: accent).frame(height: 5)
            }
            Spacer(minLength: 0)
            if !small {
                HStack {
                    if let target = trip.target {
                        Text((abs(target - spent)).formatted(.currency(code: trip.currency)) + (spent > target ? " over target" : " left"))
                            .foregroundStyle(spent > target ? (fullColor ? widgetColor(scheme == .dark ? 0xFFBE9B : 0xA13820) : ink) : accent)
                    } else { Text("Set a target in Seur").foregroundStyle(accent) }
                    Spacer(minLength: 2)
                    if let burn = trip.burnRate(at: date) { Text(burn.formatted(.currency(code: trip.currency)) + "/day").foregroundStyle(muted) }
                }.font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.75)
            } else if let target = trip.target, spent > target {
                footer((spent - target).formatted(.currency(code: trip.currency)) + " over target")
            } else if trip.target == nil { footer("Set a target in Seur") }
            footer(trip.rateDate.map { "Saved FX · " + $0 } ?? "Completed & paid plans")
        } else {
            Text(trip.originalSpent).font(.system(size: 23, design: .serif)).lineLimit(2).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text("Open Seur to load conversion rates.").font(.caption).foregroundStyle(muted)
        }
    }

    @ViewBuilder private var profileContent: some View {
        if let profile = snapshot?.travelProfile(at: date), profile.trips > 0 {
            if small {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(profile.countries.formatted()).font(.system(size: 42, design: .serif)).lineLimit(1).minimumScaleFactor(0.6)
                        eyebrow("Countries")
                    }
                    Spacer(minLength: 0)
                    WidgetGlobe().stroke(accent.opacity(0.65), lineWidth: 0.65).frame(width: 44, height: 44).rotationEffect(.degrees(-14)).accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    profileMetric(profile.cities, "Cities")
                    profileMetric(profile.trips, "Trips")
                    profileMetric(profile.nights, "Nights")
                }
            } else if large {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(profile.countries.formatted()).font(.system(size: 62, design: .serif)).lineLimit(1).minimumScaleFactor(0.6)
                        eyebrow("Countries explored")
                    }
                    Spacer()
                    WidgetGlobe().stroke(accent.opacity(0.8), lineWidth: 0.85).frame(width: 82, height: 82).rotationEffect(.degrees(-14)).padding(.trailing, 12).accessibilityHidden(true)
                }
                rule
                HStack(spacing: 16) {
                    profileMetric(profile.cities, "Cities")
                    profileMetric(profile.trips, "Trips")
                    profileMetric(profile.nights, profile.nightsLabel)
                }
                rule
                eyebrow("Recent completed journeys")
                ForEach(Array(profile.recent.prefix(3).enumerated()), id: \.offset) { _, journey in
                    HStack(spacing: 9) {
                        Image(systemName: "location.circle").font(.system(size: 14, weight: .light)).foregroundStyle(accent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(journey.title).font(.system(size: 13, weight: .medium, design: .serif)).lineLimit(1)
                            Text(journey.destination).font(.system(size: 9)).foregroundStyle(muted).lineLimit(1)
                        }
                        Spacer(minLength: 3)
                        Text(historyDate(journey.endDay)).font(.system(size: 9)).foregroundStyle(muted)
                    }
                }
                Spacer(minLength: 0)
                if let cities = profile.favoriteCities { footer("Most visited · " + cities) }
                if profile.stars > 0 { footer("\(profile.stars) Michelin stars collected") }
            } else {
                HStack(alignment: .center, spacing: 20) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(profile.countries.formatted()).font(.system(size: 51, design: .serif)).lineLimit(1).minimumScaleFactor(0.6)
                        Text("countries").font(.system(size: 11, design: .serif)).foregroundStyle(accent)
                    }.widgetAccentable()
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 5) {
                        compactMetric(profile.cities, "cities")
                        compactMetric(profile.trips, "trips")
                        compactMetric(profile.nights, "nights")
                    }
                }
                rule
                if let recent = profile.recent.first {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) { eyebrow("Last completed journey"); Text(recent.title).font(.system(size: 14, design: .serif)).lineLimit(1) }
                        Spacer(minLength: 5)
                        Text(historyDate(recent.endDay)).font(.system(size: 9)).foregroundStyle(muted)
                    }
                }
                Spacer(minLength: 0)
            }
            if let savedAt = snapshot?.savedAt { footer("As of " + savedAt.formatted(.dateTime.month(.abbreviated).day())) }
        } else { emptyContent }
    }
    private func profileMetric(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted()).font(.system(size: small ? 18 : 24, design: .serif)).lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(.system(size: small ? 8 : 9)).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .ignore).accessibilityLabel("\(value) \(label)")
    }
    private func compactMetric(_ value: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value.formatted()).font(.system(size: 16, design: .serif)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
        }.accessibilityElement(children: .combine)
    }
    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            if !small {
                Image(systemName: kind == .profile ? "globe.europe.africa" : kind == .budget ? "chart.pie" : "airplane.departure")
                    .font(.system(size: large ? 45 : 25, weight: .ultraLight)).foregroundStyle(accent).accessibilityHidden(true)
            }
            Text(expired ? "Time for a refresh" : kind == .profile ? "A world of stories" : kind == .budget ? "Make room for more" : kind == .nextTrip ? "Somewhere new awaits" : "Let the day unfold")
                .font(.system(size: small ? 24 : large ? 34 : 27, design: .serif)).lineLimit(3).minimumScaleFactor(0.8)
            Text(kind == .profile ? (snapshot?.travelProfile(at: date) == nil ? "Open Seur to refresh your travel profile." : "Your completed trips and logged visits appear here.") : expired ? "Open Seur for your latest saved trips." : "Add a dated trip in Seur to begin.")
                .font(.system(size: 11)).foregroundStyle(muted).lineLimit(3)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    private func historyDate(_ day: String) -> String {
        guard let value = WidgetCalendar.date(day) else { return day }
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
        return formatter.string(from: value)
    }

    @ViewBuilder private var accessory: some View {
        if family == .accessoryInline { Label(accessoryText, systemImage: symbol) }
        else if family == .accessoryCircular {
            ZStack {
                Circle().strokeBorder(.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [1, 3])).padding(2)
                VStack(spacing: 0) {
                    Image(systemName: "airplane").font(.system(size: 11)).widgetAccentable()
                    Text(trip.map { $0.isActive(at: date) ? "Now" : String($0.daysUntil(date)) } ?? "—").font(.system(size: 23, design: .serif)).minimumScaleFactor(0.7).lineLimit(1)
                    if trip?.isActive(at: date) == false { Text("DAYS").font(.system(size: 7, weight: .semibold)).tracking(1) }
                }
            }
        } else {
            HStack(spacing: 9) {
                Capsule().fill(.primary).frame(width: 3).widgetAccentable()
                VStack(alignment: .leading, spacing: 3) {
                    Label(heading.uppercased(), systemImage: symbol).font(.system(size: 9, weight: .semibold)).tracking(1).widgetAccentable()
                    Text(accessoryText).font(.system(size: 15, weight: .medium, design: .serif)).lineLimit(2)
                    if let item = active?.remaining(at: date).first, kind == .today { Text(item.schedule + " · " + item.zoneLabel(at: date)).font(.system(size: 10)).lineLimit(1) }
                }
            }
        }
    }
    private var accessoryText: String {
        guard let trip else { return "Open Seur to plan a trip" }
        if kind == .today, let active { return active.remaining(at: date).first?.title ?? "Enjoy " + (active.stop(at: date)?.name ?? active.title) }
        return (trip.isActive(at: date) ? "Travelling · " : "\(trip.daysUntil(date)) days · ") + trip.title
    }
}

private extension JourneyWidgetItem {
    func zoneLabel(at date: Date) -> String { TimeZone(identifier: zone)?.abbreviation(for: start ?? date) ?? zone }
}
private extension JourneyWidgetTrip {
    var dateLabel: String {
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.setLocalizedDateFormatFromTemplate("MMM d")
        guard let a = WidgetCalendar.date(startDay), let b = WidgetCalendar.date(endDay) else { return startDay }
        return formatter.string(from: a) + " – " + formatter.string(from: b)
    }
}
private struct WidgetPerforation: Shape {
    func path(in rect: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) } }
}
struct WidgetGlobe: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addEllipse(in: rect)
            p.addEllipse(in: rect.insetBy(dx: rect.width * 0.23, dy: 0))
            p.addEllipse(in: rect.insetBy(dx: 0, dy: rect.height * 0.25))
            p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
private struct WidgetBudgetSegments: View {
    let fraction: Double
    let color: Color
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<20) { index in
                Capsule().fill(color.opacity(Double(index) < max(0, min(1, fraction)) * 20 ? 1 : 0.16))
            }
        }.accessibilityLabel("Budget used").accessibilityValue(max(0, fraction).formatted(.percent.precision(.fractionLength(0)))).widgetAccentable()
    }
}
private struct WidgetBudgetDial: View {
    let fraction: Double
    let color, ink, track: Color
    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: 5)
            Circle().trim(from: 0, to: max(0, min(1, fraction))).stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90)).widgetAccentable()
            VStack(spacing: 0) {
                Text(max(0, fraction).formatted(.percent.precision(.fractionLength(0)))).font(.system(size: 16, weight: .medium, design: .serif)).lineLimit(1).minimumScaleFactor(0.6)
                Text("USED").font(.system(size: 6, weight: .semibold)).tracking(1)
            }.foregroundStyle(ink).padding(8)
        }.padding(3).accessibilityElement(children: .ignore).accessibilityLabel("Budget used").accessibilityValue(max(0, fraction).formatted(.percent.precision(.fractionLength(0))))
    }
}

struct JourneyWidgetBackground: View {
    var kind: JourneyWidgetKind = .today
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    var body: some View {
        let palette = WidgetPalette(dark: scheme == .dark)
        GeometryReader { geometry in
            ZStack {
                if renderingMode == .fullColor {
                    LinearGradient(colors: [palette.start, palette.end], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if kind == .profile {
                        WidgetGlobe().stroke(palette.accent.opacity(0.07), lineWidth: 1)
                            .frame(width: geometry.size.width * 0.9, height: geometry.size.width * 0.9)
                            .rotationEffect(.degrees(-18)).offset(x: geometry.size.width * 0.42, y: geometry.size.height * 0.08)
                    } else {
                        WidgetContours(kind: kind).stroke(palette.accent.opacity(0.075), lineWidth: 0.7)
                    }
                    if kind == .nextTrip {
                        Circle().fill(palette.accent.opacity(0.035)).frame(width: geometry.size.width * 0.5)
                            .offset(x: geometry.size.width * 0.42, y: -geometry.size.height * 0.35)
                    }
                } else { Color.primary.opacity(0.06) }
            }.clipped()
        }.accessibilityHidden(true)
    }
}
private struct WidgetContours: Shape {
    let kind: JourneyWidgetKind
    func path(in r: CGRect) -> Path {
        Path { p in
            if kind == .today {
                for step in 0..<7 {
                    let radius = r.width * 0.23 + CGFloat(step) * 16
                    let center = CGPoint(x: r.maxX * 1.05, y: r.minY - 8)
                    p.move(to: CGPoint(x: center.x + radius * cos(.pi / 9), y: center.y + radius * sin(.pi / 9)))
                    p.addArc(center: center, radius: radius, startAngle: .degrees(20), endAngle: .degrees(175), clockwise: false)
                }
            } else {
                for step in 0..<7 {
                    let y = r.maxY * 0.63 + CGFloat(step) * 13
                    p.move(to: CGPoint(x: r.minX - 20, y: y))
                    p.addCurve(to: CGPoint(x: r.maxX + 20, y: y - r.height * 0.4), control1: CGPoint(x: r.midX * 0.6, y: y + r.height * 0.4), control2: CGPoint(x: r.midX * 1.6, y: y - r.height * 0.8))
                }
            }
        }
    }
}

/// Shared with app render previews; the Live Activity's data and update contract stay unchanged.
struct SeurFlightWidgetCard: View {
    let attributes: FlightActivityAttributes
    let state: FlightActivityAttributes.ContentState
    let stale: Bool
    var date: Date = .now
    @Environment(\.colorScheme) private var scheme
    private var palette: WidgetPalette { WidgetPalette(dark: scheme == .dark) }
    private var gold: Color { palette.accent }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("SEUR  /  " + attributes.flightNumber, systemImage: "airplane").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(gold)
                Spacer(minLength: 6)
                Text(stale ? "Update pending" : state.status).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    .padding(.horizontal, 9).padding(.vertical, 5).background(palette.ink.opacity(0.06), in: .capsule)
            }
            HStack(alignment: .center, spacing: 16) {
                endpoint(attributes.origin, time: state.departureTime)
                ZStack {
                    Path { p in p.move(to: CGPoint(x: 0, y: 16)); p.addQuadCurve(to: CGPoint(x: 90, y: 16), control: CGPoint(x: 45, y: -12)) }.stroke(gold.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    Image(systemName: "airplane").font(.system(size: 17)).foregroundStyle(gold).rotationEffect(.degrees(-10))
                }.frame(width: 90, height: 28).accessibilityHidden(true)
                endpoint(attributes.destination, time: state.arrivalTime)
            }.frame(maxWidth: .infinity)
            Rectangle().fill(gold.opacity(0.25)).frame(height: 0.5)
            HStack(spacing: 8) {
                Text(state.gate.isEmpty ? "Gate —" : "Gate " + state.gate).fontWeight(.semibold)
                if !state.terminal.isEmpty { Text("· Terminal " + state.terminal) }
                Spacer(minLength: 2)
                if state.phase == "scheduled", state.departure > date.timeIntervalSince1970 {
                    Text(timerInterval: date...Date(timeIntervalSince1970: state.departure), countsDown: true).monospacedDigit().frame(maxWidth: 80)
                } else { Text(state.delayMinutes > 0 ? "\(state.delayMinutes)m late" : "Airport local times") }
            }.font(.system(size: 10)).foregroundStyle(gold).lineLimit(1).minimumScaleFactor(0.8)
        }.foregroundStyle(palette.ink).padding(16)
            .background { JourneyWidgetBackground(kind: .today) }
    }
    private func endpoint(_ code: String, time: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(code).font(.system(size: 32, weight: .regular, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
            Text(time).font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
