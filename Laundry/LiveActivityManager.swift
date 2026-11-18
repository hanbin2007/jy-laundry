import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<LaundryActivityAttributes>?

    private init() {
        activity = Activity<LaundryActivityAttributes>.activities.first
    }

    var isRunning: Bool { activity != nil }

    func sync(enabled: Bool, start: Int, end: Int, snapshot: Snapshot?, now: Date = .now) {
        guard enabled, let snapshot, Self.inWindow(now, start: start, end: end) else {
            stop()
            return
        }

        let state = LaundryActivityAttributes.ContentState(
            idleCount: snapshot.machines.filter(\.isIdle).count,
            machines: snapshot.machines.map {
                LaundryActivityAttributes.Machine(
                    id: $0.id,
                    label: $0.label,
                    idle: $0.isIdle,
                    remaining: $0.remaining
                )
            },
            updatedAt: now
        )
        let content = ActivityContent(state: state, staleDate: Self.staleDate(now, end: end))

        if let activity {
            Task { await activity.update(content) }
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: LaundryActivityAttributes(title: "洗衣"),
                content: content,
                pushType: nil
            )
        } catch {
            print("live activity request failed: \(error)")
        }
    }

    func stop() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    static func inWindow(_ date: Date, start: Int, end: Int) -> Bool {
        guard start != end else { return false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return start < end
            ? (minute >= start && minute < end)
            : (minute >= start || minute < end)
    }

    private static func staleDate(_ now: Date, end: Int) -> Date {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        parts.hour = end / 60
        parts.minute = end % 60
        parts.second = 0
        let target = Calendar.current.date(from: parts) ?? now
        let deadline = target > now
            ? target
            : Calendar.current.date(byAdding: .day, value: 1, to: target) ?? target
        return min(now.addingTimeInterval(15 * 60), deadline)
    }
}
