import Foundation

nonisolated struct LaunchpadFolder: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var appPaths: [String]

    init(id: UUID = UUID(), name: String = "文件夹", appPaths: [String]) {
        self.id = id
        self.name = name
        self.appPaths = appPaths
    }
}

nonisolated enum LaunchpadItem: Identifiable, Hashable, Sendable {
    case app(InstalledApp)
    case folder(LaunchpadFolder)

    var id: String {
        switch self {
        case .app(let app):
            "app:\(app.url.path)"
        case .folder(let folder):
            "folder:\(folder.id.uuidString)"
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    var appValue: InstalledApp? {
        if case .app(let app) = self { return app }
        return nil
    }

    var folderValue: LaunchpadFolder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }
}
