#if DEBUG
import SwiftUI
import WidgetKit

/// Launch with `-gallery` to see the widgets and Live Activity rendered in the app (no Lock Screen needed).
struct WidgetGallery: View {
    @Environment(\.colorScheme) private var scheme

    private var busyEntry: StatusEntry {
        var e = StatusEntry.sample
        e.items[0].state = .busy
        e.items[0].progress = 0.35
        e.items = [
            .init(id: 1, label: "57号机", number: "57", state: .busy, progress: 0.35,
                  startsAt: .now.addingTimeInterval(-13 * 60), endsAt: .now.addingTimeInterval(24 * 60)),
            e.items[1],
        ]
        return e
    }

    private var activity: LaundryActivityAttributes.ContentState {
        .init(building: "前3栋", machines: [
            .init(id: 1, label: "57号机", number: "57", state: .idle, progress: nil, startedAt: nil, endsAt: nil),
            .init(id: 2, label: "58号机", number: "58", state: .busy, progress: 0.62,
                  startedAt: .now.addingTimeInterval(-22 * 60), endsAt: .now.addingTimeInterval(11 * 60)),
        ], updatedAt: .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    tile(StatusEntry.sample, family: .systemSmall, width: 170, height: 170)
                    tile(busyEntry, family: .systemSmall, width: 170, height: 170)
                }
                tile(StatusEntry.sample, family: .systemMedium, width: 360, height: 170)
                tile(busyEntry, family: .systemMedium, width: 360, height: 170)

                HStack(spacing: 14) {
                    StatusWidgetView(entry: .sample, familyOverride: .accessoryCircular)
                        .frame(width: 72, height: 72)
                    StatusWidgetView(entry: busyEntry, familyOverride: .accessoryCircular)
                        .frame(width: 72, height: 72)
                    StatusWidgetView(entry: busyEntry, familyOverride: .accessoryRectangular)
                        .frame(width: 160, height: 72)
                }
                .padding(14)
                .background(.black.opacity(0.35), in: .rect(cornerRadius: 20))
                .environment(\.colorScheme, .dark)

                LockScreenActivity(state: activity)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 26))
                    .environment(\.colorScheme, .dark)
                // A rough stand-in for the expanded island; the real one is laid out by the system.
                VStack(spacing: 10) {
                    HStack(alignment: .top) {
                        IslandExpandedLeading(state: activity, isStale: false)
                        Spacer()
                        IslandExpandedTrailing(state: activity, isStale: false)
                    }
                    IslandExpandedBottom(state: activity, isStale: false)
                }
                .padding(16)
                .background(.black, in: .rect(cornerRadius: 40))
                .environment(\.colorScheme, .dark)
            }
            .padding(16)
        }
        .background(LinearGradient(colors: [.indigo, .teal], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func tile(_ entry: StatusEntry, family: WidgetFamily, width: CGFloat, height: CGFloat) -> some View {
        StatusWidgetView(entry: entry, familyOverride: family)
            .padding(16)
            .frame(width: width, height: height)
            .background(WidgetBackdrop(entry: entry))
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
    }
}
#endif
