import SwiftUI

/// The main screen, for the machine in view:
/// how long it has left, its last 24 hours, and, side by side, its idle rate by hour and the machine itself in 3D.
/// Swipe the machine to switch.
///
/// Layout grid: every line of text starts on one left edge; sections are 32 pt apart; in the lower half
/// the chart's axis and the machine's floor share one line, and the page dots sit in the axis row.
struct OverviewView: View {
    @Environment(LaundryStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The machine in view, by id, so it stays in view when machines are added, removed or reordered.
    @State private var selectedID: Int?
    @State private var path: [Int] = []
    @State private var onScreen = false

    var body: some View {
        let machines = store.machines
        let i = selectedID.flatMap { id in machines.firstIndex { $0.id == id } } ?? 0
        let machine = machines.isEmpty ? nil : machines[i]
        // The carousel and the dots work with positions; they are turned back into ids here.
        let shown = Binding(get: { i }, set: { k in
            let list = store.machines
            if list.indices.contains(k) { selectedID = list[k].id }
        })

        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                StatusBlock(machine: machine)
                    .padding(.top, 16)
                if let machine {
                    RecordBlock(machine: machine, windowStart: store.windowStart, windowMinutes: store.windowMinutes)
                        .padding(.top, 32)
                    LowerHalf(
                        machines: machines,
                        machine: machine,
                        selection: shown,
                        forecast: store.forecast(for: machine.id),
                        forecastLoaded: store.hasWeek,
                        looks: machines.map { look(for: $0) },
                        dark: scheme == .dark,
                        animates: !reduceMotion,
                        active: onScreen && path.isEmpty && scenePhase == .active
                    )
                    .padding(.top, 32)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // This screen is laid out to fit; very large text sizes are served by the 记录 tab's list
            // and by the detail screens, which are not capped.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .background { OverviewBackground(state: machine?.drumState).ignoresSafeArea() }
            .navigationTitle("概览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ReminderMenu(machine: machine)
                }
                ToolbarItem(placement: .principal) {
                    RoomTitle()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("设备详情", systemImage: "info.circle") {
                        if let machine { path.append(machine.id) }
                    }
                    .disabled(machine == nil)
                }
            }
            .navigationDestination(for: Int.self) { id in
                MachineDetailView(id: id)
            }
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
        }
        .animation(.smooth(duration: 0.35), value: machine?.id)
        .sensoryFeedback(.selection, trigger: machine?.id)
        .onChange(of: store.linkedMachineID, initial: true) { _, id in
            guard let id else { return }
            path = []
            selectedID = id
            store.linkedMachineID = nil
        }
        #if DEBUG
        .task(id: machines.count) {
            if selectedID == nil, let k = Demo.machine, machines.indices.contains(k) { selectedID = machines[k].id }
        }
        .task {
            guard let delay = Demo.switchAfter else { return }
            try? await Task.sleep(for: .seconds(delay))
            let list = store.machines
            guard !list.isEmpty else { return }
            let now = selectedID.flatMap { id in list.firstIndex { $0.id == id } } ?? 0
            selectedID = list[(now + 1) % list.count].id
        }
        #endif
    }

    private func look(for m: MachineState) -> WasherLook {
        var clock = ""
        if m.isBusy, let end = store.endsAt(m), let minutes = Self.minutesLeft(until: end, now: .now) {
            clock = Fmt.hoursMinutes(minutes)
        }
        return WasherLook(id: m.id, label: m.number, state: m.drumState, spinning: m.isSpinning, clock: clock)
    }

    /// Whole minutes left, rounded up; nil once the estimated end has passed (the data is then out of date).
    static func minutesLeft(until end: Date, now: Date) -> Int? {
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        return max(1, Int((seconds / 60).rounded(.up)))
    }
}

// MARK: - Top bar

private struct RoomTitle: View {
    @Environment(LaundryStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            VStack(spacing: 1) {
                Text("\(store.buildingName)洗衣房")
                    .font(.headline)
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.connectionColor)
                        .frame(width: 6, height: 6)
                    Text(store.isLive ? "共 \(store.total) 台 · \(store.idleCount) 台空闲" : store.connectionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }
}

private struct ReminderMenu: View {
    let machine: MachineState?
    @Environment(LaundryStore.self) private var store

