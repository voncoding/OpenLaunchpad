import AppKit
import Foundation

nonisolated struct InstalledApp: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let latinName: String
    let initials: String
    let bundleIdentifier: String?
    /// Calculated during the background scan, never while rendering an icon.
    var iconRevision: String = ""

    var id: URL { url }

    func matches(_ rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        if name.localizedStandardContains(query) { return true }
        if latinName.localizedCaseInsensitiveContains(query) { return true }
        let compactQuery = query.filter { !$0.isWhitespace }
        if latinName.filter({ !$0.isWhitespace }).localizedCaseInsensitiveContains(compactQuery) { return true }
        if initials.localizedCaseInsensitiveContains(query.replacingOccurrences(of: " ", with: "")) {
            return true
        }
        if bundleIdentifier?.localizedCaseInsensitiveContains(query) == true { return true }
        return false
    }
}

nonisolated enum AppScanner: Sendable {
    private static let skippedBundleIDs: Set<String> = [
        "a.Launchpad",
    ]

    nonisolated static var applicationRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    nonisolated static func scan(roots: [URL] = applicationRoots) -> [InstalledApp] {
        let fileManager = FileManager.default

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
            if url.pathExtension.lowercased() == "app" {
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
            bundleIdentifier: bundle?.bundleIdentifier,
            iconRevision: iconRevision(at: url, bundle: bundle)
        )
    }

    private nonisolated static func iconRevision(at url: URL, bundle: Bundle?) -> String {
        let resources = url.appendingPathComponent("Contents/Resources")
        var sources = [url, url.appendingPathComponent("Contents/Info.plist"), resources,
                       resources.appendingPathComponent("Assets.car")]
        if let icon = bundle?.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            let iconURL = resources.appendingPathComponent(icon)
            sources.append(iconURL.pathExtension.isEmpty ? iconURL.appendingPathExtension("icns") : iconURL)
        }
        return sources.map { source in
            let values = try? source.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values?.fileSize ?? 0)"
        }.joined(separator: "|")
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
