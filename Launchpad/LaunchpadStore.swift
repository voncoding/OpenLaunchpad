import AppKit
import Observation
import SwiftUI

enum MoveDirection {
    case left, right, up, down
}

@Observable
@MainActor
final class LaunchpadStore {
    /// Flat catalog of every scanned app (including those inside folders).
    private(set) var appCatalog: [String: InstalledApp] = [:]
    /// Page boundaries are part of the layout, including unused space at the bottom.
    private var itemPages: [[LaunchpadItem]] = [[]]
    var items: [LaunchpadItem] {
        get { itemPages.flatMap { $0 } }
        set { itemPages = chunked(newValue) }
    }
    var query = "" {
        didSet {
            if query != oldValue {
                selectedID = nil
                if !isSearching { clampPage() }
            }
        }
    }
    var currentPage = 0 {
        didSet {
            persistCurrentPage()
            prefetchVisibleIcons()
        }
    }
    var selectedID: String?
    var isPresented = false
    var columns = 7
    var rows = 5
    private(set) var usesAutomaticGrid: Bool
    private(set) var preferredColumns: Int
    private(set) var preferredRows: Int
    private(set) var maximumColumns = 7
    private(set) var maximumRows = 5
    private(set) var hiddenAppPaths: Set<String>
    @ObservationIgnored private var lastLayoutSize: CGSize?
    var isLoading = true
    var wallpaper: NSImage?
    var wallpaperStatus: WallpaperLoader.Status = .loading
    var topInset: CGFloat = 28
    var bottomInset: CGFloat = 80
    var horizontalInset: CGFloat = 118
    var folderPanelFrame: CGRect = .zero
    var folderColumns = 7

    var draggingItem: LaunchpadItem?
    var dragPosition: CGPoint?
    var mergeTargetID: String?
    var openFolderID: UUID?
    var folderNameDraft: String = ""
    /// Drives folder expand/collapse animation separately from the data id.
    var isFolderExpanded = false

    private var dragOriginIndex: Int?
    private var dragHasMoved = false
    /// When dragging an app out of an open folder.
    private var dragSourceFolderID: UUID?
    private var dragOriginPage = 0
    private var reorderTargetIndex: Int?
    private var mergeCandidateID: String?
    private var edgeDirection = 0
    private var lastDragTranslation: CGSize = .zero
    @ObservationIgnored private var mergeTask: Task<Void, Never>?
    @ObservationIgnored private var edgeTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var catalogGeneration: UInt = 0
    @ObservationIgnored private var completedCatalogGeneration: UInt?
    @ObservationIgnored private var lastScanTime: TimeInterval?
    @ObservationIgnored private let scanCatalog: @MainActor () async -> [InstalledApp]
    @ObservationIgnored private let uptime: @MainActor () -> TimeInterval
    @ObservationIgnored private let refreshInterval: TimeInterval
    private(set) var isRefreshing = false
    @ObservationIgnored private var pendingCatalog: [InstalledApp]?
    @ObservationIgnored private var folderAnimationTask: Task<Void, Never>?
    @ObservationIgnored private var selectionBeforeOpeningFolder: String?
    @ObservationIgnored private let defaults: UserDefaults

    private let orderKey = "launchpad.iconOrder"
    private let pageLayoutKey = "launchpad.pageLayout.v1"
    private let foldersKey = "launchpad.folders"
    private let pageKey = "launchpad.lastPage"