    var body: some View {
        let anySet = store.hasReminder(LaundryStore.anyMachine)
        let machineSet = machine.map { store.hasReminder($0.id) } ?? false
        let showsMachine = machine.map { $0.isBusy || machineSet } ?? false
        let showsAny = store.allBusy || anySet

        Menu {
            if let machine, showsMachine {
                Button(machineSet ? "取消\(machine.label)的完成提醒" : "\(machine.label)完成时通知我",
                       systemImage: machineSet ? "bell.slash" : "bell") {
                    Task { await store.toggleReminder(for: machine) }
                }
            }
            if showsAny {
                Button(anySet ? "取消空闲提醒" : "有设备空闲时通知我",
                       systemImage: anySet ? "bell.slash" : "bell") {
                    Task { await store.toggleAnyReminder() }
                }
            }
            if !showsMachine && !showsAny {
                Text(machine.map { "\($0.label)当前\(Wording.state($0.drumState))，无需设置提醒" } ?? "暂无可设置的提醒")
            }
        } label: {
            Label("提醒", systemImage: store.reminders.isEmpty ? "bell" : "bell.badge")
        }
    }
}

// MARK: - Status

/// "00:34 剩余": the state of the machine in view and when it will be free.
private struct StatusBlock: View {
    let machine: MachineState?
    @Environment(LaundryStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let machine {
                content(machine, now: context.date)
            } else {
                placeholder
            }
        }
    }

