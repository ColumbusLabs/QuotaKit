import CloudKit
import CodexBarSync
import SwiftUI
import UIKit
import UserNotifications

@main
struct CodexBarMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var usageData: SyncedUsageData

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

        if arguments.contains("UI_TEST_RESET_DEFAULTS") {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: MobileSettingsKeys.usageCostChartStyle)
            defaults.removeObject(forKey: MobileSettingsKeys.dashboardCostChartStyle)
            defaults.removeObject(forKey: MobileSettingsKeys.hidePersonalInfo)
            defaults.removeObject(forKey: MobileSettingsKeys.openCostByDefault)
            defaults.removeObject(forKey: MobileSettingsKeys.usagePercentDisplayMode)
            defaults.removeObject(forKey: MobileSettingsKeys.showRemainingUsage)
            defaults.removeObject(forKey: "onboardingSeenVersion")
        }

        if arguments.contains("UI_TEST_SKIP_ONBOARDING") {
            UserDefaults.standard.set(currentVersion, forKey: "onboardingSeenVersion")
        }

        if arguments.contains("UI_TEST_PREVIEW_DATA") {
            _usageData = State(initialValue: PreviewData.makeSyncedUsageData())
        } else {
            _usageData = State(initialValue: SyncedUsageData())
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(usageData: usageData)
                .onAppear {
                    guard !ProcessInfo.processInfo.arguments.contains("UI_TEST_PREVIEW_DATA") else { return }
                    usageData.startObserving()
                }
        }
    }
}

// MARK: - AppDelegate

/// Minimal `UIApplicationDelegate` for the alert-push design. Only responsibilities:
///
/// 1. Request notification permission on first launch (`.alert + .sound + .badge`).
///    The user must grant this for visible push notifications to display.
/// 2. Register for remote notifications so iOS hands the device's APNs token to
///    CloudKit's internal subscription dispatcher.
/// 3. Configure the two `CKQuerySubscription`s on `QuotaTransition` records.
/// 4. Re-run subscription setup on `CKAccountChangedNotification` so the new account
///    gets fresh subscriptions.
/// 5. As `UNUserNotificationCenterDelegate`, allow notifications to display in
///    foreground (otherwise iOS suppresses them by default for the active app).
///
/// We deliberately do NOT implement `didReceiveRemoteNotification` — alert pushes
/// are displayed by the system without app code running.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        let isTestLaunch = ProcessInfo.processInfo.arguments.contains("UI_TEST_RESET_DEFAULTS")
            || ProcessInfo.processInfo.arguments.contains("UI_TEST_PREVIEW_DATA")
        guard !isTestLaunch else { return true }

        // 1. Request notification permission on first launch (Decision A — option 1).
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(
                    options: [.alert, .sound, .badge])
                let msg = granted ? "✓ granted" : "✗ denied by user"
                print("[CodexBar Push v2] Notification permission \(msg)")
                PushSetupDiagnostic.shared.recordPermission(msg)
            } catch {
                let msg = "✗ request failed: \(error.localizedDescription)"
                print("[CodexBar Push v2] \(msg)")
                PushSetupDiagnostic.shared.recordPermission(msg)
            }
        }

        // 2. Register for remote notifications so CloudKit knows the APNs token.
        application.registerForRemoteNotifications()

        // 3. Set up the two CKQuerySubscriptions on the user's private database.
        Task { @MainActor in
            await QuotaTransitionSubscriptions.shared.setupIfNeeded()
        }

        // 4. Re-setup on iCloud account change.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.iCloudAccountChanged),
            name: .CKAccountChanged,
            object: nil)

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let prefix = String(token.prefix(16))
        print("[CodexBar Push v2] Remote notification registration succeeded. Token: \(prefix)…")
        Task { @MainActor in
            PushSetupDiagnostic.shared.recordRegistration("✓ token: \(prefix)…")
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[CodexBar Push v2] Remote notification registration FAILED: " +
            "\(error.localizedDescription)")
        Task { @MainActor in
            PushSetupDiagnostic.shared.recordRegistration("✗ \(error.localizedDescription)")
        }
    }

    @objc private func iCloudAccountChanged() {
        print("[CodexBar Push v2] iCloud account changed — re-running subscription setup")
        Task { @MainActor in
            await QuotaTransitionSubscriptions.shared.setupIfNeeded()
        }
    }

    /// Allow alert push to display while the app is in the foreground. Without this,
    /// iOS silently suppresses the notification UI for the currently active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
