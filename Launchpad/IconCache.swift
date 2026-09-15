import AppKit
import CryptoKit
import Foundation
import ImageIO

/// The revision comes from the background catalog scan. Constructing this key never
/// queries the filesystem, so a SwiftUI body can safely use it on every render.
nonisolated struct IconRequestID: Hashable, Sendable {
    let path: String
    let revision: String

    init(app: InstalledApp) {
        path = app.url.path
        revision = app.iconRevision
    }

    var memoryKey: NSString { "\(path.utf8.count):\(path)\(revision)" as NSString }
}

nonisolated enum IconCache {
    private static let pipeline = IconLoadingPipeline(loader: loadImage)

    static func cachedImage(for app: InstalledApp) -> NSImage? {
        pipeline.cachedImage(for: app)
    }

    static func image(for app: InstalledApp) async -> NSImage {
        await pipeline.image(for: app)
    }

    static func preheatAsync(apps: [InstalledApp]) {
        pipeline.preheat(apps: apps)
    }

    // Everything below runs only on the pipeline's bounded worker queue, including
    // hashing, cache-directory creation, PNG decoding and workspace icon lookup.
    private static func loadImage(for app: InstalledApp) -> NSImage {
        let request = IconRequestID(app: app)
        let raw = "v2|\(request.memoryKey)|\(Int(LaunchpadMetrics.iconPixelSize))"
        let digest = SHA256.hash(data: Data(raw.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        let file = diskURL(for: key)
        if let file,
           let data = try? Data(contentsOf: file),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, [
               kCGImageSourceShouldCacheImmediately: true,
               kCGImageSourceShouldCache: true,
           ] as CFDictionary) {
            return NSImage(cgImage: image, size: iconSize)
        }

        let image = rasterize(NSWorkspace.shared.icon(forFile: app.url.path))
        if let file,
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let data = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, cgImage, nil)
                if CGImageDestinationFinalize(destination) {
                    try? (data as Data).write(to: file, options: .atomic)
                }
            }
        }
        return image
    }

    private static var iconSize: NSSize {
        NSSize(width: LaunchpadMetrics.iconSize, height: LaunchpadMetrics.iconSize)
    }

    private static func diskURL(for key: String) -> URL? {
        let manager = FileManager.default
        guard let base = manager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = base.appendingPathComponent("OpenLaunchpad/Icons", isDirectory: true)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent("\(key).png", isDirectory: false)
        } catch {
            return nil
        }
    }

    private static func rasterize(_ source: NSImage) -> NSImage {
        let pixel = Int(LaunchpadMetrics.iconPixelSize)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: nil, width: pixel, height: pixel, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo
        ) else {
            source.size = iconSize
            return source
        }

        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        source.draw(in: CGRect(x: 0, y: 0, width: pixel, height: pixel), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = context.makeImage() else {
            source.size = iconSize
            return source
        }
        return NSImage(cgImage: cgImage, size: iconSize)
    }
}

/// A single request is shared by previews, full-size icons and preheating. Only the
/// worker queue invokes the loader; the lock protects request bookkeeping, never I/O.
nonisolated final class IconLoadingPipeline: @unchecked Sendable {
    typealias Loader = @Sendable (InstalledApp) -> NSImage

    private struct Pending {
        var waiters: [CheckedContinuation<NSImage, Never>]
        let operation: BlockOperation
    }

    private let memory = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private let queue: OperationQueue
    private let loader: Loader
    private var pending: [IconRequestID: Pending] = [:]

    init(maxConcurrentLoads: Int = 2, loader: @escaping Loader) {
        self.loader = loader
        queue = OperationQueue()
        queue.name = "a.Launchpad.IconCache"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(1, maxConcurrentLoads)
        memory.countLimit = 500
        memory.totalCostLimit = 64 * 1024 * 1024
    }

    func cachedImage(for app: InstalledApp) -> NSImage? {
        memory.object(forKey: IconRequestID(app: app).memoryKey)
    }

    func image(for app: InstalledApp) async -> NSImage {
        await withCheckedContinuation { continuation in
            request(app, waiter: continuation)
        }
    }

    func preheat(apps: [InstalledApp]) {
        for app in apps { request(app, waiter: nil) }
    }

    private func request(_ app: InstalledApp, waiter: CheckedContinuation<NSImage, Never>?) {
        let id = IconRequestID(app: app)
        lock.lock()
        if let image = memory.object(forKey: id.memoryKey) {
            lock.unlock()
            waiter?.resume(returning: image)
            return
        }
        if var existing = pending[id] {
            if let waiter {
                existing.waiters.append(waiter)
                existing.operation.queuePriority = .normal
                pending[id] = existing
            }
            lock.unlock()
            return
        }
        let operation = BlockOperation { [self] in
            autoreleasepool {
                let image = loader(app)
                lock.lock()
                let cost = Int(LaunchpadMetrics.iconPixelSize * LaunchpadMetrics.iconPixelSize) * 4
                memory.setObject(image, forKey: id.memoryKey, cost: cost)
                let waiters = pending.removeValue(forKey: id)?.waiters ?? []
                lock.unlock()
                for waiter in waiters { waiter.resume(returning: image) }
            }
        }
        operation.queuePriority = waiter == nil ? .low : .normal
        pending[id] = Pending(waiters: waiter.map { [$0] } ?? [], operation: operation)
        lock.unlock()
        queue.addOperation(operation)
    }
}
