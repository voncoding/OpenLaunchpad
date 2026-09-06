import Foundation

/// NSWorkspace can return DefaultDesktop.heic for Photos wallpapers on Tahoe.
/// Resolve the selected asset through the wallpaper service's own copied image.
/// These on-disk formats are optional: never select an arbitrary cached photo.
enum WallpaperSourceResolver {
    static func wallpaperURL(workspaceURL: URL?, displayID: String?, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let index = readPlist(home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist"))
        let preferencePaths = [
            "Library/Containers/com.apple.wallpaper.extension.image/Data/Library/Preferences/com.apple.wallpaper.extension.image.plist",
            "Library/Containers/com.apple.wallpaper.extension.photos/Data/Library/Preferences/com.apple.wallpaper.extension.photos.plist"
        ]
        let preferences = preferencePaths.compactMap { readPlist(home.appendingPathComponent($0)) }
        return resolve(workspaceURL: workspaceURL, displayID: displayID, index: index, preferences: preferences)
    }

    static func resolve(workspaceURL: URL?, displayID: String?, index: [String: Any]?, preferences: [[String: Any]]) -> URL? {
        // The public API remains authoritative when it supplies a real image,
        // including a different wallpaper on the active Space.
        if let workspaceURL, !isDefaultDesktop(workspaceURL), usableFile(workspaceURL) {
            return workspaceURL
        }

        let choices = selectedChoices(in: index, displayID: displayID)
        if let choices {
            // Albums/shuffles need the currently selected frame, not their first entry.
            guard choices.count == 1, let choice = choices.first else { return nil }
            let provider = choice["Provider"] as? String ?? ""
            if provider == "com.apple.wallpaper.extension.photos" || provider == "com.apple.wallpaper.extension.image" {
                let configuration = dictionary(choice["Configuration"])
                if configuration?["type"] as? String == "asset",
                   let identifier = configuration?["identifier"] as? String {
                    for preference in preferences {
                        for raw in preference["ChoiceRequests.Assets"] as? [Any] ?? [] {
                            guard let asset = dictionary(raw), asset["identifier"] as? String == identifier,
                                  let url = fileURL(asset["copyURL"]), usableFile(url) else { continue }
                            return url
                        }
                    }
                    // A missing Photos copy must not silently become a system wallpaper.
                    return nil
                }
                let files = choice["Files"] as? [Any] ?? []
                if files.count == 1, let url = fileURL(files[0]), usableFile(url) { return url }
                return nil
            }
        }
        return workspaceURL.flatMap { usableFile($0) ? $0 : nil }
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

    private static func readPlist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return dictionary(data)
    }
}
