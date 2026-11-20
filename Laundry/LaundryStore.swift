import Foundation
import Observation

@MainActor
@Observable
final class LaundryStore {
    /// Reminder key for "tell me when any machine frees up".
    static let anyMachine = 0

    private let defaults = UserDefaults.standard

    private(set) var snapshot: Snapshot?
    private(set) var forecast = Forecast(snapshot: nil)
    /// The same week of history, one forecast per machine id.
    private(set) var machineForecasts: [Int: Forecast] = [:]
    private(set) var lastFetched: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    /// Bumps whenever a machine turns free while the app is open (drives haptics).
    private(set) var freedTick = 0
    /// Reminder key (machine id, or `anyMachine`) -> when it should fire.
    private(set) var reminders: [Int: Date] = [:]
    var notice: String?
    /// A machine a widget or the Live Activity asked to see; the overview shows it and clears this.
    var linkedMachineID: Int?

    private var weekFetched: Date?
    /// Bumped on every server change, so answers to requests made under the old settings are dropped.
    private var configGeneration = 0

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
        #if DEBUG
        if Demo.forcesActivity {
            activityStartMinutes = 0
            activityEndMinutes = 1439
            activityEnabled = true
        }
        #endif
        if let saved = defaults.dictionary(forKey: "reminders") as? [String: Double] {
            for (key, value) in saved {
                if let id = Int(key) { reminders[id] = Date(timeIntervalSince1970: value) }
            }
        }
    }

    // MARK: Derived

    var machines: [MachineState] { snapshot?.sortedMachines ?? [] }

    var total: Int { machines.count }
    var idleCount: Int { machines.filter(\.isIdle).count }
    var busyCount: Int { machines.filter(\.isBusy).count }
    var allBusy: Bool { total > 0 && idleCount == 0 && busyCount > 0 }
    var windowMinutes: Int { snapshot?.window.minutes ?? 1440 }
    var windowStart: Int { snapshot?.window.start ?? 0 }
    var campusName: String { machines.first?.campus ?? "本部" }
    var buildingName: String { machines.first?.building ?? "前3栋" }

    var serverHost: String { URL(string: baseURL)?.host() ?? baseURL }

    var ageSeconds: Int {
        guard let poll = snapshot?.lastPoll else { return .max }
        let reference = poll.fetchedAt ?? poll.minute
        return max(0, Int(Date().timeIntervalSince1970) - reference)
    }

    var ageText: String {
        guard snapshot?.lastPoll != nil else { return "未连接" }
        if ageSeconds < 10 { return "刚刚" }
        if ageSeconds < 60 { return "\(ageSeconds) 秒前" }
        if ageSeconds < 3600 { return "\(ageSeconds / 60) 分钟前" }
        return "\(ageSeconds / 3600) 小时前"
    }

    var isStale: Bool { ageSeconds > 180 }


    func machine(id: Int) -> MachineState? { machines.first { $0.id == id } }

    /// The hourly forecast for one machine. Empty (never the whole room's) until its week of history arrives.
    func forecast(for id: Int) -> Forecast { machineForecasts[id] ?? Forecast(snapshot: nil) }

    /// The week of history has been loaded at least once.
    var hasWeek: Bool { !machineForecasts.isEmpty }

    func endsAt(_ m: MachineState) -> Date? {
        guard let snapshot else { return nil }
        return m.cycleEnd(fetchedAt: snapshot.fetchedAt)
    }

    var soonestBusy: MachineState? {
        machines
            .filter { $0.isBusy && $0.remainingMinutes != nil }
            .min { ($0.remainingMinutes ?? .max) < ($1.remainingMinutes ?? .max) }
    }

    // MARK: Fetching

    func refresh(silent: Bool = false) async {
        #if DEBUG
        if let demo = Demo.snapshot(hours: 24) {
            let previous = snapshot
            snapshot = demo
            if previous == nil {
                let week = Demo.snapshot(hours: 168)
                forecast = Forecast(snapshot: week)
                machineForecasts = Forecast.perMachine(week)
            }
            error = nil
            handleTransitions(from: previous, to: demo)
            syncActivity()
            return
        }
        #endif
        guard let url = URL(string: baseURL), url.scheme != nil else {
            error = APIError.badURL.localizedDescription
            isLoading = false
            return
        }
        if !silent { isLoading = true }
        defer { isLoading = false }

        let generation = configGeneration
        let api = HistoryAPI(baseURL: url, token: token)
        do {
            let result = try await api.fetch(hours: 24, live: true)
            guard generation == configGeneration else { return }
            let previous = snapshot
            snapshot = result
            lastFetched = .now
            error = nil
            handleTransitions(from: previous, to: result)
            syncActivity()
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            guard generation == configGeneration else { return }
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        // Every 10 minutes; sooner (at most once a minute) when a machine has appeared that the last week lacks.
        let newMachine = hasWeek && (snapshot?.machines.contains { machineForecasts[$0.id] == nil } ?? false)
        if weekFetched.map({ Date().timeIntervalSince($0) > (newMachine ? 60 : 600) }) ?? true {
            await refreshWeek(api: api, generation: generation)
        }
    }

    private func refreshWeek(api: HistoryAPI, generation: Int) async {
        do {
            let week = try await api.fetch(hours: 168, live: false)
            guard generation == configGeneration else { return }
            forecast = Forecast(snapshot: week)
            machineForecasts = Forecast.perMachine(week)
            weekFetched = .now
        } catch {
            // The forecast is a nice-to-have; keep the last one.
        }
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

    func syncActivity() {
        LiveActivityManager.shared.sync(
            enabled: activityEnabled,
            start: activityStartMinutes,
            end: activityEndMinutes,
            snapshot: snapshot
        )
    }

    func saveConfig(base: String, token: String) {
        baseURL = base.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        configGeneration += 1
        snapshot = nil
        weekFetched = nil
        forecast = Forecast(snapshot: nil)
        machineForecasts = [:]
        error = nil
    }

    func resetConfig() {
        saveConfig(base: Config.defaultBaseURL, token: Config.defaultToken)
    }

    // MARK: Reminders

    func hasReminder(_ key: Int) -> Bool { reminders[key] != nil }

    func toggleReminder(for machine: MachineState) async {
        if reminders[machine.id] != nil {
            Notifier.shared.cancel(key: machine.id)
            reminders[machine.id] = nil
            saveReminders()
            return
        }
        guard machine.isBusy else { return }
        guard await Notifier.shared.authorize() else {
            notice = "请在系统设置中允许“洗衣”发送通知，以便在洗涤完成时接收提醒。"
            return
        }
        let target = endsAt(machine) ?? Date().addingTimeInterval(TimeInterval((machine.averageCycle ?? 40) * 60))
        reminders[machine.id] = target
        Notifier.shared.schedule(key: machine.id, at: target,
                                 title: "\(machine.label)预计已完成",
                                 body: "根据剩余时间估算，本次洗涤应已结束。")
        saveReminders()
    }

    func toggleAnyReminder() async {
        let key = Self.anyMachine
        if reminders[key] != nil {
            Notifier.shared.cancel(key: key)
            reminders[key] = nil
            saveReminders()
            return
        }
        guard await Notifier.shared.authorize() else {
            notice = "请在系统设置中允许“洗衣”发送通知，以便在设备空闲时接收提醒。"
            return
        }
        let target = soonestBusy.flatMap { endsAt($0) } ?? Date().addingTimeInterval(30 * 60)
        reminders[key] = target
        Notifier.shared.schedule(key: key, at: target,
                                 title: "预计已有设备空闲",
                                 body: "\(soonestBusy?.label ?? "一台设备")预计已完成洗涤。")
        saveReminders()
    }

    /// Fire reminders the moment the real state changes, and keep the rest pinned to the latest estimate.
    private func handleTransitions(from old: Snapshot?, to new: Snapshot) {
        // A reminder whose time has passed was already delivered by the system: it is used up,
        // and must not fire again or move on to the machine's next wash.
        let now = Date()
        for (key, date) in reminders where date <= now {
            reminders[key] = nil
        }

        if let old {
            let wasIdle = Set(old.machines.filter(\.isIdle).map(\.id))
            let freed = new.machines.filter { $0.isIdle && !wasIdle.contains($0.id) }
            if !freed.isEmpty { freedTick += 1 }

            for m in freed where reminders[m.id] != nil {
                Notifier.shared.fireNow(key: m.id, title: "\(m.label)已完成", body: "设备现已空闲，可前往取衣。")
                reminders[m.id] = nil
            }
        }

        if reminders[Self.anyMachine] != nil, let free = new.machines.first(where: \.isIdle) {
            Notifier.shared.fireNow(key: Self.anyMachine, title: "已有设备空闲", body: "\(free.label)现已空闲。")
            reminders[Self.anyMachine] = nil
        }

        for (key, scheduled) in reminders {
            let target: Date?
            let title: String
            if key == Self.anyMachine {
                target = soonestBusy.flatMap { endsAt($0) }
                title = "预计已有设备空闲"
            } else if let m = machine(id: key) {
                target = endsAt(m)
                title = "\(m.label)预计已完成"
            } else {
                target = nil
                title = ""
            }
            if let target, target > now, abs(target.timeIntervalSince(scheduled)) > 45 {
                reminders[key] = target
                Notifier.shared.schedule(key: key, at: target, title: title, body: "根据剩余时间估算，本次洗涤应已结束。")
            }
        }
        saveReminders()
    }

    private func saveReminders() {
        let dict = Dictionary(uniqueKeysWithValues: reminders.map { (String($0.key), $0.value.timeIntervalSince1970) })
        defaults.set(dict, forKey: "reminders")
    }
}
