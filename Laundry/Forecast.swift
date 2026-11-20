import Foundation

/// From up to a week of history: for each hour of the day, how often at least one machine was free
/// (or, for one machine, how often that machine was free).
struct Forecast {
    struct Hour {
        var availability: Double?
        var utilization: Double?
        var observedMinutes: Int
    }

    private(set) var hours: [Hour]
    private(set) var observedMinutes: Int

    /// One forecast per machine, keyed by machine id.
    static func perMachine(_ snapshot: Snapshot?) -> [Int: Forecast] {
        guard let snapshot else { return [:] }
        return Dictionary(snapshot.machines.map { ($0.id, Forecast(snapshot: snapshot, machineID: $0.id)) },
                          uniquingKeysWith: { first, _ in first })
    }

    init(snapshot: Snapshot?, machineID: Int? = nil) {
        hours = Array(repeating: Hour(availability: nil, utilization: nil, observedMinutes: 0), count: 24)
        observedMinutes = 0
        guard let s = snapshot, s.window.minutes > 0 else { return }
        let machines = machineID.map { id in s.machines.filter { $0.id == id } } ?? s.machines
        guard !machines.isEmpty else { return }

        let n = s.window.minutes
        var idle = [Int](repeating: 0, count: n)
        var busy = [Int](repeating: 0, count: n)
        var known = [Bool](repeating: false, count: n)
        for m in machines {
            for run in m.runs where run.count == 3 && run[2] != -1 {
                let lo = max(0, run[0]), hi = min(n, run[0] + run[1])
                guard lo < hi else { continue }
                for k in lo..<hi {
                    known[k] = true
                    if run[2] == 10 { idle[k] += 1 }
                    else if run[2] == 20 { busy[k] += 1 }
                }
            }
        }

        var seen = [Int](repeating: 0, count: 24)
        var free = [Int](repeating: 0, count: 24)
        var used = [Int](repeating: 0, count: 24)
        for k in 0..<n where known[k] {
            let hour = Fmt.minuteOfDay(s.window.start + k * 60) / 60
            seen[hour] += 1
            if idle[k] > 0 { free[hour] += 1 }
            if busy[k] > 0 { used[hour] += 1 }
        }

        for h in 0..<24 {
            hours[h] = Hour(
                availability: seen[h] >= 15 ? Double(free[h]) / Double(seen[h]) : nil,
                utilization: seen[h] >= 15 ? Double(used[h]) / Double(seen[h]) : nil,
                observedMinutes: seen[h]
            )
        }
        observedMinutes = seen.reduce(0, +)
    }

    /// Below a day of history the shape is mostly noise; the card says it is still learning.
    var isLearning: Bool { observedMinutes < 24 * 60 }
    var hasAny: Bool { hours.contains { $0.availability != nil } }

    /// The best hour within the next `span` hours (including this one).
    func bestHour(after now: Date = .now, span: Int = 12) -> (hour: Int, availability: Double)? {
        let current = Calendar.current.component(.hour, from: now)
        var best: (Int, Double)?
        for step in 0..<span {
            let h = (current + step) % 24
            guard let a = hours[h].availability else { continue }
            if best == nil || a > best!.1 + 0.02 { best = (h, a) }
        }
        return best.map { (hour: $0.0, availability: $0.1) }
    }

    /// The busiest hour within the next `span` hours (including this one).
    func peakUsageHour(after now: Date = .now, span: Int = 12) -> (hour: Int, utilization: Double)? {
        let current = Calendar.current.component(.hour, from: now)
        var peak: (Int, Double)?
        for step in 0..<span {
            let h = (current + step) % 24
            guard let u = hours[h].utilization else { continue }
            if peak == nil || u > peak!.1 + 0.02 { peak = (h, u) }
        }
        return peak.map { (hour: $0.0, utilization: $0.1) }
    }
}
