import CoreServices
import Darwin
import Foundation

/// Watches catalog roots, including application bundle contents, without polling.
@MainActor
final class AppDirectoryMonitor {
    private var roots: [String] = []
    private var watchedPaths: [String] = []
    private var onChange: (@MainActor () -> Void)?
    private var stream: StreamHandle?
    private var pendingChange: Task<Void, Never>?
    private var needsRestart = false
    private var generation: UInt64 = 0

    func start(roots: [URL], onChange: @escaping @MainActor () -> Void) {
        stop()
        self.roots = Array(Set(roots.filter(\.isFileURL).map {
            Self.canonicalPath($0.standardizedFileURL.path)
        })).sorted()
        self.onChange = onChange
        refreshStream(force: true)
    }

    func stop() {
        generation &+= 1
        pendingChange?.cancel()
        pendingChange = nil
        stream = nil
        roots = []
        watchedPaths = []
        onChange = nil
        needsRestart = false
    }

    private func refreshStream(force: Bool) {
        let candidates = Set(roots.map(Self.existingAncestor))
        let paths = candidates.filter { candidate in
            !candidates.contains { $0 != candidate && Self.contains(candidate, in: $0) }
        }.sorted()
        guard force || paths != watchedPaths else { return }
        generation &+= 1
        let currentGeneration = generation
        stream = nil
        watchedPaths = paths
        guard !paths.isEmpty else { return }

        let context = CallbackContext { [weak self] paths, flags in
            guard let self, self.generation == currentGeneration else { return }
            self.receive(paths: paths, flags: flags)
        }
        stream = StreamHandle(paths: paths, context: context)
    }

    private func receive(paths: [String], flags: [FSEventStreamEventFlags]) {
        let uncertainFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs |
            kFSEventStreamEventFlagUserDropped |
            kFSEventStreamEventFlagKernelDropped |
            kFSEventStreamEventFlagRootChanged
        )
        var relevant = false
        for (path, flag) in zip(paths, flags) {
            if flag & uncertainFlags != 0 {
                // A dropped batch may contain changes under a missing root's parent.
                relevant = true
                needsRestart = needsRestart || flag & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
            } else if roots.contains(where: { Self.contains(path, in: $0) || Self.contains($0, in: path) }) {
                relevant = true
            }
        }
        guard relevant, pendingChange == nil else { return }

        // One callback per short burst, with bounded latency even during a long install.
        let currentGeneration = generation
        pendingChange = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            guard let self, self.generation == currentGeneration else { return }
            self.pendingChange = nil
            let restart = self.needsRestart
            self.needsRestart = false
            // A formerly missing root can now be watched directly; a removed root
            // falls back to its parent so its subsequent recreation is still seen.
            self.refreshStream(force: restart)
            self.onChange?()
        }
    }

    nonisolated private static func contains(_ path: String, in directory: String) -> Bool {
        path == directory || path.hasPrefix(directory == "/" ? "/" : directory + "/")
    }

    nonisolated private static func existingAncestor(of path: String) -> String {
        var url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        while !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path else { break }
            url = parent
        }
        return url.path
    }

    nonisolated private static func canonicalPath(_ path: String) -> String {
        // Foundation deliberately shortens /private/var to /var, whereas FSEvents
        // reports the physical path. Resolve an existing prefix with realpath so
        // filtering also works for temporary folders and symlinked home folders.
        var candidate = path
        var missingComponents: [String] = []
        while true {
            if let resolved = realpath(candidate, nil) {
                defer { free(resolved) }
                let prefix = String(cString: resolved)
                return missingComponents.reversed().reduce(prefix) { partial, component in
                    (partial as NSString).appendingPathComponent(component)
                }
            }
            let parent = (candidate as NSString).deletingLastPathComponent
            guard !parent.isEmpty, parent != candidate else { return path }
            missingComponents.append((candidate as NSString).lastPathComponent)
            candidate = parent
        }
    }

    nonisolated private final class CallbackContext {
        let deliver: @MainActor ([String], [FSEventStreamEventFlags]) -> Void

        init(deliver: @escaping @MainActor ([String], [FSEventStreamEventFlags]) -> Void) {
            self.deliver = deliver
        }
    }

    /// Native ownership releases both the stream and its callback context even if
    /// the monitor is deallocated without an explicit stop().
    nonisolated private final class StreamHandle {
        private let value: FSEventStreamRef

        init?(paths: [String], context: CallbackContext) {
            var nativeContext = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(context).toOpaque(),
                retain: { pointer in
                    guard let pointer else { return nil }
                    _ = Unmanaged<CallbackContext>.fromOpaque(pointer).retain()
                    return pointer
                },
                release: { pointer in
                    guard let pointer else { return }
                    Unmanaged<CallbackContext>.fromOpaque(pointer).release()
                },
                copyDescription: nil
            )
            let options = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagWatchRoot
            )
            guard let created = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, info, count, rawPaths, flags, _ in
                    guard let info else { return }
                    let context = Unmanaged<CallbackContext>.fromOpaque(info).takeUnretainedValue()
                    let paths = unsafeBitCast(rawPaths, to: NSArray.self) as! [String]
                    let eventFlags = Array(UnsafeBufferPointer(start: flags, count: count))
                    // The stream is scheduled exclusively on DispatchQueue.main.
                    MainActor.assumeIsolated { context.deliver(paths, eventFlags) }
                },
                &nativeContext,
                paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.15,
                options
            ) else { return nil }
            FSEventStreamSetDispatchQueue(created, .main)
            guard FSEventStreamStart(created) else {
                FSEventStreamInvalidate(created)
                FSEventStreamRelease(created)
                return nil
            }
            value = created
        }

        deinit {
            FSEventStreamStop(value)
            FSEventStreamInvalidate(value)
            FSEventStreamRelease(value)
        }
    }
}
