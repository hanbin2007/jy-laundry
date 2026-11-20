import SwiftUI
import UIKit

enum AppTab: Hashable {
    case overview, records, settings
}

/// Three tabs: the overview of the machine in view, the records of every machine, and settings.
/// Polling, the "machine freed" haptic and the notification-permission alert live here, so they
/// work whichever tab is open.
struct RootView: View {
    @Environment(LaundryStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var tab: AppTab = .overview

    var body: some View {
        TabView(selection: $tab) {
            Tab("概览", systemImage: "washer", value: AppTab.overview) {
                OverviewView()
            }
            Tab("记录", systemImage: "chart.bar.xaxis", value: AppTab.records) {
                HomeView()
            }
            Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                SettingsSheet(showsDone: false)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.liveLoop()
        }
        .sensoryFeedback(.success, trigger: store.freedTick)
        // A tap on a widget or the Live Activity lands on the overview, on the machine it was about.
        .onOpenURL { url in
            guard url.scheme == "laundry" else { return }
            tab = .overview
            store.linkedMachineID = DeepLink.machineID(in: url)
        }
        .alert("未开启通知", isPresented: Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.notice = nil } }
        )) {
            Button("前往设置") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(store.notice ?? "")
        }
        #if DEBUG
        .onAppear {
            switch Demo.tab {
            case "records": tab = .records
            case "settings": tab = .settings
            default: if Demo.showsSettings { tab = .settings }
            }
        }
        #endif
    }
}
