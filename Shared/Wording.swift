import Foundation

/// Every user-facing status phrase in one place, in formal written Chinese.
enum Wording {
    static func state(_ s: DrumState) -> String {
        switch s {
        case .idle: return "空闲"
        case .busy: return "运行中"
        case .offline: return "不可用"
        }
    }

    /// "剩余约 11 分钟" / "即将完成"
    static func remaining(_ minutes: Int) -> String {
        minutes <= 1 ? "即将完成" : "剩余约 \(minutes) 分钟"
    }

    /// "预计 19:06 完成"
    static func finish(_ date: Date) -> String {
        "预计 \(Fmt.time(date)) 完成"
    }

    /// "已空闲 23 分钟" / "刚刚空闲"
    static func idleFor(_ minutes: Int) -> String {
        minutes > 1 ? "已空闲 \(Fmt.duration(minutes))" : "刚刚空闲"
    }

    static let offlineDetail = "设备离线或故障"

    static let roomNoun = "洗衣房"

    /// "前3栋洗衣房"; just "洗衣房" while the building is not known yet.
    static func room(_ building: String) -> String {
        building == roomNoun || building.isEmpty ? roomNoun : building + roomNoun
    }
}
