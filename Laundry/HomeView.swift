import SwiftUI

/// The 记录 tab: every machine at a glance, then the last 24 hours and the hourly forecast for the whole room.
struct HomeView: View {
    @Environment(LaundryStore.self) private var store
    @Namespace private var zoom

    @State private var path: [Int] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        Summary()

                        MachineList(zoom: zoom) { path.append($0) }

                        if store.snapshot != nil {
                            UsageCard().id("usage")
                            ForecastCard().id("forecast")
                        }

                        Text("应用打开时每 5 秒自动刷新 · 数据来源：\(store.serverHost)")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                #if DEBUG
                .task(id: store.snapshot != nil) {
                    guard store.snapshot != nil else { return }
                    if let target = Demo.scroll {
                        try? await Task.sleep(for: .milliseconds(300))
                        proxy.scrollTo(target, anchor: .top)
                    }
                    if let id = Demo.open, path.isEmpty { path.append(id) }
                }
                #endif
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("记录")
            .refreshable { await store.refresh() }
            .navigationDestination(for: Int.self) { id in
                MachineDetailView(id: id)
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
            }
        }
    }
}

// MARK: - Summary

/// The answer first: how many machines are free, and when the next one will be.
private struct Summary: View {
    @Environment(LaundryStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var countSize: CGFloat = 54

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.snapshot == nil {
                Text(store.error == nil ? "正在获取数据…" : "无法连接服务器")
                    .font(.title.weight(.bold))
                if let error = store.error {
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Button("重试", systemImage: "arrow.clockwise") {
                        Task { await store.refresh() }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) { countLine }
                    VStack(alignment: .leading, spacing: 2) { countLine }
                }
                .accessibilityElement(children: .combine)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
            }

            ConnectionLine(store: store)
                .padding(.top, 2)

            if store.allBusy {
                AnyReminderButton()
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 4)
        .animation(.snappy, value: store.idleCount)
        .animation(.snappy, value: store.allBusy)
    }

    @ViewBuilder private var countLine: some View {
        Text("\(store.idleCount)")
            .font(.system(size: countSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(store.idleCount > 0 ? Palette.ink(.idle, dark: scheme == .dark) : .primary)
            .contentTransition(.numericText())
        Text("台空闲")
            .font(.title2.weight(.semibold))
        Text("共 \(store.total) 台")
            .font(.title3)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private var detail: String {
        let all = store.machines
        guard !all.isEmpty else { return "服务器未返回任何设备" }
        let offline = all.filter { !$0.isIdle && !$0.isBusy }.count
        var text: String

        if store.idleCount == all.count {
            text = "所有设备均可使用"
        } else if let next = store.soonestBusy, let end = store.endsAt(next), let m = next.remainingMinutes {
            text = store.idleCount > 0
                ? "\(next.label)\(Wording.finish(end))"
                : "最早于 \(Fmt.time(end)) 空闲（\(m <= 1 ? "即将完成" : "约 \(m) 分钟后")）"
        } else if store.busyCount > 0 {
            text = "运行中设备的剩余时间暂不可知"
        } else {
            text = "暂无可用设备"
        }
        if offline > 0, offline < all.count { text += "；\(offline) 台设备不可用" }
        return text
    }
}

private struct AnyReminderButton: View {
    @Environment(LaundryStore.self) private var store

    var body: some View {
        let on = store.hasReminder(LaundryStore.anyMachine)
        Group {
            if on {
                Button {
                    Task { await store.toggleAnyReminder() }
                } label: {
                    Label("已设置空闲提醒，轻点取消", systemImage: "bell.badge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await store.toggleAnyReminder() }
                } label: {
                    Label("有设备空闲时通知我", systemImage: "bell")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
        .tint(Palette.water)
        .sensoryFeedback(.impact(weight: .light), trigger: on)
    }
}

// MARK: - Machines

private struct MachineList: View {
    @Environment(LaundryStore.self) private var store
    let zoom: Namespace.ID
    let open: (Int) -> Void

    var body: some View {
        let machines = store.machines
        SectionCard(title: "设备", padding: 0) {
            if machines.isEmpty {
                Text(store.snapshot == nil ? "正在加载设备列表…" : "暂无设备")
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(machines.enumerated()), id: \.element.id) { index, m in
                        Button { open(m.id) } label: {
                            MachineRow(machine: m, endsAt: store.endsAt(m), reminded: store.hasReminder(m.id))
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: m.id, in: zoom)
                        if index < machines.count - 1 {
                            Divider().padding(.leading, 78)
                        }
                    }
                }
            }
        }
    }
}

private struct MachineRow: View {
    let machine: MachineState
    let endsAt: Date?
    let reminded: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 14) {
            MachineIcon(machine: machine)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(machine.label)
                        .font(.headline)
                    if reminded {
                        Image(systemName: "bell.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.water)
                            .accessibilityLabel("已设置提醒")
                    }
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                if let p = machine.progress {
                    CycleBar(progress: p)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            trailing

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看设备详情")
    }

    @ViewBuilder private var trailing: some View {
        if machine.isBusy, let m = machine.remainingMinutes {
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(m)")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text("分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Palette.ink(.busy, dark: scheme == .dark))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Wording.remaining(m))
        } else {
            StatusPill(state: machine.drumState)
        }
    }

    private var detail: String {
        switch machine.drumState {
        case .busy:
            let phase = machine.isSpinning ? "脱水阶段" : "运行中"
            if let endsAt { return "\(phase) · \(Wording.finish(endsAt))" }
            return "运行中，剩余时间未知"
        case .idle:
            return Wording.idleFor(machine.currentRunMinutes)
        case .offline:
            return Wording.offlineDetail
        }
    }
}
