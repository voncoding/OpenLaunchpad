import AppKit
import Foundation

/// A lightweight regression runner against the real app sources, without an Xcode test target.
@main
@MainActor
struct InteractionRegressionTests {
    struct CheckFailure: Error, CustomStringConvertible {
        let description: String
    }

    struct Fixture {
        let store: LaunchpadStore
        let defaults: UserDefaults
        let suiteName: String

        init(apps: [InstalledApp], folders: [LaunchpadFolder] = [], order: [String]? = nil, savedPage: Int = 0) {
            suiteName = "OpenLaunchpad.InteractionTests.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.set(savedPage, forKey: "launchpad.lastPage")
            if let order {
                defaults.set(order, forKey: "launchpad.iconOrder")
            } else if folders.isEmpty {
                defaults.set(apps.map { LaunchpadItem.app($0).id }, forKey: "launchpad.iconOrder")
            }
            if !folders.isEmpty {
                defaults.set(try! JSONEncoder().encode(folders), forKey: "launchpad.folders")
            }
            store = LaunchpadStore(defaults: defaults)
            store.columns = 4
            store.rows = 3
            store.applyScannedApps(apps)
        }

        func cleanUp() {
            store.cancelDrag()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    static let pageFrame = CGSize(width: 624, height: 474)

    static func app(_ name: String) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: "/OpenLaunchpadTestFixtures/\(name).app"),
            name: name,
            latinName: name.lowercased(),
            initials: String(name.prefix(1)).lowercased(),
            bundleIdentifier: "test.openlaunchpad.\(name.lowercased())"
        )
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ description: String) throws {
        guard condition() else { throw CheckFailure(description: description) }
    }

    static func pauseForHover() async throws {
        try await Task.sleep(for: .milliseconds(600))
    }

    static func main() async {
        let tests: [(String, @MainActor () async throws -> Void)] = [
            ("quick drop reorders without creating a folder", quickDrop),
            ("hover over icon center merges only after delay", deliberateMerge),
            ("hover over cell gap keeps reorder intent", gapDoesNotMerge),
            ("cancelling drag preserves order and preferences", cancelPreservesOrder),
            ("folder drag uses the actual panel boundary", folderBoundary),
            ("extracting an app dissolves a two-app folder", dissolveFolder),
            ("folder rename trims input and preserves a nonempty name", renameFolder),
            ("search keyboard starts at the first result", searchSelection),
            ("folder keyboard uses its own columns", folderSelection),
            ("Return on a selected folder opens it", keyboardOpensFolder),
            ("closing a mouse-opened folder clears its highlight", mouseFolderClosure),
            ("closing a keyboard-opened folder restores navigation", keyboardFolderClosure),
            ("opening another folder cancels the previous close", reopenDuringFolderClosure),
            ("startup preserves saved page before apps finish loading", savedPageBeforeScan),
            ("saved folders recover without an order array", restoreFoldersWithoutOrder),
            ("saved duplicate app membership is normalized", duplicateFolderMembership),
            ("returning to drag origin disarms a merge", returningToOrigin),
            ("edge hover moves an app to another page", edgePageDrop),
            ("cancelling an edge drag restores the original page", cancelEdgeDrag),
            ("a scan arriving during drag preserves the dropped order", scanDuringDrag),
            ("a scan arriving during rename preserves the new name", scanDuringRename),
            ("clearing search clamps the page after catalog shrink", shrinkDuringSearch),
            ("folder scrollbars stay hidden with the Always preference", FolderScrollbarRegression.run),
            ("merging preserves page gaps across restart", PageLayoutRegression.mergeAndRestore),
            ("partial pages keep correct drag and keyboard coordinates", PageLayoutRegression.secondPageCoordinates),
            ("an emptied page stays empty and remains navigable", PageLayoutRegression.emptyPageAndKeyboard),
            ("scanning never backfills an earlier page", PageLayoutRegression.scanPreservesPages),
            ("screen resizing preserves page boundaries", PageLayoutRegression.resizingPreservesBoundaries),
            ("folder extraction preserves later pages", PageLayoutRegression.folderExtractionPreservesPages),
            ("legacy layout migration preserves page boundaries", PageLayoutRegression.legacyMigration),
            ("pager uses full viewport and settles gestures ending outside", PagerEdgeRegression.run),
            ("Photos wallpaper resolves the selected cached asset", WallpaperSourceRegression.selectedAsset),
            ("wallpaper selection is reread after settings change", WallpaperSourceRegression.changingSelection),
            ("wallpaper respects the requested display's desktop setting", WallpaperSourceRegression.displaySelection),
            ("wallpaper never substitutes an arbitrary photo or directory entry", WallpaperSourceRegression.safeFallback),
        ]
        var failures = 0
        for (name, test) in tests {
            do {
                try await test()
                print("PASS \(name)")
            } catch {
                failures += 1
                print("FAIL \(name): \(error)")
            }
        }
        print("\(tests.count - failures)/\(tests.count) interaction regressions passed")
        if failures > 0 { exit(1) }
    }

    static func quickDrop() async throws {
        let apps = [app("Alpha"), app("Beta"), app("Gamma")]
        let fixture = Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.beginDrag(.app(apps[0]), pageFrame: pageFrame)
        store.updateDrag(translation: CGSize(width: 156, height: -18), pageFrame: pageFrame)
        try expect(store.mergeTargetID == nil, "merge must require a deliberate pause")
        store.endDrag()
        try expect(store.items.map(\.id) == [apps[1], apps[0], apps[2]].map { LaunchpadItem.app($0).id }, "quick drop should move the app to its destination")
        try expect(store.items.allSatisfy { !$0.isFolder }, "quick drop unexpectedly created a folder")
        try expect(fixture.defaults.stringArray(forKey: "launchpad.iconOrder") == store.items.map(\.id), "reordered layout was not persisted")
    }

    static func deliberateMerge() async throws {
        let apps = [app("Alpha"), app("Beta"), app("Gamma")]
        let fixture = Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.beginDrag(.app(apps[0]), pageFrame: pageFrame)
        store.updateDrag(translation: CGSize(width: 156, height: -18), pageFrame: pageFrame)
        try await pauseForHover()
        try expect(store.mergeTargetID == LaunchpadItem.app(apps[1]).id, "stationary hover did not arm the target")
        store.endDrag()
        let folders = store.items.compactMap(\.folderValue)
        try expect(folders.count == 1, "deliberate drop did not create exactly one folder")
        try expect(Set(folders[0].appPaths) == Set(apps.prefix(2).map { $0.url.path }), "folder lost or duplicated a merged app")
        try expect(store.items.count == 2, "merge left extra top-level items")
        try expect(!store.isReordering && store.mergeTargetID == nil, "drag feedback stayed active after drop")
    }

    static func gapDoesNotMerge() async throws {
        let apps = [app("Alpha"), app("Beta"), app("Gamma")]
        let fixture = Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.beginDrag(.app(apps[0]), pageFrame: pageFrame)
        // x = 300 is inside Beta's cell (156..<312), but outside its icon.
        store.updateDrag(translation: CGSize(width: 222, height: 0), pageFrame: pageFrame)
        try await pauseForHover()
        try expect(store.mergeTargetID == nil, "empty space around an icon armed a merge")
        store.endDrag()
        try expect(store.items.allSatisfy { !$0.isFolder }, "dropping in a cell gap created a folder")
    }

    static func cancelPreservesOrder() async throws {
        let apps = [app("Alpha"), app("Beta"), app("Gamma")]
        let fixture = Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let original = store.items.map(\.id)
        store.beginDrag(.app(apps[0]), pageFrame: pageFrame)
        store.updateDrag(translation: CGSize(width: 312, height: 40), pageFrame: pageFrame)
        store.cancelDrag()
        try await pauseForHover()
        try expect(store.items.map(\.id) == original, "cancel changed the original order")
        try expect(fixture.defaults.stringArray(forKey: "launchpad.iconOrder") == original, "cancel persisted a partial order")
        try expect(!store.isReordering && store.mergeTargetID == nil, "a delayed hover survived cancellation")
    }

    static func folderBoundary() async throws {
        let apps = [app("Alpha"), app("Beta"), app("Gamma")]
        let folder = LaunchpadFolder(name: "Tools", appPaths: apps.map { $0.url.path })
        let fixture = Fixture(apps: apps, folders: [folder])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.openFolder(folder)
        store.folderPanelFrame = CGRect(x: 100, y: 100, width: 400, height: 400)
        store.beginFolderDrag(apps[0], folderID: folder.id, startInOverlay: CGPoint(x: 150, y: 150))
        store.updateDrag(translation: CGSize(width: 200, height: 0), pageFrame: pageFrame)
        store.endFolderDrag()
        try expect(store.openFolder?.appPaths.count == 3, "moving more than 140 points inside the panel removed an app")
        store.beginFolderDrag(apps[0], folderID: folder.id, startInOverlay: CGPoint(x: 120, y: 150))
        store.updateDrag(translation: CGSize(width: -60, height: 0), pageFrame: pageFrame)
        store.endDrag() // Also exercises the mouse-up safety monitor's generic drop path.
        try expect(store.items.contains { $0.appValue?.id == apps[0].id }, "a short drag across the panel edge failed to extract the app")
        try expect(store.items.compactMap(\.folderValue).first?.appPaths.count == 2, "extraction did not remove membership from the source folder")
    }

    static func dissolveFolder() async throws {
        let apps = [app("Alpha"), app("Beta")]
        let folder = LaunchpadFolder(name: "Tools", appPaths: apps.map { $0.url.path })
        let fixture = Fixture(apps: apps, folders: [folder])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.openFolder(folder)
        store.folderPanelFrame = CGRect(x: 100, y: 100, width: 400, height: 400)
        store.beginFolderDrag(apps[0], folderID: folder.id, startInOverlay: CGPoint(x: 120, y: 150))
        store.updateDrag(translation: CGSize(width: -60, height: 0), pageFrame: pageFrame)
        store.endFolderDrag()
        try expect(store.items.compactMap(\.folderValue).isEmpty, "one-app folder was not dissolved")
        try expect(Set(store.items.compactMap(\.appValue).map(\.id)) == Set(apps.map(\.id)), "dissolving folder lost an app")
        try expect(store.openFolderID == nil, "dissolved folder stayed open")
    }

    static func renameFolder() async throws {
        let apps = [app("Alpha"), app("Beta")]
        let folder = LaunchpadFolder(name: "Tools", appPaths: apps.map { $0.url.path })
        let fixture = Fixture(apps: apps, folders: [folder])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.openFolder(folder)
        store.renameOpenFolder("  \n")
        store.commitOpenFolderName()
        try expect(store.openFolder?.name == "Tools" && store.folderNameDraft == "Tools", "blank rename erased the folder name")
        store.renameOpenFolder("  Work Apps  ")
        store.commitOpenFolderName()
        try expect(store.openFolder?.name == "Work Apps", "rename did not trim whitespace")
        let persisted = try JSONDecoder().decode([LaunchpadFolder].self, from: fixture.defaults.data(forKey: "launchpad.folders")!)
        try expect(persisted.first?.name == "Work Apps", "rename was not persisted")
    }

    static func searchSelection() async throws {
        let apps = (0..<30).map { app(String(format: "Tool%02d", $0)) }
        let fixture = Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.currentPage = 2
        store.query = "Tool"
        store.selectedID = nil
        store.moveSelection(.down)
        try expect(store.selectedID == LaunchpadItem.app(apps[0]).id, "search started at an offset from the old page")
        store.moveSelection(.right)
        try expect(store.selectedID == LaunchpadItem.app(apps[1]).id, "search navigation did not advance to the next result")
        try expect(fixture.defaults.integer(forKey: "launchpad.lastPage") == 2, "search overwrote the remembered page")
        store.query = "   "
        try expect(!store.isSearching, "whitespace-only input must behave as an empty search")
    }

    static func folderSelection() async throws {
        let apps = (0..<8).map { app("Tool\($0)") }
        let folder = LaunchpadFolder(name: "Tools", appPaths: apps.map { $0.url.path })
        let fixture = Fixture(apps: apps, folders: [folder])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.openFolder(folder)
        store.folderColumns = 3
        store.selectedID = LaunchpadItem.app(apps[0]).id
        store.moveSelection(.down)
        try expect(store.selectedID == LaunchpadItem.app(apps[3]).id, "folder navigation used the background grid's columns")
        store.moveSelection(.right)
        try expect(store.selectedID == LaunchpadItem.app(apps[4]).id, "folder navigation did not stay within its apps")
    }

    static func keyboardOpensFolder() async throws {
        let apps = [app("Alpha"), app("Beta")]
        let folder = LaunchpadFolder(name: "Tools", appPaths: apps.map { $0.url.path })
        let fixture = Fixture(apps: apps, folders: [folder])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.selectedID = LaunchpadItem.folder(folder).id
        store.launchSelected()
        try expect(store.openFolderID == folder.id, "Return ignored the selected folder")
    }

    static func mouseFolderClosure() async throws {
        let apps = [app("Alpha"), app("Beta")]
        let folder = LaunchpadFolder(name: "Tools", appPaths: apps.map { $0.url.path })
        let fixture = Fixture(apps: apps, folders: [folder])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.selectedID = nil
        store.openFolder(folder)
        // Navigating inside a mouse-opened folder must not select its outer tile.
        store.moveSelection(.right)
        try expect(store.selectedID == LaunchpadItem.app(apps[0]).id, "test precondition: folder navigation did not select an app")
        store.closeFolder()
        try await Task.sleep(for: .milliseconds(300))
        try expect(store.openFolderID == nil && !store.isFolderExpanded, "folder did not finish closing")
        try expect(store.selectedID == nil, "mouse-opened folder retained an outer selection highlight after closing")
    }

    static func keyboardFolderClosure() async throws {
        let apps = [app("Alpha"), app("Beta"), app("Gamma")]
        let folder = LaunchpadFolder(name: "Tools", appPaths: apps.prefix(2).map { $0.url.path })
        let folderItemID = LaunchpadItem.folder(folder).id
        let nextAppID = LaunchpadItem.app(apps[2]).id
        let fixture = Fixture(apps: apps, folders: [folder], order: [folderItemID, nextAppID])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.selectedID = folderItemID
        store.launchSelected()
        store.moveSelection(.right)
        store.closeFolder()
        try await Task.sleep(for: .milliseconds(300))
        try expect(store.openFolderID == nil, "keyboard-opened folder did not finish closing")
        try expect(store.selectedID == folderItemID, "closing a keyboard-opened folder lost its navigation position")
        store.moveSelection(.right)
        try expect(store.selectedID == nextAppID, "keyboard navigation did not continue from the closed folder")
    }

    static func reopenDuringFolderClosure() async throws {
        let apps = [app("Alpha"), app("Beta"), app("Gamma"), app("Delta")]
        let first = LaunchpadFolder(name: "First", appPaths: apps.prefix(2).map { $0.url.path })
        let second = LaunchpadFolder(name: "Second", appPaths: apps.suffix(2).map { $0.url.path })
        let fixture = Fixture(apps: apps, folders: [first, second])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.selectedID = LaunchpadItem.folder(first).id
        store.launchSelected()
        store.closeFolder()
        store.openFolder(second)
        try await Task.sleep(for: .milliseconds(300))
        try expect(store.openFolderID == second.id && store.isFolderExpanded, "a stale close callback dismissed the newly opened folder")
        try expect(store.folderNameDraft == second.name, "a stale close callback cleared the new folder name")
        try expect(store.selectedID == nil, "a stale close callback restored selection from the previous folder")
        store.closeFolder()
        try await Task.sleep(for: .milliseconds(300))
        try expect(store.openFolderID == nil && store.selectedID == nil, "new folder inherited the previous folder's keyboard selection")
    }

    static func savedPageBeforeScan() async throws {
        let suite = "OpenLaunchpad.InteractionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: "launchpad.lastPage")
        let store = LaunchpadStore(defaults: defaults)
        store.updateLayout(for: CGSize(width: 1440, height: 900), topInset: 28, bottomInset: 80)
        store.resetForPresentation()
        try expect(store.currentPage == 2, "empty loading state discarded the restored page")
        try expect(defaults.integer(forKey: "launchpad.lastPage") == 2, "empty loading state overwrote preferences")
        store.applyScannedApps((0..<100).map { app("Tool\($0)") })
        try expect(store.currentPage == 2, "app scan failed to preserve an existing valid page")
        store.applyScannedApps([app("OnlyApp")])
        try expect(store.currentPage == 0, "completed scan did not clamp a page that no longer exists")
    }

    static func restoreFoldersWithoutOrder() async throws {
        let apps = [app("Alpha"), app("Beta"), app("Gamma")]
        let folder = LaunchpadFolder(name: "Tools", appPaths: apps.prefix(2).map { $0.url.path })
        let fixture = Fixture(apps: apps, folders: [folder])
        defer { fixture.cleanUp() }
        try expect(fixture.store.items.compactMap(\.folderValue).map(\.id) == [folder.id], "saved folder disappeared when order preferences were absent")
        try expect(fixture.store.items.compactMap(\.appValue).map(\.id) == [apps[2].id], "folder recovery duplicated or lost apps")
    }

    static func duplicateFolderMembership() async throws {
        let apps = [app("Alpha"), app("Beta"), app("Gamma")]
        let first = LaunchpadFolder(name: "First", appPaths: [apps[0].url.path, apps[1].url.path, apps[0].url.path])
        let second = LaunchpadFolder(name: "Second", appPaths: [apps[1].url.path, apps[2].url.path])
        let fixture = Fixture(apps: apps, folders: [first, second])
        defer { fixture.cleanUp() }
        let paths = fixture.store.items.flatMap { item -> [String] in
            switch item {
            case .app(let app): return [app.url.path]
            case .folder(let folder): return folder.appPaths
            }
        }
        try expect(paths.count == apps.count && Set(paths) == Set(apps.map { $0.url.path }), "restored layout duplicated app membership or lost an app")
    }

    static func returningToOrigin() async throws {
        let apps = [app("Alpha"), app("Beta"), app("Gamma")]
        let fixture = Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let original = store.items.map(\.id)
        store.beginDrag(.app(apps[0]), pageFrame: pageFrame)
        store.updateDrag(translation: CGSize(width: 156, height: -18), pageFrame: pageFrame)
        try await pauseForHover()
        try expect(store.mergeTargetID != nil, "test precondition: hover did not arm a merge")
        store.updateDrag(translation: .zero, pageFrame: pageFrame)
        try expect(store.mergeTargetID == nil, "returning to the original position kept the stale merge target")
        store.endDrag()
        try expect(store.items.map(\.id) == original, "returning to the original position still reordered or merged")
    }

    static func waitForNextPage(_ store: LaunchpadStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while store.currentPage == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try expect(store.currentPage == 1, "holding at the page edge did not advance to the adjacent page")
    }

    static func edgePageDrop() async throws {
        let apps = (0..<25).map { app("Tool\($0)") }
        let fixture = Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.beginDrag(.app(apps[0]), pageFrame: pageFrame)
        store.updateDrag(translation: CGSize(width: 544, height: 0), pageFrame: pageFrame)
        try await waitForNextPage(store)
        // Move away from the edge to the second cell on the destination page.
        store.updateDrag(translation: CGSize(width: 156, height: 0), pageFrame: pageFrame)
        store.endDrag()
        try expect(store.pages[1][1].id == LaunchpadItem.app(apps[0]).id, "cross-page drop used the original page's coordinates")
        try expect(store.pages[0].count == 11 && store.pages[0].last?.id == LaunchpadItem.app(apps[11]).id, "cross-page drop filled the source page from the next page")
        try expect(store.currentPage == 1, "successful drop did not stay on its destination page")
        try expect(store.items.count == apps.count && store.items.allSatisfy { !$0.isFolder }, "cross-page reordering lost or merged an app")
    }

    static func cancelEdgeDrag() async throws {
        let apps = (0..<25).map { app("Tool\($0)") }
        let fixture = Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        let original = store.items.map(\.id)
        store.beginDrag(.app(apps[0]), pageFrame: pageFrame)
        store.updateDrag(translation: CGSize(width: 544, height: 0), pageFrame: pageFrame)
        try await waitForNextPage(store)
        store.cancelDrag()
        try await Task.sleep(for: .milliseconds(750))
        try expect(store.currentPage == 0, "cancellation failed to restore the origin page or left a pending edge timer")
        try expect(store.items.map(\.id) == original, "cancelled cross-page drag changed app order")
        try expect(fixture.defaults.integer(forKey: "launchpad.lastPage") == 0, "cancelled cross-page drag saved an unintended page")
    }

    static func scanDuringDrag() async throws {
        let apps = [app("Alpha"), app("Beta"), app("Gamma")]
        let added = app("Delta")
        let fixture = Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.beginDrag(.app(apps[0]), pageFrame: pageFrame)
        store.updateDrag(translation: CGSize(width: 156, height: -18), pageFrame: pageFrame)
        store.applyScannedApps(apps + [added])
        try expect(store.appCatalog[added.url.path] == nil, "scan replaced the catalog in the middle of a drag")
        store.endDrag()
        try expect(store.items.prefix(3).map(\.id) == [apps[1], apps[0], apps[2]].map { LaunchpadItem.app($0).id }, "deferred scan discarded the completed drag order")
        try expect(store.appCatalog[added.url.path] != nil && store.items.last?.id == LaunchpadItem.app(added).id, "deferred scan never included the newly installed app")
    }

    static func scanDuringRename() async throws {
        let apps = [app("Alpha"), app("Beta")]
        let added = app("Gamma")
        let folder = LaunchpadFolder(name: "Tools", appPaths: apps.map { $0.url.path })
        let fixture = Fixture(apps: apps, folders: [folder])
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.openFolder(folder)
        store.renameOpenFolder("Work")
        store.applyScannedApps(apps + [added])
        try expect(store.folderNameDraft == "Work" && store.appCatalog[added.url.path] == nil, "scan interrupted the folder rename")
        store.closeFolder()
        try await Task.sleep(for: .milliseconds(300))
        try expect(store.items.compactMap(\.folderValue).first?.name == "Work", "deferred scan discarded the committed folder name")
        try expect(store.appCatalog[added.url.path] != nil, "scan stayed deferred after folder closure")
    }

    static func shrinkDuringSearch() async throws {
        let apps = (0..<30).map { app("Tool\($0)") }
        let fixture = Fixture(apps: apps)
        defer { fixture.cleanUp() }
        let store = fixture.store
        store.currentPage = 2
        store.query = "Tool"
        store.applyScannedApps(Array(apps.prefix(2)))
        store.query = ""
        try expect(store.currentPage == 0, "clearing search displayed an empty page after apps were removed")
        try expect(fixture.defaults.integer(forKey: "launchpad.lastPage") == 0, "clamped page was not saved after clearing search")
    }
}
