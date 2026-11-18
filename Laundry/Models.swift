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

    var statusText: String {
        if isIdle { return "空闲" }
        if isBusy { return remaining.isEmpty ? "使用中" : "剩 \(remaining)" }
        return "不可用"
    }

    var idleMinutes: Int { runs.reduce(0) { $0 + ($1.count == 3 && $1[2] == 10 ? $1[1] : 0) } }
    var busyMinutes: Int { runs.reduce(0) { $0 + ($1.count == 3 && $1[2] == 20 ? $1[1] : 0) } }
    var sessions: Int { runs.filter { $0.count == 3 && $0[2] == 20 }.count }
    var longestIdle: Int {
        runs.filter { $0.count == 3 && $0[2] == 10 }.map { $0[1] }.max() ?? 0
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
            if ch.isNumber {
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
    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) 分钟" }
        return String(format: "%.1f 小时", Double(minutes) / 60)
    }

    static func clock(_ epoch: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(epoch))
            .formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func hourLabel(_ epoch: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(epoch))
            .formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))
    }
}
