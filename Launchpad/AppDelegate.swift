import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appDirectoryMonitor = AppDirectoryMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = launchEvent?.eventID == kAEOpenApplication
            && launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        NSApp.setActivationPolicy(.regular)
        appDirectoryMonitor.start(roots: AppScanner.applicationRoots) {
            OverlayController.shared.store.invalidateCatalog()
        }
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

        if !launchedAtLogin {
            OverlayController.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        OverlayController.shared.toggle()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        appDirectoryMonitor.stop()
    }
}

extension Notification.Name {
    static let launchpadHotkeyPressed = Notification.Name("launchpad.hotkeyPressed")
}
