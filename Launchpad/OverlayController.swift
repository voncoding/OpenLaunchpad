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

    private var window: LaunchpadWindow?
    private var localMonitor: Any?
    private var isVisible = false
    private var visibilityGeneration: UInt64 = 0
    private var isOpeningApplication = false
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    private var overlayPresentationOptions: NSApplication.PresentationOptions?

    private init() {}

    func prepare() {
        store.reload()
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard !isVisible else {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            return
        }
        visibilityGeneration &+= 1
        let generation = visibilityGeneration
        let screen = Self.screenUnderCursor() ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        store.resetForPresentation()
        store.reload()
        if let screen {
            // The main grid leaves room for the normally visible Dock and menu bar.
            let dockHeight = max(screen.visibleFrame.minY - screen.frame.minY, 0)
            let menuHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 0)
            store.updateLayout(for: frame.size, topInset: menuHeight + 8, bottomInset: dockHeight + 36)
            store.wallpaper = WallpaperLoader.blurredWallpaper(for: screen)
        } else {
            store.updateLayout(for: frame.size, topInset: 28, bottomInset: 72)
            store.wallpaper = nil
        }

        if window == nil {
            window = makeWindow(frame: frame)
        } else {
            window?.setFrame(frame, display: true)
        }

        guard let window else { return }

        if !window.isVisible {
            window.alphaValue = 0
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        isVisible = true
        store.isPresented = true
        installKeyMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            window.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isVisible, self.visibilityGeneration == generation else { return }
                self.window?.alphaValue = 1
            }
        }

        // Don't put the caret in the search field until the user clicks it.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window,
                  self.isVisible, self.visibilityGeneration == generation else { return }
            window.makeFirstResponder(nil)
        }
    }

    func hide() {
        guard isVisible else { return }
        visibilityGeneration &+= 1
        let generation = visibilityGeneration
        isVisible = false
        endPresentation()
        store.cancelDrag()
        window?.makeFirstResponder(nil)
        store.commitOpenFolderName()
        store.isPresented = false
        store.query = ""
        removeKeyMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isVisible, self.visibilityGeneration == generation else { return }
                self.window?.orderOut(nil)
                self.window?.alphaValue = 1
            }
        }
    }

    func hideIfVisible() {
        // Ignore delayed activation notifications once our own app is frontmost.
        guard isVisible,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        hide()
    }

    func launch(_ app: InstalledApp) {
        guard !store.isReordering, !isOpeningApplication else { return }
        isOpeningApplication = true
        let generation = visibilityGeneration
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOpeningApplication = false
                guard self.isVisible, self.visibilityGeneration == generation else { return }
                if let error {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "无法打开“\(app.name)”"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "好")
                    if let window = self.window {
                        alert.beginSheetModal(for: window)
                    }
                } else {
                    self.hide()
                }
            }
        }
    }

    func updateFolderPresentation() {
        guard isVisible else { return }
        if store.openFolderID != nil {
            beginPresentation()
        } else {
            endPresentation()
        }
    }

    private func beginPresentation() {
        guard previousPresentationOptions == nil else { return }
        let previousOptions = NSApp.presentationOptions
        var options = previousOptions
        // Avoid conflicting hide/auto-hide flags, and retain any other app options.
        options.subtract([.hideDock, .hideMenuBar])
        options.formUnion([.autoHideDock, .autoHideMenuBar])
        previousPresentationOptions = previousOptions
        overlayPresentationOptions = options
        NSApp.presentationOptions = options
    }

    private func endPresentation() {
        guard let previousOptions = previousPresentationOptions else { return }
        // Restore synchronously: a settings window or a quick reopen may follow
        // before the closing animation finishes. Never restore from its callback.
        if NSApp.presentationOptions == overlayPresentationOptions {
            NSApp.presentationOptions = previousOptions
        }
        previousPresentationOptions = nil
        overlayPresentationOptions = nil
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
        // Keep the auto-hidden Dock and menu bar reachable at the screen edges.
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
            let handled = MainActor.assumeIsolated { [weak self] in
                self?.handleKey(event) ?? false
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard isVisible, let window,
              NSApp.keyWindow === window, event.window === window,
              window.attachedSheet == nil else { return false }

        let input = window.firstResponder as? NSTextView
        if input?.hasMarkedText() == true {
            return false
        }

        if event.keyCode == UInt16(kVK_Escape) {
            if store.isReordering {
                store.cancelDrag()
            } else if store.openFolderID != nil {
                store.closeFolder()
            } else if !store.isSearching {
                hide()
            } else {
                store.query = ""
            }
            return true
        }

        // Leave shortcuts and text navigation to the current field editor.
        if !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            return false
        }
        if store.openFolderID != nil, input?.isEditable == true {
            return false
        }
        if store.isReordering {
            return [kVK_Return, kVK_ANSI_KeypadEnter, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
                .contains(Int(event.keyCode))
        }

        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            store.launchSelected()
            return true
        }

        if event.keyCode == UInt16(kVK_LeftArrow) && input?.isEditable != true {
            store.moveSelection(.left)
            return true
        }
        if event.keyCode == UInt16(kVK_RightArrow) && input?.isEditable != true {
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
