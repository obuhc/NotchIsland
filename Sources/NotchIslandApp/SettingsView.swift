import SwiftUI

/// 设置面板：轮询间隔 + 开机启动 + Claude 官方用量授权。
struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var showConsent = false

    var body: some View {
        Form {
            Section("刷新") {
                Picker("轮询间隔", selection: $settings.refreshInterval) {
                    Text("5 秒").tag(5.0)
                    Text("10 秒").tag(10.0)
                    Text("30 秒").tag(30.0)
                    Text("60 秒").tag(60.0)
                }
            }

            Section("启动") {
                Toggle("开机自动启动", isOn: $settings.launchAtLogin)
            }

            Section("Claude 官方用量") {
                Toggle("启用官方用量（需授权）", isOn: Binding(
                    get: { settings.claudeOfficialEnabled },
                    set: { wantOn in
                        if wantOn && !settings.claudeOfficialEnabled {
                            showConsent = true                 // 开启需先确认授权
                        } else {
                            settings.claudeOfficialEnabled = wantOn   // 关闭无需确认
                        }
                    }
                ))
                Text("开启后读取本机 Claude 登录凭证，调用 Anthropic 官方用量接口获取你账号的精确 5h / 周限额。关闭时 Claude 仅用 ccusage 本地估算。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 320)
        .alert("授权读取你的 Claude 用量？", isPresented: $showConsent) {
            Button("授权并启用") { settings.claudeOfficialEnabled = true }
            Button("取消", role: .cancel) { }
        } message: {
            Text("将读取本机 Claude 登录凭证（OAuth token，首次可能弹系统钥匙串授权框），调用 Anthropic 官方用量接口获取你账号的 5h / 周限额。数据仅本地使用、不外传，可随时关闭。")
        }
    }
}
