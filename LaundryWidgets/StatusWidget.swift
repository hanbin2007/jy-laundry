import SwiftUI
import WidgetKit

// MARK: - Timeline

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        if context.isPreview { completion(.sample); return }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        Task {
            let entry = await load()
            var entries = [entry]
            let ends = entry.items.compactMap(\.endsAt)
                .filter { $0 > entry.date && $0 < entry.date.addingTimeInterval(2 * 3600) }
                .sorted()
            for end in ends { entries.append(entry.advanced(to: end)) }

            let soon = ends.first.map { $0.addingTimeInterval(90) } ?? .distantFuture
            let next = min(entry.date.addingTimeInterval(entry.failed ? 15 * 60 : 10 * 60), soon)
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }

    private func load() async -> StatusEntry {
        guard let url = URL(string: Config.defaultBaseURL) else { return .failure(.now) }
        do {
            let snap = try await HistoryAPI(baseURL: url, token: Config.defaultToken).fetch(hours: 1, live: false)
            let fetched = snap.fetchedAt
            let items = snap.sortedMachines.map {
                StatusEntry.Item(id: $0.id, label: $0.label, number: $0.number, state: $0.drumState,
                                 progress: $0.progress, endsAt: $0.cycleEnd(fetchedAt: fetched))
            }
            // The server keeps answering from its database even if it stopped reading the machines.
            let stale = !(snap.lastPoll?.ok ?? false) || Date().timeIntervalSince(fetched) > 10 * 60
            return StatusEntry(date: .now, building: snap.machines.first?.building ?? "洗衣房", items: items,
                               failed: false, stale: stale, updatedAt: snap.lastPoll == nil ? nil : fetched)
        } catch {
            return .failure(.now)
        }
    }
}

// MARK: - Widget

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LaundryStatus", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop(entry: entry) }
        }
        .configurationDisplayName("洗衣房")
        .description("显示各设备的状态及剩余时间。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemMedium) {
    StatusWidget()
} timeline: {
    StatusEntry.sample
}
