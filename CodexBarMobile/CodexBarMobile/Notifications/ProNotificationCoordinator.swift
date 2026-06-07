import Foundation
import UIKit
import UserNotifications

struct ProNotificationSetupPlan: Equatable {
    let shouldSetupSilentSync: Bool
    let shouldRequestAlertPermission: Bool
    let shouldSetupQuotaAlerts: Bool
    let shouldRemoveQuotaAlerts: Bool
}

enum ProNotificationSetupPlanner {
    static func plan(isProUnlocked: Bool) -> ProNotificationSetupPlan {
        ProNotificationSetupPlan(
            shouldSetupSilentSync: true,
            shouldRequestAlertPermission: isProUnlocked,
            shouldSetupQuotaAlerts: isProUnlocked,
            shouldRemoveQuotaAlerts: !isProUnlocked)
    }
}

@MainActor
final class ProNotificationCoordinator {
    static let shared = ProNotificationCoordinator()

    private init() {}

    func reconcile(isProUnlocked: Bool) async {
        let plan = ProNotificationSetupPlanner.plan(isProUnlocked: isProUnlocked)

        if plan.shouldSetupSilentSync {
            await DeviceProviderZoneSubscription.shared.setupIfNeeded()
        }

        if plan.shouldRequestAlertPermission {
            await self.requestAlertPermission()
            UIApplication.shared.registerForRemoteNotifications()
        }

        if plan.shouldSetupQuotaAlerts {
            await QuotaTransitionSubscriptions.shared.setupIfNeeded()
        } else if plan.shouldRemoveQuotaAlerts {
            await QuotaTransitionSubscriptions.shared.removeManagedSubscriptions()
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
