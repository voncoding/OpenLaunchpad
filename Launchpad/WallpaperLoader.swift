import AppKit
import CoreImage

nonisolated enum WallpaperLoader {
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 6
        return cache
    }()
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    @MainActor
    static func blurredWallpaper(for screen: NSScreen) async -> NSImage? {
        let display = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let uuid = display.flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }
        let displayID = uuid.map { CFUUIDCreateString(nil, $0) as String }
        let workspaceURL = NSWorkspace.shared.desktopImageURL(for: screen)
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        // Reading another app's wallpaper cache may wait on macOS privacy UI.
        // Keep that file access and image decoding off the application's event loop.
        return await Task.detached(priority: .userInitiated) {
            guard let url = WallpaperSourceResolver.wallpaperURL(workspaceURL: workspaceURL, displayID: displayID) else { return nil }
            return renderWallpaper(url: url, size: size, scale: scale)
        }.value
    }

    private static func renderWallpaper(url: URL, size: CGSize, scale: CGFloat) -> NSImage? {
        let key = cacheKey(size: size, scale: scale, url: url) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let source = NSImage(contentsOf: url) else { return nil }
        let blurred = blur(source, to: size)
        cache.setObject(blurred, forKey: key)
        return blurred
    }

    private static func cacheKey(size: CGSize, scale: CGFloat, url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let bytes = values?.fileSize ?? 0
        return "\(url.absoluteString)|\(modified)|\(bytes)|\(size.width)x\(size.height)|\(scale)"
    }

    private static func blur(_ image: NSImage, to size: CGSize) -> NSImage {
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
