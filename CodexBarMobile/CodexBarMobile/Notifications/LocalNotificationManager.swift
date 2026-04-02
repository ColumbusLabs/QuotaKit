import Foundation
import UserNotifications

/// Manages local notification permissions and posting for session quota alerts.
final class LocalNotificationManager: Sendable {

    static let shared = LocalNotificationManager()

    private init() {}

    /// Requests notification authorization. Call early in app lifecycle.
    func requestAuthorization() async {
        do {
            try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Notification authorization failed: \(error)")
        }
    }

    /// Posts a local notification for a session quota transition.
    func postSessionQuotaNotification(providerName: String, transition: SessionQuotaMonitor.Transition) async {
        guard transition != .none else { return }

        let content = UNMutableNotificationContent()

        switch transition {
        case .depleted:
            content.title = String(format: String(localized: "%@ session depleted"), providerName)
            content.body = String(localized: "0% left. Will notify when it's available again.")
        case .restored:
            content.title = String(format: String(localized: "%@ session restored"), providerName)
            content.body = String(localized: "Session quota is available again.")
        case .none:
            return
        }

        content.sound = .default

        let id = "session-\(providerName)-\(transition)-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to post notification: \(error)")
        }
    }
}