    init(
        defaults: UserDefaults = .standard,
        refreshInterval: TimeInterval = 300,
        uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        scanCatalog: @escaping @MainActor () async -> [InstalledApp] = {
            await Task.detached(priority: .userInitiated) { AppScanner.scan() }.value
        }
    ) {
        self.defaults = defaults
        self.refreshInterval = refreshInterval
        self.uptime = uptime
        self.scanCatalog = scanCatalog
        usesAutomaticGrid = defaults.object(forKey: "launchpad.grid.automatic") as? Bool ?? true
        preferredColumns = max(1, min(12, defaults.object(forKey: "launchpad.grid.columns") as? Int ?? 7))
        preferredRows = max(1, min(8, defaults.object(forKey: "launchpad.grid.rows") as? Int ?? 5))
        hiddenAppPaths = Set(defaults.stringArray(forKey: "launchpad.hiddenAppPaths") ?? [])
        currentPage = max(0, defaults.integer(forKey: pageKey))
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isReordering: Bool { draggingItem != nil }
    var dragSourceIsFolder: Bool { dragSourceFolderID != nil }

    var pageSize: Int { max(1, columns * rows) }

    var displayItems: [LaunchpadItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        var result: [LaunchpadItem] = []
        var seenPaths = Set<String>()

        for item in items {
            switch item {
            case .app(let app):
                if app.matches(trimmed) {
                    result.append(item)
                    seenPaths.insert(app.url.path)
                }
            case .folder(let folder):
                if folder.name.localizedStandardContains(trimmed) {
                    result.append(item)
                }
                for path in folder.appPaths {
                    guard !hiddenAppPaths.contains(path), let app = appCatalog[path], !seenPaths.contains(path), app.matches(trimmed) else { continue }
                    result.append(.app(app))
                    seenPaths.insert(path)
                }
            }
        }
        return result
    }

    var pages: [[LaunchpadItem]] {
        isSearching ? chunked(displayItems) : itemPages
    }

    private func chunked<T>(_ list: [T]) -> [[T]] {
        guard !list.isEmpty else { return [[]] }
        return stride(from: 0, to: list.count, by: pageSize).map { start in
            Array(list[start..<min(start + pageSize, list.count)])
        }
    }

    var openFolder: LaunchpadFolder? {
        guard let openFolderID else { return nil }
        return items.compactMap(\.folderValue).first { $0.id == openFolderID }
    }

    var openFolderApps: [InstalledApp] {
        guard let folder = openFolder else { return [] }
        return apps(in: folder)
    }

    var selectedApp: InstalledApp? {
        selectedItem?.appValue
    }

    private var navigationItems: [LaunchpadItem] {
        openFolderID == nil ? displayItems : openFolderApps.map(LaunchpadItem.app)
    }

    private var selectedItem: LaunchpadItem? {
        let list = navigationItems
        if let selectedID { return list.first { $0.id == selectedID } }
        return isSearching || openFolderID != nil ? list.first : nil
    }

    var appsIsEmpty: Bool { appCatalog.isEmpty }

    func apps(in folder: LaunchpadFolder) -> [InstalledApp] {
        folder.appPaths.filter { !hiddenAppPaths.contains($0) }.compactMap { appCatalog[$0] }
    }

    var hiddenAppCount: Int { appCatalog.keys.filter { hiddenAppPaths.contains($0) }.count }

    func setAppVisible(_ visible: Bool, path: String) {
        guard let app = appCatalog[path], visible == hiddenAppPaths.contains(path) else { return }
        cancelDrag()
        if visible {
            hiddenAppPaths.remove(path)
            let belongsToFolder = items.contains { $0.folderValue?.appPaths.contains(path) == true }
            if !belongsToFolder, position(of: LaunchpadItem.app(app).id) == nil {
                let last = itemPages.count - 1
                if itemPages[last].count < pageSize { itemPages[last].append(.app(app)) }
                else { itemPages.append([.app(app)]) }
            }
        } else {
            hiddenAppPaths.insert(path)
            if let location = position(of: LaunchpadItem.app(app).id) {
                itemPages[location.page].remove(at: location.index)
            }
            if selectedID == LaunchpadItem.app(app).id { selectedID = nil }
            trimTrailingEmptyPages()
        }
        defaults.set(hiddenAppPaths.sorted(), forKey: "launchpad.hiddenAppPaths")
        persistLayout()
        clampPage()
        prefetchVisibleIcons()
    }

    func setAutomaticGrid(_ automatic: Bool) {
        guard usesAutomaticGrid != automatic else { return }
        if !automatic, defaults.object(forKey: "launchpad.grid.columns") == nil {
            preferredColumns = columns
            preferredRows = rows
        }
        usesAutomaticGrid = automatic
        saveGridSettings()
    }

    func setGridColumns(_ value: Int) {
        preferredColumns = max(1, min(maximumColumns, value))
        saveGridSettings()
    }

    func setGridRows(_ value: Int) {
        preferredRows = max(1, min(maximumRows, value))
        saveGridSettings()
    }

    private func saveGridSettings() {
        cancelDrag()
        defaults.set(usesAutomaticGrid, forKey: "launchpad.grid.automatic")
        defaults.set(preferredColumns, forKey: "launchpad.grid.columns")
        defaults.set(preferredRows, forKey: "launchpad.grid.rows")
        if let size = lastLayoutSize {
            updateLayout(for: size, topInset: topInset, bottomInset: bottomInset)
        }
    }

    func resetForPresentation() {
        cancelDrag()
        folderAnimationTask?.cancel()
        query = ""
        selectedID = nil
        openFolderID = nil
        folderNameDraft = ""
        isFolderExpanded = false
        folderPanelFrame = .zero
        currentPage = max(0, defaults.integer(forKey: pageKey))
        // A fresh scan may be waiting for a folder that was hidden without closing.
        // Apply it now because the next reload can reuse the cached catalog.
        applyPendingCatalog()
        clampPage()
    }

    func updateLayout(for size: CGSize, topInset: CGFloat, bottomInset: CGFloat) {
        lastLayoutSize = size
        let visibleAnchor = itemPages.indices.contains(currentPage) ? itemPages[currentPage].first?.id : nil
        let previousCapacity = pageSize
        self.topInset = max(topInset, 24)
        self.bottomInset = max(bottomInset, 72)
        // Native Launchpad keeps a generous side inset so corner icons don't feel clipped.
        horizontalInset = min(118, max(24, size.width * 0.08))
        let horizontalPadding = horizontalInset * 2
        let verticalChrome = self.topInset + self.bottomInset + 132
        maximumColumns = max(1, min(12, Int((size.width - horizontalPadding) / LaunchpadMetrics.cellWidth)))
        maximumRows = max(1, min(8, Int((size.height - verticalChrome) / LaunchpadMetrics.cellHeight)))
        columns = min(maximumColumns, usesAutomaticGrid ? 7 : preferredColumns)
        rows = min(maximumRows, usesAutomaticGrid ? 5 : preferredRows)
        if previousCapacity != pageSize {
            // Smaller screens may split a page; larger screens never join pages.
            fitPagesToCapacity()
            if let visibleAnchor, let position = position(of: visibleAnchor) {
                currentPage = position.page
            }
            if !isLoading { persistLayout() }
        }
        clampPage()
    }

    /// Reopening uses the catalog already in memory. A periodic check on open
    /// also covers missed filesystem events without running a background timer.
    func reload(force: Bool = false) {
        if force { catalogGeneration &+= 1 }
        guard reloadTask == nil else { return }
        if completedCatalogGeneration == catalogGeneration,
           let lastScanTime, uptime() - lastScanTime < refreshInterval { return }
        let requestedGeneration = catalogGeneration
        let scan = scanCatalog
        isRefreshing = true
        reloadTask = Task { [weak self] in
            let scanned = await scan()
            guard let self else { return }
            self.reloadTask = nil
            self.isRefreshing = false
            // A change during scanning requires one more scan. Never persist a
            // snapshot made obsolete by an installation or removal in progress.
            guard self.catalogGeneration == requestedGeneration else {
                self.reload()
                return
            }
            self.completedCatalogGeneration = requestedGeneration
            self.lastScanTime = self.uptime()
            let catalog = Dictionary(scanned.map { ($0.url.path, $0) }, uniquingKeysWith: { first, _ in first })
            if self.isLoading || self.pendingCatalog != nil || catalog != self.appCatalog {
                self.applyScannedApps(scanned)
            }
        }
    }

    func invalidateCatalog() {
        catalogGeneration &+= 1
        reload()
    }

    func applyScannedApps(_ scanned: [InstalledApp]) {
        // A scan must not replace a layout while a gesture or rename is in progress.
        guard !isReordering, openFolderID == nil else {
            pendingCatalog = scanned
            return
        }
        rebuildItems(from: scanned)
        isLoading = false
        persistLayout()
        clampPage()
        prefetchVisibleIcons()
    }

    private func applyPendingCatalog() {
        guard !isReordering, openFolderID == nil, let scanned = pendingCatalog else { return }
        pendingCatalog = nil
        applyScannedApps(scanned)
    }

    func prefetchVisibleIcons() {
        let visiblePages = pages
        let pageIndex = min(max(currentPage, 0), visiblePages.count - 1)
        var appsToPreheat: [InstalledApp] = []
        for item in visiblePages[pageIndex] {
            switch item {
            case .app(let app):
                appsToPreheat.append(app)
            case .folder(let folder):
                appsToPreheat.append(contentsOf: apps(in: folder).prefix(4))
            }
        }
        // Warm a few icons in either direction without loading the entire catalog.
        for neighbor in [pageIndex - 1, pageIndex + 1] where visiblePages.indices.contains(neighbor) {
            for item in visiblePages[neighbor].prefix(columns) {
                if case .app(let app) = item { appsToPreheat.append(app) }
            }
        }
        IconCache.preheatAsync(apps: appsToPreheat)
    }

    func beginDrag(_ item: LaunchpadItem, pageFrame: CGSize) {
        guard !isSearching, !isReordering else { return }
        guard let position = position(of: item.id), position.page == currentPage else { return }
        let index = position.page * pageSize + position.index
        draggingItem = item
        dragOriginIndex = index
        dragOriginPage = currentPage
        reorderTargetIndex = index
        lastDragPageFrame = pageFrame
        dragHasMoved = false
        dragSourceFolderID = nil
        mergeTargetID = nil
        selectedID = nil
        dragPosition = cellCenter(for: index, pageWidth: pageFrame.width, pageHeight: pageFrame.height)
        DragSafetyMonitor.shared.start(store: self)
    }

    func beginDragAppFromFolder(_ app: InstalledApp, folderID: UUID, at localPoint: CGPoint) {
        beginFolderDrag(app, folderID: folderID, startInOverlay: localPoint)
    }

    private var folderDragBase: CGPoint?
    private var lastDragPageFrame: CGSize = .zero

    func beginFolderDrag(_ app: InstalledApp, folderID: UUID, startInOverlay: CGPoint) {
        guard !isReordering,
              let folder = items.compactMap(\.folderValue).first(where: { $0.id == folderID }),
              folder.appPaths.contains(app.url.path) else { return }
        draggingItem = .app(app)
        dragOriginIndex = nil
        dragHasMoved = false
        dragSourceFolderID = folderID
        mergeTargetID = nil
        selectedID = nil
        folderDragBase = startInOverlay
        dragPosition = startInOverlay
        lastDragPageFrame = .zero
        DragSafetyMonitor.shared.start(store: self)
    }

    func updateDrag(translation: CGSize, pageFrame: CGSize) {
        guard draggingItem != nil else { return }
        lastDragPageFrame = pageFrame
        lastDragTranslation = translation

        // Folder-source drag: only track position for drop-out detection.
        if dragSourceFolderID != nil {
            guard let base = folderDragBase else { return }
            let distance = hypot(translation.width, translation.height)
            if distance > 10 { dragHasMoved = true }
            dragPosition = CGPoint(x: base.x + translation.width, y: base.y + translation.height)
            return
        }

        guard pageFrame.width > 1, pageFrame.height > 1 else { return }
        guard let origin = dragOriginIndex else { return }
        let start = cellCenter(for: origin, pageWidth: pageFrame.width, pageHeight: pageFrame.height)
        let pointer = CGPoint(
            x: start.x + translation.width + CGFloat(currentPage - dragOriginPage) * pageFrame.width,
            y: start.y + translation.height
        )
        dragPosition = pointer

        let distance = hypot(translation.width, translation.height)
        if distance > 10 { dragHasMoved = true }
        guard dragHasMoved else { return }

        updateEdgePaging(pointer: pointer, pageFrame: pageFrame)
        updateMergeCandidate(at: pointer, pageFrame: pageFrame)

        let xInPage = pointer.x - CGFloat(currentPage) * pageFrame.width
        let cellWidth = pageFrame.width / CGFloat(max(columns, 1))
        let cellHeight = pageFrame.height / CGFloat(max(rows, 1))
        let column = min(max(Int(xInPage / cellWidth), 0), max(columns - 1, 0))
        let row = min(max(Int(pointer.y / cellHeight), 0), max(rows - 1, 0))
        reorderTargetIndex = currentPage * pageSize + row * columns + column
    }

    private func updateMergeCandidate(at pointer: CGPoint, pageFrame: CGSize) {
        let candidate = mergeTarget(at: pointer, pageFrame: pageFrame, excluding: draggingItem?.id ?? "")
        guard candidate != mergeCandidateID else { return }
        mergeTask?.cancel()
        mergeTargetID = nil
        mergeCandidateID = candidate
        guard let candidate else { return }
        mergeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard let self, self.isReordering, self.mergeCandidateID == candidate else { return }
            self.mergeTargetID = candidate
        }
    }

