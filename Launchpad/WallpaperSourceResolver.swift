import Foundation

/// NSWorkspace can return DefaultDesktop.heic for Photos wallpapers on Tahoe.
/// Resolve the selected asset through the wallpaper service's own copied image.
/// These on-disk formats are optional: never select an arbitrary cached photo.
nonisolated enum WallpaperSourceResolver {
    enum Resolution: Equatable, Sendable {
        case image(URL)
        case accessDenied
        case unavailable

        var url: URL? {
            guard case .image(let url) = self else { return nil }
            return url
        }
    }

    static func wallpaperURL(workspaceURL: URL?, displayID: String?, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        wallpaperSource(workspaceURL: workspaceURL, displayID: displayID, home: home).url
    }

    static func wallpaperSource(workspaceURL: URL?, displayID: String?,
                                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                readData: (URL) throws -> Data = { try Data(contentsOf: $0) }) -> Resolution {
        // A concrete public URL never needs another app's protected preferences.
        if let workspaceURL, !isDefaultDesktop(workspaceURL), usableFile(workspaceURL) {
            return .image(workspaceURL)
        }
        let index = readPlist(home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist"), readData: readData)
        guard !index.accessDenied else { return .accessDenied }
        return resolveSource(workspaceURL: workspaceURL, displayID: displayID, index: index.value) { identifier in
            // Only a selected Photos/image asset needs these private cache records.
            let preferencePaths = [
                "Library/Containers/com.apple.wallpaper.extension.image/Data/Library/Preferences/com.apple.wallpaper.extension.image.plist",
                "Library/Containers/com.apple.wallpaper.extension.photos/Data/Library/Preferences/com.apple.wallpaper.extension.photos.plist"
            ]
            var accessDenied = false
            for path in preferencePaths {
                let preference = readPlist(home.appendingPathComponent(path), readData: readData)
                accessDenied = accessDenied || preference.accessDenied
                if let url = assetURL(identifier: identifier, preference: preference.value) {
                    return .image(url)
                }
            }
            return accessDenied ? .accessDenied : .unavailable
        }
    }

    static func resolve(workspaceURL: URL?, displayID: String?, index: [String: Any]?, preferences: [[String: Any]]) -> URL? {
        resolveSource(workspaceURL: workspaceURL, displayID: displayID, index: index) { identifier in
            for preference in preferences {
                if let url = assetURL(identifier: identifier, preference: preference) { return .image(url) }
            }
            return .unavailable
        }.url
    }

    private static func resolveSource(workspaceURL: URL?, displayID: String?, index: [String: Any]?,
                                      selectedAsset: (String) -> Resolution) -> Resolution {
        // The public API remains authoritative when it supplies a real image,
        // including a different wallpaper on the active Space.
        if let workspaceURL, !isDefaultDesktop(workspaceURL), usableFile(workspaceURL) {
            return .image(workspaceURL)
        }

        let choices = selectedChoices(in: index, displayID: displayID)
        if let choices {
            // Albums/shuffles need the currently selected frame, not their first entry.
            guard choices.count == 1, let choice = choices.first else { return .unavailable }
            let provider = choice["Provider"] as? String ?? ""
            if provider == "com.apple.wallpaper.extension.photos" || provider == "com.apple.wallpaper.extension.image" {
                let configuration = dictionary(choice["Configuration"])
                if configuration?["type"] as? String == "asset",
                   let identifier = configuration?["identifier"] as? String {
                    // A missing Photos copy must not silently become a system wallpaper.
                    return selectedAsset(identifier)
                }
                let files = choice["Files"] as? [Any] ?? []
                if files.count == 1, let url = fileURL(files[0]), usableFile(url) { return .image(url) }
                return .unavailable
            }
        }
        if let workspaceURL, usableFile(workspaceURL) { return .image(workspaceURL) }
        return .unavailable
    }

    private static func assetURL(identifier: String, preference: [String: Any]?) -> URL? {
        for raw in preference?["ChoiceRequests.Assets"] as? [Any] ?? [] {
            guard let asset = dictionary(raw), asset["identifier"] as? String == identifier,
                  let url = fileURL(asset["copyURL"]), usableFile(url) else { continue }
            return url
        }
        return nil
    }

    private static func selectedChoices(in index: [String: Any]?, displayID: String?) -> [[String: Any]]? {
        guard let index else { return nil }
        var selection: [String: Any]?
        if let displayID, let displays = index["Displays"] as? [String: Any],
           let key = displays.keys.first(where: { $0.caseInsensitiveCompare(displayID) == .orderedSame }) {
            selection = displays[key] as? [String: Any]
        }
        if selection == nil { selection = index["AllSpacesAndDisplays"] as? [String: Any] }
        // Desktop takes priority over the screen saver when they are unlinked.
        let desktop = selection?["Desktop"] as? [String: Any] ?? selection?["Linked"] as? [String: Any]
        let content = desktop?["Content"] as? [String: Any]
        return content?["Choices"] as? [[String: Any]]
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        if let data = value as? Data {
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        }
        return value as? [String: Any]
    }

    private static func fileURL(_ value: Any?) -> URL? {
        let string = value as? String ?? (value as? [String: Any])?["relative"] as? String
        guard let string, let url = URL(string: string), url.isFileURL else { return nil }
        return url
    }

    private static func usableFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
    }

    private static func isDefaultDesktop(_ url: URL) -> Bool {
        let fallback = URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")
        return url.standardizedFileURL == fallback || url.resolvingSymlinksInPath() == fallback.resolvingSymlinksInPath()
    }

    private static func readPlist(_ url: URL, readData: (URL) throws -> Data) -> (value: [String: Any]?, accessDenied: Bool) {
        do {
            return (dictionary(try readData(url)), false)
        } catch {
            return (nil, isAccessDenied(error))
        }
    }

    private static func isAccessDenied(_ error: Error) -> Bool {
        var current = error as NSError
        // Foundation sometimes wraps the POSIX failure in a generic file-read error.
        for _ in 0..<8 {
            if current.domain == NSCocoaErrorDomain,
               current.code == CocoaError.fileReadNoPermission.rawValue { return true }
            if current.domain == NSPOSIXErrorDomain,
               current.code == Int(EPERM) || current.code == Int(EACCES) { return true }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            current = underlying
        }
        return false
    }
}
