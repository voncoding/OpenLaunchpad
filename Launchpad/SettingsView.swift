import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(LaunchpadStore.self) private var store
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled

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
            }

            Section("关于") {
                LabeledContent("应用数") {
                    Text("\(store.apps.count)")
                }
                Text("扫描 /Applications、系统应用和用户应用文件夹。支持中文名、拼音和首字母搜索。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
        .onAppear {
            launchesAtLogin = SMAppService.mainApp.status == .enabled
            OverlayController.shared.hideIfVisible()
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { launchesAtLogin },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchesAtLogin = SMAppService.mainApp.status == .enabled
                } catch {
                    launchesAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        )
    }
}
