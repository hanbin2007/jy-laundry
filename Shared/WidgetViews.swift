import SwiftUI
import WidgetKit

// Views shared by the widget extension and the app's debug gallery.

// MARK: - Entry

struct StatusEntry: TimelineEntry {
    struct Item: Identifiable, Hashable {
        let id: Int
        let label: String
        let number: String
        var state: DrumState
        var progress: Double?
        let endsAt: Date?
        /// True once the estimated finish has passed but the server has not confirmed it yet.
        var predicted = false
    }

    var date: Date
    var building: String
    var items: [Item]
    var failed: Bool
    /// The server answered, but its last successful read of the machines is too old to trust.
    var stale = false
    var updatedAt: Date? = nil

    /// Confirmed free machines only; estimated finishes are counted separately.
    var idle: Int { items.filter { $0.state == .idle && !$0.predicted }.count }
    var predictedFree: Int { items.filter(\.predicted).count }
    var total: Int { items.count }

    var soonest: Item? {
        items.filter { $0.state == .busy && $0.endsAt != nil }
            .min { ($0.endsAt ?? .distantFuture) < ($1.endsAt ?? .distantFuture) }
    }

    /// The same entry as it should look at `later`, with finished cycles shown as (probably) free.
    func advanced(to later: Date) -> StatusEntry {
        var copy = self
        copy.date = later
        copy.items = items.map { item in
            var item = item
            if item.state == .busy, let end = item.endsAt, end <= later {
                item.state = .idle
                item.predicted = true
                item.progress = nil
            }
            return item
        }
        return copy
    }

    static let sample = StatusEntry(
        date: .now, building: "前3栋",
        items: [
            Item(id: 1, label: "57号机", number: "57", state: .idle, progress: nil, endsAt: nil),
            Item(id: 2, label: "58号机", number: "58", state: .busy, progress: 0.62, endsAt: .now.addingTimeInterval(11 * 60)),
        ],
        failed: false)

    static func failure(_ date: Date) -> StatusEntry {
        StatusEntry(date: date, building: "洗衣房", items: [], failed: true)
    }
}

/// Countdown text that never builds an invalid range.
struct Countdown: View {
    let from: Date
    let to: Date

    var body: some View {
        Text(timerInterval: from...max(to, from), countsDown: true)
            .monospacedDigit()
    }
}

// MARK: - Widget views

struct WidgetBackdrop: View {
    let entry: StatusEntry
    var body: some View { Color(.systemBackground) }
}

