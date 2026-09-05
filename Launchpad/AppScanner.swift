import AppKit
import Foundation

struct InstalledApp: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let latinName: String
    let initials: String
    let bundleIdentifier: String?

    var id: URL { url }

    func matches(_ rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        if name.localizedStandardContains(query) { return true }
        if latinName.localizedCaseInsensitiveContains(query) { return true }
        if initials.localizedCaseInsensitiveContains(query.replacingOccurrences(of: " ", with: "")) {
            return true
        }
        if bundleIdentifier?.localizedCaseInsensitiveContains(query) == true { return true }
        return false
    }
}

enum AppScanner: Sendable {
    private static let skippedBundleIDs: Set<String> = [
        "a.Launchpad",
    ]

    nonisolated static func scan() -> [InstalledApp] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
            home.appendingPathComponent("Applications"),
        ]

        var unique = [String: InstalledApp]()
        var unnamed = [InstalledApp]()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            collect(from: root, depth: 0, fileManager: fileManager, unique: &unique, unnamed: &unnamed)
        }

        let selfURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        var apps = Array(unique.values) + unnamed
        apps.removeAll { $0.url.resolvingSymlinksInPath() == selfURL }
        apps.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return apps
    }

    private nonisolated static func collect(
        from directory: URL,
        depth: Int,
        fileManager: FileManager,
        unique: inout [String: InstalledApp],
        unnamed: inout [InstalledApp]
    ) {
        guard depth < 3 else { return }

        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants,
        ]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: options
        ) else { return }

        for url in contents {
            if url.pathExtension == "app" {
                if let app = makeApp(at: url) {
                    if let bundleID = app.bundleIdentifier {
                        if unique[bundleID] == nil {
                            unique[bundleID] = app
                        }
                    } else {
                        unnamed.append(app)
                    }
                }
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true, values?.isPackage != true {
                collect(from: url, depth: depth + 1, fileManager: fileManager, unique: &unique, unnamed: &unnamed)
            }
        }
    }

    private nonisolated static func makeApp(at url: URL) -> InstalledApp? {
        let bundle = Bundle(url: url)
        if bundle?.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool == true {
            return nil
        }
        if let bundleID = bundle?.bundleIdentifier, skippedBundleIDs.contains(bundleID) {
            return nil
        }

        let name =
            (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let latin = latinize(trimmed)
        return InstalledApp(
            url: url,
            name: trimmed,
            latinName: latin,
            initials: initials(from: latin),
            bundleIdentifier: bundle?.bundleIdentifier
        )
    }

    private nonisolated static func latinize(_ string: String) -> String {
        let mutable = NSMutableString(string: string)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String).lowercased()
    }

    private nonisolated static func initials(from latin: String) -> String {
        latin
            .split { !$0.isLetter && !$0.isNumber }
            .compactMap { $0.first }
            .map(String.init)
            .joined()
    }
}

enum IconCache: Sendable {
    nonisolated(unsafe) private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    nonisolated static func image(for url: URL) -> NSImage {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let source = NSWorkspace.shared.icon(forFile: url.path)
        let raster = rasterize(source)
        cache.setObject(raster, forKey: key)
        return raster
    }

    nonisolated static func preheat(urls: [URL]) {
        for url in urls {
            _ = image(for: url)
        }
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