    private func updateEdgePaging(pointer: CGPoint, pageFrame: CGSize) {
        let localX = pointer.x - CGFloat(currentPage) * pageFrame.width
        let margin = min(44, pageFrame.width * 0.08)
        let lastPage = itemPages.count - 1
        let direction: Int
        if localX < margin, currentPage > 0 { direction = -1 }
        else if localX > pageFrame.width - margin, currentPage < lastPage { direction = 1 }
        else { direction = 0 }
        guard direction != edgeDirection else { return }
        edgeTask?.cancel()
        edgeDirection = direction
        guard direction != 0 else { return }
        edgeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard let self, self.isReordering, self.edgeDirection == direction else { return }
            self.currentPage += direction
            self.edgeDirection = 0
            self.updateDrag(translation: self.lastDragTranslation, pageFrame: self.lastDragPageFrame)
        }
    }

    func endFolderDrag(dropOutside: Bool? = nil) {
        defer { clearDragState() }
        guard dragHasMoved else { return }
        let outside: Bool
        if let dropOutside {
            outside = dropOutside
        } else if let pos = dragPosition, !folderPanelFrame.isEmpty {
            outside = !folderPanelFrame.insetBy(dx: -12, dy: -12).contains(pos)
        } else {
            outside = false
        }
        guard outside,
              let folderID = dragSourceFolderID,
              case .app(let app) = draggingItem else {
            return
        }
        commitOpenFolderName()
        guard let folderPosition = position(of: "folder:\(folderID.uuidString)") else { return }
        removeAppFromFolder(app.url.path, folderID: folderID)
        insert(.app(app), onPage: folderPosition.page, at: folderPosition.index + 1)
        folderAnimationTask?.cancel()
        openFolderID = nil
        isFolderExpanded = false
        folderNameDraft = ""
        query = ""
        currentPage = position(of: LaunchpadItem.app(app).id)?.page ?? folderPosition.page
        selectedID = LaunchpadItem.app(app).id
        persistLayout()
        clampPage()
    }

    private func clearDragState() {
        mergeTask?.cancel()
        mergeTask = nil
        edgeTask?.cancel()
        edgeTask = nil
        mergeCandidateID = nil
        edgeDirection = 0
        reorderTargetIndex = nil
        lastDragPageFrame = .zero
        lastDragTranslation = .zero
        draggingItem = nil
        dragPosition = nil
        dragOriginIndex = nil
        dragHasMoved = false
        mergeTargetID = nil
        dragSourceFolderID = nil
        folderDragBase = nil
        DragSafetyMonitor.shared.stop()
        applyPendingCatalog()
    }

    func endDrag() {
        if dragSourceIsFolder {
            endFolderDrag()
            return
        }
        defer { clearDragState() }
        guard dragHasMoved else { return }

        if let mergeID = mergeTargetID, case .app(let app) = draggingItem {
            performMerge(app: app, ontoItemID: mergeID)
        } else if let target = reorderTargetIndex {
            moveDraggingItem(to: target)
        }
        persistLayout()
        clampPage()
    }

    func cancelDrag() {
        if isReordering, !dragSourceIsFolder { currentPage = dragOriginPage }
        clearDragState()
    }

    func openFolder(_ folder: LaunchpadFolder) {
        folderAnimationTask?.cancel()
        let folderItemID = LaunchpadItem.folder(folder).id
        selectionBeforeOpeningFolder = selectedID == folderItemID ? folderItemID : nil
        openFolderID = folder.id
        folderNameDraft = folder.name
        cancelDrag()
        selectedID = nil
        folderPanelFrame = .zero
        isFolderExpanded = false
        folderAnimationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, openFolderID == folder.id else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isFolderExpanded = true
            }
        }
    }

    func closeFolder() {
        commitOpenFolderName()
        guard openFolderID != nil else { return }
        cancelDrag()
        folderAnimationTask?.cancel()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.92)) {
            isFolderExpanded = false
        }
        let closingID = openFolderID
        // Preserve keyboard focus (and search scroll position), without adding
        // a selection highlight after a folder was opened with the mouse.
        let returningSelection = isSearching
            ? closingID.map { "folder:\($0.uuidString)" }
            : selectionBeforeOpeningFolder
        folderAnimationTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard openFolderID == closingID, !isFolderExpanded else { return }
            openFolderID = nil
            folderNameDraft = ""
            selectedID = returningSelection
            selectionBeforeOpeningFolder = nil
            applyPendingCatalog()
        }
    }

    func renameOpenFolder(_ name: String) {
        folderNameDraft = name
    }

    func commitOpenFolderName() {
        guard let openFolderID,
              let position = position(of: "folder:\(openFolderID.uuidString)"),
              var folder = itemPages[position.page][position.index].folderValue else { return }
        let trimmed = folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            folderNameDraft = folder.name
            return
        }
        guard folder.name != trimmed else { return }
        folder.name = trimmed
        itemPages[position.page][position.index] = .folder(folder)
        persistLayout()
    }

    func launchSelected() {
        guard !isReordering, let selectedItem else { return }
        switch selectedItem {
        case .app(let app): OverlayController.shared.launch(app)
        case .folder(let folder): openFolder(folder)
        }
    }

    func revealInFinder(_ app: InstalledApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    func moveSelection(_ direction: MoveDirection) {
        if !isSearching, openFolderID == nil {
            moveGridSelection(direction)
            return
        }
        let list = navigationItems
        guard !isReordering, !list.isEmpty else { return }

        let firstIndex = isSearching || openFolderID != nil ? 0 : min(currentPage * pageSize, list.count - 1)
        guard let currentIndex = list.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = list[firstIndex].id
            return
        }

        let clamped = min(max(currentIndex, 0), list.count - 1)
        let columnCount = openFolderID == nil ? columns : folderColumns

        let nextIndex: Int
        switch direction {
        case .left: nextIndex = max(0, clamped - 1)
        case .right: nextIndex = min(list.count - 1, clamped + 1)
        case .up: nextIndex = max(0, clamped - columnCount)
        case .down: nextIndex = min(list.count - 1, clamped + columnCount)
        }

        selectedID = list[nextIndex].id
        if !isSearching, openFolderID == nil {
            currentPage = nextIndex / pageSize
        }
    }

    func goToPage(_ page: Int) {
        guard !isSearching, !isReordering else { return }
        currentPage = min(max(0, page), max(pages.count - 1, 0))
        selectedID = nil
    }

    func clampPage() {
        // During the initial scan the empty grid is not the saved layout.
        guard !isLoading, !isSearching else { return }
        let last = itemPages.count - 1
        let clamped = min(max(currentPage, 0), last)
        if currentPage != clamped {
            currentPage = clamped
        }
    }

    // MARK: - Private

    private func rebuildItems(from scanned: [InstalledApp]) {
        appCatalog = Dictionary(scanned.map { ($0.url.path, $0) }, uniquingKeysWith: { first, _ in first })
        var remaining = appCatalog

        var seenFolderIDs = Set<UUID>()
        let savedFolders = loadFolders().filter { seenFolderIDs.insert($0.id).inserted }.map { folder -> LaunchpadFolder in
            var copy = folder
            copy.appPaths = folder.appPaths.filter { path in
                remaining.removeValue(forKey: path) != nil
            }
            return copy
        }.filter { !$0.appPaths.isEmpty }

        let folderByID = Dictionary(uniqueKeysWithValues: savedFolders.map { ($0.id, $0) })
        let legacyOrder = defaults.stringArray(forKey: orderKey) ?? []
        let savedPages = (defaults.array(forKey: pageLayoutKey) as? [[String]]) ?? chunked(legacyOrder)
        var usedFolderIDs = Set<UUID>()
        itemPages = savedPages.map { tokens in
            tokens.compactMap { token -> LaunchpadItem? in
                if token.hasPrefix("folder:") {
                    let idString = String(token.dropFirst("folder:".count))
                    guard let id = UUID(uuidString: idString), let folder = folderByID[id],
                          usedFolderIDs.insert(id).inserted else { return nil }
                    return .folder(folder)
                }
                let path = token.hasPrefix("app:") ? String(token.dropFirst("app:".count)) : token
                let app = remaining.removeValue(forKey: path)
                return hiddenAppPaths.contains(path) ? nil : app.map(LaunchpadItem.app)
            }
        }
        fitPagesToCapacity()
        trimTrailingEmptyPages()

        // New apps join the last page; earlier pages keep their deliberately unused space.
        let extras = savedFolders.filter { !usedFolderIDs.contains($0.id) }.map(LaunchpadItem.folder)
            + remaining.values.filter { !hiddenAppPaths.contains($0.url.path) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map(LaunchpadItem.app)
        for item in extras {
            let last = itemPages.count - 1
            if itemPages[last].count < pageSize { itemPages[last].append(item) }
            else { itemPages.append([item]) }
        }
    }

    private func position(of id: String) -> (page: Int, index: Int)? {
        for (page, pageItems) in itemPages.enumerated() {
            if let index = pageItems.firstIndex(where: { $0.id == id }) { return (page, index) }
        }
        return nil
    }

    private func fitPagesToCapacity() {
        itemPages = itemPages.flatMap { chunked($0) }
        if itemPages.isEmpty { itemPages = [[]] }
    }

    private func trimTrailingEmptyPages() {
        while itemPages.count > 1, itemPages.last?.isEmpty == true { itemPages.removeLast() }
        if itemPages.isEmpty { itemPages = [[]] }
    }

    /// Explicit insertion may push a full page forward, but never pulls items backward.
    private func insert(_ item: LaunchpadItem, onPage page: Int, at index: Int) {
        while itemPages.count <= page { itemPages.append([]) }
        itemPages[page].insert(item, at: min(max(index, 0), itemPages[page].count))
        var overflowPage = page
        while itemPages[overflowPage].count > pageSize {
            let overflow = itemPages[overflowPage].removeLast()
            overflowPage += 1
            if overflowPage == itemPages.count { itemPages.append([]) }
            itemPages[overflowPage].insert(overflow, at: 0)
        }
    }

    private func performMerge(app: InstalledApp, ontoItemID targetID: String) {
        let draggedID = LaunchpadItem.app(app).id
        guard draggedID != targetID, let source = position(of: draggedID),
              position(of: targetID) != nil else { return }
        itemPages[source.page].remove(at: source.index)
        guard let target = position(of: targetID) else { return }
        switch itemPages[target.page][target.index] {
        case .app(let other):
            itemPages[target.page][target.index] = .folder(LaunchpadFolder(appPaths: [other.url.path, app.url.path]))
        case .folder(var folder):
            if !folder.appPaths.contains(app.url.path) { folder.appPaths.append(app.url.path) }
            itemPages[target.page][target.index] = .folder(folder)
        }
        trimTrailingEmptyPages()
        mergeTargetID = nil
    }

    private func removeAppFromFolder(_ path: String, folderID: UUID) {
        guard let position = position(of: "folder:\(folderID.uuidString)"),
              var folder = itemPages[position.page][position.index].folderValue else { return }
        folder.appPaths.removeAll { $0 == path }
        if folder.appPaths.count <= 1 && !folder.appPaths.contains(where: { hiddenAppPaths.contains($0) }) {
            itemPages[position.page].remove(at: position.index)
            if let last = folder.appPaths.first, let app = appCatalog[last] {
                itemPages[position.page].insert(.app(app), at: position.index)
            }
            if openFolderID == folderID { openFolderID = nil }
        } else {
            itemPages[position.page][position.index] = .folder(folder)
        }
    }

    private func moveDraggingItem(to target: Int) {
        guard let draggingItem, let source = position(of: draggingItem.id) else { return }
        let destinationPage = min(max(target / pageSize, 0), itemPages.count - 1)
        let destinationIndex = target % pageSize
        itemPages[source.page].remove(at: source.index)
        insert(draggingItem, onPage: destinationPage, at: destinationIndex)
        trimTrailingEmptyPages()
    }

    private func mergeTarget(at pointer: CGPoint, pageFrame: CGSize, excluding excludedID: String) -> String? {
        guard case .app = draggingItem, itemPages.indices.contains(currentPage) else { return nil }
        let xInPage = pointer.x - CGFloat(currentPage) * pageFrame.width
        let cellWidth = pageFrame.width / CGFloat(max(columns, 1))
        let cellHeight = pageFrame.height / CGFloat(max(rows, 1))
        guard cellWidth > 1, cellHeight > 1 else { return nil }
        let column = Int(floor(xInPage / cellWidth))
        let row = Int(floor(pointer.y / cellHeight))
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        let localIndex = row * columns + column
        guard localIndex < itemPages[currentPage].count else { return nil }
        let candidate = itemPages[currentPage][localIndex]
        guard candidate.id != excludedID else { return nil }
        let slot = currentPage * pageSize + localIndex
        let center = cellCenter(for: slot, pageWidth: pageFrame.width, pageHeight: pageFrame.height)
        let radius = LaunchpadMetrics.iconSize * (mergeTargetID == candidate.id ? 0.48 : 0.34)
        guard abs(pointer.x - center.x) <= radius, abs(pointer.y - center.y) <= radius else { return nil }
        return candidate.id
    }

    private func moveGridSelection(_ direction: MoveDirection) {
        guard !isReordering else { return }
        let forward = direction == .right || direction == .down
        guard let selectedID, let current = position(of: selectedID) else {
            if itemPages.indices.contains(currentPage), let first = itemPages[currentPage].first {
                self.selectedID = first.id
            } else if let page = adjacentOccupiedPage(to: currentPage, forward: forward) {
                currentPage = page
                self.selectedID = itemPages[page].first?.id
            }
            return
        }
        let count = itemPages[current.page].count
        let column = current.index % max(columns, 1)
        let next: Int
        switch direction {
        case .left: next = current.index - 1
        case .right: next = current.index + 1
        case .up: next = current.index - columns
        case .down: next = current.index + columns
        }
        if next >= 0, next < count {
            self.selectedID = itemPages[current.page][next].id
            currentPage = current.page
        } else if direction == .down, current.index / columns < (count - 1) / columns {
            // The final row may have fewer columns; select its last occupied cell.
            self.selectedID = itemPages[current.page][count - 1].id
        } else if let page = adjacentOccupiedPage(to: current.page, forward: forward) {
            let nextCount = itemPages[page].count
            let index: Int
            switch direction {
            case .left: index = nextCount - 1
            case .right: index = 0
            case .up: index = min(((nextCount - 1) / columns) * columns + column, nextCount - 1)
            case .down: index = min(column, nextCount - 1)
            }
            self.selectedID = itemPages[page][index].id
            currentPage = page
        }
    }

    private func adjacentOccupiedPage(to page: Int, forward: Bool) -> Int? {
        var candidate = page + (forward ? 1 : -1)
        while itemPages.indices.contains(candidate) {
            if !itemPages[candidate].isEmpty { return candidate }
            candidate += forward ? 1 : -1
        }
        return nil
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

    private func loadFolders() -> [LaunchpadFolder] {
        guard let data = defaults.data(forKey: foldersKey) else { return [] }
        return (try? JSONDecoder().decode([LaunchpadFolder].self, from: data)) ?? []
    }

    private func persistLayout() {
        let tokens: [String] = items.map { item in
            switch item {
            case .app(let app): "app:\(app.url.path)"
            case .folder(let folder): "folder:\(folder.id.uuidString)"
            }
        }
        defaults.set(tokens, forKey: orderKey)
        defaults.set(itemPages.map { $0.map(\.id) }, forKey: pageLayoutKey)

        let folders = items.compactMap(\.folderValue)
        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: foldersKey)
        }
    }

    private func persistCurrentPage() {
        guard !isSearching, !isLoading else { return }
        defaults.set(currentPage, forKey: pageKey)
    }
}
