import ActivityKit
import Foundation

struct FlightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var departure: Double
        var arrival: Double
        var departureTime: String
        var arrivalTime: String
        var gate: String
        var terminal: String
        var delayMinutes: Int
        var phase: String
        var updatedAt: Double
    }
    var watchID: String
    var flightNumber: String
    var origin: String
    var destination: String
}
