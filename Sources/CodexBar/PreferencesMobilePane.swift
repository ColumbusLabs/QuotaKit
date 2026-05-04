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

    /// Mock provider toggle. Bound to UserDefaults key
    /// `CodexBarMockProvidersEnabled` so the same flag toggles whether
    /// `MockProviderInjector` injects 8 synthetic snapshots into every
    /// sync cycle. Visible in Settings whenever `iCloudSyncEnabled` is
    /// on so QA can flip the switch and immediately see iPhone behavior.
    @AppStorage("CodexBarMockProvidersEnabled")
    private var mockProvidersEnabled: Bool = false

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

                Divider()
                self.mockProviderSection

                if self.isDevelopmentBuild {
                    Divider()
                    self.devTestSection
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Mock Provider Data (visible to all users; default OFF)

    /// Reference list of all 8 mocks the injector emits when active.
    /// Hardcoded here so the Settings UI can show side-by-side
    /// "what should appear on my iPhone" vs. what actually appears.
    /// Kept in sync with `MockProviderInjector` mocks (see Mac 0.23.5+
    /// docstring there for the mix design rationale).
    private struct MockReferenceCard: Identifiable {
        let id: String
        let displayName: String
        let subtitle: String
        let badge: String
    }

    private static let mockReference: [MockReferenceCard] = [
        MockReferenceCard(
            id: "codex|alice",
            displayName: "Codex (Alice · Mock)",
            subtitle: "café-mock@codex.test · 35% / 60%",
            badge: "first-class"),
        MockReferenceCard(
            id: "codex|bob",
            displayName: "Codex (Bob · Mock)",
            subtitle: "bob-mock@codex.test · 75% / 100%",
            badge: "first-class"),
        MockReferenceCard(
            id: "codex|carol",
            displayName: "Codex (Carol · Mock)",
            subtitle: "carol-mock@codex.test · 0% / 12%",
            badge: "first-class"),
        MockReferenceCard(
            id: "claude|personal",
            displayName: "Claude (Personal · Mock)",
            subtitle: "personal-mock@claude.test · 5h+Sonnet+Opus",
            badge: "first-class"),
        MockReferenceCard(
            id: "claude|work",
            displayName: "Claude (Work · Mock)",
            subtitle: "work-mock@claude.test · 5h+Sonnet",
            badge: "first-class"),
        MockReferenceCard(
            id: "perplexity|pro",
            displayName: "Perplexity (Pro · Mock)",
            subtitle: "pro-mock@perplexity.test · $410 credits",
            badge: "first-class"),
        MockReferenceCard(
            id: "_mock_cursor_unknown",
            displayName: "Cursor (Cookie expired · Mock)",
            subtitle: "expired-mock@cursor.test · isError=true",
            badge: "fallback"),
        MockReferenceCard(
            id: "_mock_synthetic_unknown",
            displayName: "Synthetic (3-lane fallback · Mock)",
            subtitle: "lanes-mock@synthetic.test · 30-day history",
            badge: "fallback"),
    ]

    private var mockProviderSection: some View {
        SettingsSection(contentSpacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "testtube.2")
                    .foregroundStyle(.purple)
                    .font(.caption)
                Text("Debug · Mock Provider Data")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .textCase(.uppercase)
            }

            PreferenceToggleRow(
                title: "Inject mock provider data",
                subtitle: "Pushes 32 synthetic providers across 29 IDs (6 rich mocks for codex/"
                    + "claude/perplexity multi-account paths, 24 simple mocks covering every other "
                    + "real provider, 2 unknown-ID mocks for fallback rendering) on every sync. "
                    + "All mock emails use the `.test` TLD so iPhone (1.5.2+) renders them with a "
                    + "MOCK badge. Toggle off and CloudKit automatically purges them within ~1 "
                    + "cycle. Default OFF.",
                binding: self.$mockProvidersEnabled)

            if self.mockProvidersEnabled {
                Divider()
                Text("Reference — most-tested 8 mocks (24 simple mocks omitted for brevity):")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Self.mockReference) { card in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(card.badge == "first-class" ? "●" : "◌")
                                .font(.caption2.monospaced())
                                .foregroundStyle(
                                    card.badge == "first-class"
                                        ? Color.green
                                        : Color.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(card.displayName)
                                    .font(.caption)
                                Text(card.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Mocks add ~$85 to your 30-day cost dashboard while active. "
                        + "Toggle off to restore real numbers.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - DEV Test

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

            // Codex
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex").font(.caption.bold())
                HStack(spacing: 12) {
                    Button {
                        self.runTestPush(provider: "Codex", providerID: "codex", state: "depleted")
                    } label: {
                        Label("Depleted", systemImage: "bell.badge")
                    }
                    .controlSize(.small)
                    Button {
                        self.runTestPush(provider: "Codex", providerID: "codex", state: "restored")
                    } label: {
                        Label("Restored", systemImage: "bell")
                    }
                    .controlSize(.small)
                }
            }
            .disabled(!self.settings.notificationPushToiOSEnabled)

            // Claude
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude").font(.caption.bold())
                HStack(spacing: 12) {
                    Button {
                        self.runTestPush(provider: "Claude", providerID: "claude", state: "depleted")
                    } label: {
                        Label("Depleted", systemImage: "bell.badge")
                    }
                    .controlSize(.small)
                    Button {
                        self.runTestPush(provider: "Claude", providerID: "claude", state: "restored")
                    } label: {
                        Label("Restored", systemImage: "bell")
                    }
                    .controlSize(.small)
                }
            }
            .disabled(!self.settings.notificationPushToiOSEnabled)

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
            var lines = ["=== Verify Push Setup ==="]

            // 1. List subscriptions on BOTH databases
            for (label, db) in [
                ("Private", container.privateCloudDatabase),
                ("Public", container.publicCloudDatabase),
            ] {
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
                    case let .success(record):
                        let prov = (record["providerName"] as? String) ?? "?"
                        let st = (record["state"] as? String) ?? "?"
                        lines.append("  \(id.recordName): \(prov) \(st)")
                    case let .failure(err):
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
            // --- Test A: CKQuerySubscription persistence ---
            lines.append("")
            lines.append("--- Test A: CKQuerySubscription persistence ---")
            let testQuerySubID = "mac-test-query-sub"
            defer { Task { try? await db.deleteSubscription(withID: testQuerySubID) } }
            do {
                try? await db.deleteSubscription(withID: testQuerySubID)
                let sub = CKQuerySubscription(
                    recordType: CloudSyncConstants.quotaTransitionRecordType,
                    predicate: NSPredicate(format: "state == %@", "depleted"),
                    subscriptionID: testQuerySubID,
                    options: [.firesOnRecordCreation])
                let info = CKSubscription.NotificationInfo()
                info.alertBody = "Test"
                info.soundName = "default"
                sub.notificationInfo = info
                _ = try await db.modifySubscriptions(saving: [sub], deleting: [])
                lines.append("  save: ✓")

                // NOW check if it actually persisted
                let allSubs = try await db.allSubscriptions()
                let found = allSubs.first(where: { $0.subscriptionID == testQuerySubID })
                if found != nil {
                    lines.append("  allSubscriptions: ✓ FOUND — CKQuerySubscription persists!")
                } else {
                    lines.append("  allSubscriptions: ✗ NOT FOUND — save succeeded but didn't persist")
                    lines.append("  (total subs: \(allSubs.count))")
                }
            } catch {
                lines.append("  ✗ Error: \(error.localizedDescription)")
            }

            // --- Test B: CKRecordZoneSubscription persistence (on private DB) ---
            lines.append("")
            lines.append("--- Test B: CKRecordZoneSubscription persistence ---")
            let testZoneSubID = "mac-test-zone-sub"
            defer { Task { try? await container.privateCloudDatabase.deleteSubscription(withID: testZoneSubID) } }
            let privDB = container.privateCloudDatabase
            let testZoneID = CKRecordZone.ID(
                zoneName: CloudSyncConstants.quotaTransitionsZoneName,
                ownerName: CKCurrentUserDefaultName)
            do {
                // Ensure zone exists before creating a zone subscription
                do {
                    _ = try await privDB.recordZone(for: testZoneID)
                } catch let ckErr as CKError where ckErr.code == .zoneNotFound {
                    _ = try await privDB.modifyRecordZones(
                        saving: [CKRecordZone(zoneID: testZoneID)], deleting: [])
                }
                try? await privDB.deleteSubscription(withID: testZoneSubID)
                let sub = CKRecordZoneSubscription(
                    zoneID: testZoneID, subscriptionID: testZoneSubID)
                let info = CKSubscription.NotificationInfo()
                info.alertBody = "Test zone"
                info.soundName = "default"
                sub.notificationInfo = info
                _ = try await privDB.modifySubscriptions(saving: [sub], deleting: [])
                lines.append("  save: ✓")

                let allSubs = try await privDB.allSubscriptions()
                let found = allSubs.first(where: { $0.subscriptionID == testZoneSubID })
                if found != nil {
                    lines.append("  allSubscriptions: ✓ FOUND — CKRecordZoneSubscription persists!")
                } else {
                    lines.append("  allSubscriptions: ✗ NOT FOUND")
                    lines.append("  (total subs: \(allSubs.count))")
                }
            } catch {
                lines.append("  ✗ Error: \(error.localizedDescription)")
            }

            self.lastTestResult = lines.joined(separator: "\n")
        }
    }

    private func runTestPush(provider: String, providerID: String, state: String) {
        self.lastTestResult = "Writing \(provider) \(state)…"
        Task {
            let result = await CloudSyncManager.shared.writeQuotaTransition(
                providerName: provider,
                providerID: providerID,
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
