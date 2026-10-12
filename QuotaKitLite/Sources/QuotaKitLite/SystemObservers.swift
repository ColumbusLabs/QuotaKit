import AppKit
import CoreGraphics
import Foundation
import Network

/// Feeds system state into the `RefreshScheduler` (068 §5): sleep and wake, display sleep, screen lock,
/// network restored, Low Power Mode and thermal state. Everything is a notification or a path callback, so it
/// costs nothing while the system is quiet.
///
/// User idle time is deliberately not observed here: the scheduler samples it with
/// `secondsSinceLastUserInput()` only when it decides the heartbeat.
@MainActor
final class SystemObservers {
    private let scheduler: RefreshScheduler
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var processTokens: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    private var lastPathSatisfied: Bool?
    private var isRunning = false

    init(scheduler: RefreshScheduler) {
        self.scheduler = scheduler
    }

    isolated deinit {
        self.stop()
    }

    /// Seconds since the last keyboard, mouse or trackpad input, from the window server. A single cheap call.
    static func secondsSinceLastUserInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func start() {
        guard !self.isRunning else { return }
        self.isRunning = true
        self.observeWorkspace()
        self.observeScreenLock()
        self.observeProcessState()
        self.observeNetwork()
        self.applyProcessState()
    }

    func stop() {
        guard self.isRunning else { return }
        self.isRunning = false
        for token in self.workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        for token in self.distributedTokens {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        for token in self.processTokens {
            NotificationCenter.default.removeObserver(token)
        }
        self.workspaceTokens = []
        self.distributedTokens = []
        self.processTokens = []
        self.pathMonitor?.cancel()
        self.pathMonitor = nil
    }

    // MARK: - Observation

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        self.workspaceTokens = [
            self.observe(NSWorkspace.willSleepNotification, on: center) { scheduler in
                scheduler.updateEnvironment { $0.isSystemAsleep = true }
            },
            self.observe(NSWorkspace.didWakeNotification, on: center) { scheduler in
                scheduler.systemDidWake()
            },
            self.observe(NSWorkspace.screensDidSleepNotification, on: center) { scheduler in
                scheduler.updateEnvironment { $0.isDisplayAsleep = true }
            },
            self.observe(NSWorkspace.screensDidWakeNotification, on: center) { scheduler in
                scheduler.updateEnvironment { $0.isDisplayAsleep = false }
            },
        ]
    }

    private func observeScreenLock() {
        let center = DistributedNotificationCenter.default()
        self.distributedTokens = [
            self.observe(Notification.Name("com.apple.screenIsLocked"), on: center) { scheduler in
                scheduler.updateEnvironment { $0.isScreenLocked = true }
            },
            self.observe(Notification.Name("com.apple.screenIsUnlocked"), on: center) { scheduler in
                scheduler.updateEnvironment { $0.isScreenLocked = false }
            },
        ]
    }

    private func observeProcessState() {
        let center = NotificationCenter.default
        self.processTokens = [
            center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyProcessState() }
            },
            center.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: .main)
            { [weak self] _ in
                MainActor.assumeIsolated { self?.applyProcessState() }
            },
        ]
    }

    /// Low Power Mode, or a serious or critical thermal state, slows the activity throttle and the heartbeat.
    private func applyProcessState() {
        let info = ProcessInfo.processInfo
        let thermal = info.thermalState == .serious || info.thermalState == .critical
        let lowPower = info.isLowPowerModeEnabled
        self.scheduler.updateEnvironment {
            $0.isLowPowerMode = lowPower
            $0.isThermallyConstrained = thermal
        }
    }

    private func observeNetwork() {
        let monitor = NWPathMonitor()
        self.lastPathSatisfied = nil
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            MainActor.assumeIsolated { self?.pathChanged(satisfied: satisfied) }
        }
        monitor.start(queue: .main)
        self.pathMonitor = monitor
    }

    /// The first callback reports the starting state, not a change, so only a flip to reachable counts.
    private func pathChanged(satisfied: Bool) {
        let restored = satisfied && self.lastPathSatisfied == false
        self.lastPathSatisfied = satisfied
        if restored { self.scheduler.networkRestored() }
    }

    private func observe(
        _ name: Notification.Name,
        on center: NotificationCenter,
        _ handler: @escaping @MainActor (RefreshScheduler) -> Void) -> NSObjectProtocol
    {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let scheduler = self?.scheduler else { return }
                handler(scheduler)
            }
        }
    }
}
