import AppKit
import CoreImage

@MainActor
enum WallpaperLoader {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 6
        return cache
    }()
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func blurredWallpaper(for screen: NSScreen) -> NSImage? {
        guard let url = wallpaperURL(for: screen) else { return nil }
        let key = cacheKey(for: screen, url: url) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let source = NSImage(contentsOf: url) else { return nil }
        let blurred = blur(source, to: screen.frame.size)
        cache.setObject(blurred, forKey: key)
        return blurred
    }

    private static func cacheKey(for screen: NSScreen, url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let bytes = values?.fileSize ?? 0
        return "\(url.absoluteString)|\(modified)|\(bytes)|\(screen.frame.width)x\(screen.frame.height)|\(screen.backingScaleFactor)"
    }

    static func wallpaperURL(for screen: NSScreen) -> URL? {
        let display = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let uuid = display.flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }
        let displayID = uuid.map { CFUUIDCreateString(nil, $0) as String }
        return WallpaperSourceResolver.wallpaperURL(
            workspaceURL: NSWorkspace.shared.desktopImageURL(for: screen), displayID: displayID
        )
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
