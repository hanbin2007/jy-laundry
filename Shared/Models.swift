import Foundation

struct Snapshot: Decodable {
    let ok: Bool
    let generatedAt: Int
    let window: Window
    let lastPoll: LastPoll?
    let series: [[Int?]]
    let machines: [MachineState]

    struct Window: Decodable {
        let start: Int
        let minutes: Int
    }

    struct LastPoll: Decodable {
        let minute: Int
        let ok: Bool
        let total: Int
        let idle: Int
        let error: String?
        let ageSeconds: Int
        let fetchedAt: Int?
    }

    /// When the vendor was last read. `remaining` strings are relative to this moment.
    var fetchedAt: Date {
        Date(timeIntervalSince1970: TimeInterval(lastPoll?.fetchedAt ?? lastPoll?.minute ?? generatedAt))
    }

    /// Epoch second of the minute *after* the last one in the window.
    var windowEnd: Int { window.start + window.minutes * 60 }

    var sortedMachines: [MachineState] {
        machines.sorted { NaturalOrder.less($0.label, $1.label) }
    }
}

/// The three things a washer can be, as far as a person standing in the laundry room cares.
enum DrumState: String, Codable, Hashable {
    case idle, busy, offline
}

struct MachineState: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let campus: String
    let building: String
    let label: String
    let status: Int
    let remaining: String
    let runs: [[Int]]

    var isIdle: Bool { status == 10 }
    var isBusy: Bool { status == 20 }

    var drumState: DrumState { isIdle ? .idle : isBusy ? .busy : .offline }

    /// "57号机" -> "57"
    var number: String {
        NaturalOrder.numbers(label).first.map(String.init) ?? label
    }

    var idleMinutes: Int { runs.reduce(0) { $0 + ($1.count == 3 && $1[2] == 10 ? $1[1] : 0) } }
    var busyMinutes: Int { runs.reduce(0) { $0 + ($1.count == 3 && $1[2] == 20 ? $1[1] : 0) } }
    var observedMinutes: Int { idleMinutes + busyMinutes }

    /// Wash sessions that started inside the window (a run cut off by the window start is not counted).
    var sessions: Int { runs.filter { $0.count == 3 && $0[2] == 20 && $0[0] > 0 }.count }

    var longestIdle: Int {
        runs.filter { $0.count == 3 && $0[2] == 10 }.map { $0[1] }.max() ?? 0
    }

    var utilization: Double? {
        observedMinutes > 0 ? Double(busyMinutes) / Double(observedMinutes) : nil
    }

    /// Minutes left on the current wash, parsed from the vendor's text ("11分钟", "1小时5分钟", "12:30").
    var remainingMinutes: Int? {
        isBusy ? Fmt.minutes(in: remaining) : nil
    }

    /// How long the machine has been in its current state, from the end of the history.
    var currentRunMinutes: Int {
        let code = isIdle ? 10 : isBusy ? 20 : -1
        guard let last = runs.last, last.count == 3, last[2] == code else { return 0 }
        return last[1]
    }

    /// 0...1 through the current wash, if we know both ends.
    var progress: Double? {
        guard isBusy, let left = remainingMinutes else { return nil }
        let done = currentRunMinutes
        let total = done + left
        guard total > 0 else { return nil }
        return min(1, max(0, Double(done) / Double(total)))
    }

    /// The final minutes of a wash are the spin cycle.
    var isSpinning: Bool {
        guard let left = remainingMinutes else { return false }
        return left <= 4
    }

    func cycleStart(fetchedAt: Date) -> Date? {
        isBusy ? fetchedAt.addingTimeInterval(TimeInterval(-currentRunMinutes * 60)) : nil
    }

    func cycleEnd(fetchedAt: Date) -> Date? {
        remainingMinutes.map { fetchedAt.addingTimeInterval(TimeInterval($0 * 60)) }
    }

    /// Mean length of finished washes in the window, ignoring ones cut off at either edge.
    var averageCycle: Int? {
        let valid = runs.indices.filter { i in
            let r = runs[i]
            guard r.count == 3, r[2] == 20, r[0] > 0 else { return false }
            if i == runs.count - 1 { return false }
            return (8...150).contains(r[1])
        }
        guard !valid.isEmpty else { return nil }
        return valid.map { runs[$0][1] }.reduce(0, +) / valid.count
    }

    func state(at offset: Int) -> Int {
        for run in runs where run.count == 3 {
            if offset >= run[0] && offset < run[0] + run[1] { return run[2] }
        }
        return -1
    }
}

enum NaturalOrder {
    static func numbers(_ s: String) -> [Int] {
        var out: [Int] = []
        var cur = ""
        for ch in s {
            if ch.isASCII && ch.isNumber {
                cur.append(ch)
            } else if !cur.isEmpty {
                out.append(Int(cur) ?? 0)
                cur = ""
            }
        }
        if !cur.isEmpty { out.append(Int(cur) ?? 0) }
        return out
    }

    static func less(_ a: String, _ b: String) -> Bool {
        let na = numbers(a), nb = numbers(b)
        for (x, y) in zip(na, nb) where x != y { return x < y }
        if na.count != nb.count { return na.count < nb.count }
        return a < b
    }
}

enum Fmt {
    static func minutes(in text: String) -> Int? {
        let nums = NaturalOrder.numbers(text)
        guard let first = nums.first else { return nil }
        if text.contains("小时") || text.contains("时") {
            return first * 60 + (nums.count > 1 ? nums[1] : 0)
        }
        if text.contains(":"), nums.count >= 2 {
            // Vendor countdowns with a colon are mm:ss (or h:mm:ss); round seconds up.
            if nums.count >= 3 { return nums[0] * 60 + nums[1] + (nums[2] > 0 ? 1 : 0) }
            return nums[0] + (nums[1] > 0 ? 1 : 0)
        }
        return first
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) 分钟" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分"
    }

    /// Always 24-hour "HH:mm", whatever the device's 12/24-hour setting: a laundry time is a clock reading.
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func time(_ date: Date) -> String {
        clockFormatter.timeZone = .current
        return clockFormatter.string(from: date)
    }

    static func clock(_ epoch: Int) -> String {
        time(Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    /// "00:11" for 11 minutes, "01:05" for 65: hours and minutes, as on the machine's own display.
    static func hoursMinutes(_ minutes: Int) -> String {
        let m = max(0, minutes)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Minute of the local day (0..<1440) for an epoch second.
    static func minuteOfDay(_ epoch: Int) -> Int {
        let tz = TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(epoch)))
        return (((epoch + tz) % 86_400) + 86_400) % 86_400 / 60
    }
}
