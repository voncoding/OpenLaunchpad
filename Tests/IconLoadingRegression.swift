import AppKit
import Foundation

@MainActor
enum IconLoadingRegression {
    typealias Checks = InteractionRegressionTests

    nonisolated private final class Probe: @unchecked Sendable {
        struct Snapshot {
            let calls: Int
            let peak: Int
            let ranOnMain: Bool
        }

        private let lock = NSLock()
        private var calls = 0
        private var active = 0
        private var peak = 0
        private var ranOnMain = false
        let gate: DispatchSemaphore?

        init(gate: DispatchSemaphore? = nil) { self.gate = gate }

        func load(_ app: InstalledApp) -> NSImage {
            lock.lock()
            calls += 1
            active += 1
            peak = max(peak, active)
            ranOnMain = ranOnMain || Thread.isMainThread
            lock.unlock()
            if let gate {
                _ = gate.wait(timeout: .now() + 3)
            } else {
                // A slow decode allows simultaneous callers to exercise coalescing.
                Thread.sleep(forTimeInterval: 0.06)
            }
            let image = NSImage(size: NSSize(width: 96, height: 96))
            lock.lock()
            active -= 1
            lock.unlock()
            return image
        }

        func snapshot() -> Snapshot {
            lock.lock()
            defer { lock.unlock() }
            return Snapshot(calls: calls, peak: peak, ranOnMain: ranOnMain)
        }
    }

    static func memoryAndCoalescing() async throws {
        let app = Checks.app("SharedIcon")
        let probe = Probe()
        let pipeline = IconLoadingPipeline(loader: probe.load)
        try Checks.expect(pipeline.cachedImage(for: app) == nil, "cold memory lookup should return a placeholder")
        try Checks.expect(probe.snapshot().calls == 0, "memory lookup invoked the loader")
        pipeline.preheat(apps: [app, app, app])
        let images = await withTaskGroup(of: NSImage.self, returning: [NSImage].self) { group in
            for _ in 0..<20 { group.addTask { await pipeline.image(for: app) } }
            var images: [NSImage] = []
            for await image in group { images.append(image) }
            return images
        }
        try Checks.expect(probe.snapshot().calls == 1, "preheating and visible consumers loaded the same icon more than once")
        try Checks.expect(!probe.snapshot().ranOnMain, "icon loading ran on the main thread")
        try Checks.expect(images.count == 20 && images.allSatisfy { $0 === images[0] }, "shared requests did not receive the same image")
        try Checks.expect(pipeline.cachedImage(for: app) === images[0], "completed image is missing from memory")
        let cached = await pipeline.image(for: app)
        try Checks.expect(cached === images[0] && probe.snapshot().calls == 1, "cache hit performed another load")
    }

    static func revisionAndConcurrency() async throws {
        var original = Checks.app("UpdatedIcon")
        original.iconRevision = "1"
        let probe = Probe()
        let pipeline = IconLoadingPipeline(maxConcurrentLoads: 2, loader: probe.load)
        let oldImage = await pipeline.image(for: original)
        var updated = original
        updated.iconRevision = "2"
        try Checks.expect(pipeline.cachedImage(for: updated) == nil, "updated application reused a stale icon")
        let updatedImage = await pipeline.image(for: updated)
        try Checks.expect(updatedImage !== oldImage && probe.snapshot().calls == 2, "new icon revision was not loaded")
        let apps = (0..<10).map { Checks.app("BoundedIcon\($0)") }
        pipeline.preheat(apps: apps + apps)
        await withTaskGroup(of: Void.self) { group in
            for app in apps { group.addTask { _ = await pipeline.image(for: app) } }
        }
        let result = probe.snapshot()
        try Checks.expect(result.calls == 12, "preheating duplicated icon loads")
        try Checks.expect(result.peak <= 2, "icon decode concurrency exceeded its configured limit")
        try Checks.expect(!result.ranOnMain, "preheating or image decode ran on the main thread")
    }

    static func slowLoadDoesNotBlockRendering() async throws {
        let app = Checks.app("SlowIcon")
        let gate = DispatchSemaphore(value: 0)
        let probe = Probe(gate: gate)
        let pipeline = IconLoadingPipeline(loader: probe.load)
        defer { gate.signal() }
        pipeline.preheat(apps: [app])
        for _ in 0..<100 where probe.snapshot().calls == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        try Checks.expect(probe.snapshot().calls == 1, "background load never started")
        // This synchronous read executes while the decoder is blocked, proving that
        // rendering is not waiting on either the decoder or a lock held across I/O.
        try Checks.expect(pipeline.cachedImage(for: app) == nil, "unfinished image appeared in the cache")
        try Checks.expect(!probe.snapshot().ranOnMain, "slow icon load blocked the render thread")
        gate.signal()
        _ = await pipeline.image(for: app)
        try Checks.expect(pipeline.cachedImage(for: app) != nil, "completed slow load did not populate memory")
    }
}
