import CodexBarSync
import Foundation
import LiteCore
@preconcurrency import UserNotifications

/// Delivers alerts (068 §6.4): iPhone pushes as `QuotaTransition` records written exactly as the full app's
/// `QuotaTransitionWriter` does, and Mac banners through `UNUserNotificationCenter`.
@MainActor
final class AlertDelivery {
    private var iPhoneDebouncer = AlertDebouncer()
    private var macDebouncer = AlertDebouncer()
    private var didRequestAuthorization = false

    func deliver(_ events: [AlertEvent], mac: Bool, iPhone: Bool) {
        let now = Date()
        for event in events {
            if mac, self.macDebouncer.allows(event, at: now) {
                self.macDebouncer.recordDelivery(of: event, at: now)
                self.postBanner(for: event)
            }
            if iPhone, self.iPhoneDebouncer.allows(event, at: now) {
                self.writeRecord(for: event, at: now)
            }
        }
    }

    // MARK: - iPhone

    private func writeRecord(for event: AlertEvent, at now: Date) {
        Task {
            let manager = CloudSyncManager.shared
            let result: SyncPushResult = switch event.kind {
            case .depleted, .restored:
                await manager.writeQuotaTransition(
                    providerName: event.provider.displayName,
                    providerID: event.provider.rawValue,
                    state: event.state,
                    transitionAt: now,
                    accountEmail: event.accountEmail,
                    deduplicationScope: event.deduplicationScope)
            case let .warning(lane, threshold, _):
                await manager.writeQuotaWarningTransition(
                    providerName: event.provider.displayName,
                    providerID: event.provider.rawValue,
                    window: lane.rawValue,
                    threshold: threshold,
                    transitionAt: now,
                    accountEmail: event.accountEmail,
                    deduplicationScope: event.deduplicationScope,
                    windowDisplayLabel: nil)
            }
            if result.succeeded {
                self.iPhoneDebouncer.recordDelivery(of: event, at: now)
            } else {
                NSLog("QuotaKit Lite: alert record write failed: %@", result.message ?? "unknown")
            }
        }
    }

    // MARK: - Mac

    /// Permission is requested the first time a banner would show, never at launch.
    private func postBanner(for event: AlertEvent) {
        let center = UNUserNotificationCenter.current()
        let (title, body) = event.banner
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let needsAuthorization = !self.didRequestAuthorization
        self.didRequestAuthorization = true
        Task {
            if needsAuthorization {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(request)
        }
    }
}
