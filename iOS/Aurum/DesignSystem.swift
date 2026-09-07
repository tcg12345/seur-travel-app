import SwiftUI
import SafariServices

extension Color {
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.080, green: 0.075, blue: 0.070, alpha: 1) : UIColor(red: 0.974, green: 0.964, blue: 0.946, alpha: 1) })
    static let bronze = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.83, green: 0.70, blue: 0.51, alpha: 1) : UIColor(red: 0.55, green: 0.39, blue: 0.22, alpha: 1) })
    static let brandInk = Color(red: 0.20, green: 0.17, blue: 0.14)
    static let brandBronze = Color(red: 0.55, green: 0.39, blue: 0.22)
    // Content cards have one surface. Keep sections/carousels that contain cards
    // transparent; use headings, spacing and dividers instead of another rounded box.
    // Icons inside a card stay unboxed; photographs and compact control/status badges
    // are not additional content containers.
    static let cardSurface = Color(uiColor: .secondarySystemGroupedBackground)
}

/// The shared Seur flight-ribbon mark. Uses the same artwork as the home-screen icon.
struct SeurLogo: View {
    var size: CGFloat = 32
    var body: some View {
        Image("SeurLogo").resizable().scaledToFit().frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.23))
            .accessibilityLabel("Seur").accessibilityIdentifier("seur-logo")
    }
}

struct Editorial: View {
    let text: String
    @ScaledMetric var size: CGFloat
    init(_ text: String, size: CGFloat = 32) { self.text = text; self._size = ScaledMetric(wrappedValue: size) }
    var body: some View { Text(text).font(.system(size: size, weight: .regular, design: .serif)).tracking(-0.9).fixedSize(horizontal: false, vertical: true) }
}
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(.caption2, design: .rounded, weight: .semibold)).tracking(2.1).foregroundStyle(Color.bronze) }
}
struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Editorial(title, size: 27)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct HotelPhoto: View {
    let hotel: Hotel
    var body: some View {
        GeometryReader { geo in
            if let name = hotel.image {
                Image(name).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
            } else {
                ZStack {
                    Color.bronze.opacity(0.13)
                    VStack(spacing: 10) {
                        Image(systemName: "building.2.crop.circle").font(.system(size: 35, weight: .ultraLight))
                        Text(hotel.city).font(.system(.title2, design: .serif))
                        Text("Photograph not yet available").font(.caption).foregroundStyle(.secondary)
                    }.foregroundStyle(Color.bronze)
                }.frame(width: geo.size.width, height: geo.size.height)
            }
        }.accessibilityLabel(hotel.image == nil ? "\(hotel.name), photography unavailable" : hotel.name)
    }
}
struct SaveButton: View {
    @Environment(TravelStore.self) private var store
    let hotel: Hotel
    var body: some View {
        Button { store.toggleSave(hotel) } label: {
            Image(systemName: store.saved.contains(hotel.id) ? "heart.fill" : "heart")
                .contentTransition(.symbolEffect(.replace)).foregroundStyle(store.saved.contains(hotel.id) ? Color.bronze : .primary)
                .frame(width: 44, height: 44)
        }.buttonStyle(.glass).buttonBorderShape(.circle)
            .sensoryFeedback(.selection, trigger: store.saved.contains(hotel.id))
            .accessibilityLabel(store.saved.contains(hotel.id) ? "Unsave hotel" : "Save hotel")
            .accessibilityIdentifier("save-\(hotel.id)")
    }
}
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
struct HotelRow: View {
    let hotel: Hotel
    var showsChevron = true
    var body: some View {
        HStack(spacing: 15) {
            HotelPhoto(hotel: hotel).frame(width: 90, height: 104).clipShape(.rect(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 7) {
                Text(hotel.city.uppercased()).font(.caption2.weight(.medium)).tracking(1.5).foregroundStyle(Color.bronze)
                Text(hotel.name).font(.system(.headline, design: .serif)).foregroundStyle(.primary)
                Label("\(hotel.venues.count) dining options", systemImage: "fork.knife").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
        }.padding(12).background(.background, in: .rect(cornerRadius: 24)).contentShape(.rect(cornerRadius: 24))
    }
}
struct BrowserDestination: Identifiable { let id = UUID(); let url: URL }
struct InAppBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
struct EmptyState: View {
    let title, message, symbol: String
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: symbol) } description: { Text(message) }
            .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}
