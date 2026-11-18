import ActivityKit
import Foundation

struct LaundryActivityAttributes: ActivityAttributes {
    struct Machine: Codable, Hashable, Identifiable {
        var id: Int
        var label: String
        var idle: Bool
        var remaining: String
    }

    struct ContentState: Codable, Hashable {
        var idleCount: Int
        var machines: [Machine]
        var updatedAt: Date
    }

    var title: String
}
