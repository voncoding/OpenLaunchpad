import AppKit
import CoreImage

enum WallpaperLoader: Sendable {
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()
    nonisolated(unsafe) private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    nonisolated static func blurredWallpaper(for screen: NSScreen) -> NSImage? {
        let key = cacheKey(for: screen) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let source = rawWallpaper(for: screen) else { return nil }
        let blurred = blur(source, to: screen.frame.size)
        cache.setObject(blurred, forKey: key)
        return blurred
    }

    nonisolated static func invalidate() {
        cache.removeAllObjects()
    }

    private nonisolated static func cacheKey(for screen: NSScreen) -> String {
        let url = NSWorkspace.shared.desktopImageURL(for: screen)?.absoluteString ?? ""
        return "\(url)|\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }

    private nonisolated static func rawWallpaper(for screen: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }

        if url.hasDirectoryPath {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            let match = files.first { ["jpg", "jpeg", "png", "heic", "tif", "tiff"].contains($0.pathExtension.lowercased()) }
            if let match, let image = NSImage(contentsOf: match) {
                return image
            }
        }

        return NSImage(contentsOf: url)
    }

    private nonisolated static func blur(_ image: NSImage, to size: CGSize) -> NSImage {
        let pixelSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        guard let cgSource = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let ciImage = CIImage(cgImage: cgSource)
        let scale = max(pixelSize.width / ciImage.extent.width, pixelSize.height / ciImage.extent.height)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let cropRect = CGRect(
            x: (scaled.extent.width - pixelSize.width) / 2,
            y: (scaled.extent.height - pixelSize.height) / 2,
            width: pixelSize.width,
            height: pixelSize.height
        )
        let cropped = scaled.cropped(to: cropRect)
        let blurred = cropped
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 28])
            .cropped(to: cropped.extent)

        guard let cgImage = ciContext.createCGImage(blurred, from: blurred.extent) else {
            return image
        }
        return NSImage(cgImage: cgImage, size: size)
    }
}
