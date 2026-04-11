import CloudKit
import CodexBarSync
import Foundation
import Observation

/// Minimal diagnostic store for the alert-push subscription setup.
/// Stores the result of each setup attempt so the user can see it in
/// Settings → Developer Tools without needing Xcode Console.
@Observable
@MainActor
final class PushSetupDiagnostic {
    static let shared = PushSetupDiagnostic()

    private(set) var zoneStatus: String = "pending"
    private(set) var depletedSubStatus: String = "pending"
    private(set) var restoredSubStatus: String = "pending"
    private(set) var notificationPermission: String = "pending"
    private(set) var remoteRegistration: String = "pending"
    private(set) var subscriptionList: String = "pending"
    private(set) var lastError: String?
    private(set) var lastUpdated: Date?

    private init() {}

    func recordZone(_ status: String) {
        self.zoneStatus = status
        self.lastUpdated = Date()
    }

    func recordDepletedSub(_ status: String) {
        self.depletedSubStatus = status
        self.lastUpdated = Date()
    }

    func recordRestoredSub(_ status: String) {
        self.restoredSubStatus = status
        self.lastUpdated = Date()
    }

    func recordPermission(_ status: String) {
        self.notificationPermission = status
        self.lastUpdated = Date()
    }

    func recordRegistration(_ status: String) {
        self.remoteRegistration = status
        self.lastUpdated = Date()
    }

    func recordError(_ error: String) {
        self.lastError = error
        self.lastUpdated = Date()
    }

    /// Queries CloudKit for the actual subscription list from THIS app's perspective.
    func refreshSubscriptionList() async {
        let container = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
        let db = container.privateCloudDatabase
        do {
            let subs = try await db.allSubscriptions()
            var lines: [String] = ["\(subs.count) subscription(s):"]
            for sub in subs {
                var desc = "[\(sub.subscriptionID)] \(type(of: sub))"
                if let q = sub as? CKQuerySubscription {
                    desc += " rt=\(q.recordType ?? "nil")"
                    desc += " zone=\(q.zoneID?.zoneName ?? "nil")"
                    desc += " pred=\(q.predicate.predicateFormat)"
                }
                if let info = sub.notificationInfo {
                    desc += " titleKey=\(info.titleLocalizationKey ?? "nil")"
                    desc += " alertKey=\(info.alertLocalizationKey ?? "nil")"
                    desc += " sound=\(info.soundName ?? "nil")"
                }
                lines.append(desc)
            }
            self.subscriptionList = lines.joined(separator: "\n")
        } catch {
            self.subscriptionList = "ERROR: \(error.localizedDescription)"
        }
        self.lastUpdated = Date()
    }
}
