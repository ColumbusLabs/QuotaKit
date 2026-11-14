import CodexBarCore
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class AppNotifications {
    static let shared = AppNotifications()

    private let centerProvider: @Sendable () -> UNUserNotificationCenter
    private let logger = CodexBarLog.logger(LogCategories.notifications)
    private var authorizationTask: Task<Bool, Never>?

    init(centerProvider: @escaping @Sendable () -> UNUserNotificationCenter = { UNUserNotificationCenter.current() }) {
        self.centerProvider = centerProvider
    }

    func requestAuthorizationOnStartup() {
        guard !Self.isRunningUnderTests else { return }
        _ = self.ensureAuthorizationTask()
    }

    func post(
        idPrefix: String,
        title: String,
        body: String,
        badge: NSNumber? = nil,
        soundEnabled: Bool = true,
        identifier: String? = nil,
        isCurrent: @escaping @MainActor () -> Bool = { true },
        onCompletion: (@MainActor (Bool) -> Void)? = nil)
    {
        guard !Self.isRunningUnderTests else {
            onCompletion?(false)
            return
        }
        let center = self.centerProvider()
        let logger = self.logger

        Task { @MainActor in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = soundEnabled ? .default : nil
            content.badge = badge

            let request = UNNotificationRequest(
                identifier: identifier ?? "codexbar-\(idPrefix)-\(UUID().uuidString)",
                content: content,
                trigger: nil)

            logger.info("posting", metadata: ["prefix": idPrefix])
            do {
                let delivered = try await Self.deliverIfCurrent(
                    authorize: { await self.ensureAuthorized() },
                    submit: { try await center.add(request) },
                    remove: {
                        await withCheckedContinuation { continuation in
                            self.remove(identifier: request.identifier) { continuation.resume() }
                        }
                    },
                    isCurrent: isCurrent)
                onCompletion?(delivered)
            } catch {
                onCompletion?(false)
                let errorText = String(describing: error)
                logger.error("failed to post", metadata: ["prefix": idPrefix, "error": errorText])
            }
        }
    }

    func remove(identifier: String, completion: @escaping @Sendable () -> Void = {}) {
        guard !Self.isRunningUnderTests else {
            completion()
            return
        }
        let centerProvider = self.centerProvider
        Self.scheduleRemoval(identifiers: [identifier]) { identifiers in
            let center = centerProvider()
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
            completion()
        }
    }

    /// The notification service can block on synchronous XPC. Keep removals ordered off the main actor.
    nonisolated static func scheduleRemoval(
        identifiers: [String],
        perform: @escaping @Sendable ([String]) -> Void)
    {
        self.removalQueue.async { perform(identifiers) }
    }

    private nonisolated static let removalQueue = DispatchQueue(
        label: "com.columbuslabs.quotakit.notifications.removal",
        qos: .utility)

    @discardableResult
    static func deliverIfCurrent(
        authorize: () async -> Bool,
        submit: () async throws -> Void,
        remove: () async -> Void,
        isCurrent: () -> Bool) async throws -> Bool
    {
        guard isCurrent(), await authorize(), isCurrent() else { return false }
        do {
            try await submit()
        } catch {
            await remove()
            throw error
        }
        guard isCurrent() else {
            await remove()
            return false
        }
        return true
    }

    // MARK: - Private

    private func ensureAuthorizationTask() -> Task<Bool, Never> {
        if let authorizationTask { return authorizationTask }
        let task = Task { @MainActor in
            await self.requestAuthorization()
        }
        self.authorizationTask = task
        return task
    }

    private func ensureAuthorized() async -> Bool {
        let granted = await self.ensureAuthorizationTask().value
        // A later System Settings permission change must be observable after a denied attempt.
        if !granted { self.authorizationTask = nil }
        return granted
    }

    private func requestAuthorization() async -> Bool {
        if let existing = await self.notificationAuthorizationStatus() {
            if existing == .authorized || existing == .provisional {
                return true
            }
            if existing == .denied {
                return false
            }
        }

        let center = self.centerProvider()
        return await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func notificationAuthorizationStatus() async -> UNAuthorizationStatus? {
        let center = self.centerProvider()
        return await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private static var isRunningUnderTests: Bool {
        // Swift Testing doesn't always set XCTest env vars, and removing XCTest imports from
        // the test target can make NSClassFromString("XCTestCase") return nil. If we're not
        // running inside an app bundle, treat it as "tests/headless" to avoid crashes when
        // accessing UNUserNotificationCenter.
        if Bundle.main.bundleURL.pathExtension != "app" { return true }
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["TESTING_LIBRARY_VERSION"] != nil { return true }
        if env["SWIFT_TESTING"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }
}
