import AppKit
import QuartzCore
import SwiftUI

nonisolated enum LaunchpadMetrics {
    static let iconSize: CGFloat = 96
    static let iconPixelSize: CGFloat = 192
    static let cellWidth: CGFloat = 156
    static let cellHeight: CGFloat = 158
    static let labelHeight: CGFloat = 36
    static let pageSnapDuration: CFTimeInterval = 0.32

    static var iconBlockHeight: CGFloat { iconSize + 8 + labelHeight }
}

struct PagingScrollHost: NSViewRepresentable {
    @Bindable var store: LaunchpadStore
    let pageFrame: CGSize
    var horizontalInset: CGFloat = 0
    let onLaunch: (InstalledApp) -> Void
    let onReveal: (InstalledApp) -> Void
    let onOpenFolder: (LaunchpadFolder) -> Void
    let onEmptyTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LaunchpadPagerView {
        let view = LaunchpadPagerView()
        view.coordinator = context.coordinator
        context.coordinator.onPageSettled = { [store] page in
            if store.currentPage != page {
                store.goToPage(page)
            }
        }
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: LaunchpadPagerView, context: Context) {
        context.coordinator.onPageSettled = { [store] page in
            if store.currentPage != page {
                store.goToPage(page)
            }
        }
        let pages = store.pages
        let pageCount = max(pages.count, 1)
        // Structural only — never include drag/merge ids or the hosting tree is rebuilt
        // mid-gesture and endDrag never runs (ghost icon stuck).
        let signature = ContentSignature(
            columns: store.columns,
            rows: store.rows,
            size: pageFrame,
            horizontalInset: horizontalInset
        )

        if context.coordinator.signature != signature {
            context.coordinator.signature = signature
            view.updateContent(
                rootView: PagesStrip(
                    store: store,
                    pageSize: pageFrame,
                    onLaunch: onLaunch,
                    onReveal: onReveal,
                    onOpenFolder: onOpenFolder,
                    onEmptyTap: onEmptyTap,
                    pageFrame: CGSize(width: max(pageFrame.width - 2 * horizontalInset, 1), height: pageFrame.height),
                    horizontalInset: horizontalInset
                ),
                pageWidth: max(pageFrame.width, 1),
                pageHeight: max(pageFrame.height, 1),
                pageCount: pageCount
            )
        } else {
            view.updateMetrics(
                pageWidth: max(pageFrame.width, 1),
                pageHeight: max(pageFrame.height, 1),
                pageCount: pageCount
            )
        }

        view.onEmptyTap = onEmptyTap
        view.isReordering = store.isReordering
        view.updateGrid(
            columns: store.columns,
            rows: store.rows,
            appsOnPages: pages.map(\.count),
            horizontalInset: horizontalInset
        )

        if !view.isTracking, view.settledPage != store.currentPage {
            let animated = context.coordinator.didApplyInitialPage
            view.scrollToPage(store.currentPage, animated: animated)
        }
        context.coordinator.didApplyInitialPage = true
    }

    @MainActor
    final class Coordinator {
        var onPageSettled: ((Int) -> Void)?
        var signature: ContentSignature?
        var didApplyInitialPage = false

    }
}

struct ContentSignature: Equatable {
    var columns: Int
    var rows: Int
    var size: CGSize
    var horizontalInset: CGFloat
}

