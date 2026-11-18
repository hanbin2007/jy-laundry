import SwiftUI

struct MachineDetailView: View {
    let machineID: Int
    @Environment(LaundryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int?
    @State private var timelineFrame: CGRect = .zero

    private var machine: MachineState? { store.machine(id: machineID) }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 14) {
                    topBar

                    if let machine {
                        headerCard(machine)
                        statsCard(machine)
                        timelineCard(machine)
                        legend

                        Text("前台 5 秒刷新 · 历史保留 7 天")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.tertiary.opacity(0.9))
                            .padding(.top, 4)
                    } else {
                        ProgressView().tint(Palette.jade).padding(.top, 60)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .coordinateSpace(name: "detail")
        .simultaneousGesture(swipeBack)
        .onPreferenceChange(TimelineFrameKey.self) { timelineFrame = $0 }
        .toolbar(.hidden, for: .navigationBar)
        .enablesSwipeBack()
    }

    private var swipeBack: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .named("detail"))
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard value.startLocation.x > 40,
                      !timelineFrame.contains(value.startLocation),
                      dx > 90,
                      abs(dy) < 70,
                      dx > abs(dy) * 1.6 else { return }
                dismiss()
            }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.6), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 2)
    }

    private func headerCard(_ machine: MachineState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(machine.label)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(machine.isIdle ? Palette.jade : Palette.busy)
                Spacer()
                Text(machine.statusText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(machine.isIdle ? Palette.jade : Palette.busy)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        (machine.isIdle ? Palette.jade : Palette.busy).opacity(0.1),
                        in: Capsule()
                    )
            }
            Text(machine.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.tertiary)
        }
        .padding(20)
        .glassSurface(corner: 28)
    }

    private func statsCard(_ machine: MachineState) -> some View {
        HStack(spacing: 0) {
            stat("空闲", Fmt.duration(machine.idleMinutes))
            divider
            stat("启动", "\(machine.sessions) 次")
            divider
            stat("最长空闲", Fmt.duration(machine.longestIdle))
        }
        .padding(.vertical, 16)
        .glassSurface(corner: 24)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(width: 0.5, height: 26)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func timelineCard(_ machine: MachineState) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近 3 小时")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                Spacer()
                Text(selection == nil
                     ? "已记录 \(store.recordedMinutes) 分钟"
                     : selectionText(machine))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiary)
            }

            GeometryReader { geo in
                ZStack {
                    HistoryBar(runs: machine.runs,
                               minutes: store.windowMinutes,
                               height: 100,
                               showsData: store.coverage >= 0.01,
                               segments: 3,
                               cornerRadius: 16)

                    if store.coverage < 0.01 {
                        Text("开始记录")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.tertiary)
                    }

                    if let selection {
                        Rectangle()
                            .fill(Palette.ink.opacity(0.4))
                            .frame(width: 1, height: 100)
                            .position(x: markerX(selection, width: geo.size.width), y: 50)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                            selection = Int(ratio * CGFloat(store.windowMinutes - 1))
                        }
                )
            }
            .frame(height: 100)

            HStack {
                ForEach(axisHours, id: \.self) { hour in
                    Text(Fmt.hourLabel(store.windowStart + hour * 3600))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiary)
                    if hour != axisHours.last { Spacer() }
                }
            }
        }
        .padding(18)
        .glassSurface(corner: 26)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TimelineFrameKey.self,
                    value: proxy.frame(in: .named("detail"))
                )
            }
        )
    }

    private var axisHours: [Int] { [0, 1, 2, 3] }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(Palette.mint, "空闲")
            legendDot(Palette.busyBar, "使用中")
            legendDot(Palette.line, "未采集")
            Spacer()
            Text("拖动查看")
                .font(.system(size: 11))
                .foregroundStyle(Palette.tertiary.opacity(0.85))
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Palette.tertiary)
        .padding(.horizontal, 6)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
    }

    private func markerX(_ offset: Int, width: CGFloat) -> CGFloat {
        let ratio = CGFloat(offset) / CGFloat(max(store.windowMinutes - 1, 1))
        return min(max(width * ratio, 0), width - 1)
    }

    private func selectionText(_ machine: MachineState) -> String {
        guard let selection else { return "拖动查看" }
        let epoch = store.windowStart + selection * 60
        let state = machine.state(at: selection)
        let text: String
        switch state {
        case 10: text = "空闲"
        case 20: text = "使用中"
        default: text = "未采集"
        }
        return "\(Fmt.clock(epoch)) · \(text)"
    }
}

private struct TimelineFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
