import SwiftUI

struct SettingsView: View {
    @Environment(LaundryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var base = ""
    @State private var token = ""

    var body: some View {
        @Bindable var store = store

        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("设置")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Palette.secondary)
                                .frame(width: 30, height: 30)
                                .background(.white.opacity(0.6), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        field(title: "服务器地址", text: $base, secure: false)
                        field(title: "访问令牌", text: $token, secure: true)
                    }
                    .padding(16)
                    .glassSurface(corner: 22)

                    Button {
                        store.saveConfig(base: base, token: token)
                        dismiss()
                        Task { await store.refresh() }
                    } label: {
                        Text("保存并刷新")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Palette.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    activityCard(store: store)

                    Button("恢复默认") {
                        base = Config.defaultBaseURL
                        token = Config.defaultToken
                        store.resetConfig()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
                .padding(22)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.height(640)])
        .presentationBackground(.clear)
        .onAppear {
            base = store.baseURL
            token = store.token
        }
    }

    private func activityCard(store: LaundryStore) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("实时活动")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("锁屏显示两台洗衣机的状态")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.tertiary)
                }
                Spacer()
                Toggle("", isOn: $store.activityEnabled)
                    .labelsHidden()
                    .tint(Palette.jade)
            }

            if store.activityEnabled {
                HStack(spacing: 12) {
                    timePicker("开始", $store.activityStartMinutes)
                    timePicker("结束", $store.activityEndMinutes)
                }

                Text("时间段内自动开启。应用打开时每 5 秒更新；退回后台后保留最后一次状态，再次打开即继续。灵动岛只显示一个圆点和空闲数量。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.tertiary)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .glassSurface(corner: 22)
    }

    private func timePicker(_ title: String, _ minutes: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 0)
            DatePicker("", selection: timeBinding(minutes), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Palette.jade)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60,
                                      minute: minutes.wrappedValue % 60,
                                      second: 0,
                                      of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func field(title: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.tertiary)
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                        .keyboardType(.URL)
                }
            }
            .font(.system(size: 16))
            .foregroundStyle(Palette.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
    }
}