struct PagesStrip: View {
    @Bindable var store: LaunchpadStore
    let pageSize: CGSize
    let onLaunch: (InstalledApp) -> Void
    let onReveal: (InstalledApp) -> Void
    let onOpenFolder: (LaunchpadFolder) -> Void
    let onEmptyTap: () -> Void
    let pageFrame: CGSize
    var horizontalInset: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(store.pages.enumerated()), id: \.offset) { _, pageItems in
                ItemGridPage(
                    items: pageItems,
                    columns: store.columns,
                    rows: store.rows,
                    selectedID: store.selectedID,
                    onLaunch: onLaunch,
                    onReveal: onReveal,
                    onOpenFolder: onOpenFolder,
                    onEmptyTap: onEmptyTap,
                    fillsPage: true,
                    draggingID: store.draggingItem?.id,
                    mergeTargetID: store.mergeTargetID,
                    onLift: { item in
                        store.beginDrag(item, pageFrame: pageFrame)
                    },
                    onDrag: { translation in
                        store.updateDrag(translation: translation, pageFrame: pageFrame)
                    },
                    onDrop: {
                        store.endDrag()
                    },
                    resolveFolderApps: { store.apps(in: $0) }
                )
                .frame(width: max(pageSize.width - 2 * horizontalInset, 1), height: pageSize.height)
                .padding(.horizontal, horizontalInset)
            }
        }
        .frame(
            width: pageSize.width * CGFloat(max(store.pages.count, 1)),
            height: pageSize.height,
            alignment: .topLeading
        )
    }
}

final class LaunchpadPagerView: NSView {
    weak var coordinator: PagingScrollHost.Coordinator?
    var onEmptyTap: (() -> Void)?
    var isReordering = false

    private let clipLayerHost = FlippedClipView()
    private var hostingView: NSHostingView<PagesStrip>?
    private let gapCatcher = PageGapCatcherView()
    private var scrollMonitor: Any?

    private(set) var isTracking = false
    private(set) var settledPage = 0

    private var pageWidth: CGFloat = 1
    private var pageHeight: CGFloat = 1
    private var pageCount = 1
    private var gridColumns = 7
    private var gridRows = 5
    private var gridInset: CGFloat = 0
    private var appsOnPages: [Int] = []
    private var offset: CGFloat = 0
    private var axisLock: Axis?
    private var gestureStartOffset: CGFloat = 0
    private var smoothedDelta: CGFloat = 0
    private var mouseStartX: CGFloat?
    private var mousePaging = false

    private enum Axis {
        case horizontal, vertical
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        clipsToBounds = true
        clipLayerHost.wantsLayer = true
        clipLayerHost.clipsToBounds = true
        clipLayerHost.layerContentsRedrawPolicy = .onSetNeedsDisplay
        addSubview(clipLayerHost)
        gapCatcher.pager = self
        clipLayerHost.addSubview(gapCatcher)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitors()
        guard window != nil else { return }

