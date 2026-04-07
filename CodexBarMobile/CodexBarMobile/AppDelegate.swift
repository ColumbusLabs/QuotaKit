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
        let prefix = String(token.prefix(16))
        print("[CodexBar] Remote notifications registered. Token: \(prefix)...")
        Task { @MainActor in
            PushDiagnosticStore.shared.recordRegistrationSuccess(tokenPrefix: prefix)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[CodexBar] ERROR: Failed to register for remote notifications: \(error.localizedDescription)")
        Task { @MainActor in
            PushDiagnosticStore.shared.recordRegistrationFailure(error)
        }
    }

    // MARK: - Remote Notification Handling

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        let summary = userInfo
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")
        print("[CodexBar] Received remote notification: \(userInfo)")
        await MainActor.run {
            PushDiagnosticStore.shared.recordPushReceived(userInfoSummary: summary)
        }

        let reader = CloudSyncReader()
        let result = await reader.fetchAllDeviceSnapshots()

        switch result {
        case .success(let snapshots):
            await MainActor.run {
                PushDiagnosticStore.shared.recordFetch(.success(deviceCount: snapshots.count))
            }
            guard let merged = CloudSyncReader.mergeSnapshots(snapshots) else {
                print("[CodexBar] Remote notification: no mergeable data")
                await MainActor.run {
                    PushDiagnosticStore.shared.recordFetch(.empty)
                }
                return .noData
            }

            // Always detect transitions to keep baseline current,
            // even when notifications are disabled. This prevents
            // stale notifications firing when the toggle is re-enabled.
            let transitions = self.quotaMonitor.detectTransitions(in: merged)
            let transitionSummary = transitions.isEmpty
                ? "(none)"
                : transitions.map { "\($0.providerName):\($0.transition)" }.joined(separator: ", ")
            print("[CodexBar] Transitions detected: \(transitionSummary)")
            await MainActor.run {
                PushDiagnosticStore.shared.recordTransitions(transitionSummary, count: transitions.count)
            }

            // Check both: iOS-side toggle AND Mac-side push toggle (from snapshot)
            let key = MobileSettingsKeys.sessionQuotaNotificationsEnabled
            let localEnabled = UserDefaults.standard.object(forKey: key) as? Bool ?? true
            let macPushEnabled = merged.notificationPushEnabled ?? true

            if localEnabled, macPushEnabled {
                var posted = 0
                for pt in transitions {
                    let ok = await LocalNotificationManager.shared.postSessionQuotaNotification(
                        providerName: pt.providerName,
                        transition: pt.transition)
                    if ok { posted += 1 }
                    print("[CodexBar] Posted local notification: \(pt.providerName) \(pt.transition)")
                }
                if !transitions.isEmpty {
                    await MainActor.run {
                        PushDiagnosticStore.shared.recordNotificationPost(.success(count: posted))
                    }
                }
            } else {
                let reason = "local=\(localEnabled), mac=\(macPushEnabled)"
                print("[CodexBar] Notifications suppressed (\(reason))")
                await MainActor.run {
                    PushDiagnosticStore.shared.recordNotificationPost(.suppressed(reason: reason))
                }
            }

            return transitions.isEmpty ? .noData : .newData

        case .empty:
            print("[CodexBar] Remote notification: CloudKit returned empty")
            await MainActor.run {
                PushDiagnosticStore.shared.recordFetch(.empty)
            }
            return .noData

        case .error(let syncError):
            print("[CodexBar] Remote notification: CloudKit error: \(syncError)")
            await MainActor.run {
                PushDiagnosticStore.shared.recordFetch(.failed(message: syncError.description))
            }
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
