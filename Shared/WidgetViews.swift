import SwiftUI
import WidgetKit

// The Home Screen and Lock Screen widgets. Shared with the app's debug gallery.
//
// Small answers one question: is a washer free, and if not, when. Medium adds each machine.
// The Lock Screen sizes say the same in one ring, three lines or one line.

// MARK: - Entry

struct StatusEntry: TimelineEntry {
    struct Item: Identifiable, Hashable {
        let id: Int
        let label: String
        let number: String
        var state: DrumState
        var progress: Double?
        var startsAt: Date? = nil
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

    /// The machine a tap should open: a free one if there is one, otherwise the next to finish.
    var link: URL {
        let target = items.first { $0.state == .idle } ?? soonest
        return target.map { DeepLink.machine($0.id) } ?? DeepLink.overview
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
            Item(id: 2, label: "58号机", number: "58", state: .busy, progress: 0.62,
                 startsAt: .now.addingTimeInterval(-18 * 60), endsAt: .now.addingTimeInterval(11 * 60)),
        ],
        failed: false, updatedAt: .now)

    static func failure(_ date: Date) -> StatusEntry {
        StatusEntry(date: date, building: Wording.roomNoun, items: [], failed: true)
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

    // MARK: What to say

    private enum Summary {
        case failed
        case stale
        case free(Int)
        /// None confirmed free, but this many washes should have ended by now.
        case likelyFree(Int)
        case wait(StatusEntry.Item, Date)
        case running
        case unavailable
    }

    private var summary: Summary {
        if entry.failed { return .failed }
        if entry.stale { return .stale }
        if entry.idle > 0 { return .free(entry.idle) }
        if entry.predictedFree > 0 { return .likelyFree(entry.predictedFree) }
        if let s = entry.soonest, let end = s.endsAt, end > entry.date { return .wait(s, end) }
        if entry.items.contains(where: { $0.state == .busy }) { return .running }
        return .unavailable
    }

    private func ink(_ state: DrumState) -> Color { Palette.ink(state, dark: scheme == .dark) }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
            Spacer(minLength: 4)
            hero
            Spacer(minLength: 4)
            footnote
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(entry.link)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                title
                Spacer(minLength: 4)
                hero
                Spacer(minLength: 4)
                // Widgets refresh every few minutes at best, so say how old the reading is.
                Text(entry.updatedAt.map { "\(Fmt.time($0)) 更新" } ?? " ")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(entry.items.prefix(3)) { item in
                    Link(destination: DeepLink.machine(item.id)) { machineRow(item) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .widgetURL(entry.link)
    }

    private var title: some View {
        Label(Wording.room(entry.building), systemImage: "washer.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// The one thing the widget is for, large.
    @ViewBuilder private var hero: some View {
        switch summary {
        case .failed:
            heroText("无法连接", symbol: "wifi.exclamationmark")
        case .stale:
            heroText("数据未更新", symbol: "clock.badge.exclamationmark")
        case .free(let count):
            heroCount(count, unit: "台空闲", color: ink(.idle))
        case .likelyFree(let count):
            heroCount(count, unit: "台应已完成", color: .primary)
        case .wait(_, let end):
            VStack(alignment: .leading, spacing: 0) {
                Text("暂无空闲")
                    .font(.subheadline.weight(.semibold))
                Countdown(from: entry.date, to: end, alignment: .leading)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(ink(.busy))
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .combine)
        case .running:
            heroText("暂无空闲", symbol: "timer")
        case .unavailable:
            heroText("暂无可用设备", symbol: "xmark.circle")
        }
    }

    private func heroCount(_ count: Int, unit: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(count)")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(color)
                .widgetAccentable()
            Text(unit)
                .font(.headline)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }

    private func heroText(_ text: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            Text(text)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    /// One supporting line under the hero.
    @ViewBuilder private var footnote: some View {
        switch summary {
        case .failed:
            Text("将自动重试")
        case .stale:
            Text(entry.updatedAt.map { "\(Fmt.time($0)) 更新" } ?? "状态暂不可知")
        case .free:
            if entry.predictedFree > 0 {
                Text("另有 \(entry.predictedFree) 台应已完成")
            } else if let s = entry.soonest, let end = s.endsAt, end > entry.date {
                // A clock time, not a bare countdown: "22:23" alone could be read as either.
                Text("\(s.label) · \(Fmt.time(end)) 完成")
            } else {
                Text("共 \(entry.total) 台")
            }
        case .likelyFree:
            Text("按预计时间推算")
        case .wait(let item, let end):
            Text("\(item.label) · \(Fmt.time(end)) 完成")
        case .running:
            Text("剩余时间未知")
        case .unavailable:
            Text("共 \(entry.total) 台")
        }
    }

    private func machineRow(_ item: StatusEntry.Item) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: item.predicted ? "checkmark.circle" : item.state.symbol)
                    .foregroundStyle(Palette.tint(item.state))
                    .widgetAccentable()
                Text(item.label)
                    .lineLimit(1)
                Spacer(minLength: 4)
                status(item)
                    .fontWeight(.semibold)
                    .foregroundStyle(ink(item.state))
            }
            .font(.subheadline.weight(.medium))
            if item.state == .busy {
                CycleProgress(start: item.startsAt, end: item.endsAt, fraction: item.progress)
                    .tint(Palette.water)
                    .widgetAccentable()
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func status(_ item: StatusEntry.Item) -> some View {
        switch item.state {
        case .idle: Text(item.predicted ? "应已完成" : "空闲")
        case .offline: Text("不可用")
        case .busy:
            if let end = item.endsAt, end > entry.date {
                Countdown(from: entry.date, to: end)
            } else if item.endsAt != nil {
                Text("即将完成")
            } else {
                Text("运行中")
            }
        }
    }

    // MARK: Lock Screen

    /// A ring, like a complication: how many of the washers are free, or how far the soonest wash has got.
    @ViewBuilder private var circular: some View {
        switch summary {
        case .failed, .stale:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.title3.weight(.semibold))
            }
            .accessibilityLabel(entry.failed ? "洗衣房无法连接" : "洗衣房数据未更新")
        case .wait(let item, let end):
            ProgressView(timerInterval: (item.startsAt ?? entry.date)...end, countsDown: false) {
                Image(systemName: "washer.fill")
            } currentValueLabel: {
                Countdown(from: entry.date, to: end, alignment: .center)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.7)
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        default:
            Gauge(value: Double(entry.idle), in: 0...Double(max(1, entry.total))) {
                Image(systemName: "washer.fill")
            } currentValueLabel: {
                Text("\(entry.idle)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
            .accessibilityLabel("洗衣房")
            .accessibilityValue("\(entry.idle) 台空闲，共 \(entry.total) 台")
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(rectangularTitle, systemImage: "washer.fill")
                .font(.headline)
                .widgetAccentable()
            if entry.failed || entry.stale || entry.items.isEmpty {
                Text(entry.failed ? "将自动重试" : entry.updatedAt.map { "\(Fmt.time($0)) 更新" } ?? "状态暂不可知")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.items.prefix(2)) { item in
                    HStack(spacing: 4) {
                        Text(item.label)
                        Spacer(minLength: 2)
                        status(item)
                    }
                    .font(.subheadline.weight(.medium))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var rectangularTitle: String {
        switch summary {
        case .failed: return "无法连接"
        case .stale: return "数据未更新"
        case .free(let count): return "\(count) 台空闲"
        case .likelyFree(let count): return "\(count) 台应已完成"
        case .wait, .running: return "暂无空闲"
        case .unavailable: return "暂无可用设备"
        }
    }

    private var inline: some View {
        Label {
            switch summary {
            case .failed: Text("洗衣房无法连接")
            case .stale: Text("洗衣房数据未更新")
            case .free(let count): Text("\(count) 台洗衣机空闲")
            case .likelyFree(let count): Text("\(count) 台洗衣机应已完成")
            case .wait(_, let end): Text("洗衣机最早 \(Fmt.time(end)) 空闲")
            case .running: Text("洗衣机暂无空闲")
            case .unavailable: Text("洗衣机暂不可用")
            }
        } icon: {
            Image(systemName: "washer.fill")
        }
    }
}
