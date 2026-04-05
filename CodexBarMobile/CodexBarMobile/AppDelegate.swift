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

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        let reader = CloudSyncReader()
        let result = await reader.fetchAllDeviceSnapshots()

        switch result {
        case .success(let snapshots):
            guard let merged = CloudSyncReader.mergeSnapshots(snapshots) else {
                return .noData
            }

            // Always detect transitions to keep baseline current,
            // even when notifications are disabled. This prevents
            // stale notifications firing when the toggle is re-enabled.
            let transitions = quotaMonitor.detectTransitions(in: merged)

            // Check both: iOS-side toggle AND Mac-side push toggle (from snapshot)
            let key = MobileSettingsKeys.sessionQuotaNotificationsEnabled
            let localEnabled = UserDefaults.standard.object(forKey: key) as? Bool ?? true
            let macPushEnabled = merged.notificationPushEnabled ?? true

            if localEnabled, macPushEnabled {
                for pt in transitions {
                    await LocalNotificationManager.shared.postSessionQuotaNotification(
                        providerName: pt.providerName,
                        transition: pt.transition)
                }
            }

            return transitions.isEmpty ? .noData : .newData

        case .empty:
            return .noData

        case .error:
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
