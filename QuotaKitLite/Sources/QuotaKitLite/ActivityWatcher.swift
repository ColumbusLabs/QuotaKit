import CoreServices
import Foundation
import LiteCore

/// One FSEvents stream over the directories where Claude, Codex and Antigravity write while in use
/// (068 §5.1). It never reads a file: it only maps each changed directory to a provider and reports it.
///
/// - 15 s latency, so the kernel coalesces a burst into one callback at most every 15 s.
/// - Directory-level events only (no file-level flag).
/// - Roots that don't exist are skipped, because FSEvents reports nothing for a path that appears later.
///   Call `rescan()` (for example on menu open or wake) to pick up a CLI that was installed since launch.
@MainActor
final class ActivityWatcher {
    private static let latency: CFTimeInterval = 15

    private let roots: ActivityRoots
    private let fileExists: (String) -> Bool
    private let onActivity: (LiteProvider) -> Void
    private var stream: FSEventStreamRef?
    private var watchedPaths: [String] = []

    /// - Parameter onActivity: called on the main queue, once per provider per callback.
    init(
        roots: ActivityRoots = ActivityWatcher.defaultRoots(),
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        onActivity: @escaping (LiteProvider) -> Void)
    {
        self.roots = roots
        self.fileExists = fileExists
        self.onActivity = onActivity
    }

    /// The §5.1 paths for this user, honouring `CODEX_HOME` and `CLAUDE_CONFIG_DIR`. FSEvents reports real
    /// paths, so symlinks (for example a dotfiles-managed `~/.claude`) are resolved up front.
    static func defaultRoots() -> ActivityRoots {
        ActivityRoots(
            homeDirectory: NSHomeDirectory(),
            environment: ProcessInfo.processInfo.environment,
            resolve: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
    }

    isolated deinit {
        self.stop()
    }

    /// Starts the stream over the roots that exist now. Safe to call again; it restarts.
    func start() {
        self.stop()
        let paths = self.roots.watchPaths.filter(self.fileExists)
        self.watchedPaths = paths
        guard !paths.isEmpty else { return }

        let box = CallbackBox { [weak self] eventPaths in
            guard let self else { return }
            for provider in self.roots.providers(forEventPaths: eventPaths) {
                self.onActivity(provider)
            }
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(box).toOpaque(),
            retain: nil,
            release: { info in
                if let info { Unmanaged<CallbackBox>.fromOpaque(info).release() }
            },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] ?? []
            box.deliver(Array(paths.prefix(count)))
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes))
        else {
            // Creation failed before the stream took ownership of the retained box.
            Unmanaged<CallbackBox>.fromOpaque(context.info!).release()
            return
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        if FSEventStreamStart(stream) {
            self.stream = stream
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func stop() {
        guard let stream = self.stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        self.watchedPaths = []
    }

    /// Re-checks which roots exist (a few `stat` calls). When one appeared since the last start, restarts the
    /// stream and reports activity for its provider, since a CLI that just created its directory is in use.
    func rescan() {
        let existing = self.roots.watchPaths.filter(self.fileExists)
        guard existing != self.watchedPaths else { return }
        let added = Set(existing).subtracting(self.watchedPaths)
        self.start()
        let providers = self.roots.roots.filter { root in
            added.contains { $0 == root.path || root.path.hasPrefix($0 + "/") }
        }.map(\.provider)
        for provider in LiteProvider.allCases where providers.contains(provider) {
            self.onActivity(provider)
        }
    }
}

/// Carries the Swift handler through FSEvents' C context pointer. FSEvents calls back on the main queue
/// because the stream is attached to it, which is what makes the main-actor assumption below safe.
private final class CallbackBox: @unchecked Sendable {
    private let handler: @MainActor ([String]) -> Void

    init(handler: @escaping @MainActor ([String]) -> Void) {
        self.handler = handler
    }

    func deliver(_ paths: [String]) {
        MainActor.assumeIsolated {
            self.handler(paths)
        }
    }
}
