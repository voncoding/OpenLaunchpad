import AppKit

/// Clears a stuck icon drag if SwiftUI's DragGesture is torn down before `onEnded`.
@MainActor
final class DragSafetyMonitor {
    static let shared = DragSafetyMonitor()

    private weak var store: LaunchpadStore?
    private var monitor: Any?
    private var ending = false

    private init() {}

    func start(store: LaunchpadStore) {
        self.store = store
        ending = false
        stopMonitoringOnly()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            // Defer so SwiftUI can apply the final drag translation first.
            DispatchQueue.main.async { [weak self] in
                guard let self, let store = self.store, store.isReordering, !self.ending else { return }
                self.ending = true
                store.endDrag()
                self.ending = false
            }
            return event
        }
    }

    func stop() {
        stopMonitoringOnly()
        ending = false
    }

    private func stopMonitoringOnly() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
