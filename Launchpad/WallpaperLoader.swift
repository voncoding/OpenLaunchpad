import AppKit
import CoreImage
import OSLog

nonisolated enum WallpaperLoader {
    enum Status: Equatable, Sendable {
        case loading, ready, accessDenied, unavailable, unreadableImage

        var needsAttention: Bool {
            self == .accessDenied || self == .unavailable || self == .unreadableImage
        }

        var description: String {
            switch self {
            case .loading: return "正在读取当前桌面壁纸…"
            case .ready: return "跟随当前桌面壁纸"
            case .accessDenied: return "macOS 不允许读取当前照片壁纸的配置。自动跟随此类壁纸需要在系统设置中允许启动台的“完整磁盘访问”。"
            case .unavailable: return "暂时找不到当前壁纸的图片。请在系统壁纸设置中重新选择壁纸后重试。"
            case .unreadableImage: return "当前壁纸图片无法读取。请检查文件访问权限，或重新选择壁纸后重试。"
            }
        }
    }

    struct Result {
        let image: NSImage?
        let status: Status
    }

    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 6
        return cache
    }()
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private static let logger = Logger(subsystem: "a.Launchpad", category: "Wallpaper")

    @MainActor
    static func blurredWallpaper(for screen: NSScreen) async -> Result {
        let display = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let uuid = display.flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }
        let displayID = uuid.map { CFUUIDCreateString(nil, $0) as String }
        let workspaceURL = NSWorkspace.shared.desktopImageURL(for: screen)
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        // Reading another app's wallpaper cache may wait on macOS privacy UI.
        // Keep that file access and image decoding off the application's event loop.
        return await Task.detached(priority: .userInitiated) {
            let result: Result
            switch WallpaperSourceResolver.wallpaperSource(workspaceURL: workspaceURL, displayID: displayID) {
            case .image(let url):
                let image = renderWallpaper(url: url, size: size, scale: scale)
                result = Result(image: image, status: image == nil ? .unreadableImage : .ready)
            case .accessDenied:
                result = Result(image: nil, status: .accessDenied)
            case .unavailable:
                result = Result(image: nil, status: .unavailable)
            }
            logger.notice("Wallpaper load status: \(String(describing: result.status), privacy: .public)")
            return result
        }.value
    }

    private static func renderWallpaper(url: URL, size: CGSize, scale: CGFloat) -> NSImage? {
        let key = cacheKey(size: size, scale: scale, url: url) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let source = NSImage(contentsOf: url) else { return nil }
        guard let blurred = blur(source, to: size) else { return nil }
        cache.setObject(blurred, forKey: key)
        return blurred
    }

    private static func cacheKey(size: CGSize, scale: CGFloat, url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let bytes = values?.fileSize ?? 0
        return "\(url.absoluteString)|\(modified)|\(bytes)|\(size.width)x\(size.height)|\(scale)"
    }

    private static func blur(_ image: NSImage, to size: CGSize) -> NSImage? {
        let pixelSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        guard let cgSource = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
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
            return NSImage(cgImage: cgSource, size: image.size)
        }
        return NSImage(cgImage: cgImage, size: size)
    }
}
