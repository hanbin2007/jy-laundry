import ActivityKit
import Foundation

struct LaundryActivityAttributes: ActivityAttributes {
    struct Machine: Codable, Hashable, Identifiable {
        var id: Int
        var label: String
        var number: String
        var state: DrumState
        var progress: Double?
        var startedAt: Date?
        var endsAt: Date?
    }

    struct ContentState: Codable, Hashable {
        var building: String
        var machines: [Machine]
        var updatedAt: Date

        var idleCount: Int { machines.filter { $0.state == .idle }.count }

        var soonest: Machine? {
            machines
                .filter { $0.state == .busy && $0.endsAt != nil }
                .min { ($0.endsAt ?? .distantFuture) < ($1.endsAt ?? .distantFuture) }
        }
    }

    var title: String
}
