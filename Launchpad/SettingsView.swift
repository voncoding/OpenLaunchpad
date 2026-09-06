import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(LaunchpadStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("快捷键") {
                LabeledContent("打开启动台") {
                    Text("⌥⌘L")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text("也可以点击程序坞图标、菜单栏网格图标，或在键盘上按 Escape 关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("外观") {
                LabeledContent("网格") {
                    Text("\(store.columns) × \(store.rows)")
                        .foregroundStyle(.secondary)
                }
                Text("会按当前屏幕大小自动排布，接近原来的启动台。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("启动") {
                Toggle("登录时启动启动台", isOn: loginBinding)
                Text("登录后会在菜单栏常驻，不会自动弹出网格。点击程序坞图标或按 ⌥⌘L 即可打开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if loginStatus == .requiresApproval {
                    Text("还需要在系统设置中允许登录时启动。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("打开登录项设置") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }

            Section("关于") {
                LabeledContent("应用数") {
                    Text("\(store.appCatalog.count)")
                }
                Text("扫描 /Applications、系统应用和用户应用文件夹。支持中文名、拼音和首字母搜索。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
        .onAppear {
            loginStatus = SMAppService.mainApp.status
            OverlayController.shared.hide()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                loginStatus = SMAppService.mainApp.status
            }
        }
        .alert("无法更改登录启动", isPresented: Binding(
            get: { loginError != nil },
            set: { if !$0 { loginError = nil } }
        )) {
            Button("好", role: .cancel) { loginError = nil }
        } message: {
            Text(loginError ?? "")
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginStatus == .enabled || loginStatus == .requiresApproval },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    loginStatus = SMAppService.mainApp.status
                } catch {
                    loginStatus = SMAppService.mainApp.status
                    loginError = error.localizedDescription
                }
            }
        )
    }
}