struct StatusWidgetView: View {
    let entry: StatusEntry
    /// Lets the app's debug gallery pick a family; widgets leave it nil.
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.colorScheme) private var scheme
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(entry.building)洗衣房")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            summary(compact: true)
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.items.prefix(3)) { row($0, font: .caption) }
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(entry.building)洗衣房")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                summary(compact: false)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(entry.items.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        row(item, font: .subheadline)
                        if item.state == .busy, let p = item.progress {
                            ProgressView(value: p)
                                .tint(Palette.water)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder private func summary(compact: Bool) -> some View {
        if entry.failed {
            Text("无法连接")
                .font(.headline)
            Text("将自动重试")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if entry.stale {
            Text("数据未更新")
                .font(.headline)
            Text(entry.updatedAt.map { "最后更新于 \(Fmt.time($0))" } ?? "状态暂不可知")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if entry.idle > 0 || entry.soonest == nil {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(entry.idle)")
                    .font(.system(size: compact ? 40 : 44, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.idle > 0 ? Palette.ink(.idle, dark: scheme == .dark) : .primary)
                Text("台空闲")
                    .font(.subheadline.weight(.semibold))
            }
            Text(entry.predictedFree > 0 ? "另有 \(entry.predictedFree) 台应已完成" : "共 \(entry.total) 台")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let s = entry.soonest, let end = s.endsAt {
            Text("暂无空闲")
                .font(.headline)
            Text("最早 \(Fmt.time(end)) 空闲")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ item: StatusEntry.Item, font: Font) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Palette.tint(item.state))
                .frame(width: 7, height: 7)
            Text(item.label)
                .lineLimit(1)
            Spacer(minLength: 4)
            status(item)
                .foregroundStyle(Palette.ink(item.state, dark: scheme == .dark))
        }
        .font(font.weight(.medium))
    }

    @ViewBuilder private func status(_ item: StatusEntry.Item) -> some View {
        switch item.state {
        case .idle: Text(item.predicted ? "应已完成" : "空闲")
        case .offline: Text("不可用")
        case .busy:
            if let end = item.endsAt, end > entry.date {
                Countdown(from: entry.date, to: end)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 56, alignment: .trailing)
            } else if item.endsAt != nil {
                Text("即将完成")
            } else {
                Text("运行中")
            }
        }
    }

    // MARK: Lock Screen

    @ViewBuilder private var circular: some View {
        if entry.failed || entry.stale {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
            }
        } else if entry.idle == 0, let s = entry.soonest, let end = s.endsAt, end > entry.date {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("剩余")
                        .font(.system(size: 10, weight: .medium))
                    Countdown(from: entry.date, to: end)
                        .font(.system(size: 12, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
                .padding(4)
            }
        } else {
            Gauge(value: Double(entry.idle), in: 0...Double(max(1, entry.total))) {
                Text("空闲")
            } currentValueLabel: {
                Text("\(entry.idle)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.failed ? "洗衣房 · 无法连接" : entry.stale ? "洗衣房 · 数据未更新" : "洗衣房 · \(entry.idle) 台空闲")
                .font(.headline)
                .widgetAccentable()
            ForEach(entry.items.prefix(2)) { item in
                HStack(spacing: 4) {
                    Text(item.label)
                    Spacer(minLength: 2)
                    status(item)
                }
                .font(.caption)
            }
        }
    }

    private var inline: some View {
        Label {
            if entry.failed {
                Text("洗衣房无法连接")
            } else if entry.stale {
                Text("洗衣房数据未更新")
            } else if entry.idle > 0 {
                Text("洗衣机 \(entry.idle)/\(entry.total) 台空闲")
            } else if let s = entry.soonest, let end = s.endsAt {
                Text("洗衣机预计 \(Fmt.time(end)) 空闲")
            } else {
                Text("洗衣机暂无空闲")
            }
        } icon: {
            Image(systemName: "washer")
        }
    }
}

// MARK: - Live Activity

enum ActivityWords {
    static func headline(_ s: LaundryActivityAttributes.ContentState) -> String {
        if s.idleCount > 0 { return "\(s.idleCount) 台空闲" }
        if s.machines.contains(where: { $0.state == .busy }) { return "暂无空闲" }
        return "暂无可用设备"
    }

    static func detail(_ s: LaundryActivityAttributes.ContentState) -> String {
        if s.idleCount > 0 { return "共 \(s.machines.count) 台，可立即使用" }
        if let soon = s.soonest, let end = soon.endsAt { return "最早 \(Fmt.time(end)) 空闲" }
        return "剩余时间暂不可知"
    }

    static func tint(_ s: LaundryActivityAttributes.ContentState) -> Color {
        s.idleCount > 0 ? Palette.fresh : Palette.water
    }

    @ViewBuilder static func trailing(_ s: LaundryActivityAttributes.ContentState) -> some View {
        if s.idleCount > 0 {
            Text("空闲 \(s.idleCount)")
        } else if let soon = s.soonest, let end = soon.endsAt {
            Countdown(from: s.updatedAt, to: end)
                .multilineTextAlignment(.trailing)
        } else {
            Text("运行中")
        }
    }
}

struct LockScreenActivity: View {
    let state: LaundryActivityAttributes.ContentState
    var isStale = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(state.building)洗衣房")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(isStale ? "数据已过时" : ActivityWords.headline(state))
                    .font(.title3.weight(.bold))
                Text(isStale ? "最后更新于 \(Fmt.time(state.updatedAt))，请打开应用刷新" : ActivityWords.detail(state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.machines.prefix(3)) { m in
                    ActivityRow(machine: m, updatedAt: state.updatedAt)
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(isStale ? 0.45 : 1)
        }
        .padding(16)
    }
}

struct ActivityRow: View {
    let machine: LaundryActivityAttributes.Machine
    let updatedAt: Date

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.tint(machine.state))
                    .frame(width: 7, height: 7)
                Text(machine.label)
                Spacer(minLength: 4)
                Group {
                    switch machine.state {
                    case .idle: Text("空闲")
                    case .offline: Text("不可用")
                    case .busy:
                        if let end = machine.endsAt {
                            Countdown(from: updatedAt, to: end)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 52, alignment: .trailing)
                        } else {
                            Text("运行中")
                        }
                    }
                }
                .foregroundStyle(Palette.ink(machine.state, dark: scheme == .dark))
            }
            .font(.subheadline.weight(.medium))
            if machine.state == .busy, let p = machine.progress {
                ProgressView(value: p)
                    .tint(Palette.water)
            }
        }
    }
}
