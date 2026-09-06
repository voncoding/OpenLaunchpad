import Foundation

@MainActor
enum WallpaperSourceRegression {
    private static let defaultURL = URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")

    private static func choice(_ id: String) throws -> [String: Any] {
        ["Provider": "com.apple.wallpaper.extension.photos", "Files": [],
         "Configuration": try encode(["type": "asset", "identifier": id])]
    }

    private static func selection(_ id: String) throws -> [String: Any] {
        ["Linked": ["Content": ["Choices": [try choice(id)]]]]
    }

    private static func encode(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    private static func withFiles(_ body: (URL, URL, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first photo")
        let second = directory.appendingPathComponent("second photo")
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        try body(directory, first, second)
    }

    private static func preferences(_ first: URL, _ second: URL) throws -> [String: Any] {
        ["ChoiceRequests.Assets": [
            try encode(["identifier": "first", "copyURL": ["relative": first.absoluteString]]),
            try encode(["identifier": "second", "copyURL": ["relative": second.absoluteString]])]]
    }

    static func selectedAsset() throws {
        try withFiles { _, first, second in
            let result = WallpaperSourceResolver.resolve(workspaceURL: defaultURL, displayID: nil,
                index: ["AllSpacesAndDisplays": try selection("second")], preferences: [try preferences(first, second)])
            try InteractionRegressionTests.expect(result == second,
                "Photos must resolve the selected identifier, not the first cached image or DefaultDesktop")
        }
    }

    static func changingSelection() throws {
        try withFiles { home, first, second in
            let indexURL = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
            let preferenceURL = home.appendingPathComponent("Library/Containers/com.apple.wallpaper.extension.image/Data/Library/Preferences/com.apple.wallpaper.extension.image.plist")
            for url in [indexURL, preferenceURL] {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            try encode(preferences(first, second)).write(to: preferenceURL)
            for (id, expected) in [("first", first), ("second", second)] {
                try encode(["AllSpacesAndDisplays": selection(id)]).write(to: indexURL)
                let actual = WallpaperSourceResolver.wallpaperURL(workspaceURL: defaultURL, displayID: nil, home: home)
                try InteractionRegressionTests.expect(actual == expected,
                    "reopening must reread the current setting instead of retaining the previously selected photo")
            }
        }
    }

    static func displaySelection() throws {
        try withFiles { _, first, second in
            let index: [String: Any] = ["AllSpacesAndDisplays": try selection("first"),
                "Displays": ["DISPLAY-B": ["Desktop": ["Content": ["Choices": [try choice("second")]]],
                                            "Linked": ["Content": ["Choices": [try choice("first")]]]]]]
            let actual = WallpaperSourceResolver.resolve(workspaceURL: defaultURL, displayID: "display-b",
                index: index, preferences: [try preferences(first, second)])
            try InteractionRegressionTests.expect(actual == second,
                "the requested display's desktop selection must take priority over linked/global settings")
        }
    }

    static func safeFallback() throws {
        try withFiles { directory, first, second in
            let prefs = [try preferences(first, second)]
            let index = ["AllSpacesAndDisplays": try selection("missing")]
            try InteractionRegressionTests.expect(WallpaperSourceResolver.resolve(workspaceURL: defaultURL,
                displayID: nil, index: index, preferences: prefs) == nil,
                "missing selected Photos assets must not silently show an unrelated default wallpaper")
            try InteractionRegressionTests.expect(WallpaperSourceResolver.resolve(workspaceURL: first,
                displayID: nil, index: index, preferences: prefs) == first,
                "a concrete image from the public API must remain authoritative for the active Space")
            try InteractionRegressionTests.expect(WallpaperSourceResolver.resolve(workspaceURL: directory,
                displayID: nil, index: nil, preferences: prefs) == nil,
                "a wallpaper folder must not be treated as its alphabetically first image")
            let shuffle = ["AllSpacesAndDisplays": ["Linked": ["Content": ["Choices": [try choice("first"), try choice("second")]]]]]
            try InteractionRegressionTests.expect(WallpaperSourceResolver.resolve(workspaceURL: defaultURL,
                displayID: nil, index: shuffle,
                preferences: prefs) == nil, "a shuffle must not select an arbitrary entry")
        }
    }
}
