import CodexBarCore
import SwiftUI

@MainActor
struct MobilePane: View {
    @Bindable var settings: SettingsStore
    let syncCoordinator: SyncCoordinator

    /// True when running in development mode. Checks:
    /// 1. Debug bundle ID (.debug suffix)
    /// 2. CODEXBAR_DEV=1 environment variable
    /// 3. Debug menu is enabled in Settings → Advanced
    private var isDevelopmentBuild: Bool {
        Bundle.main.bundleIdentifier?.contains(".debug") == true
            || ProcessInfo.processInfo.environment["CODEXBAR_DEV"] == "1"
            || self.settings.debugMenuEnabled
    }

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

                // Notifications
                SettingsSection(contentSpacing: 12) {
                    Text("Notifications")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    PreferenceToggleRow(
                        title: "Session quota notifications",
                        subtitle: "Notifies when the 5-hour session quota hits 0% and when it becomes " +
                            "available again.",
                        binding: self.$settings.sessionQuotaNotificationsEnabled)

                    PreferenceToggleRow(
                        title: "Push notifications to iOS",
                        subtitle: "When enabled, quota changes are synced to CloudKit so the iOS app " +
                            "can show push notifications.",
                        binding: self.$settings.notificationPushToiOSEnabled)
                }

                // DEV-only test section
                if self.isDevelopmentBuild {
                    Divider()

                    SettingsSection(contentSpacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "hammer.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("DEV — Push Notification Testing")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .textCase(.uppercase)
                        }

                        Text("These buttons simulate quota transitions and push the snapshot to CloudKit, " +
                            "triggering an iOS notification.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                self.testPush(.depleted)
                            } label: {
                                Label("Test Depleted", systemImage: "exclamationmark.triangle")
                            }
                            .controlSize(.small)

                            Button {
                                self.testPush(.restored)
                            } label: {
                                Label("Test Restored", systemImage: "checkmark.circle")
                            }
                            .controlSize(.small)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
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

    // MARK: - Test Push

    private func testPush(_ transition: SessionQuotaTransition) {
        // Post Mac-side notification
        SessionQuotaNotifier().post(transition: transition, provider: .claude, badge: 1)

        // Push a snapshot with a synthetic session window that iOS can detect as a transition.
        // Depleted = 100% used (0% remaining), Restored = 0% used (100% remaining).
        Task {
            await self.syncCoordinator.pushTestSnapshot(
                simulatedUsedPercent: transition == .depleted ? 100.0 : 0.0)
        }
    }

    private static func formatSyncTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
