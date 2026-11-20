#if DEBUG
import Foundation

/// Debug-only launch arguments for looking at every state without waiting for real laundry:
///   -demo busy | mixed | spin | trio   use a made-up snapshot instead of the server (trio: three machines)
///   -scroll dial | forecast        start scrolled to a section
///   -open <machine id>             open a machine's detail screen (记录 tab)
///   -tab records | settings        start on another tab
///   -machine <index>               show another machine on the overview
///   -activity                      keep the Live Activity on whatever the time of day
///   -staleSoon                     let the Live Activity go out of date after a few seconds
enum Demo {
    static var mode: String? { value(after: "-demo") }
    static var scroll: String? { value(after: "-scroll") }
    static var open: Int? { value(after: "-open").flatMap(Int.init) }
    static var tab: String? { value(after: "-tab") }
    static var machine: Int? { value(after: "-machine").flatMap(Int.init) }
    /// Seconds after launch at which the overview switches to the next machine, as a tap on the page dots would.
    static var switchAfter: Double? { value(after: "-switchAfter").flatMap(Double.init) }
    static var showsSettings: Bool { ProcessInfo.processInfo.arguments.contains("-settings") }
    static var forcesActivity: Bool { ProcessInfo.processInfo.arguments.contains("-activity") }
    /// Lets the Live Activity go out of date a few seconds after it is shown.
    static var staleSoon: Bool { ProcessInfo.processInfo.arguments.contains("-staleSoon") }

    private static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func snapshot(hours: Int) -> Snapshot? {
        guard let mode else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let minutes = hours * 60
        let start = now - now % 60 - (minutes - 1) * 60

        // A believable day: washes of ~36 minutes, busier in the evening.
        func history(seed: Int, endState: Int, endRun: Int) -> [[Int]] {
            var runs: [[Int]] = []
            var t = 0
            var rng = UInt64(seed)
            func next(_ n: Int) -> Int {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                return Int((rng >> 33) % UInt64(n))
            }
            while t < minutes - endRun {
                let hour = Fmt.minuteOfDay(start + t * 60) / 60
                let evening = (19...23).contains(hour)
                let idle = min(minutes - endRun - t, evening ? 10 + next(40) : 40 + next(160))
                if idle > 0 { runs.append([t, idle, 10]); t += idle }
                guard t < minutes - endRun else { break }
                let busy = min(minutes - endRun - t, 32 + next(8))
                runs.append([t, busy, 20]); t += busy
            }
            runs.append([minutes - endRun, endRun, endState])
            return runs
        }

        let a: (Int, String, [[Int]])
        let b: (Int, String, [[Int]])
        // "trio" adds a third machine, to see how the layouts hold with three.
        let c: (Int, String, [[Int]])? = mode == "trio" ? (20, "31分钟", history(seed: 3, endState: 20, endRun: 5)) : nil
        switch mode {
        case "busy":
            a = (20, "11分钟", history(seed: 7, endState: 20, endRun: 25))
            b = (20, "27分钟", history(seed: 11, endState: 20, endRun: 9))
        case "spin":
            a = (20, "3分钟", history(seed: 7, endState: 20, endRun: 33))
            b = (10, "", history(seed: 11, endState: 10, endRun: 48))
        default:
            a = (10, "", history(seed: 7, endState: 10, endRun: 23))
            b = (20, "15分钟", history(seed: 11, endState: 20, endRun: 21))
        }

        func machine(_ id: Int, _ label: String, _ m: (Int, String, [[Int]])) -> String {
            let runs = m.2.map { "[\($0[0]),\($0[1]),\($0[2])]" }.joined(separator: ",")
            return """
            {"id":\(id),"name":"本部前3栋\(label)","campus":"本部","building":"前3栋","label":"\(label)",
             "status":\(m.0),"remaining":"\(m.1)","runs":[\(runs)]}
            """
        }

        let json = """
        {"ok":true,"generatedAt":\(now),"window":{"start":\(start),"minutes":\(minutes)},
         "lastPoll":{"minute":\(now - now % 60),"ok":true,"total":2,"idle":0,"error":null,"ageSeconds":2,"fetchedAt":\(now - 2)},
         "series":[],
         "machines":[\(machine(1, "57号机", a)),\(machine(2, "58号机", b))\(c.map { "," + machine(3, "59号机", $0) } ?? "")]}
        """
        return try? JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }
}
#endif
