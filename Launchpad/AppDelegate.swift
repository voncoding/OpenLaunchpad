import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        OverlayController.shared.prepare()
        HotkeyMonitor.shared.start()

        NotificationCenter.default.addObserver(
            forName: .launchpadHotkeyPressed,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                OverlayController.shared.toggle()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in
                OverlayController.shared.hideIfVisible()
            }
        }

        OverlayController.shared.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        OverlayController.shared.toggle()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

extension Notification.Name {
    static let launchpadHotkeyPressed = Notification.Name("launchpad.hotkeyPressed")
}
