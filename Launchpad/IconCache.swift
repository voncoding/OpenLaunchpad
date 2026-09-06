import AppKit
import CryptoKit
import Foundation

enum IconCache: Sendable {
    nonisolated(unsafe) private static let memory: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()

    nonisolated private static let diskQueue = DispatchQueue(label: "a.Launchpad.IconCache", qos: .utility)
    nonisolated(unsafe) private static let fileManager = FileManager.default

    nonisolated private static var diskDirectory: URL? {
        guard let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("OpenLaunchpad/Icons", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Synchronously return a displayable icon (memory → disk → rasterize).
    nonisolated static func image(for url: URL) -> NSImage {
        let key = cacheKey(for: url)
        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }

        if let diskImage = loadFromDisk(key: key) {
            memory.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }

        let source = NSWorkspace.shared.icon(forFile: url.path)
        let raster = rasterize(source)
        memory.setObject(raster, forKey: key as NSString)
        diskQueue.async {
            saveToDisk(raster, key: key)
        }
        return raster
    }

    /// Warm a small set of icons off the main thread (current page / visible folders).
    nonisolated static func preheatAsync(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let unique = Array(Set(urls))
        diskQueue.async {
            for url in unique {
                _ = image(for: url)
            }
        }
    }

    nonisolated static func preheat(urls: [URL]) {
        preheatAsync(urls: urls)
    }

    nonisolated private static func cacheKey(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let mtime = (try? fileManager.attributesOfItem(atPath: path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let raw = "\(path)|\(Int(mtime))|\(Int(LaunchpadMetrics.iconPixelSize))"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func diskURL(for key: String) -> URL? {
        diskDirectory?.appendingPathComponent("\(key).png", isDirectory: false)
    }

    nonisolated private static func loadFromDisk(key: String) -> NSImage? {
        guard let file = diskURL(for: key),
              fileManager.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: LaunchpadMetrics.iconSize, height: LaunchpadMetrics.iconSize)
        return image
    }

    nonisolated private static func saveToDisk(_ image: NSImage, key: String) {
        guard let file = diskURL(for: key),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: file, options: .atomic)
    }

    private nonisolated static func rasterize(_ source: NSImage) -> NSImage {
        let pixel = Int(LaunchpadMetrics.iconPixelSize)
        let size = NSSize(width: LaunchpadMetrics.iconSize, height: LaunchpadMetrics.iconSize)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let context = CGContext(
            data: nil,
            width: pixel,
            height: pixel,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            source.size = size
            return source
        }

        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        source.draw(
            in: CGRect(x: 0, y: 0, width: pixel, height: pixel),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else {
            source.size = size
            return source
        }
        return NSImage(cgImage: cgImage, size: size)
    }
}
