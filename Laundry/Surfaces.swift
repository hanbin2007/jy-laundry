import SwiftUI

// MARK: - Sections

/// A grouped section in the style of the system's inset-grouped lists: a quiet header above a card.
struct SectionCard<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .accessibilityAddTraits(.isHeader)
            }
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground),
                            in: .rect(cornerRadius: 22, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Status

struct StatusPill: View {
    let state: DrumState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(Wording.state(state))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.ink(state, dark: scheme == .dark))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Palette.tint(state).opacity(scheme == .dark ? 0.22 : 0.14), in: .capsule)
    }
}

/// A slim progress bar for a running cycle.
struct CycleBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(Palette.water)
                    .frame(width: max(6, geo.size.width * progress))
            }
        }
        .frame(height: 6)
        .animation(.smooth, value: progress)
        .accessibilityElement()
        .accessibilityLabel("进度")
        .accessibilityValue(Fmt.percent(progress))
    }
}

/// The washer door as a small status icon. It animates gently while running and is still otherwise.
struct MachineIcon: View {
    let machine: MachineState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let animate = machine.isBusy && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animate)) { timeline in
            Porthole(
                state: machine.drumState,
                progress: machine.progress,
                spinning: machine.isSpinning,
                time: animate ? timeline.date.timeIntervalSinceReferenceDate : 0
            )
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Connection status

struct ConnectionLine: View {
    let store: LaundryStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            HStack(spacing: 6) {
                Circle()
                    .fill(store.connectionColor)
                    .frame(width: 7, height: 7)
                Text(store.connectionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

extension LaundryStore {
    /// Connected, with fresh data.
    var isLive: Bool { snapshot != nil && error == nil && !isStale }

    var connectionText: String {
        if snapshot == nil { return error == nil ? "正在连接服务器" : "无法连接服务器" }
        if error != nil { return "连接中断，显示 \(ageText)的数据" }
        if isStale { return "数据更新于 \(ageText)" }
        return "实时更新"
    }

    var connectionColor: Color {
        if snapshot == nil { return error == nil ? .secondary : .red }
        if error != nil || isStale { return Palette.ember }
        return Palette.fresh
    }
}
