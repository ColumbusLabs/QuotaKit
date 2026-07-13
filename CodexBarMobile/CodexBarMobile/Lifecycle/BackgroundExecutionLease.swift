import UIKit

@MainActor
protocol BackgroundTaskManaging: AnyObject {
    func beginBackgroundTask(
        withName taskName: String?,
        expirationHandler handler: (@MainActor @Sendable () -> Void)?) -> UIBackgroundTaskIdentifier
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier)
}

extension UIApplication: BackgroundTaskManaging {}

/// Keeps a short, synchronous persistence transaction alive if the app moves
/// from active to background while SQLite is committing it.
///
/// The lease must never wrap CloudKit or other network work. It exists only to
/// let an already-started local transaction release its file lock cleanly.
@MainActor
enum BackgroundExecutionLease {
    static func withExtendedTime<Result>(
        name: String,
        manager: any BackgroundTaskManaging = UIApplication.shared,
        operation: () throws -> Result) rethrows -> Result
    {
        let lease = Lease(manager: manager, name: name)
        defer { lease.end() }
        return try operation()
    }

    @MainActor
    private final class Lease {
        private let manager: any BackgroundTaskManaging
        private var identifier: UIBackgroundTaskIdentifier = .invalid

        init(manager: any BackgroundTaskManaging, name: String) {
            self.manager = manager
            self.identifier = manager.beginBackgroundTask(withName: name) { [weak self] in
                self?.end()
            }
        }

        func end() {
            guard self.identifier != .invalid else { return }
            let identifier = self.identifier
            self.identifier = .invalid
            self.manager.endBackgroundTask(identifier)
        }
    }
}
