import SwiftUI
import UIKit
import UserNotifications

struct SettingsSheet: View {
    /// Show a 完成 button; off when this is a tab rather than a sheet.
    var showsDone = true

    @Environment(LaundryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var draftURL = ""
    @State private var draftToken = ""
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    Toggle("在锁定屏幕和灵动岛显示", isOn: $store.activityEnabled)
                    if store.activityEnabled {
                        DatePicker("开始时间", selection: timeBinding(\.activityStartMinutes), displayedComponents: .hourAndMinute)
                        DatePicker("结束时间", selection: timeBinding(\.activityEndMinutes), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("实时活动")
                } footer: {
                    Text("在设定时段内打开本应用后，锁定屏幕和灵动岛将持续显示各设备的状态及剩余时间。")
                }

                Section {
                    LabeledContent("通知权限") {
                        Text(statusText)
                            .foregroundStyle(notificationStatus == .denied ? Palette.ember : .secondary)
                    }
                    if notificationStatus == .denied {
                        Button("前往系统设置") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("可通过概览页左上角的提醒按钮或设备详情设置完成提醒；所有设备均在运行时，还可设置空闲提醒。")
                }

                Section {
                    TextField("服务器地址", text: $draftURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("访问令牌", text: $draftToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存并重新连接") {
                        store.saveConfig(base: draftURL, token: draftToken)
                        Task { await store.refresh() }
                    }
                    .disabled(draftURL == store.baseURL && draftToken == store.token)
                    Button("恢复默认设置", role: .destructive) {
                        store.resetConfig()
                        draftURL = store.baseURL
                        draftToken = store.token
                        Task { await store.refresh() }
                    }
                } header: {
                    Text("服务器")
                } footer: {
                    Text("桌面小组件始终使用默认服务器。")
                }

                Section("数据") {
                    LabeledContent("最近更新", value: store.ageText)
                    LabeledContent("刷新频率", value: "每 5 秒（应用打开时）")
                    LabeledContent("历史记录", value: "最近 7 天")
                    if let error = store.error {
                        LabeledContent("最近错误", value: error)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
            }
            .onAppear {
                draftURL = store.baseURL
                draftToken = store.token
            }
            .task {
                notificationStatus = await Notifier.shared.status()
            }
        }
    }

    private var statusText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "已允许"
        case .denied: return "已关闭"
        default: return "尚未设置"
        }
    }

    private func timeBinding(_ key: ReferenceWritableKeyPath<LaundryStore, Int>) -> Binding<Date> {
        Binding {
            let m = store[keyPath: key]
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            store[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}
