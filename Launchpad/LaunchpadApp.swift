import SwiftUI

@main
struct LaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("launchpad.showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra("启动台", systemImage: "square.grid.3x3.fill", isInserted: Binding(
            get: { showMenuBarIcon },
            set: { visible in
                // Tahoe writes the insertion state back while reconciling menus.
                // Rewriting the same AppStorage value causes a menu update loop.
                if showMenuBarIcon != visible { showMenuBarIcon = visible }
            }
        )) {
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
