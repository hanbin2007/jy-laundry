import SwiftUI
import WidgetKit

// The Live Activity on the Lock Screen (and, scaled up, in StandBy). The same order as the expanded
// island: the summary first, the machines below. It keeps the system's own background, light or dark,
// so it sits well on any wallpaper, and the standard 14 pt margin, so it lines up with notifications.

struct LockScreenActivity: View {
    let state: LaundryActivityAttributes.ContentState
    var isStale = false

    @Environment(\.colorScheme) private var scheme

    private var reading: StatusRing.Reading { state.reading(isStale: isStale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StatusRing(reading: reading, size: 44, namesMachine: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.title3.weight(.bold))
                    Text(detail)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if case .washing(let number, _, let end, _) = reading {
                    VStack(alignment: .trailing, spacing: 2) {
                        Countdown(from: state.updatedAt, to: end)
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Palette.ink(.busy, dark: scheme == .dark))
                        Text("\(number)号机")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            // When there is less to say, the activity is shorter: out-of-date countdowns would mislead.
            if !isStale, !state.machines.isEmpty {
                MachineTiles(state: state)
            }
        }
        .padding(14)
    }

    private var headline: String {
        switch reading {
        case .free(let count): return "\(count) 台空闲"
        case .washing, .running: return "暂无空闲"
        case .unavailable: return "暂无可用设备"
        case .outdated: return "数据已过时"
        }
    }

    private var detail: String {
        let room = Wording.room(state.building)
        switch reading {
        case .free: return "\(room) · 共 \(state.machines.count) 台"
        case .washing(_, _, let end, _): return "\(room) · 最早 \(Fmt.time(end))"
        case .running, .unavailable: return room
        case .outdated: return "\(Fmt.time(state.updatedAt)) 更新 · 打开应用即可刷新"
        }
    }
}
