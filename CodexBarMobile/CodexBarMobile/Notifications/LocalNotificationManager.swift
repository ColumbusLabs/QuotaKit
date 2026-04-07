import Foundation
import UserNotifications

/// Manages local notification permissions and posting for session quota alerts.
final class LocalNotificationManager: Sendable {

    static let shared = LocalNotificationManager()

    private init() {}

    /// Requests notification authorization. Call early in app lifecycle.
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                PushDiagnosticStore.shared.recordAuthorizationStatus(granted)
            }
        } catch {
            print("Notification authorization failed: \(error)")
            await MainActor.run {
                PushDiagnosticStore.shared.recordAuthorizationStatus(false)
            }
        }
    }

    /// Posts a local notification for a session quota transition.
    /// Returns `true` if the notification was added successfully.
    @discardableResult
    func postSessionQuotaNotification(
        providerName: String,
        transition: SessionQuotaMonitor.Transition
    ) async -> Bool {
        guard transition != .none else { return false }

        let content = UNMutableNotificationContent()

        switch transition {
        case .depleted:
            content.title = String(format: String(localized: "%@ session depleted"), providerName)
            content.body = String(localized: "0% left. Will notify when it's available again.")
        case .restored:
            content.title = String(format: String(localized: "%@ session restored"), providerName)
            content.body = String(localized: "Session quota is available again.")
        case .none:
            return false
        }

        content.sound = .default

        let id = "session-\(providerName)-\(transition)-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)

        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            print("Failed to post notification: \(error)")
            await MainActor.run {
                PushDiagnosticStore.shared.recordNotificationPost(
                    .failed(message: error.localizedDescription))
            }
            return false
        }
    }

    /// DEV: posts a manual test notification to verify the UN pipeline end-to-end.
    @discardableResult
    func postDiagnosticTestNotification() async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = "CodexBar Diagnostic Test"
        content.body = "If you see this, local notifications are working."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "diagnostic-\(UUID().uuidString)",
            content: content,
            trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            print("Diagnostic notification failed: \(error)")
            return false
        }
    }
}