    private func content(_ m: MachineState, now: Date) -> some View {
        let dark = scheme == .dark
        let end = m.isBusy ? store.endsAt(m) : nil
        let minutes = end.flatMap { OverviewView.minutesLeft(until: $0, now: now) }

        return VStack(alignment: .leading, spacing: 8) {
            Group {
                if end != nil, minutes == nil {
                    // The estimated end has passed but no newer data has arrived yet.
                    Text("即将完成")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink(.busy, dark: dark))
                } else if let minutes {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Fmt.hoursMinutes(minutes))
                            .font(.system(size: 80, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .tracking(-2)
                            .foregroundStyle(Palette.ink(.busy, dark: dark))
                            .contentTransition(.numericText(countsDown: true))
                        Text("剩余")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(Wording.state(m.drumState))
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink(m.drumState, dark: dark))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(height: 84, alignment: .leading)

            Text(detail(m, end: end, now: now))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(m, minutes: minutes, end: end, now: now))
    }

    private var placeholder: some View {
        let empty = store.snapshot != nil && store.error == nil
        return VStack(alignment: .leading, spacing: 8) {
            Text(empty ? "暂无设备" : store.error == nil ? "正在获取数据…" : "无法连接服务器")
                .font(.system(size: 34, weight: .bold))
            if empty {
                Text("服务器未返回任何设备。")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            } else if let error = store.error {
                Text(error)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Button("重试", systemImage: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ m: MachineState, end: Date?, now: Date) -> String {
        switch m.drumState {
        case .busy:
            guard let end else { return "剩余时间暂不可知" }
            if end <= now { return "运行中 · 正在等待设备状态更新" }
            return "\(m.isSpinning ? "脱水阶段" : "运行中") · \(Wording.finish(end))"
        case .idle:
            return "\(Wording.idleFor(m.currentRunMinutes)) · 可立即使用"
        case .offline:
            return Wording.offlineDetail
        }
    }

    private func spoken(_ m: MachineState, minutes: Int?, end: Date?, now: Date) -> String {
        var parts = [m.label]
        if let minutes { parts.append(Wording.remaining(minutes)) }
        else if end != nil { parts.append("即将完成") }
        else { parts.append(Wording.state(m.drumState)) }
        parts.append(detail(m, end: end, now: now))
        return parts.joined(separator: "，")
    }
}

// MARK: - Record

/// The last 24 hours of the machine in view as one bar.
private struct RecordBlock: View {
    let machine: MachineState
    let windowStart: Int
    let windowMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("记录")
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("近 \(max(1, windowMinutes / 60)) 小时 · 洗涤 \(machine.sessions) 次")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            UsageStrip(machine: machine, windowMinutes: windowMinutes, cornerRadius: 6)
                .frame(height: 20)
            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { k, text in
                    if k > 0 { Spacer(minLength: 0) }
                    Text(text)
                }
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    /// The window's start, then every quarter of it, then 现在.
    private var labels: [String] {
        let step = windowMinutes * 60 / 4
        return (0..<4).map { Fmt.clock(windowStart + $0 * step) } + ["现在"]
    }
}

// MARK: - Lower half

private struct LowerHalf: View {
    let machines: [MachineState]
    let machine: MachineState
    @Binding var selection: Int
    let forecast: Forecast
    let forecastLoaded: Bool
    let looks: [WasherLook]
    let dark: Bool
    let animates: Bool
    let active: Bool

    /// Measurements from the design (390 × 844), in points at scale 1.
    private enum Design {
        static let floor: CGFloat = 338        // from the top of the lower half to the floor line
        static let axisRow: CGFloat = 20       // gap and labels under the floor line
        static let above: CGFloat = 22         // the 3D view starts this far above the lower half
        static let below: CGFloat = 60         // and reaches this far below the floor, for the shadow
        static let margin: CGFloat = 24        // it spans the full screen width, past the page margins
        static let rightOfAnchor: CGFloat = 89 // from the floor point under the front machine to the right margin
        static let anchorRise: CGFloat = 36    // that floor point sits this far above the floor line
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let floorY = geo.size.height - Design.axisRow
            let s = min(1.2, max(0.7, floorY / Design.floor))
            let column = (width * 0.44).rounded()
            let frame = CGSize(width: width + 2 * Design.margin, height: Design.above + floorY + Design.below * s)
            let anchorX = width - Design.rightOfAnchor * s

            ZStack(alignment: .topLeading) {
                // Behind the text column, so a machine leaving to the left passes softly behind the chart;
                // a swipe anywhere in the lower half switches machines.
                WasherCarousel(
                    machines: looks,
                    selection: $selection,
                    anchor: CGPoint(x: anchorX + Design.margin, y: Design.above + floorY - Design.anchorRise * s),
                    scale: s,
                    dark: dark,
                    animates: animates,
                    active: active
                )
                .frame(width: frame.width, height: frame.height)
                .offset(x: -Design.margin, y: -Design.above)
                .accessibilityElement()
                .accessibilityLabel("\(machine.label)的三维模型")
                .accessibilityValue(Wording.state(machine.drumState))
                .accessibilityHint(machines.count > 1 ? "向上或向下轻扫以切换设备" : "")
                .accessibilityAdjustableAction { direction in
                    guard machines.count > 1 else { return }
                    let n = machines.count
                    switch direction {
                    case .increment: selection = (selection + 1) % n
                    case .decrement: selection = (selection - 1 + n) % n
                    @unknown default: break
                    }
                }

                MachineColumn(machine: machine, forecast: forecast, loaded: forecastLoaded)
                    .frame(width: column, height: geo.size.height)

                if machines.count > 1 {
                    PageDots(labels: machines.map(\.label), selection: $selection)
                        .position(x: anchorX, y: floorY + 12)
                }
            }
        }
    }
}

/// Which machine, then its idle rate for each hour of the day.
private struct MachineColumn: View {
    let machine: MachineState
    let forecast: Forecast
    /// The week of history has arrived (until then the chart is empty because it is loading, not because data is missing).
    let loaded: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let hour = Calendar.current.component(.hour, from: .now)
        let now = forecast.hours[hour].availability

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(machine.number)
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-1.5)
                    .contentTransition(.numericText())
                Text("号机")
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(height: 60)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(machine.label)
            .accessibilityAddTraits(.isHeader)

            Text("各时段空闲率")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 28)
            Group {
                if let now {
                    Text("近 7 天 · 现在 \(Text(Fmt.percent(now)).fontWeight(.semibold).foregroundStyle(Palette.ink(.busy, dark: scheme == .dark)))")
                } else {
                    Text(!loaded ? "正在加载…" : forecast.hasAny ? "近 7 天" : "数据收集中")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 2)

            HourBars(forecast: forecast, hour: hour)
                .padding(.top, 12)

            HourTicks()
                .frame(height: 14)
                .padding(.top, 6)
        }
        .allowsHitTesting(false)
    }
}

