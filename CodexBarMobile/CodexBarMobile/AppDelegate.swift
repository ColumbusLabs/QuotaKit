import CodexBarSync
import UIKit
import UserNotifications

/// Handles remote notifications from CloudKit subscriptions.
/// When Mac pushes a DeviceSnapshot update to CloudKit, the CKQuerySubscription
/// fires a silent push. This delegate receives it, fetches the latest data,
/// detects quota transitions, and posts local notifications.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    private let quotaMonitor = SessionQuotaMonitor()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        let isTestLaunch = ProcessInfo.processInfo.arguments.contains("UI_TEST_RESET_DEFAULTS")
            || ProcessInfo.processInfo.arguments.contains("UI_TEST_PREVIEW_DATA")
        guard !isTestLaunch else { return true }

        application.registerForRemoteNotifications()

        Task {
            await LocalNotificationManager.shared.requestAuthorization()
        }

        return true
    }

    // MARK: - Remote Notification Registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[CodexBar] Remote notifications registered. Token: \(token.prefix(16))...")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[CodexBar] ERROR: Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - Remote Notification Handling

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        print("[CodexBar] Received remote notification: \(userInfo)")

        let reader = CloudSyncReader()
        let result = await reader.fetchAllDeviceSnapshots()

        switch result {
        case .success(let snapshots):
            guard let merged = CloudSyncReader.mergeSnapshots(snapshots) else {
                print("[CodexBar] Remote notification: no mergeable data")
                return .noData
            }

            // Always detect transitions to keep baseline current,
            // even when notifications are disabled. This prevents
            // stale notifications firing when the toggle is re-enabled.
            let transitions = quotaMonitor.detectTransitions(in: merged)
            print("[CodexBar] Transitions detected: \(transitions.map { "\($0.providerName): \($0.transition)" })")

            // Check both: iOS-side toggle AND Mac-side push toggle (from snapshot)
            let key = MobileSettingsKeys.sessionQuotaNotificationsEnabled
            let localEnabled = UserDefaults.standard.object(forKey: key) as? Bool ?? true
            let macPushEnabled = merged.notificationPushEnabled ?? true

            if localEnabled, macPushEnabled {
                for pt in transitions {
                    await LocalNotificationManager.shared.postSessionQuotaNotification(
                        providerName: pt.providerName,
                        transition: pt.transition)
                    print("[CodexBar] Posted local notification: \(pt.providerName) \(pt.transition)")
                }
            } else {
                print("[CodexBar] Notifications suppressed (local=\(localEnabled), mac=\(macPushEnabled))")
            }

            return transitions.isEmpty ? .noData : .newData

        case .empty:
            print("[CodexBar] Remote notification: CloudKit returned empty")
            return .noData

        case .error(let syncError):
            print("[CodexBar] Remote notification: CloudKit error: \(syncError)")
            return .failed
        }
    }

    // Show notifications even when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
