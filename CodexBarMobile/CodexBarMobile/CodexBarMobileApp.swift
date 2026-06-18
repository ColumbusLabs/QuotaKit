import CloudKit
import CodexBarSync
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@main
struct CodexBarMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var usageData: SyncedUsageData
    @State private var proEntitlementStore = ProEntitlementStore()
    @State private var remoteConfigStore = RemoteConfigStore()

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
            defaults.removeObject(forKey: MobileSettingsKeys.freeSelectedProviderID)
            defaults.removeObject(forKey: MobileSettingsKeys.freeSelectedProviderLockedUntil)
            defaults.removeObject(forKey: ProEntitlementCacheStore.key)
            defaults.removeObject(forKey: "onboardingSeenVersion")
            defaults.removeObject(forKey: MobileSettingsKeys.appearanceMode)
            QuotaKitWidgetDisplayModeStore.appGroupDefaults()?
                .removeObject(forKey: QuotaKitWidgetDisplayModeStore.key)
            QuotaKitWidgetProviderPreferencesStore.appGroupDefaults()?
                .removeObject(forKey: QuotaKitWidgetProviderPreferencesStore.providerOrderKey)
            QuotaKitWidgetProviderPreferencesStore.appGroupDefaults()?
                .removeObject(forKey: QuotaKitWidgetProviderPreferencesStore.selectedProviderKey)
        }

        if arguments.contains("UI_TEST_SKIP_ONBOARDING") {
            UserDefaults.standard.set(currentVersion, forKey: "onboardingSeenVersion")
        }

        if Self.isAutomatedTestLaunch {
            _usageData = State(initialValue: PreviewData.makeSyncedUsageData())
        } else {
            _usageData = State(initialValue: SyncedUsageData())
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(usageData: usageData)
                .environment(self.proEntitlementStore)
                .environment(self.remoteConfigStore)
                .quotaKitThemed()
                .onAppear {
                    guard !Self.isAutomatedTestLaunch else { return }
                    self.remoteConfigStore.start()
                    self.proEntitlementStore.start()
                    usageData.startObserving()
                    if self.proEntitlementStore.isProUnlocked {
                        WidgetTimelineRefresher.reloadAllTimelines()
                    }
                    Task {
                        await ProNotificationCoordinator.shared.reconcile(
                            isProUnlocked: self.proEntitlementStore.isProUnlocked)
                    }
                }
                .onChange(of: self.proEntitlementStore.isProUnlocked) { _, isUnlocked in
                    guard !Self.isAutomatedTestLaunch else { return }
                    WidgetTimelineRefresher.reloadAllTimelines()
                    Task {
                        await ProNotificationCoordinator.shared.reconcile(
                            isProUnlocked: isUnlocked)
                    }
                }
                .onChange(of: self.scenePhase) { _, phase in
                    guard phase == .active, !Self.isAutomatedTestLaunch else { return }
                    Task { await self.remoteConfigStore.refresh() }
                    // Foreground freshness: refresh synced usage when the
                    // last completed refresh is stale. Quick app switches
                    // no-op via the staleness gate; the launch-time fetch
                    // from `startObserving()` is coalesced with this one
                    // inside SyncedUsageData, so cold start never double-
                    // fetches.
                    Task { await self.usageData.refreshIfStale() }
                }
        }
        // P2a: attach SwiftData container. Views do not yet use @Query;
        // this makes the mainContext available for P2b migration and ensures
        // the container is bootstrapped at launch for parallel-write.
        .modelContainer(ModelContainerFactory.shared())
    }

    private static var isAutomatedTestLaunch: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        return arguments.contains("UI_TEST_PREVIEW_DATA")
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}

extension Notification.Name {
    /// Posted by AppDelegate when a silent CloudKit push arrives from the
    /// per-provider zone. `SyncedUsageData` listens and triggers its
    /// cache-based incremental refresh (Research/011 v2).
    static let quotaKitProviderZoneDidChange = Notification.Name(
        "com.columbuslabs.quotakit.providerZoneDidChange")
}

private extension WidgetBackgroundSnapshotRefreshResult {
    var backgroundFetchResult: UIBackgroundFetchResult {
        switch self {
        case .newData:
            .newData
        case .noData:
            .noData
        case .failed:
            .failed
        }
    }
}

// MARK: - AppDelegate

/// `UIApplicationDelegate` responsibilities:
///
/// 1. Register for remote notifications so CloudKit can dispatch subscriptions.
/// 2. Configure the silent-push DeviceProvidersZone subscription.
/// 3. Let `ProNotificationCoordinator` configure or remove visible quota
///    subscriptions after StoreKit entitlement state is known.
/// 4. Re-run all subscription setup on iCloud account change.
/// 5. Handle incoming silent pushes on DeviceProvidersZone — post a notification
///    so SyncedUsageData can refresh against its in-memory cache.
/// 6. Allow alert-push to display in foreground via
///    `UNUserNotificationCenterDelegate`.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        let environment = ProcessInfo.processInfo.environment
        let isTestLaunch = ProcessInfo.processInfo.arguments.contains("UI_TEST_RESET_DEFAULTS")
            || ProcessInfo.processInfo.arguments.contains("UI_TEST_PREVIEW_DATA")
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
        guard !isTestLaunch else { return true }

        // 1. Register for remote notifications so CloudKit knows the APNs token.
        // Alert permission is requested later by ProNotificationCoordinator
        // only when QuotaKit Pro is unlocked.
        application.registerForRemoteNotifications()

        // 2. Set up silent-push subscription on DeviceProvidersZone. Visible
        // quota alert subscriptions are gated by ProNotificationCoordinator.
        Task { @MainActor in
            await DeviceProviderZoneSubscription.shared.setupIfNeeded()
        }

        // 4. Re-setup on iCloud account change.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.iCloudAccountChanged),
            name: .CKAccountChanged,
            object: nil)

        return true
    }

    /// Handle silent CloudKit push. Today only the DeviceProvidersZone
    /// subscription fires here (quota subs render their alertBody without
    /// app code). On match, refresh the widget snapshot directly before
    /// completing the background fetch. Then broadcast so an already-running
    /// app scene can update its in-memory UI model too.
    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard DeviceProviderZoneSubscription.isPushForThisSubscription(userInfo: userInfo) else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            let result = await WidgetBackgroundSnapshotRefresh.refresh()
            NotificationCenter.default.post(
                name: .quotaKitProviderZoneDidChange, object: nil)
            completionHandler(result.backgroundFetchResult)
        }
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

    /// MUST be `nonisolated` — `CKAccountChanged` posts on
    /// `com.apple.cloudkit.CKProcessScopedStateManager.notificationQueue`,
    /// not the main queue. Without `nonisolated`, the implicit
    /// `@MainActor` isolation on `AppDelegate` (inherited from
    /// `UIApplicationDelegate` conformance under Swift 6 strict
    /// concurrency) causes `_swift_task_checkIsolatedSwift` to trap
    /// (`EXC_BREAKPOINT`) the moment the notification fires. Crash
    /// happens on every cold launch as soon as CloudKit's first
    /// account-state read posts the notification — was the cause of
    /// the App Store 1.5.2 (112) review rejection ("App crashed after
    /// initial launch"). The body still hops to `@MainActor` via
    /// `Task { @MainActor in ... }` so the actual subscription setup
    /// is properly main-isolated.
    @objc nonisolated private func iCloudAccountChanged() {
        print("[CodexBar Push v2] iCloud account changed — re-running subscription setup")
        Task { @MainActor in
            await ProNotificationCoordinator.shared.reconcile(
                isProUnlocked: ProEntitlementCacheStore.load() != nil)
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
