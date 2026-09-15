import Foundation

@MainActor
enum AppDirectoryMonitorRegression {
    private final class Events {
        var count = 0
    }

    private final class WeakMonitor {
        weak var value: AppDirectoryMonitor?
        init(_ value: AppDirectoryMonitor?) { self.value = value }
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLaunchpad-Monitor-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func settle() async throws {
        try await Task.sleep(for: .milliseconds(800))
    }

    private static func expectChange(_ events: Events, after count: Int, _ message: String) async throws {
        for _ in 0..<60 {
            if events.count > count { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        try InteractionRegressionTests.expect(events.count > count, message)
    }

    static func bundleChanges() async throws {
        let root = try temporaryDirectory()
        let monitor = AppDirectoryMonitor()
        let events = Events()
        defer {
            monitor.stop()
            try? FileManager.default.removeItem(at: root)
        }
        monitor.start(roots: [root]) { events.count += 1 }
        try await settle()
        events.count = 0

        let app = root.appendingPathComponent("Utilities/Example.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        for index in 0..<20 {
            try Data([UInt8(index)]).write(to: resources.appendingPathComponent("asset-\(index)"))
        }
        try await expectChange(events, after: 0, "installing a nested application did not invalidate the catalog")
        try await settle()
        try InteractionRegressionTests.expect(events.count == 1, "a single installation burst triggered repeated invalidations")

        var count = events.count
        try Data([99]).write(to: resources.appendingPathComponent("asset-0"))
        try await expectChange(events, after: count, "updating an existing bundle resource was not detected")
        try await settle()

        count = events.count
        let renamed = app.deletingLastPathComponent().appendingPathComponent("Renamed.app")
        try FileManager.default.moveItem(at: app, to: renamed)
        try await expectChange(events, after: count, "renaming an application was not detected")
        try await settle()

        count = events.count
        try FileManager.default.removeItem(at: renamed)
        try await expectChange(events, after: count, "uninstalling an application was not detected")
    }

    static func missingRootAndFiltering() async throws {
        let parent = try temporaryDirectory()
        let root = parent.appendingPathComponent("User/Applications", isDirectory: true)
        let monitor = AppDirectoryMonitor()
        let events = Events()
        defer {
            monitor.stop()
            try? FileManager.default.removeItem(at: parent)
        }
        monitor.start(roots: [root]) { events.count += 1 }
        try await settle()
        events.count = 0

        let sibling = parent.appendingPathComponent("Unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try Data([1]).write(to: sibling.appendingPathComponent("note.txt"))
        try await settle()
        try InteractionRegressionTests.expect(events.count == 0, "unrelated files under the fallback parent invalidated the catalog")

        try FileManager.default.createDirectory(at: root.appendingPathComponent("First.app"), withIntermediateDirectories: true)
        try await expectChange(events, after: 0, "creating a previously missing Applications directory was not detected")
        try await settle()
        var count = events.count
        try FileManager.default.removeItem(at: root)
        try await expectChange(events, after: count, "removing the watched Applications directory was not detected")
        try await settle()

        count = events.count
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Second.app"), withIntermediateDirectories: true)
        try await expectChange(events, after: count, "recreating the watched Applications directory was not detected")
    }

    static func restartAndStop() async throws {
        let parent = try temporaryDirectory()
        let first = parent.appendingPathComponent("First", isDirectory: true)
        let second = parent.appendingPathComponent("Second", isDirectory: true)
        for url in [first, second] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let events = Events()
        let oldEvents = Events()
        var monitor: AppDirectoryMonitor? = AppDirectoryMonitor()
        defer {
            monitor?.stop()
            try? FileManager.default.removeItem(at: parent)
        }
        monitor?.start(roots: [first]) { oldEvents.count += 1 }
        monitor?.start(roots: [second]) { events.count += 1 }
        try await settle()
        events.count = 0
        oldEvents.count = 0
        try Data([1]).write(to: first.appendingPathComponent("ignored"))
        try await settle()
        try InteractionRegressionTests.expect(oldEvents.count == 0 && events.count == 0,
            "restarting retained the old root or callback")

        try Data([2]).write(to: second.appendingPathComponent("detected"))
        try await expectChange(events, after: 0, "restarting did not watch the new root")
        try await settle()
        let count = events.count
        try Data([3]).write(to: second.appendingPathComponent("cancelled"))
        monitor?.stop()
        monitor?.stop()
        try await settle()
        try InteractionRegressionTests.expect(events.count == count, "stop allowed a queued change callback to fire")

        monitor?.start(roots: [second]) { events.count += 1 }
        let released = WeakMonitor(monitor)
        monitor = nil
        try InteractionRegressionTests.expect(released.value == nil, "the native callback context retained its monitor")
        try Data([4]).write(to: second.appendingPathComponent("after-deinit"))
        try await settle()
        try InteractionRegressionTests.expect(events.count == count, "a deallocated monitor continued delivering callbacks")
    }
}
