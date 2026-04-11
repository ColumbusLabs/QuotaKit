import CloudKit
import CodexBarCore
import CodexBarSync
import SwiftUI

@MainActor
struct MobilePane: View {
    @Bindable var settings: SettingsStore
    let syncCoordinator: SyncCoordinator

    /// True when running in development mode. Checks:
    /// 1. Debug bundle ID (.debug suffix)
    /// 2. CODEXBAR_DEV=1 environment variable
    /// 3. Debug menu enabled in Settings → Advanced
    private var isDevelopmentBuild: Bool {
        Bundle.main.bundleIdentifier?.contains(".debug") == true
            || ProcessInfo.processInfo.environment["CODEXBAR_DEV"] == "1"
            || self.settings.debugMenuEnabled
    }

    @State private var lastTestResult: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                // iCloud Sync
                SettingsSection(contentSpacing: 12) {
                    Text("iCloud Sync")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    PreferenceToggleRow(
                        title: "Sync usage to iCloud",
                        subtitle: "Pushes usage data to iCloud so the iOS companion app can display it.",
                        binding: self.$settings.iCloudSyncEnabled)

                    if self.settings.iCloudSyncEnabled {
                        self.syncStatusView
                    }
                }

                Divider()

                // iOS Push Notifications (independent of Mac local notifications)
                SettingsSection(contentSpacing: 12) {
                    Text("iOS Push Notifications")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    PreferenceToggleRow(
                        title: "Push notifications to iOS",
                        subtitle: "When a session quota is depleted or restored, send a visible " +
                            "alert push to the iOS companion app via iCloud. This is independent " +
                            "of Mac local notifications — you can keep Mac quiet but still get " +
                            "alerts on your iPhone.",
                        binding: self.$settings.notificationPushToiOSEnabled)
                }

                if self.isDevelopmentBuild {
                    Divider()
                    self.devTestSection
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - DEV Test

    @ViewBuilder
    private var devTestSection: some View {
        SettingsSection(contentSpacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("DEV — iOS Push Test")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textCase(.uppercase)
            }

            Text("Writes a real `QuotaTransition` record to CloudKit, which fires the same " +
                "alert push the iOS app would receive in production. Subject to the toggle " +
                "above (must be ON).")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    self.runTestPush(state: "depleted")
                } label: {
                    Label("Test Codex Depleted", systemImage: "bell.badge")
                }
                .controlSize(.small)
                .disabled(!self.settings.notificationPushToiOSEnabled)

                Button {
                    self.runTestPush(state: "restored")
                } label: {
                    Label("Test Codex Restored", systemImage: "bell")
                }
                .controlSize(.small)
                .disabled(!self.settings.notificationPushToiOSEnabled)
            }

            Button {
                self.verifyPushSetup()
            } label: {
                Label("Verify Push Setup", systemImage: "checklist")
            }
            .controlSize(.small)