/// Hour labels under the bars, each centred on its own bar: "0 时" starts at the left edge, then 6, 12, 18 and 23.
private struct HourTicks: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let bar = (w - 23 * HourBars.gap) / 24
            ZStack(alignment: .topLeading) {
                Text("0 时")
                ForEach([6, 12, 18, 23], id: \.self) { h in
                    let center = CGFloat(h) * (bar + HourBars.gap) + bar / 2
                    Text("\(h)")
                        .fixedSize()
                        .position(x: min(center, w - 7), y: 7)
                }
            }
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

/// 24 bars, the current hour in full colour and the rest lighter, standing on the floor line.
private struct HourBars: View {
    let forecast: Forecast
    let hour: Int
    @Environment(\.colorScheme) private var scheme

    /// Space between bars; the hour labels use it too, to sit under their bars.
    static let gap: CGFloat = 2

    var body: some View {
        let dark = scheme == .dark
        let light = dark ? Color(red: 0.56, green: 0.69, blue: 1).opacity(0.34) : Palette.water.opacity(0.24)
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: Self.gap) {
                ForEach(0..<24, id: \.self) { h in
                    let a = forecast.hours[h].availability
                    UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                        .fill(h == hour ? Palette.water : light)
                        .frame(height: a.map { max(2, geo.size.height * $0) } ?? 0)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(dark ? 0.18 : 0.12))
                .frame(height: 1)
        }
        .accessibilityElement()
        .accessibilityLabel("各时段空闲率")
        .accessibilityValue(summary)
    }

    private var summary: String {
        var parts: [String] = []
        if let a = forecast.hours[hour].availability { parts.append("现在（\(hour) 时）\(Fmt.percent(a))") }
        if let best = forecast.bestHour() { parts.append("未来 12 小时内 \(best.hour) 时最高（\(Fmt.percent(best.availability))）") }
        return parts.isEmpty ? "暂无足够记录" : parts.joined(separator: "，")
    }
}

private struct PageDots: View {
    let labels: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(labels.indices, id: \.self) { k in
                Button {
                    selection = k
                } label: {
                    Capsule()
                        .fill(k == selection ? Color.primary : Color.primary.opacity(0.25))
                        .frame(width: k == selection ? 16 : 6, height: 6)
                        .frame(width: 22, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("切换到\(labels[k])")
                .accessibilityAddTraits(k == selection ? .isSelected : [])
            }
        }
        .animation(.smooth(duration: 0.3), value: selection)
    }
}

// MARK: - Background

/// A soft gradient, with a glow behind the machine in the colour of its state.
private struct OverviewBackground: View {
    let state: DrumState?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                LinearGradient(
                    stops: dark
                        ? [.init(color: Color(red: 0.10, green: 0.11, blue: 0.13), location: 0),
                           .init(color: Color(red: 0.08, green: 0.09, blue: 0.11), location: 0.48),
                           .init(color: Color(red: 0.05, green: 0.05, blue: 0.07), location: 1)]
                        : [.init(color: Color(red: 0.97, green: 0.97, blue: 0.98), location: 0),
                           .init(color: Color(red: 0.93, green: 0.95, blue: 0.96), location: 0.46),
                           .init(color: Color(red: 0.87, green: 0.90, blue: 0.94), location: 1)],
                    startPoint: .top, endPoint: .bottom)
                glow(Palette.water.opacity(dark ? 0.30 : 0.22), in: size)
                    .opacity(state == .busy ? 1 : 0)
                glow(Palette.fresh.opacity(dark ? 0.24 : 0.20), in: size)
                    .opacity(state == .idle ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.5), value: state)
        }
    }

    /// An ellipse 70% of the width by 40% of the height across, fading out by 72% of the way to its edge,
    /// centred behind the machine. It is drawn as a circle that fades to nothing at its own edge, then squashed.
    private func glow(_ color: Color, in size: CGSize) -> some View {
        let rx = size.width * 0.7 * 0.72, ry = size.height * 0.4 * 0.72
        return RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: rx)
            .frame(width: rx * 2, height: rx * 2)
            .scaleEffect(x: 1, y: ry / rx)
            .position(x: size.width * 0.74, y: size.height * 0.68)
            .allowsHitTesting(false)
    }
}
