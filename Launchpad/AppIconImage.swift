import AppKit
import SwiftUI

private struct AppIconLoadingEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var appIconLoadingEnabled: Bool {
        get { self[AppIconLoadingEnabledKey.self] }
        set { self[AppIconLoadingEnabledKey.self] = newValue }
    }
}

/// Memory hits draw immediately. Cold icons keep their square layout while the
/// shared loader reads and decodes them away from the main thread.
struct AppIconImage: View {
    let app: InstalledApp
    @Environment(\.appIconLoadingEnabled) private var loadingEnabled
    @State private var loadedID: IconRequestID?
    @State private var loadedImage: NSImage?

    private struct LoadID: Equatable {
        let request: IconRequestID
        let enabled: Bool
    }

    var body: some View {
        let requestID = IconRequestID(app: app)
        let image = loadedID == requestID ? loadedImage : IconCache.cachedImage(for: app)
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.14))
                    .overlay {
                        Image(systemName: "app")
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: LoadID(request: requestID, enabled: loadingEnabled)) {
            guard loadingEnabled else { return }
            let image = await IconCache.image(for: app)
            guard !Task.isCancelled else { return }
            loadedID = requestID
            loadedImage = image
        }
        .accessibilityHidden(true)
    }
}
