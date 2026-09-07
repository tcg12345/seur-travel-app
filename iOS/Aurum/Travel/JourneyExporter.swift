import UIKit
import CoreText

enum JourneyExportFormat: String, CaseIterable, Identifiable { case pdf, txt, json, csv; var id: String { rawValue } }
@MainActor enum JourneyExporter {
    static func export(_ document: JourneyDocument, format: JourneyExportFormat) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AurumExports/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = document.title.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = directory.appendingPathComponent(String((safeName.isEmpty ? "Aurum-journey" : safeName).prefix(80)) + "." + format.rawValue)
        let data: Data
        switch format {
        case .json: let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; data = try encoder.encode(JourneyArchive(document: document))
        case .txt: data = Data(text(document).utf8)
        case .csv: data = Data(csv(document).utf8)
        case .pdf: data = pdf(document)
        }
        try data.write(to: url, options: .atomic)
        return url
    }
    static func text(_ d: JourneyDocument) -> String {
        var lines = ["AURUM", d.title, "TRIP", d.routeLabel, d.description]
        if let start = d.startDate { lines.append("Dates: \(start) – \(d.endDate ?? start)") }
        if !d.stops.isEmpty || !d.hotels.isEmpty || !d.flights.isEmpty || !d.events.isEmpty {
            lines += ["", "YOUR ROUTE"] + d.stops.map { "\($0.name) \($0.code) · \($0.nights) nights" + (d.dateMode == .dates ? " · \($0.arrival) – \($0.departure)" : "") }
            for day in d.days {
                lines += ["", "\(day.date ?? "Day \(day.index + 1)") · \(day.city)"]
                for event in d.events.filter({ $0.stopID == day.stopID && $0.day == day.localDay }).sorted(by: { $0.sortMinute < $1.sortMinute }) {
                    lines += ["\(event.scheduleLabel) — \(event.displayTitle) [\(event.categoryTitle)]", event.description, event.isPlaceVisit ? "" : event.place.name, event.attendees ?? ""] + placeLines(event.place) + event.links
                    if let cost = event.cost { lines.append("Price: " + cost.formatted) }
                }
            }
            lines += ["", "HOTEL BOOKING RECORDS"]
            for hotel in d.hotels { lines += [hotel.place.name, "\(hotel.checkIn) – \(hotel.checkOut) · \(hotel.guests) guests · \(hotel.rooms) rooms", "Room: \(hotel.roomType)", "Confirmation: \(hotel.confirmation)", "Total: \(hotel.cost?.formatted ?? "Not recorded")", hotel.notes, hotel.overview] + placeLines(hotel.place) }
            lines += ["", "FLIGHT BOOKING RECORDS"]
            for flight in d.flights { lines += ["\(flight.airline) \(flight.flightNumber)", "From \(flight.departureAirport) · \(flight.departureDay) \(flight.departureTime) \(flight.departureZone)", "To \(flight.arrivalAirport) · \(flight.arrivalDay) \(flight.arrivalTime) \(flight.arrivalZone)", "Airport-local times. Total: \(flight.cost?.formatted ?? "Not recorded")", flight.bookingLink, flight.notes] }
            lines += ["", "EVENT TOTALS"] + d.eventTotals.keys.sorted().map { TravelMoney(amount: d.eventTotals[$0]!, currency: $0).formatted }
            lines += ["", "TOTAL PLANNED COST"] + d.totals.keys.sorted().map { TravelMoney(amount: d.totals[$0]!, currency: $0).formatted }
            lines.append("Currencies are separate. Missing prices excluded. Booking records do not make or verify reservations.")
        }
        if !d.places.isEmpty {
            lines += ["", "TRIP JOURNAL", "\(d.places.count) places · Average personal score: \(d.averageScore.map { String(format: "%.1f / 10", $0) } ?? "Not rated")"]
            for place in d.places {
                lines += ["", place.place.name, "\(place.place.category.title) · \(place.overall > 0 ? String(format: "%.1f / 10", place.overall) : "Not rated")", "Visited: \(place.visitedOn ?? "Not recorded")", "Price range: \(place.priceRange)"] + placeLines(place.place)
                lines += place.scores.keys.sorted().map { "\($0): \(String(format: "%.1f / 10", place.scores[$0]!))" }
                if let stars = place.michelinStars { lines.append("Michelin stars (personal record): \(stars)") }
                lines += [place.notes, "Photos: \(place.photos.count) (embedded in PDF and JSON)"]
            }
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
    private static func placeLines(_ p: PlaceRecord) -> [String] {
        var lines = [p.address, p.city, p.phone, p.website]
        if p.hasCoordinate { lines.append("Coordinates: \(p.latitude!), \(p.longitude!)") }
        if let rating = p.rating { lines.append("\(p.source) rating: \(rating) / 5") }
        if let link = p.sourceURL { lines.append(link) }
        return lines.filter { !$0.isEmpty }
    }
    static func csv(_ d: JourneyDocument) -> String {
        let header = ["record_type", "name", "category", "city", "date", "end_date", "time", "arrival_time", "address", "phone", "website", "latitude", "longitude", "provider_rating", "source", "description", "links", "amount", "currency", "guests", "rooms", "room_type", "confirmation", "airline", "flight_number", "departure_airport", "arrival_airport", "departure_zone", "arrival_zone", "overall_score", "category_scores", "visited_on", "price_range", "michelin_stars", "photo_count", "event_type", "venue", "all_day", "duration_minutes", "end_time", "attendees"]
        var rows: [[String: String]] = []
        func placeValues(_ p: PlaceRecord) -> [String: String] { ["name": p.name, "category": p.category.rawValue, "city": p.city, "address": p.address, "phone": p.phone, "website": p.website, "latitude": p.latitude.map(String.init(describing:)) ?? "", "longitude": p.longitude.map(String.init(describing:)) ?? "", "provider_rating": p.rating.map(String.init(describing:)) ?? "", "source": p.source] }
        func price(_ money: TravelMoney?, _ row: inout [String: String]) { if let money { row["amount"] = NSDecimalNumber(decimal: money.amount).stringValue; row["currency"] = money.currency } }
        rows.append(["record_type": d.kind.rawValue, "name": d.title, "city": d.routeLabel, "description": d.description, "date": d.startDate ?? "", "end_date": d.endDate ?? ""])
        for stop in d.stops { rows.append(["record_type": "destination", "name": stop.name, "city": stop.name, "date": d.dateMode == .dates ? stop.arrival : "", "end_date": d.dateMode == .dates ? stop.departure : "", "description": "\(stop.nights) nights · \(stop.code)"]) }
        for e in d.events { var row = placeValues(e.place); row["record_type"] = "event"; row["name"] = e.displayTitle; row["category"] = e.categoryTitle; row["event_type"] = (e.kind ?? .place).rawValue; row["venue"] = e.place.name; row["all_day"] = String(e.allDay ?? false); row["duration_minutes"] = e.allDay == true ? "" : e.durationMinutes.map(String.init) ?? ""; row["end_time"] = e.endTimeLabel ?? ""; row["attendees"] = e.attendees ?? ""; row["date"] = d.date(for: e) ?? "Local day \(e.day + 1)"; row["time"] = e.allDay == true ? "" : e.timeLabel; row["description"] = e.description; row["links"] = e.links.joined(separator: "\n"); price(e.cost, &row); rows.append(row) }
        for h in d.hotels { var row = placeValues(h.place); row["record_type"] = "hotel"; row["date"] = h.checkIn; row["end_date"] = h.checkOut; row["guests"] = String(h.guests); row["rooms"] = String(h.rooms); row["room_type"] = h.roomType; row["confirmation"] = h.confirmation; row["description"] = h.notes + "\n" + h.overview; price(h.cost, &row); rows.append(row) }
        for f in d.flights { var row = ["record_type": "flight", "name": f.airline + " " + f.flightNumber, "airline": f.airline, "flight_number": f.flightNumber, "departure_airport": f.departureAirport, "arrival_airport": f.arrivalAirport, "date": f.departureDay, "end_date": f.arrivalDay, "time": f.departureTime, "arrival_time": f.arrivalTime, "departure_zone": f.departureZone, "arrival_zone": f.arrivalZone, "website": f.bookingLink, "description": f.notes]; price(f.cost, &row); rows.append(row) }
        for p in d.places { var row = placeValues(p.place); row["record_type"] = "rated_place"; row["overall_score"] = p.overall > 0 ? String(p.overall) : ""; row["category_scores"] = p.scores.keys.sorted().map { "\($0):\(p.scores[$0]!)" }.joined(separator: "; "); row["visited_on"] = p.visitedOn ?? ""; row["description"] = p.notes; row["price_range"] = p.priceRange; row["michelin_stars"] = p.michelinStars.map(String.init) ?? ""; row["photo_count"] = String(p.photos.count); rows.append(row) }
        return ([header] + rows.map { row in header.map { row[$0] ?? "" } }).map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n")
    }
    static func csvCell(_ text: String) -> String {
        // Quoting alone does not prevent spreadsheet formula execution.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.first.map { "=+-@".contains($0) } == true || text.hasPrefix("\t") || text.hasPrefix("\r") ? "'" + text : text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    private static func pdf(_ d: JourneyDocument) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            var y: CGFloat = 0
            var page = 0
            func newPage() {
                context.beginPage(); page += 1; y = 57
                UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1).setFill(); context.fill(bounds)
                ("AURUM    /    \("THE WHOLE JOURNEY")" as NSString).draw(at: CGPoint(x: 42, y: 28), withAttributes: [.font: UIFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: UIColor.brown])
                ("\(page)" as NSString).draw(at: CGPoint(x: 545, y: 808), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
            }
            newPage()
            let content = text(d)
            let style = NSMutableParagraphStyle(); style.lineSpacing = 4; style.paragraphSpacing = 9
            let attributed = NSMutableAttributedString(string: content, attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray, .paragraphStyle: style])
            let titleRange = (content as NSString).range(of: d.title)
            if titleRange.location != NSNotFound { attributed.addAttribute(.font, value: UIFont.systemFont(ofSize: 27, weight: .light), range: titleRange) }
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            var location = 0
            while location < attributed.length {
                if location > 0 { newPage() }
                let path = CGPath(rect: CGRect(x: 42, y: 57, width: 511, height: 725), transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { break }
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: 0, y: 842)
                context.cgContext.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, context.cgContext)
                context.cgContext.restoreGState()
                location += visible.length
            }
            for place in d.places where !place.photos.isEmpty {
                newPage()
                (place.place.name as NSString).draw(at: CGPoint(x: 42, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 22, weight: .light)]); y += 45
                for photo in place.photos {
                    guard let image = UIImage(data: photo.jpeg) else { continue }
                    let height = min(300, 511 * image.size.height / image.size.width)
                    if y + height > 785 { newPage() }
                    let width = height * image.size.width / image.size.height
                    image.draw(in: CGRect(x: 42, y: y, width: min(511, width), height: height)); y += height + 20
                }
            }
        }
    }
}
