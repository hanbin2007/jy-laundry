import SwiftUI
import WidgetKit

// The Dynamic Island. One statement, split around the camera: the ring on the leading side (how many
// washers are free, or how far the soonest wash has got) and the word or countdown that completes it on
// the trailing side. The expanded presentation is the same statement enlarged, with the machines below.

// MARK: - What the room says

extension LaundryActivityAttributes.ContentState {
    func reading(isStale: Bool) -> StatusRing.Reading {
        if isStale { return .outdated }
        if idleCount > 0 { return .free(idleCount) }
        if let m = soonest, let end = m.endsAt {
            return .washing(number: m.number, start: m.startedAt, end: end, fraction: m.progress)
        }
        if machines.contains(where: { $0.state == .busy }) { return .running }
        return .unavailable
    }

    /// The machine a tap should open: a free one if there is one, otherwise the next to finish.
    var link: URL {
        let target = machines.first { $0.state == .idle } ?? soonest
        return target.map { DeepLink.machine($0.id) } ?? DeepLink.overview
    }
}

extension StatusRing.Reading {
    /// Bold on black: the Dynamic Island is always dark.
    var islandTint: Color {
        switch self {
        case .free: return Palette.fresh
        case .washing, .running: return Palette.ink(.busy, dark: true)
        case .unavailable, .outdated: return Color(white: 0.62)
        }
    }

    var keyline: Color {
        switch self {
        case .free: return Palette.fresh
        case .washing, .running: return Palette.water
        case .unavailable, .outdated: return .gray
        }
    }
}

/// iPhone in landscape leaves the island a 28 pt circle per side (iOS 27).
struct LimitedWidthReader<Content: View>: View {
    @ViewBuilder var content: (Bool) -> Content

    var body: some View {
        if #available(iOS 27.0, *) {
            Reader(content: content)
        } else {
            content(false)
        }
    }

    @available(iOS 27.0, *)
    private struct Reader: View {
        @Environment(\.isDynamicIslandLimitedInWidth) private var limited
        let content: (Bool) -> Content
        var body: some View { content(limited) }
    }
}

/// The word, or the countdown, that completes the ring.
private struct IslandStatus: View {
    let state: LaundryActivityAttributes.ContentState
    let reading: StatusRing.Reading
    /// Compact has room for "空闲"; expanded says "1 台空闲".
    var full = false

    var body: some View {
        Group {
            switch reading {
            case .free(let count): Text(full ? "\(count) 台空闲" : "空闲")
            case .washing(_, _, let end, _): Countdown(from: state.updatedAt, to: end)
            case .running: Text("运行中")
            case .unavailable: Text("不可用")
            case .outdated: Text("已过时")
            }
        }
        .foregroundStyle(reading.islandTint)
        .lineLimit(1)
    }
}

// MARK: - Compact and minimal

struct IslandCompactLeading: View {
    let state: LaundryActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        StatusRing(reading: state.reading(isStale: isStale), size: 22)
    }
}

struct IslandCompactTrailing: View {
    let state: LaundryActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        LimitedWidthReader { limited in
            // With no room for words the ring carries the message alone, and the system hides this side.
            if !limited {
                IslandStatus(state: state, reading: state.reading(isStale: isStale))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
        }
    }
}

struct IslandMinimal: View {
    let state: LaundryActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let reading = state.reading(isStale: isStale)
        LimitedWidthReader { limited in
            if case .washing(_, _, let end, _) = reading, !limited {
                // Like the system timer: the time itself, not a logo.
                Countdown(from: state.updatedAt, to: end, alignment: .center)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(reading.islandTint)
                    .minimumScaleFactor(0.7)
            } else {
                StatusRing(reading: reading, size: 22)
            }
        }
    }
}

// MARK: - Expanded

struct IslandExpandedLeading: View {
    let state: LaundryActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 10) {
            StatusRing(reading: state.reading(isStale: isStale), size: 40, namesMachine: true)
            VStack(alignment: .leading, spacing: 1) {
                if state.building != Wording.roomNoun {
                    Text(state.building)
                        .font(.subheadline.weight(.semibold))
                }
                Text(Wording.roomNoun)
                    .font(state.building != Wording.roomNoun ? .caption.weight(.medium) : .subheadline.weight(.semibold))
                    .foregroundStyle(state.building != Wording.roomNoun ? .secondary : .primary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Wording.room(state.building))
        .padding(.top, isStale ? IslandMetrics.loneRowInset : 0)
    }
}

private enum IslandMetrics {
    /// With no machines below, the island is a short pill; this centres the one row in it, so the ring
    /// sits concentric in the rounded end instead of riding high.
    static let loneRowInset: CGFloat = 4
}

struct IslandExpandedTrailing: View {
    let state: LaundryActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let reading = state.reading(isStale: isStale)
        VStack(alignment: .trailing, spacing: 1) {
            IslandStatus(state: state, reading: reading, full: true)
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text(caption(reading))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minHeight: 40)
        .padding(.top, isStale ? IslandMetrics.loneRowInset : 0)
    }

    private func caption(_ reading: StatusRing.Reading) -> String {
        switch reading {
        case .free: return "共 \(state.machines.count) 台"
        case .washing(let number, _, _, _): return "\(number)号机最早完成"
        case .running: return "剩余时间未知"
        case .unavailable: return "暂无可用设备"
        case .outdated: return "\(Fmt.time(state.updatedAt)) 更新"
        }
    }
}

struct IslandExpandedBottom: View {
    let state: LaundryActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        // Out-of-date countdowns would mislead, so the island shrinks to its summary instead. Nothing but
        // the rounded tiles goes down here: square content would be cut by the island's bottom corners.
        if !isStale, !state.machines.isEmpty {
            MachineTiles(state: state)
                .padding(.top, 6)
        }
    }
}

// MARK: - Machine tiles (expanded island and Lock Screen)

/// One inset tile per machine, side by side.
struct MachineTiles: View {
    let state: LaundryActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            ForEach(state.machines.prefix(3)) { machine in
                Link(destination: DeepLink.machine(machine.id)) {
                    MachineTile(machine: machine, updatedAt: state.updatedAt)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MachineTile: View {
    let machine: LaundryActivityAttributes.Machine
    let updatedAt: Date

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    name
                    Spacer(minLength: 0)
                    status
                }
                VStack(alignment: .leading, spacing: 1) {
                    name
                    status
                }
            }
            bar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(scheme == .dark ? 0.12 : 0.06), in: ContainerRelativeShape())
        .accessibilityElement(children: .combine)
    }

    private var name: some View {
        Text(machine.label)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .fixedSize()
    }

    private var status: some View {
        Group {
            switch machine.state {
            case .idle: Text("空闲")
            case .offline: Text("不可用")
            case .busy:
                if let end = machine.endsAt {
                    Countdown(from: updatedAt, to: end)
                } else {
                    Text("运行中")
                }
            }
        }
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
        .foregroundStyle(Palette.ink(machine.state, dark: scheme == .dark))
        .lineLimit(1)
        .fixedSize()
    }

    /// Every tile carries a bar, so the tiles line up: full when free, moving while washing, empty when off.
    @ViewBuilder private var bar: some View {
        switch machine.state {
        case .idle: ProgressView(value: 1).tint(Palette.fresh)
        case .offline: ProgressView(value: 0)
        case .busy:
            CycleProgress(start: machine.startedAt, end: machine.endsAt, fraction: machine.progress)
                .tint(Palette.water)
        }
    }
}
