import AppKit
import SwiftUI

@MainActor
enum PagerEdgeRegression {
    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    private final class ScrollEvent: NSEvent {
        var point: CGPoint = .zero
        var scrollPhase: NSEvent.Phase = []
        var delta: CGFloat = 0
        override var locationInWindow: NSPoint { point }
        override var phase: NSEvent.Phase { scrollPhase }
        override var momentumPhase: NSEvent.Phase { [] }
        override var hasPreciseScrollingDeltas: Bool { true }
        override var scrollingDeltaX: CGFloat { delta }
        override var scrollingDeltaY: CGFloat { 0 }
    }

    static func run() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let apps = (0..<24).map { InteractionRegressionTests.app("Edge\($0)") }
        let fixture = InteractionRegressionTests.Fixture(apps: apps)
        defer { fixture.cleanUp() }
        fixture.store.horizontalInset = 88
        let size = CGSize(width: 800, height: 474)
        let window = OffscreenWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: PagedAppGrid(store: fixture.store))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }
        try await settle(host)
        guard let pager = findPager(in: host),
              let strip = pager.subviews.first?.subviews.compactMap({ $0 as? NSHostingView<PagesStrip> }).first else {
            throw InteractionRegressionTests.CheckFailure(description: "real pager was not mounted")
        }
        try InteractionRegressionTests.expect(
            abs(pager.frame.width - size.width) < 1 && abs(pager.frame.minX) < 1,
            "pager must clip at the viewport edge, not at the grid's side inset"
        )
        try InteractionRegressionTests.expect(abs(strip.frame.width - 1600) < 1,
            "each page must occupy a full viewport so adjacent icons cannot leak into the margin")
        let iconY = (158 - LaunchpadMetrics.iconBlockHeight) / 2 + 48
        try InteractionRegressionTests.expect(pager.isPointOnIcon(CGPoint(x: 88 + 78, y: iconY)),
            "first-column icon hit testing must include the inner side inset")
        try InteractionRegressionTests.expect(!pager.isPointOnIcon(CGPoint(x: 78, y: iconY)),
            "side padding must remain a gap, not an invisible icon hit target")

        func scroll(_ phase: NSEvent.Phase, dx: CGFloat = 0, outside: Bool = false) {
            let event = ScrollEvent()
            event.scrollPhase = phase
            event.delta = dx
            event.point = pager.convert(CGPoint(x: outside ? -20 : 400, y: 200), to: nil)
            _ = pager.handleScroll(event)
        }

        scroll(.began)
        scroll(.changed, dx: -100)
        try await settle(host)
        try savePreview(host, name: "pager-during-swipe")
        scroll(.ended, outside: true)
        try await settle(host)
        try InteractionRegressionTests.expect(!pager.isTracking && pager.settledPage == 1,
            "a gesture ending outside the pager must still settle on a complete page")
        try InteractionRegressionTests.expect(abs(strip.frame.minX + size.width) < 1,
            "the strip must finish exactly at the page boundary")
        try savePreview(host, name: "pager-settled")

        scroll(.began)
        scroll(.changed, dx: 100)
        scroll(.cancelled, outside: true)
        try await settle(host)
        try InteractionRegressionTests.expect(!pager.isTracking && pager.settledPage == 0 && abs(strip.frame.minX) < 1,
            "a cancelled gesture outside the pager must not leave clipped icons at the side")
    }

    private static func settle(_ host: NSView) async throws {
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }

    private static func findPager(in view: NSView) -> LaunchpadPagerView? {
        if let pager = view as? LaunchpadPagerView { return pager }
        return view.subviews.lazy.compactMap { findPager(in: $0) }.first
    }

    private static func savePreview(_ host: NSView, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["OPENLAUNCHPAD_PREVIEW_DIR"],
              let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
