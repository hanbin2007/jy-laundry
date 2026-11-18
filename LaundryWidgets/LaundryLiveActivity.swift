import ActivityKit
import SwiftUI
import WidgetKit

private enum WPalette {
    static let ink = Color(hex: 0x14171A)
    static let secondary = Color(hex: 0x8A9098)
    static let tertiary = Color(hex: 0xAFB4BA)
    static let jade = Color(hex: 0x0F7A57)
    static let mint = Color(hex: 0x3EC492)
    static let busy = Color(hex: 0xC0453E)
    static let surface = Color.white
    static let islandBusy = Color(hex: 0xF07A72)
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

struct LaundryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LaundryActivityAttributes.self) { context in
            LockScreenContent(state: context.state)
                .activityBackgroundTint(WPalette.surface)
                .activitySystemActionForegroundColor(WPalette.jade)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: "washer.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WPalette.mint)
                        Text("洗衣")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(idleText(context.state))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(context.state.idleCount > 0 ? WPalette.mint : WPalette.islandBusy)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 7) {
                        ForEach(context.state.machines) { machine in
                            IslandTile(machine: machine)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
                }
            } compactLeading: {
                Text("\(context.state.idleCount)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(context.state.idleCount > 0 ? WPalette.mint : WPalette.islandBusy)
            } compactTrailing: {
                Text("台空闲")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            } minimal: {
                Text("\(context.state.idleCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(context.state.idleCount > 0 ? WPalette.mint : WPalette.islandBusy)
            }
            .keylineTint(WPalette.jade)
        }
    }

    private func idleText(_ state: LaundryActivityAttributes.ContentState) -> String {
        state.idleCount > 0 ? "\(state.idleCount) 台空闲" : "全部使用中"
    }
}

private struct LockScreenContent: View {
    let state: LaundryActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(state.idleCount > 0 ? WPalette.mint : WPalette.busy)
                    .frame(width: 6, height: 6)
                Text("洗衣")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(WPalette.ink.opacity(0.7))
                Spacer(minLength: 0)
                Text(state.updatedAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WPalette.tertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(state.idleCount)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(state.idleCount > 0 ? WPalette.jade : WPalette.busy)
                Text("台空闲")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WPalette.secondary)
                    .padding(.bottom, 4)
            }

            HStack(spacing: 8) {
                ForEach(state.machines) { machine in
                    LockTile(machine: machine)
                }
            }
        }
        .padding(16)
    }
}

private struct LockTile: View {
    let machine: LaundryActivityAttributes.Machine

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(machine.label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(WPalette.ink.opacity(0.6))
            }
            Text(statusText)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var tint: Color { machine.idle ? WPalette.jade : WPalette.busy }
    private var statusText: String {
        if machine.idle { return "空闲" }
        return machine.remaining.isEmpty ? "使用中" : "剩 \(machine.remaining)"
    }
}

private struct IslandTile: View {
    let machine: LaundryActivityAttributes.Machine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(machine.label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Text(statusText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(machine.idle ? WPalette.mint : WPalette.islandBusy)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private var statusText: String {
        if machine.idle { return "空闲" }
        return machine.remaining.isEmpty ? "使用中" : "剩 \(machine.remaining)"
    }
}
