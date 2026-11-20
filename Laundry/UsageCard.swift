import SwiftUI

/// The last 24 hours as one horizontal bar per machine on a shared clock axis.
/// Press and hold, then drag, to read the state at any moment.
struct UsageCard: View {
    @Environment(LaundryStore.self) private var store
    @State private var scrubX: CGFloat?

    var body: some View {
        let machines = store.machines
        let sessions = machines.map(\.sessions).reduce(0, +)
        let busy = machines.map(\.busyMinutes).reduce(0, +)
        let observed = machines.map(\.observedMinutes).reduce(0, +)

        SectionCard(title: "近 24 小时使用记录") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 24) {
                    figure("\(sessions)", unit: "次", caption: "洗涤次数")
                    figure(observed > 0 ? "\(Int((Double(busy) / Double(observed) * 100).rounded()))" : "—",
                           unit: observed > 0 ? "%" : "", caption: "平均使用率")
                }

                GeometryReader { geo in
                    let width = geo.size.width
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(machines) { m in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                UsageStrip(machine: m, windowMinutes: store.windowMinutes)
                                    .frame(height: 18)
                            }
                        }
                        HourAxis(windowStart: store.windowStart, windowMinutes: store.windowMinutes)
                    }
                    .overlay(alignment: .topLeading) {
                        if let x = scrubX { scrubOverlay(x: x, width: width, machines: machines) }
                    }
                    .contentShape(.rect)
                    .gesture(scrub(width: width))
                }
                .frame(height: CGFloat(machines.count) * 40 + 18)
                .sensoryFeedback(.selection, trigger: scrubX.map { Int($0 / 8) })

                HStack(spacing: 16) {
                    legend(Palette.water, "运行中")
                    legend(Palette.fresh.opacity(0.55), "空闲")
                    legend(Color(.tertiarySystemFill), "无记录")
                    Spacer(minLength: 0)
                    Text("长按可查看具体时刻")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func figure(_ value: String, unit: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            Text(text)
        }
    }

    private func scrub(width: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                let x = drag?.location.x ?? scrubX ?? width
                scrubX = min(width - 1, max(0, x))
            }
            .onEnded { _ in withAnimation(.smooth) { scrubX = nil } }
    }

    private func scrubOverlay(x: CGFloat, width: CGFloat, machines: [MachineState]) -> some View {
        let offset = Int(x / max(1, width) * CGFloat(store.windowMinutes))
        let epoch = store.windowStart + offset * 60
        let lines = machines.map { m -> String in
            let s = m.state(at: offset)
            return "\(m.label)：\(s == 20 ? "运行中" : s == 10 ? "空闲" : "无记录")"
        }
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.primary.opacity(0.7))
                .frame(width: 1.5, height: CGFloat(machines.count) * 40)
                .offset(x: x)
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.clock(epoch)).font(.caption.weight(.bold)).monospacedDigit()
                ForEach(lines, id: \.self) { Text($0).font(.caption2) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .rect(cornerRadius: 8))
            .fixedSize()
            .offset(x: x > width / 2 ? x - 126 : x + 8, y: -4)
        }
        .allowsHitTesting(false)
    }
}

/// One machine's history as a flat bar, oldest on the left.
struct UsageStrip: View {
    let machine: MachineState
    let windowMinutes: Int
    var cornerRadius: CGFloat = 4

    var body: some View {
        Canvas { ctx, size in
            let bar = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius, style: .continuous)
            ctx.fill(bar, with: .color(Color(.tertiarySystemFill)))
            var inner = ctx
            inner.clip(to: bar)
            let scale = size.width / CGFloat(max(1, windowMinutes))
            for run in machine.runs where run.count == 3 && run[2] != -1 {
                let rect = CGRect(x: CGFloat(run[0]) * scale, y: 0,
                                  width: max(1, CGFloat(run[1]) * scale), height: size.height)
                inner.fill(Path(rect), with: .color(run[2] == 20 ? Palette.water : Palette.fresh.opacity(0.55)))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(machine.label)近 24 小时")
        .accessibilityValue("洗涤 \(machine.sessions) 次，使用率 \(machine.utilization.map(Fmt.percent) ?? "未知")")
    }
}

/// Clock labels at 00, 06, 12 and 18 o'clock, placed where those times fall in the window.
struct HourAxis: View {
    let windowStart: Int
    let windowMinutes: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(marks, id: \.self) { epoch in
                    let x = CGFloat(epoch - windowStart) / 60 / CGFloat(max(1, windowMinutes)) * w
                    Text(Fmt.clock(epoch))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: min(max(x, 16), w - 16), y: 7)
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private var marks: [Int] {
        let end = windowStart + windowMinutes * 60
        var out: [Int] = []
        var t = windowStart - windowStart % 3600 + 3600
        while t < end {
            if Fmt.minuteOfDay(t) % 360 == 0 { out.append(t) }
            t += 3600
        }
        return out
    }
}
