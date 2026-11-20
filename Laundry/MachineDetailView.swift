import SwiftUI

struct MachineDetailView: View {
    let id: Int
    @Environment(LaundryStore.self) private var store

    var body: some View {
        Group {
            if let machine = store.machine(id: id) {
                content(machine)
            } else {
                ContentUnavailableView("未找到该设备", systemImage: "washer",
                                       description: Text("该设备可能已从服务器的设备列表中移除。"))
            }
        }
    }

    private func content(_ m: MachineState) -> some View {
        List {
            Section {
                StatusBlock(machine: m, endsAt: store.endsAt(m))
            }

            if m.isBusy {
                Section {
                    reminderRows(m)
                } footer: {
                    Text("设备变为空闲时将立即通知；如未能及时获取状态，将在预计完成时间提醒。")
                }
            }

            Section("近 24 小时") {
                VStack(alignment: .leading, spacing: 6) {
                    UsageStrip(machine: m, windowMinutes: store.windowMinutes)
                        .frame(height: 22)
                    HourAxis(windowStart: store.windowStart, windowMinutes: store.windowMinutes)
                }
                .padding(.vertical, 6)
                LabeledContent("洗涤次数", value: "\(m.sessions) 次")
                LabeledContent("平均洗涤时长", value: m.averageCycle.map(Fmt.duration) ?? "暂无数据")
                LabeledContent("使用率", value: m.utilization.map(Fmt.percent) ?? "暂无数据")
                LabeledContent("最长连续空闲", value: m.longestIdle > 0 ? Fmt.duration(m.longestIdle) : "暂无数据")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(m.label)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.smooth, value: m.drumState)
    }

    @ViewBuilder private func reminderRows(_ m: MachineState) -> some View {
        if let date = store.reminders[m.id] {
            Label("已设置完成提醒（约 \(Fmt.time(date))）", systemImage: "bell.badge")
            Button("取消提醒", role: .destructive) {
                Task { await store.toggleReminder(for: m) }
            }
        } else {
            Button {
                Task { await store.toggleReminder(for: m) }
            } label: {
                Label("完成时通知我", systemImage: "bell")
            }
        }
    }
}

private struct StatusBlock: View {
    let machine: MachineState
    let endsAt: Date?

    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var bigSize: CGFloat = 48

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                StatusPill(state: machine.drumState)
                main
            }
            Spacer(minLength: 0)
            MachineIcon(machine: machine)
                .frame(width: 64, height: 64)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var main: some View {
        switch machine.drumState {
        case .busy:
            if let left = machine.remainingMinutes {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(left)")
                            .font(.system(size: bigSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        Text("分钟")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Palette.ink(.busy, dark: scheme == .dark))
                    Text([machine.isSpinning ? "脱水阶段" : nil, endsAt.map(Wording.finish)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let p = machine.progress {
                    VStack(alignment: .leading, spacing: 6) {
                        CycleBar(progress: p)
                        Text("已运行 \(Fmt.duration(machine.currentRunMinutes)) · 预计全程 \(Fmt.duration(machine.currentRunMinutes + left))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            } else {
                Text("运行中")
                    .font(.title.weight(.bold))
                Text("剩余时间暂不可知")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .idle:
            Text("可立即使用")
                .font(.title.weight(.bold))
            Text(Wording.idleFor(machine.currentRunMinutes))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .offline:
            Text("暂不可用")
                .font(.title.weight(.bold))
            Text(Wording.offlineDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
