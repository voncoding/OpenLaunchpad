import AppKit
import SwiftUI

/// Exercise SwiftUI's actual AppKit scroll view with the system's Always policy.
/// The runner supplies that policy as a process argument in an isolated home.
@MainActor
enum FolderScrollbarRegression {
    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    static func run() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try InteractionRegressionTests.expect(
            UserDefaults.standard.string(forKey: "AppleShowScrollBars") == "Always"
                && NSScroller.preferredScrollerStyle == .legacy,
            "scrollbar regression requires the isolated Always policy"
        )
        let apps = (0..<35).map { InteractionRegressionTests.app("Scrollbar\($0)") }
        let folder = LaunchpadFolder(name: "文件夹", appPaths: apps.map { $0.url.path })
        let fixture = InteractionRegressionTests.Fixture(apps: apps, folders: [folder])
        defer { fixture.cleanUp() }
        fixture.store.openFolder(folder)

        let size = CGSize(width: 1512, height: 982)
        let window = OffscreenWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: FolderOverlay(store: fixture.store))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }
        try await settle(host)
        guard let scroll = findScrollView(in: host) else {
            throw InteractionRegressionTests.CheckFailure(description: "folder did not create a scroll view")
        }
        try assertIndicatorsAbsent(scroll)
        let startY = scroll.contentView.bounds.minY
        try InteractionRegressionTests.expect(
            (scroll.documentView?.frame.height ?? 0) > scroll.contentView.bounds.height,
            "fixture must overflow the folder panel"
        )

        fixture.store.selectedID = LaunchpadItem.app(apps[34]).id
        try await settle(host)
        try InteractionRegressionTests.expect(
            scroll.contentView.bounds.minY > startY + 50,
            "selecting the last folder app must still scroll it into view"
        )
        try assertIndicatorsAbsent(scroll)
        scroll.flashScrollers()
        try await settle(host)
        try assertIndicatorsAbsent(scroll)
    }

    private static func settle(_ host: NSView) async throws {
        try await Task.sleep(for: .milliseconds(500))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
    }

    private static func assertIndicatorsAbsent(_ scroll: NSScrollView) throws {
        try InteractionRegressionTests.expect(
            !scroll.hasVerticalScroller && !scroll.hasHorizontalScroller,
            "folder must suppress scrollers even when macOS always shows them"
        )
        try InteractionRegressionTests.expect(
            scroll.verticalScroller == nil || scroll.verticalScroller!.isHidden,
            "folder vertical scroller must not be visible"
        )
    }
}
