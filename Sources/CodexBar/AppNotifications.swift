import Foundation
import OSLog
@preconcurrency import UserNotifications

@MainActor
final class AppNotifications {
    static let shared = AppNotifications()

    private let centerProvider: @Sendable () -> UNUserNotificationCenter
    private let logger = Logger(subsystem: "com.steipete.codexbar", category: "notifications")
    private var authorizationTask: Task<Bool, Never>?

    init(centerProvider: @escaping @Sendable () -> UNUserNotificationCenter = { UNUserNotificationCenter.current() }) {
        self.centerProvider = centerProvider
    }

    func requestAuthorizationOnStartup() {
        guard !Self.isRunningUnderTests else { return }
        _ = self.ensureAuthorizationTask()
    }

    func post(idPrefix: String, title: String, body: String) {
        guard !Self.isRunningUnderTests else { return }
        let center = self.centerProvider()
        let logger = self.logger

        Task { @MainActor in
            let granted = await self.ensureAuthorized()
            guard granted else {
                logger.debug("not authorized; skipping post: prefix=\(idPrefix, privacy: .public)")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body

            let request = UNNotificationRequest(
                identifier: "codexbar-\(idPrefix)-\(UUID().uuidString)",
                content: content,
                trigger: nil)

            logger.info("posting: prefix=\(idPrefix, privacy: .public)")
            do {
                try await center.add(request)
            } catch {
                let errorText = String(describing: error)
                logger
                    .debug("failed to post: prefix=\(idPrefix, privacy: .public) error=\(errorText, privacy: .public)")
            }
        }
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
        await self.ensureAuthorizationTask().value
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
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
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
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["TESTING_LIBRARY_VERSION"] != nil { return true }
        if env["SWIFT_TESTING"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }
}
