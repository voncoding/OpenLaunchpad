import AppKit
import Observation
import SwiftUI

enum MoveDirection {
    case left, right, up, down
}

@Observable
final class LaunchpadStore {
    var apps: [InstalledApp] = []
    var query = ""
    var currentPage = 0 {
        didSet {
            persistCurrentPage()
        }
    }
    var selectedID: URL?
    var isPresented = false
    var columns = 7
    var rows = 5
    var isLoading = true
    var wallpaper: NSImage?
    var topInset: CGFloat = 28
    var bottomInset: CGFloat = 80
    var draggingApp: InstalledApp?
    var dragPosition: CGPoint?
    private var dragOriginIndex: Int?
    private var dragHasMoved = false

    private let orderKey = "launchpad.iconOrder"
    private let pageKey = "launchpad.lastPage"

    init() {
        currentPage = UserDefaults.standard.integer(forKey: pageKey)
    }

    var isReordering: Bool { draggingApp != nil }

    var filteredApps: [InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return apps }
        return apps.filter { $0.matches(trimmed) }
    }

    var pageSize: Int {
        max(1, columns * rows)
    }

    var pages: [[InstalledApp]] {
        let items = filteredApps
        guard !items.isEmpty else { return [[]] }
        return stride(from: 0, to: items.count, by: pageSize).map { start in
            Array(items[start..<min(start + pageSize, items.count)])
        }
    }

    var selectedApp: InstalledApp? {
        if let selectedID, let match = filteredApps.first(where: { $0.id == selectedID }) {
            return match
        }
        return query.isEmpty ? nil : filteredApps.first
    }

    func resetForPresentation() {
        query = ""
        selectedID = nil
        cancelDrag()
        currentPage = UserDefaults.standard.integer(forKey: pageKey)
        clampPage()
    }

    func updateLayout(for size: CGSize, topInset: CGFloat, bottomInset: CGFloat) {
        self.topInset = max(topInset, 24)
        self.bottomInset = max(bottomInset, 72)
        let horizontalPadding: CGFloat = 96
        let verticalChrome = self.topInset + self.bottomInset + 120
        columns = max(4, min(7, Int((size.width - horizontalPadding) / LaunchpadMetrics.cellWidth)))
        rows = max(3, min(5, Int((size.height - verticalChrome) / LaunchpadMetrics.cellHeight)))
        clampPage()
    }

    func reload() {
        isLoading = apps.isEmpty
        Task.detached { [weak self] in
            let scanned = AppScanner.scan()
            IconCache.preheat(urls: scanned.map(\.url))
            await MainActor.run {
                guard let self else { return }
                self.apps = self.applySavedOrder(scanned)
                self.isLoading = false
                self.clampPage()
            }
        }
    }

    func beginDrag(_ app: InstalledApp, pageFrame: CGSize) {
        guard query.isEmpty else { return }
        guard let index = apps.firstIndex(of: app) else { return }
        draggingApp = app
        dragOriginIndex = index
        dragHasMoved = false
        selectedID = nil
        dragPosition = cellCenter(for: index, pageWidth: pageFrame.width, pageHeight: pageFrame.height)
    }

    func updateDrag(translation: CGSize, pageFrame: CGSize) {
        guard let draggingApp, let origin = dragOriginIndex, pageFrame.width > 1, pageFrame.height > 1 else { return }

        let start = cellCenter(for: origin, pageWidth: pageFrame.width, pageHeight: pageFrame.height)
        dragPosition = CGPoint(x: start.x + translation.width, y: start.y + translation.height)

        let distance = hypot(translation.width, translation.height)
        guard distance > 10 else { return }
        dragHasMoved = true

        let pointer = dragPosition ?? start
        let xInPage = pointer.x - CGFloat(currentPage) * pageFrame.width
        let cellWidth = pageFrame.width / CGFloat(max(columns, 1))
        let cellHeight = pageFrame.height / CGFloat(max(rows, 1))
        let column = min(max(Int(xInPage / cellWidth), 0), max(columns - 1, 0))
        let row = min(max(Int(pointer.y / cellHeight), 0), max(rows - 1, 0))
        let target = min(currentPage * pageSize + row * columns + column, max(apps.count - 1, 0))
        moveDraggingApp(to: target)
    }

    func endDrag() {
        if dragHasMoved {
            persistOrder()
        }
        draggingApp = nil
        dragPosition = nil
        dragOriginIndex = nil
        dragHasMoved = false
    }

    func cancelDrag() {
        draggingApp = nil
        dragPosition = nil
        dragOriginIndex = nil
        dragHasMoved = false
    }

    func launchSelected() {
        guard let selectedApp else { return }
        OverlayController.shared.launch(selectedApp)
    }

    func revealInFinder(_ app: InstalledApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    func select(_ app: InstalledApp) {
        selectedID = app.id
        if let index = filteredApps.firstIndex(of: app) {
            currentPage = index / pageSize
        }
    }

    func moveSelection(_ direction: MoveDirection) {
        let items = filteredApps
        guard !items.isEmpty else { return }

        let currentIndex = items.firstIndex { $0.id == selectedID } ?? (currentPage * pageSize)
        let clamped = min(max(currentIndex, 0), items.count - 1)

        let nextIndex: Int
        switch direction {
        case .left:
            nextIndex = max(0, clamped - 1)
        case .right:
            nextIndex = min(items.count - 1, clamped + 1)
        case .up:
            nextIndex = max(0, clamped - columns)
        case .down:
            nextIndex = min(items.count - 1, clamped + columns)
        }

        selectedID = items[nextIndex].id
        currentPage = nextIndex / pageSize
    }

    func goToPage(_ page: Int) {
        currentPage = min(max(0, page), max(pages.count - 1, 0))
    }

    func clampPage() {
        let last = max(pages.count - 1, 0)
        if currentPage > last {
            currentPage = last
        }
    }

    private func moveDraggingApp(to target: Int) {
        guard let draggingApp, let from = apps.firstIndex(of: draggingApp) else { return }
        let to = min(max(target, 0), apps.count - 1)
        guard from != to else { return }
        apps.remove(at: from)
        apps.insert(draggingApp, at: to)
    }

    private func cellCenter(for index: Int, pageWidth: CGFloat, pageHeight: CGFloat) -> CGPoint {
        let page = index / max(pageSize, 1)
        let local = index % max(pageSize, 1)
        let column = local % max(columns, 1)
        let row = local / max(columns, 1)
        let cellWidth = pageWidth / CGFloat(max(columns, 1))
        let cellHeight = pageHeight / CGFloat(max(rows, 1))
        return CGPoint(
            x: CGFloat(page) * pageWidth + (CGFloat(column) + 0.5) * cellWidth,
            y: (CGFloat(row) + 0.5) * cellHeight
        )
    }

    private func applySavedOrder(_ scanned: [InstalledApp]) -> [InstalledApp] {
        let order = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        var remaining = Dictionary(uniqueKeysWithValues: scanned.map { ($0.url.path, $0) })
        var ordered: [InstalledApp] = []
        for path in order {
            if let app = remaining.removeValue(forKey: path) {
                ordered.append(app)
            }
        }
        let extras = remaining.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return ordered + extras
    }

    private func persistOrder() {
        UserDefaults.standard.set(apps.map(\.url.path), forKey: orderKey)
    }

    private func persistCurrentPage() {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        UserDefaults.standard.set(currentPage, forKey: pageKey)
    }
}