            if let lastTestResult {
                Text(lastTestResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func verifyPushSetup() {
        self.lastTestResult = "Querying CloudKit…"
        Task {
            let container = CKContainer(identifier: CloudSyncConstants.containerIdentifier)
            var lines: [String] = ["=== Verify Push Setup ==="]

            // 1. List subscriptions on BOTH databases
            for (label, db) in [("Private", container.privateCloudDatabase),
                                ("Public", container.publicCloudDatabase)] {
                do {
                    let subs = try await db.allSubscriptions()
                    lines.append("\(label) DB Subscriptions: \(subs.count)")
                    for sub in subs {
                        var desc = "  [\(sub.subscriptionID)] \(type(of: sub))"
                        if let q = sub as? CKQuerySubscription {
                            desc += " rt=\(q.recordType ?? "nil") zone=\(q.zoneID?.zoneName ?? "default")"
                            desc += " pred=\(q.predicate.predicateFormat)"
                        }
                        if let info = sub.notificationInfo {
                            desc += " alert=\(info.alertBody ?? "nil") sound=\(info.soundName ?? "nil")"
                        }
                        lines.append(desc)
                    }
                } catch {
                    lines.append("\(label) DB Subscriptions ERROR: \(error.localizedDescription)")
                }
            }

            // 2. Query QuotaTransition records on PUBLIC DB (where build 46+ writes)
            let publicDB = container.publicCloudDatabase
            do {
                let query = CKQuery(
                    recordType: CloudSyncConstants.quotaTransitionRecordType,
                    predicate: NSPredicate(value: true))
                let (results, _) = try await publicDB.records(matching: query)
                lines.append("Public DB QuotaTransition records: \(results.count)")
                for (id, result) in results {
                    switch result {
                    case .success(let record):
                        let prov = (record["providerName"] as? String) ?? "?"
                        let st = (record["state"] as? String) ?? "?"
                        lines.append("  \(id.recordName): \(prov) \(st)")
                    case .failure(let err):
                        lines.append("  \(id.recordName): ERROR \(err.localizedDescription)")
                    }
                }
            } catch {
                lines.append("Public DB QuotaTransition ERROR: \(error.localizedDescription)")
            }

            // Old: also show private DB custom zone records for reference
            let privateDB = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(
                zoneName: CloudSyncConstants.customZoneName,
                ownerName: CKCurrentUserDefaultName)
            do {
                let query = CKQuery(
                    recordType: CloudSyncConstants.quotaTransitionRecordType,
                    predicate: NSPredicate(value: true))
                let (results, _) = try await privateDB.records(
                    matching: query, inZoneWith: zoneID)
                lines.append("Private DB (custom zone) QuotaTransition records: \(results.count)")
            } catch {
                lines.append("Private DB QuotaTransition: \(error.localizedDescription)")
            }

            // 3. Try to create a test subscription on PUBLIC DB to surface errors
            let db = container.publicCloudDatabase
            lines.append("")
            lines.append("--- Attempting test subscription create ---")
            let testSubID = "mac-verify-test-sub"
            // Delete any prior test sub
            do {
                try await db.deleteSubscription(withID: testSubID)
            } catch {}

            do {
                let predicate = NSPredicate(format: "state == %@", "depleted")
                let sub = CKQuerySubscription(
                    recordType: CloudSyncConstants.quotaTransitionRecordType,
                    predicate: predicate,
                    subscriptionID: testSubID,
                    options: [.firesOnRecordCreation, .firesOnRecordUpdate])
                // Do NOT set zoneID — public DB uses default zone only
                let info = CKSubscription.NotificationInfo()
                info.alertBody = "Session quota depleted"
                info.titleLocalizationKey = "Push.QuotaDepleted.title"
                info.titleLocalizationArgs = ["providerName"]
                info.alertLocalizationKey = "Push.QuotaDepleted.body"
                info.soundName = "default"
                info.shouldBadge = true
                sub.notificationInfo = info
                _ = try await db.modifySubscriptions(saving: [sub], deleting: [])
                lines.append("✓ Test subscription created OK — schema is valid")
                // Clean up
                try? await db.deleteSubscription(withID: testSubID)
            } catch let error as CKError {
                lines.append("✗ CKError code=\(error.code.rawValue) \(error.localizedDescription)")
                if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                    lines.append("  underlying: \(underlying.domain) #\(underlying.code) \(underlying.localizedDescription)")
                }
            } catch {
                lines.append("✗ Error: \(error.localizedDescription)")
            }

            self.lastTestResult = lines.joined(separator: "\n")
        }
    }

    private func runTestPush(state: String) {
        self.lastTestResult = "Writing \(state) record…"
        Task {
            let result = await CloudSyncManager.shared.writeQuotaTransition(
                providerName: "Codex",
                providerID: "codex",
                state: state,
                transitionAt: Date())
            if result.succeeded {
                self.lastTestResult = "✓ Wrote \(state) record at \(self.shortTime()). " +
                    "Check iPhone for push within ~10s."
            } else {
                self.lastTestResult = "✗ Write failed: \(result.message ?? "unknown")"
            }
        }
    }

    private func shortTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    // MARK: - Sync Status

    private var syncStatusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if self.syncCoordinator.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let lastSync = self.syncCoordinator.lastSyncTime {
                    Image(systemName: self.syncCoordinator.lastSyncSucceeded
                        ? "checkmark.icloud"
                        : "exclamationmark.icloud")
                        .foregroundColor(self.syncCoordinator.lastSyncSucceeded
                            ? Color.secondary
                            : Color.red)
                        .font(.footnote)
                    Text(
                        "\(self.syncCoordinator.lastSyncSucceeded ? "Last sync" : "Last attempt"): "
                            + Self.formatSyncTime(lastSync))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "icloud")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                    Text("No sync yet")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }

            if let message = self.syncCoordinator.lastSyncMessage, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Sync Now") {
                Task {
                    await self.syncCoordinator.pushCurrentSnapshot()
                }
            }
            .controlSize(.small)
            .disabled(self.syncCoordinator.isSyncing)
        }
    }

    private static func formatSyncTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
