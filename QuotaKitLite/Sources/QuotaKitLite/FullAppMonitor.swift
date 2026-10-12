import AppKit

/// Watches for the full QuotaKit app (068 §5.4). While it runs, Lite pauses fetching so the two apps never double
/// the API traffic; Claude's per-token 429 gate makes double polling actively harmful.
///
/// It observes `NSWorkspace.runningApplications` with KVO, so there is no polling. Launch and terminate
/// notifications can't be used: macOS doesn't post them for `LSUIElement` apps, and the full app is one.
@MainActor
final class FullAppMonitor {
    nonisolated static let bundleIdentifier = "com.columbuslabs.quotakit.mac"

    private let onChange: @MainActor (Bool) -> Void
    private var observation: NSKeyValueObservation?
    private(set) var isRunning = false

    /// - Parameter onChange: called with the new running state, only when it changes.
    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
    }

    /// Reads the current state without calling `onChange`, then starts observing.
    func start() {
        self.isRunning = Self.fullAppIsRunning()
        // The change payload isn't used: re-checking the bundle identifier is simpler and covers launch and quit.
        // AppKit posts it on the main run loop, but a hop costs nothing and doesn't depend on that.
        self.observation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.update() }
        }
    }

    private func update() {
        let running = Self.fullAppIsRunning()
        guard running != self.isRunning else { return }
        self.isRunning = running
        self.onChange(running)
    }

    /// A terminating instance is still listed for a moment, so it doesn't count.
    private static func fullAppIsRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: self.bundleIdentifier)
            .contains { !$0.isTerminated }
    }
}
