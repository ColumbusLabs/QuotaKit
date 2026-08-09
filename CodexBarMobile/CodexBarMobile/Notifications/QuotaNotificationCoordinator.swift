import Foundation
import UIKit
import UserNotifications

struct NotificationSetupPlan: Equatable {
    let shouldSetupSilentSync: Bool
    let shouldRequestAlertPermission: Bool
    let shouldSetupQuotaAlerts: Bool
}

enum NotificationSetupPlanner {
    static func plan() -> NotificationSetupPlan {
        NotificationSetupPlan(
            shouldSetupSilentSync: true,
            shouldRequestAlertPermission: true,
            shouldSetupQuotaAlerts: true)
    }
}

@MainActor
final class QuotaNotificationCoordinator {
    static let shared = QuotaNotificationCoordinator()

    private init() {}

    func reconcile() async {
        let plan = NotificationSetupPlanner.plan()

        if plan.shouldSetupSilentSync {
            await DeviceProviderZoneSubscription.shared.setupIfNeeded()
        }

        if plan.shouldRequestAlertPermission {
            await self.requestAlertPermission()
            UIApplication.shared.registerForRemoteNotifications()
        }

        if plan.shouldSetupQuotaAlerts {
            await QuotaTransitionSubscriptions.shared.setupIfNeeded()
        }
    }

    private func requestAlertPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge])
            let msg = granted ? "✓ granted" : "✗ denied by user"
            print("[QuotaKit Push] Notification permission \(msg)")
            PushSetupDiagnostic.shared.recordPermission(msg)
        } catch {
            let msg = "✗ request failed: \(error.localizedDescription)"
            print("[QuotaKit Push] \(msg)")
            PushSetupDiagnostic.shared.recordPermission(msg)
        }
    }
}
