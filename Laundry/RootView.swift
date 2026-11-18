import SwiftUI

struct RootView: View {
    @Environment(LaundryStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AuroraBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        header

                        if let error = store.error, !store.machines.isEmpty {
                            ErrorPill(message: error) {
                                Task { await store.refresh() }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        summary

                        if store.machines.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 12) {
                                ForEach(store.machines) { machine in
                                    NavigationLink(value: machine) {
                                        MachineRowCard(
                                            machine: machine,
                                            windowStart: store.windowStart,
                                            minutes: store.windowMinutes,
                                            showsData: store.coverage >= 0.01
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .animation(.snappy(duration: 0.35), value: store.machines)

                            Text("前台 5 秒刷新 · 历史保留 7 天")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.tertiary.opacity(0.9))
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MachineState.self) { machine in
                MachineDetailView(machineID: machine.id)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.liveLoop()
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-openFirst") else { return }
            for _ in 0..<30 {
                if let first = store.machines.first {
                    path.append(first)
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        .animation(.snappy(duration: 0.3), value: store.error)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("洗衣")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("本部前3栋 · \(store.machines.count) 台")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.secondary)
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.error == nil && !store.isStale ? Palette.mint : Palette.alert)
                        .frame(width: 6, height: 6)
                    Text(store.ageText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.tertiary)
                }
                .foregroundStyle(Palette.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.white.opacity(0.55), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(store.isLoading)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.55), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("可用洗衣机")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(store.idleCount)")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(store.idleCount)))
                Text("台可用")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .padding(.bottom, 10)
                Spacer(minLength: 0)
                Text("使用中 \(store.busyCount) 台")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(store.busyCount > 0 ? Palette.busy : Palette.tertiary)
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(corner: 28)
        .animation(.snappy(duration: 0.4), value: store.idleCount)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if store.isLoading {
                ProgressView().tint(Palette.jade)
            } else {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Palette.tertiary)
                Text(store.error ?? "暂无数据")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                HStack(spacing: 14) {
                    Button("重新加载") {
                        Task { await store.refresh() }
                    }
                    .foregroundStyle(Palette.jade)
                    Button("连接设置") {
                        showSettings = true
                    }
                    .foregroundStyle(Palette.secondary)
                }
                .font(.system(size: 14, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct MachineRowCard: View {
    let machine: MachineState
    let windowStart: Int
    let minutes: Int
    let showsData: Bool

    private let axisHours = [0, 1, 2, 3]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(machine.label)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(machine.isIdle ? Palette.jade : Palette.busy)
                Circle()
                    .fill(machine.isIdle ? Palette.mint : Palette.busy)
                    .frame(width: 7, height: 7)
                Spacer(minLength: 0)
                Text(machine.statusText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(machine.isIdle ? Palette.jade : Palette.busy)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.tertiary.opacity(0.8))
            }

            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.tertiary)

            HistoryBar(runs: machine.runs, minutes: minutes, height: 10,
                       showsData: showsData, segments: 3)
                .padding(.top, 2)

            HStack(spacing: 0) {
                ForEach(axisHours, id: \.self) { hour in
                    Text(Fmt.hourLabel(windowStart + hour * 3600))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiary)
                    if hour != axisHours.last { Spacer() }
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(corner: 22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(machine.isIdle ? Palette.jade.opacity(0.05) : Palette.busy.opacity(0.03))
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var subtitle: String {
        if machine.idleMinutes == 0 && machine.sessions == 0 {
            return "3h 暂无记录"
        }
        var parts = ["3h 空闲 \(Fmt.duration(machine.idleMinutes))"]
        if machine.sessions > 0 {
            parts.append("启动 \(machine.sessions) 次")
        }
        return parts.joined(separator: " · ")
    }
}
