import Foundation
import Observation

@MainActor
@Observable
final class LaundryStore {
    private let defaults = UserDefaults.standard

    private(set) var snapshot: Snapshot?
    private(set) var lastFetched: Date?
    private(set) var isLoading = false
    private(set) var error: String?

    var baseURL: String {
        didSet { defaults.set(baseURL, forKey: "serverBaseURL") }
    }

    var token: String {
        didSet { defaults.set(token, forKey: "serverToken") }
    }

    var activityEnabled: Bool {
        didSet {
            defaults.set(activityEnabled, forKey: "laActivityEnabled")
            syncActivity()
        }
    }

    var activityStartMinutes: Int {
        didSet {
            defaults.set(activityStartMinutes, forKey: "laActivityStart")
            syncActivity()
        }
    }

    var activityEndMinutes: Int {
        didSet {
            defaults.set(activityEndMinutes, forKey: "laActivityEnd")
            syncActivity()
        }
    }

    init() {
        baseURL = defaults.string(forKey: "serverBaseURL") ?? Config.defaultBaseURL
        token = defaults.string(forKey: "serverToken") ?? Config.defaultToken
        activityEnabled = defaults.object(forKey: "laActivityEnabled") as? Bool ?? false
        activityStartMinutes = defaults.object(forKey: "laActivityStart") as? Int ?? 21 * 60
        activityEndMinutes = defaults.object(forKey: "laActivityEnd") as? Int ?? 23 * 60
    }

    // MARK: Derived

    var machines: [MachineState] {
        (snapshot?.machines ?? []).sorted { NaturalOrder.less($0.label, $1.label) }
    }

    var total: Int { machines.count }
    var idleCount: Int { machines.filter(\.isIdle).count }
    var busyCount: Int { machines.filter(\.isBusy).count }
    var windowMinutes: Int { snapshot?.window.minutes ?? 1440 }
    var windowStart: Int { snapshot?.window.start ?? 0 }
    var buildingName: String { machines.first?.building ?? "前3栋" }

    var ageSeconds: Int {
        guard let poll = snapshot?.lastPoll else { return .max }
        if let fetched = poll.fetchedAt {
            return max(0, Int(Date().timeIntervalSince1970) - fetched)
        }
        return max(0, Int(Date().timeIntervalSince1970) - poll.minute)
    }

    var ageText: String {
        guard snapshot?.lastPoll != nil else { return "未连接" }
        if ageSeconds < 10 { return "刚刚" }
        if ageSeconds < 60 { return "\(ageSeconds) 秒前" }
        if ageSeconds < 3600 { return "\(ageSeconds / 60) 分钟前" }
        return "\(ageSeconds / 3600) 小时前"
    }

    var isStale: Bool { ageSeconds > 180 }

    var recordedMinutes: Int {
        machines.map { $0.idleMinutes + $0.busyMinutes }.max() ?? 0
    }

    var coverage: Double {
        guard windowMinutes > 0 else { return 0 }
        return min(1, Double(recordedMinutes) / Double(windowMinutes))
    }

    func machine(id: Int) -> MachineState? { machines.first { $0.id == id } }

    // MARK: Actions

    func refresh(silent: Bool = false) async {
        guard let url = URL(string: baseURL) else {
            error = APIError.badURL.localizedDescription
            isLoading = false
            return
        }
        if !silent { isLoading = true }
        defer { isLoading = false }

        do {
            let result = try await HistoryAPI(baseURL: url, token: token).fetch()
            snapshot = result
            lastFetched = .now
            error = nil
            syncActivity()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func syncActivity() {
        LiveActivityManager.shared.sync(
            enabled: activityEnabled,
            start: activityStartMinutes,
            end: activityEndMinutes,
            snapshot: snapshot
        )
    }

    func liveLoop() async {
        while !Task.isCancelled {
            let started = Date()
            await refresh(silent: snapshot != nil)
            let elapsed = Date().timeIntervalSince(started)
            do {
                try await Task.sleep(for: .seconds(max(1, 5 - elapsed)))
            } catch {
                return
            }
        }
    }

    func saveConfig(base: String, token: String) {
        baseURL = base.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resetConfig() {
        baseURL = Config.defaultBaseURL
        token = Config.defaultToken
    }
}
