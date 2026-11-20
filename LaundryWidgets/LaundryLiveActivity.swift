import ActivityKit
import SwiftUI
import WidgetKit

struct LaundryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LaundryActivityAttributes.self) { context in
            LockScreenActivity(state: context.state, isStale: context.isStale)
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(context.state.link)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(state: state, isStale: stale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(state: state, isStale: stale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(state: state, isStale: stale)
                }
            } compactLeading: {
                IslandCompactLeading(state: state, isStale: stale)
            } compactTrailing: {
                IslandCompactTrailing(state: state, isStale: stale)
            } minimal: {
                IslandMinimal(state: state, isStale: stale)
            }
            .keylineTint(state.reading(isStale: stale).keyline)
            .widgetURL(state.link)
        }
    }
}
