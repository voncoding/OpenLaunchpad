import Foundation

@MainActor
enum CatalogRefreshRegression {
    typealias Checks = InteractionRegressionTests

    final class Scanner {
        var calls = 0
        var now: TimeInterval = 100
        var apps = [Checks.app("CachedApp")]
        var pauseNext = false
        var release: CheckedContinuation<Void, Never>?

        func scan() async -> [InstalledApp] {
            calls += 1
            let result = apps
            if pauseNext {
                pauseNext = false
                await withCheckedContinuation { release = $0 }
            }
            return result
        }
    }

    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw Checks.CheckFailure(description: "catalog refresh did not settle")
    }

    static func reuseAndExpiry() async throws {
        let fixture = Checks.Fixture(apps: [])
        defer { fixture.cleanUp() }
        let scanner = Scanner()
        let store = LaunchpadStore(defaults: fixture.defaults, refreshInterval: 300,
                                  uptime: { scanner.now }, scanCatalog: { await scanner.scan() })
        for _ in 0..<20 { store.reload() }
        try await waitUntil { !store.isRefreshing }
        try Checks.expect(scanner.calls == 1 && store.items.count == 1, "startup requests did not share one scan")
        for _ in 0..<20 { store.resetForPresentation(); store.reload() }
        try await waitUntil { !store.isRefreshing }
        try Checks.expect(scanner.calls == 1, "reopening rescanned a fresh catalog")
        scanner.now += 299
        store.reload()
        try Checks.expect(!store.isRefreshing, "catalog expired before the fallback interval")
        scanner.now += 1
        store.reload()
        try await waitUntil { !store.isRefreshing }
        try Checks.expect(scanner.calls == 2, "expired catalog did not get a fallback check")
        store.reload(force: true)
        try await waitUntil { !store.isRefreshing }
        try Checks.expect(scanner.calls == 3, "explicit refresh was incorrectly cached")
    }

    static func changesDuringScan() async throws {
        let fixture = Checks.Fixture(apps: [])
        defer { fixture.cleanUp() }
        let scanner = Scanner()
        scanner.pauseNext = true
        let store = LaunchpadStore(defaults: fixture.defaults, scanCatalog: { await scanner.scan() })
        store.reload()
        try await waitUntil { scanner.release != nil }
        scanner.apps = [Checks.app("NewInstallation")]
        for _ in 0..<10 { store.invalidateCatalog() }
        scanner.release?.resume()
        scanner.release = nil
        try await waitUntil { !store.isRefreshing }
        try Checks.expect(scanner.calls == 2, "in-flight changes caused redundant scans or were dropped")
        try Checks.expect(store.items.first?.appValue?.name == "NewInstallation", "stale in-flight catalog was applied")
        scanner.apps = []
        store.invalidateCatalog()
        try await waitUntil { !store.isRefreshing }
        try Checks.expect(store.items.isEmpty, "removal did not invalidate the catalog")
    }

    static func changesDuringFolder() async throws {
        let first = Checks.app("FolderFirst")
        let second = Checks.app("FolderSecond")
        let folder = LaunchpadFolder(appPaths: [first.url.path, second.url.path])
        let fixture = Checks.Fixture(apps: [first, second], folders: [folder])
        defer { fixture.cleanUp() }
        let scanner = Scanner()
        scanner.apps = [first, second]
        let store = LaunchpadStore(defaults: fixture.defaults, scanCatalog: { await scanner.scan() })
        store.reload()
        try await waitUntil { !store.isRefreshing }
        store.openFolder(folder)
        let added = Checks.app("AddedWhileFolderOpen")
        scanner.apps.append(added)
        store.invalidateCatalog()
        try await waitUntil { !store.isRefreshing }
        try Checks.expect(store.openFolderID == folder.id && store.appCatalog[added.url.path] == nil,
                          "background change interrupted the open folder")
        store.closeFolder()
        try await waitUntil { store.openFolderID == nil && store.appCatalog[added.url.path] != nil }
        try Checks.expect(store.items.compactMap(\.folderValue).first?.appPaths == folder.appPaths,
                          "deferred scan changed folder membership")
    }

    static func deferredChangesOnFirstReopen() async throws {
        let first = Checks.app("ReopenFolderFirst")
        let second = Checks.app("ReopenFolderSecond")
        let removed = Checks.app("RemovedWhileFolderOpen")
        let added = Checks.app("InstalledWhileFolderOpen")
        let folder = LaunchpadFolder(appPaths: [first.url.path, second.url.path])
        let fixture = Checks.Fixture(apps: [first, second, removed], folders: [folder])
        defer { fixture.cleanUp() }
        let scanner = Scanner()
        scanner.apps = [first, second, removed]
        let store = LaunchpadStore(defaults: fixture.defaults, uptime: { scanner.now },
                                  scanCatalog: { await scanner.scan() })
        store.reload()
        try await waitUntil { !store.isRefreshing }
        store.isPresented = true
        store.openFolder(folder)
        scanner.apps = [first, second, added]
        store.invalidateCatalog()
        try await waitUntil { !store.isRefreshing }
        try Checks.expect(store.appCatalog[removed.url.path] != nil && store.appCatalog[added.url.path] == nil,
                          "catalog changes were not deferred while the folder was open")

        // Launching an app or switching away hides the overlay without closing its
        // folder. The next presentation must consume the already completed scan.
        store.isPresented = false
        store.resetForPresentation()
        store.reload()
        try Checks.expect(!store.isRefreshing && scanner.calls == 2, "first reopen unnecessarily rescanned a fresh catalog")
        try Checks.expect(store.openFolderID == nil && store.appCatalog[added.url.path] != nil,
                          "first reopen left the newly installed app in the deferred catalog")
        try Checks.expect(store.appCatalog[removed.url.path] == nil && !store.items.contains(.app(removed)),
                          "first reopen kept an uninstalled app")
        try Checks.expect(store.items.compactMap(\.folderValue).first?.appPaths == folder.appPaths,
                          "first reopen changed the deferred folder membership")
    }

    static func iconRevisionChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenLaunchpad-Revision-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("RevisionTest.app")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "test.openlaunchpad.revision", "CFBundleName": "RevisionTest", "CFBundleIconFile": "AppIcon"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let icon = resources.appendingPathComponent("AppIcon.icns")
        try Data([1, 2, 3]).write(to: icon)
        let first = await Task.detached { AppScanner.scan(roots: [root]) }.value
        try Checks.expect(first.count == 1, "fixture app was not scanned")
        try Data([4, 5, 6, 7]).write(to: icon)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: icon.path)
        let updated = await Task.detached { AppScanner.scan(roots: [root]) }.value
        try Checks.expect(updated.count == 1 && first[0].iconRevision != updated[0].iconRevision,
                          "updating an icon kept its old cache identity")
        let stable = await Task.detached { AppScanner.scan(roots: [root]) }.value
        try Checks.expect(updated == stable, "unchanged scans invalidated the icon cache")
    }
}
