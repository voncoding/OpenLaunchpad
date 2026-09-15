import Foundation

@MainActor
enum SettingsRegression {
    typealias Checks = InteractionRegressionTests

    static func gridPersistence() async throws {
        let fixture = Checks.Fixture(apps: PageLayoutRegression.catalog(25))
        defer { fixture.cleanUp() }
        let store = fixture.store
        let size = CGSize(width: 1440, height: 1000)
        store.updateLayout(for: size, topInset: 28, bottomInset: 72)
        store.setAutomaticGrid(false)
        store.setGridColumns(3)
        store.setGridRows(2)
        try Checks.expect(store.columns == 3 && store.rows == 2, "manual grid did not apply immediately")
        let smallerPages = PageLayoutRegression.ids(store)
        let restored = LaunchpadStore(defaults: fixture.defaults)
        restored.updateLayout(for: size, topInset: 28, bottomInset: 72)
        restored.applyScannedApps(Array(store.appCatalog.values))
        try Checks.expect(!restored.usesAutomaticGrid && restored.columns == 3 && restored.rows == 2, "manual grid did not survive restart")
        try Checks.expect(PageLayoutRegression.ids(restored) == smallerPages, "restart changed custom grid pages")
        store.setAutomaticGrid(true)
        try Checks.expect(PageLayoutRegression.ids(store) == smallerPages, "increasing grid capacity backfilled earlier pages")
        store.setAutomaticGrid(false)
        try Checks.expect(store.columns == 3 && store.rows == 2, "automatic toggle discarded custom grid")
    }

    static func screenLimits() async throws {
        let fixture = Checks.Fixture(apps: [])
        defer { fixture.cleanUp() }
        let store = fixture.store
        let large = CGSize(width: 1920, height: 1400)
        store.updateLayout(for: large, topInset: 28, bottomInset: 72)
        store.setAutomaticGrid(false)
        store.setGridColumns(9)
        store.setGridRows(6)
        store.updateLayout(for: CGSize(width: 800, height: 600), topInset: 28, bottomInset: 72)
        try Checks.expect(store.columns == 4 && store.rows == 2, "custom grid overflowed a smaller screen")
        store.updateLayout(for: large, topInset: 28, bottomInset: 72)
        try Checks.expect(store.columns == 9 && store.rows == 6, "smaller screen overwrote preferred dimensions")
    }

    static func visibilityPersistence() async throws {
        let apps = PageLayoutRegression.catalog(25)
        let fixture = Checks.Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let later = Array(PageLayoutRegression.ids(store).dropFirst())
        store.setAppVisible(false, path: apps[0].url.path)
        try Checks.expect(store.pages[0].count == 11 && Array(PageLayoutRegression.ids(store).dropFirst()) == later, "hiding backfilled an earlier page")
        store.query = apps[0].name
        try Checks.expect(store.displayItems.isEmpty, "hidden app remains searchable")
        store.query = ""
        let restored = LaunchpadStore(defaults: fixture.defaults)
        restored.columns = 4
        restored.rows = 3
        restored.applyScannedApps(apps)
        try Checks.expect(restored.hiddenAppCount == 1 && PageLayoutRegression.ids(restored) == PageLayoutRegression.ids(store), "scan or restart restored a hidden app")
        restored.applyScannedApps(Array(apps.dropFirst()))
        restored.applyScannedApps(apps)
        try Checks.expect(!restored.items.contains(.app(apps[0])), "reinstallation exposed a hidden app")
        restored.setAppVisible(true, path: apps[0].url.path)
        try Checks.expect(restored.pages[0].count == 11 && restored.pages.last?.last?.id == LaunchpadItem.app(apps[0]).id, "restore filled a gap instead of appending to last page")
        restored.setAppVisible(true, path: apps[0].url.path)
        try Checks.expect(restored.items.filter { $0.id == LaunchpadItem.app(apps[0]).id }.count == 1, "repeat restore duplicated an app")
    }

    static func folderVisibility() async throws {
        let apps = [Checks.app("HiddenAlpha"), Checks.app("VisibleBeta")]
        let folder = LaunchpadFolder(appPaths: apps.map { $0.url.path })
        let fixture = Checks.Fixture(apps: apps, folders: [folder])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.setAppVisible(false, path: apps[0].url.path)
        store.applyScannedApps(apps)
        try Checks.expect(store.items.first?.folderValue?.appPaths == folder.appPaths, "scan discarded hidden folder membership")
        try Checks.expect(store.apps(in: folder).map(\.id) == [apps[1].id], "folder preview exposed a hidden app")
        store.query = apps[0].name
        try Checks.expect(store.displayItems.isEmpty, "folder search exposed a hidden app")
        store.query = ""
        store.openFolder(folder)
        try Checks.expect(store.openFolderApps.map(\.id) == [apps[1].id], "open folder exposed a hidden app")
        store.beginFolderDrag(apps[1], folderID: folder.id, startInOverlay: CGPoint(x: 120, y: 150))
        store.updateDrag(translation: CGSize(width: 200, height: 0), pageFrame: Checks.pageFrame)
        store.endFolderDrag(dropOutside: true)
        try Checks.expect(store.items.compactMap(\.folderValue).first?.appPaths == [apps[0].url.path], "extracting visible app dissolved hidden membership")
        try Checks.expect(!store.items.contains(.app(apps[0])), "folder dissolution exposed a hidden app")
        store.setAppVisible(true, path: apps[0].url.path)
        let remaining = store.items.compactMap(\.folderValue).first!
        try Checks.expect(store.apps(in: remaining).map(\.id) == [apps[0].id] && store.items.count == 2, "restoring a folder app appended it outside the folder")
    }

    static func hideAll() async throws {
        let apps = PageLayoutRegression.catalog(15)
        let fixture = Checks.Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.goToPage(1)
        for app in apps { store.setAppVisible(false, path: app.url.path) }
        try Checks.expect(store.pages.count == 1 && store.pages[0].isEmpty && store.currentPage == 0, "hiding all apps left an invalid page")
        store.applyScannedApps(apps)
        try Checks.expect(store.items.isEmpty && store.hiddenAppCount == apps.count, "scan repopulated the hidden grid")
        for app in apps { store.setAppVisible(true, path: app.url.path) }
        try Checks.expect(store.items.count == apps.count && store.hiddenAppCount == 0, "restore lost applications")
    }
}
