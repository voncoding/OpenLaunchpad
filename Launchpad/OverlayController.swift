import AppKit
import Carbon.HIToolbox
import SwiftUI

final class LaunchpadWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class OverlayController {
    static let shared = OverlayController()

    let store = LaunchpadStore()
    weak var pagerView: LaunchpadPagerView?

    private var window: LaunchpadWindow?
    private var localMonitor: Any?
    private var isVisible = false
    private var ignoreHideUntil = Date.distantPast

    private init() {}

    func prepare() {
        store.reload()
    }

    var overlayVisible: Bool { isVisible }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let screen = Self.screenUnderCursor() ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        store.resetForPresentation()
        store.reload()
        if let screen {
            let dockHeight = max(screen.visibleFrame.minY - screen.frame.minY, 0)
            let menuHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 0)
            store.updateLayout(
                for: frame.size,
                topInset: menuHeight + 8,
                bottomInset: dockHeight + 36
            )
            store.wallpaper = WallpaperLoader.blurredWallpaper(for: screen)
        } else {
            store.updateLayout(for: frame.size, topInset: 32, bottomInset: 96)
        }

        if window == nil {
            window = makeWindow(frame: frame)
        } else {
            window?.setFrame(frame, display: true)
        }

        guard let window else { return }

        ignoreHideUntil = Date().addingTimeInterval(0.8)
        window.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        isVisible = true
        store.isPresented = true
        installKeyMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            window.animator().alphaValue = 1
        }

        // Don't put the caret in the search field until the user clicks it.
        DispatchQueue.main.async {
            window.makeFirstResponder(nil)
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        store.isPresented = false
        store.query = ""
        removeKeyMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window?.alphaValue = 1
        }
    }

    func hideIfVisible() {
        guard isVisible, Date() >= ignoreHideUntil else { return }
        hide()
    }

    func launch(_ app: InstalledApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
        hide()
    }

    private func makeWindow(frame: NSRect) -> LaunchpadWindow {
        let window = LaunchpadWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isMovable = false
        // Keep Dock and menu bar above the overlay, like the original Launchpad.
        window.level = NSWindow.Level(rawValue: 19)
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.animationBehavior = .utilityWindow
        window.isReleasedWhenClosed = false

        let rootView = LaunchpadView(store: store)
            .containerBackground(.clear, for: .window)
            .preferredColorScheme(.dark)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        return window
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if let input = NSApp.keyWindow?.firstResponder as? NSTextView, input.hasMarkedText() {
            return false
        }

        if event.keyCode == UInt16(kVK_Escape) {
            if store.query.isEmpty {
                hide()
            } else {
                store.query = ""
            }
            return true
        }

        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            store.launchSelected()
            return true
        }

        if event.keyCode == UInt16(kVK_LeftArrow) && store.query.isEmpty {
            store.moveSelection(.left)
            return true
        }
        if event.keyCode == UInt16(kVK_RightArrow) && store.query.isEmpty {
            store.moveSelection(.right)
            return true
        }
        if event.keyCode == UInt16(kVK_UpArrow) {
            store.moveSelection(.up)
            return true
        }
        if event.keyCode == UInt16(kVK_DownArrow) {
            store.moveSelection(.down)
            return true
        }

        return false
    }

    private static func screenUnderCursor() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }
}