        let scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handleScroll(event) ? nil : event
        }
        self.scrollMonitor = scrollMonitor
    }

    private func removeMonitors() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    override func layout() {
        super.layout()
        clipLayerHost.frame = bounds
        gapCatcher.frame = clipLayerHost.bounds
        hostingView?.setFrameSize(
            NSSize(width: pageWidth * CGFloat(pageCount), height: bounds.height)
        )
        if let hostingView {
            clipLayerHost.addSubview(hostingView, positioned: .below, relativeTo: gapCatcher)
        }
    }

    func updateContent(
        rootView: PagesStrip,
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        pageCount: Int
    ) {
        let widthChanged = abs(self.pageWidth - pageWidth) > 0.5
        self.pageWidth = max(pageWidth, 1)
        self.pageHeight = max(pageHeight, 1)
        self.pageCount = max(pageCount, 1)
        if widthChanged {
            offset = CGFloat(settledPage) * self.pageWidth
        }

        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hosting = NSHostingView(rootView: rootView)
            hosting.sizingOptions = []
            hosting.wantsLayer = true
            hosting.layerContentsRedrawPolicy = .onSetNeedsDisplay
            clipLayerHost.addSubview(hosting, positioned: .below, relativeTo: gapCatcher)
            hostingView = hosting
        }

        hostingView?.setFrameSize(
            NSSize(width: self.pageWidth * CGFloat(self.pageCount), height: max(pageHeight, bounds.height))
        )
        applyOffset(offset, animated: false)
    }

    func updateMetrics(pageWidth: CGFloat, pageHeight: CGFloat, pageCount: Int) {
        let widthChanged = abs(self.pageWidth - pageWidth) > 0.5
        self.pageWidth = max(pageWidth, 1)
        self.pageHeight = max(pageHeight, 1)
        self.pageCount = max(pageCount, 1)
        hostingView?.setFrameSize(
            NSSize(width: self.pageWidth * CGFloat(self.pageCount), height: max(pageHeight, bounds.height))
        )
        if widthChanged {
            offset = CGFloat(settledPage) * self.pageWidth
            applyOffset(offset, animated: false)
        }
    }

    func updateGrid(columns: Int, rows: Int, appsOnPages: [Int], horizontalInset: CGFloat = 0) {
        gridColumns = max(columns, 1)
        gridRows = max(rows, 1)
        gridInset = max(horizontalInset, 0)
        self.appsOnPages = appsOnPages
    }

    func scrollToPage(_ page: Int, animated: Bool) {
        let targetPage = clampPage(page)
        settledPage = targetPage
        offset = CGFloat(targetPage) * pageWidth
        applyOffset(offset, animated: animated)
    }

    fileprivate func gapMouseDown(atWindowX x: CGFloat) {
        mouseStartX = x
        mousePaging = false
        smoothedDelta = 0
        gestureStartOffset = CGFloat(settledPage) * pageWidth
        hostingView?.layer?.removeAllAnimations()
    }

    fileprivate func gapMouseDragged(atWindowX x: CGFloat, deltaX: CGFloat) {
        guard pageCount > 1, let startX = mouseStartX else { return }
        let dx = x - startX
        if !mousePaging {
            guard abs(dx) >= 6 else { return }
            mousePaging = true
            isTracking = true
        }
        offset = rubberBand(gestureStartOffset - dx)
        smoothedDelta = smoothedDelta * 0.65 - deltaX * 0.35
        applyOffset(offset, animated: false)
    }

    fileprivate func gapMouseUp(atWindowX x: CGFloat) {
        if mousePaging {
            let dx = x - (mouseStartX ?? x)
            offset = rubberBand(gestureStartOffset - dx)
            snap()
            isTracking = false
            mousePaging = false
            mouseStartX = nil
            return
        }
        mouseStartX = nil
        onEmptyTap?()
    }

    /// Only the icon square counts — not the label, not the surrounding cell padding.
    func isPointOnIcon(_ locationInPager: CGPoint) -> Bool {
        let contentX = locationInPager.x + offset
        let pageIndex = Int(floor(contentX / max(pageWidth, 1)))
        guard pageIndex >= 0, pageIndex < pageCount else { return false }

        let xInPage = contentX - CGFloat(pageIndex) * pageWidth - gridInset
        let yInPage = locationInPager.y
        let cellWidth = (pageWidth - 2 * gridInset) / CGFloat(gridColumns)
        let cellHeight = pageHeight / CGFloat(gridRows)
        guard cellWidth > 1, cellHeight > 1 else { return false }

        let column = Int(floor(xInPage / cellWidth))
        let row = Int(floor(yInPage / cellHeight))
        guard column >= 0, column < gridColumns, row >= 0, row < gridRows else { return false }

        let cellIndex = row * gridColumns + column
        let appCount = pageIndex < appsOnPages.count ? appsOnPages[pageIndex] : 0
        guard cellIndex < appCount else { return false }

        let iconSize = LaunchpadMetrics.iconSize
        let blockHeight = LaunchpadMetrics.iconBlockHeight
        let cellMinX = CGFloat(column) * cellWidth
        let cellMinY = CGFloat(row) * cellHeight
        let iconX = cellMinX + (cellWidth - iconSize) / 2
        let iconY = cellMinY + (cellHeight - blockHeight) / 2
        let iconRect = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
        return iconRect.contains(CGPoint(x: xInPage, y: yInPage))
    }

    func handleScroll(_ event: NSEvent) -> Bool {
        let location = convert(event.locationInWindow, from: nil)
        // A gesture that started here must receive its end/cancel even if the
        // pointer has since moved outside. Otherwise the strip stays half-paged.
        guard bounds.contains(location) || isTracking || axisLock != nil,
              pageWidth > 1, pageCount > 1 else { return false }

        guard !isReordering else { return true }

        let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 16
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 16

        if event.momentumPhase != [] {
            return isTracking || axisLock == .horizontal
        }

        if event.phase.contains(.began) {
            axisLock = nil
            smoothedDelta = 0
            gestureStartOffset = CGFloat(settledPage) * pageWidth
            hostingView?.layer?.removeAllAnimations()
            return true
        }

        if event.phase.contains(.changed) || event.phase == [] {
            if event.phase == [] {
                // Discrete mouse wheels have no ended phase; never leave an axis lock behind.
                axisLock = nil
                guard abs(dx) > abs(dy), abs(dx) > 1 else { return true }
                let next = settledPage + (dx < 0 ? 1 : -1)
                scrollToPage(next, animated: true)
                coordinator?.onPageSettled?(settledPage)
                return true
            }

            if axisLock == nil {
                if abs(dx) < 0.2 && abs(dy) < 0.2 { return true }
                axisLock = abs(dx) >= abs(dy) ? .horizontal : .vertical
                if axisLock == .horizontal {
                    isTracking = true
                    gestureStartOffset = CGFloat(settledPage) * pageWidth
                    smoothedDelta = 0
                }
            }
            guard axisLock == .horizontal else { return true }

            offset -= dx
            smoothedDelta = smoothedDelta * 0.72 + dx * 0.28
            offset = rubberBand(offset)
            applyOffset(offset, animated: false)
            return true
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            if axisLock == .horizontal {
                if abs(dx) > 0.01 {
                    offset -= dx
                    offset = rubberBand(offset)
                }
                snap()
            }
            isTracking = false
            axisLock = nil
            return true
        }

        return false
    }

    private func snap() {
        let translation = offset - gestureStartOffset
        let threshold = pageWidth * 0.08
        let flickToNext = smoothedDelta < -0.45
        let flickToPrevious = smoothedDelta > 0.45

        var page = settledPage
        if translation > threshold || (flickToNext && translation >= -12) {
            page += 1
        } else if translation < -threshold || (flickToPrevious && translation <= 12) {
            page -= 1
        }

        let targetPage = clampPage(page)
        settledPage = targetPage
        offset = CGFloat(targetPage) * pageWidth
        applyOffset(offset, animated: true)
        coordinator?.onPageSettled?(targetPage)
    }

    private func rubberBand(_ value: CGFloat) -> CGFloat {
        let maxOffset = CGFloat(max(pageCount - 1, 0)) * pageWidth
        if value < 0 {
            return value * 0.28
        }
        if value > maxOffset {
            return maxOffset + (value - maxOffset) * 0.28
        }
        return value
    }

    private func applyOffset(_ value: CGFloat, animated: Bool) {
        let origin = NSPoint(x: -value, y: 0)
        guard let hostingView else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = LaunchpadMetrics.pageSnapDuration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.86, 0.24, 1)
                context.allowsImplicitAnimation = true
                hostingView.animator().setFrameOrigin(origin)
            }
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hostingView.setFrameOrigin(origin)
            CATransaction.commit()
        }
    }

    private func clampPage(_ page: Int) -> Int {
        min(max(page, 0), max(pageCount - 1, 0))
    }
}

private final class FlippedClipView: NSView {
    override var isFlipped: Bool { true }
}

/// Sits above the SwiftUI grid. Gaps are captured here for click-dismiss / drag-paging.
/// Icon squares return nil from hitTest so SwiftUI still receives icon clicks and drags.
private final class PageGapCatcherView: NSView {
    weak var pager: LaunchpadPagerView?

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let pager, bounds.contains(point) else { return nil }
        if pager.isReordering { return nil }
        let pagerPoint = convert(point, to: pager)
        if pager.isPointOnIcon(pagerPoint) { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        pager?.gapMouseDown(atWindowX: event.locationInWindow.x)
    }

    override func mouseDragged(with event: NSEvent) {
        pager?.gapMouseDragged(atWindowX: event.locationInWindow.x, deltaX: event.deltaX)
    }

    override func mouseUp(with event: NSEvent) {
        pager?.gapMouseUp(atWindowX: event.locationInWindow.x)
    }
}
