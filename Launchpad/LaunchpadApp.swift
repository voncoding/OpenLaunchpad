import SwiftUI

@main
struct LaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("启动台", systemImage: "square.grid.3x3.fill") {
            Button("打开启动台") {
                OverlayController.shared.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            SettingsLink {
                Text("设置…")
            }

            Divider()

            Button("退出启动台") {
                NSApp.terminate(nil)
            }
        }

        Settings {
            SettingsView()
                .environment(OverlayController.shared.store)
        }
    }
}
