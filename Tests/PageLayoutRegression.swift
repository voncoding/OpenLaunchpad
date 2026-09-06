import Foundation

@MainActor
enum PageLayoutRegression {
    typealias Checks = InteractionRegressionTests
    static let key = "launchpad.pageLayout.v1"

    static func ids(_ store: LaunchpadStore) -> [[String]] { store.pages.map { $0.map(\.id) } }
    static func catalog(_ count: Int) -> [InstalledApp] { (0..<count).map { Checks.app("PageApp\($0)") } }

    static func mergeAndRestore() async throws {
        let apps = catalog(25)
        let fixture = Checks.Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let before = ids(store)
        store.beginDrag(.app(apps[0]), pageFrame: Checks.pageFrame)
        store.updateDrag(translation: CGSize(width: 156, height: 0), pageFrame: Checks.pageFrame)
        try await Checks.pauseForHover()
        store.endDrag()
        try Checks.expect(store.pages[0].count == 11, "merging should leave the last slot of this page unused")
        try Checks.expect(Array(ids(store).dropFirst()) == Array(before.dropFirst()), "merging pulled an app out of a later page")
        let expected = ids(store)
        let restored = LaunchpadStore(defaults: fixture.defaults)
        restored.columns = 4
        restored.rows = 3
        restored.applyScannedApps(apps)
        try Checks.expect(ids(restored) == expected, "restart filled the intentionally partial page")
    }

    static func secondPageCoordinates() async throws {
        let apps = catalog(15)
        let fixture = Checks.Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        fixture.defaults.set([Array(apps.prefix(3)), Array(apps.dropFirst(3))].map { $0.map { LaunchpadItem.app($0).id } }, forKey: key)
        store.applyScannedApps(apps)
        let firstPage = ids(store)[0]
        store.goToPage(1)
        store.moveSelection(.right)
        try Checks.expect(store.selectedID == LaunchpadItem.app(apps[3]).id, "keyboard start used a flattened page offset")
        store.beginDrag(.app(apps[3]), pageFrame: Checks.pageFrame)
        try Checks.expect(store.dragPosition?.x == 702, "drag origin did not use the visible page's first cell")
        store.updateDrag(translation: CGSize(width: 156, height: 0), pageFrame: Checks.pageFrame)
        try await Checks.pauseForHover()
        try Checks.expect(store.mergeTargetID == LaunchpadItem.app(apps[4]).id, "merge hit-testing used the wrong item after a partial page")
        store.endDrag()
        try Checks.expect(ids(store)[0] == firstPage && store.pages[1].count == 11, "editing page two changed page one")
        try Checks.expect(Set(store.pages[1][0].folderValue?.appPaths ?? []) == Set([apps[3].url.path, apps[4].url.path]), "wrong apps were merged on the second page")
    }

    static func emptyPageAndKeyboard() async throws {
        let apps = catalog(3)
        let fixture = Checks.Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        fixture.defaults.set([[LaunchpadItem.app(apps[0]).id], apps.dropFirst().map { LaunchpadItem.app($0).id }], forKey: key)
        store.applyScannedApps(apps)
        store.beginDrag(.app(apps[0]), pageFrame: Checks.pageFrame)
        store.updateDrag(translation: CGSize(width: 544, height: 0), pageFrame: Checks.pageFrame)
        try await Checks.waitForNextPage(store)
        store.updateDrag(translation: CGSize(width: 156, height: 40), pageFrame: Checks.pageFrame)
        store.endDrag()
        try Checks.expect(store.pages.count == 2 && store.pages[0].isEmpty, "moving the last app pulled the next page into its place")
        store.goToPage(0)
        store.moveSelection(.right)
        try Checks.expect(store.currentPage == 1 && store.selectedID == LaunchpadItem.app(apps[1]).id, "keyboard navigation got stuck on an empty page")
        let before = ids(store)
        store.applyScannedApps(apps)
        try Checks.expect(ids(store) == before, "refresh discarded an intentional empty page")
    }

    static func scanPreservesPages() async throws {
        let apps = catalog(25)
        let fixture = Checks.Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let before = ids(fixture.store)
        let added = Checks.app("NewlyInstalled")
        fixture.store.applyScannedApps(Array(apps.dropFirst()) + [added])
        try Checks.expect(fixture.store.pages[0].count == 11, "scan backfilled the uninstalled app's page")
        try Checks.expect(ids(fixture.store)[1] == before[1], "scan shifted the second page")
        try Checks.expect(fixture.store.pages[2].last?.id == LaunchpadItem.app(added).id, "new app filled an earlier page instead of joining the last page")
    }

    static func resizingPreservesBoundaries() async throws {
        let fixture = Checks.Fixture(apps: catalog(25))
        defer { fixture.cleanUp() }
        let store = fixture.store
        let originalIDs = store.items.map(\.id)
        store.updateLayout(for: CGSize(width: 800, height: 600), topInset: 28, bottomInset: 72)
        try Checks.expect(store.pages.map(\.count) == [8, 4, 8, 4, 1], "smaller layout merged existing page groups")
        let smallPages = ids(store)
        store.updateLayout(for: CGSize(width: 1440, height: 900), topInset: 28, bottomInset: 72)
        try Checks.expect(ids(store) == smallPages, "larger screen filled partial pages from their neighbors")
        try Checks.expect(store.items.map(\.id) == originalIDs, "screen resizing lost or reordered apps")
    }

    static func folderExtractionPreservesPages() async throws {
        let apps = catalog(25)
        let folder = LaunchpadFolder(appPaths: apps.prefix(2).map { $0.url.path })
        let fixture = Checks.Fixture(apps: apps, folders: [folder])
        defer { fixture.cleanUp() }
        let store = fixture.store
        let folderID = LaunchpadItem.folder(folder).id
        let pageOne = [folderID] + apps[2..<5].map { LaunchpadItem.app($0).id }
        let later = stride(from: 5, to: apps.count, by: 12).map { start in
            apps[start..<min(start + 12, apps.count)].map { LaunchpadItem.app($0).id }
        }
        fixture.defaults.set([pageOne] + later, forKey: key)
        store.applyScannedApps(apps)
        store.openFolder(folder)
        store.folderPanelFrame = CGRect(x: 100, y: 100, width: 400, height: 400)
        store.beginFolderDrag(apps[0], folderID: folder.id, startInOverlay: CGPoint(x: 120, y: 150))
        store.updateDrag(translation: CGSize(width: -60, height: 0), pageFrame: Checks.pageFrame)
        store.endFolderDrag()
        try Checks.expect(store.pages[0].count == 5 && Array(ids(store).dropFirst()) == later, "extracting an app repartitioned later pages")
        try Checks.expect(store.currentPage == 0 && store.pages[0][1].appValue?.id == apps[0].id, "extracted app did not remain beside its former folder")
    }

    static func legacyMigration() async throws {
        let apps = catalog(25)
        let fixture = Checks.Fixture(apps: apps)
        defer { fixture.cleanUp() }
        fixture.defaults.removeObject(forKey: key)
        let restored = LaunchpadStore(defaults: fixture.defaults)
        restored.columns = 4
        restored.rows = 3
        restored.applyScannedApps(Array(apps.dropFirst()))
        try Checks.expect(restored.pages.map(\.count) == [11, 12, 1], "legacy migration compacted across saved page boundaries")
        try Checks.expect(restored.pages[1].first?.id == LaunchpadItem.app(apps[12]).id, "legacy second page changed its starting app")
    }
}
