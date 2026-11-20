import ActivityKit
import SwiftUI
import WidgetKit

struct LaundryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LaundryActivityAttributes.self) { context in
            LockScreenActivity(state: context.state, isStale: context.isStale)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(state.building)洗衣房")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(context.isStale ? "数据已过时" : ActivityWords.headline(state))
                            .font(.headline)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(ActivityWords.detail(state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ForEach(state.machines.prefix(3)) { m in
                            ActivityRow(machine: m, updatedAt: state.updatedAt)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "washer")
                    .foregroundStyle(ActivityWords.tint(state))
            } compactTrailing: {
                ActivityWords.trailing(state)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ActivityWords.tint(state))
                    .frame(maxWidth: 48)
            } minimal: {
                Text("\(state.idleCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ActivityWords.tint(state))
            }
            .keylineTint(ActivityWords.tint(state))
        }
    }
}
