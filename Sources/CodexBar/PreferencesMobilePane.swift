import CodexBarCore
import SwiftUI
@preconcurrency import UserNotifications

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
                        title: "Push notifications to iOS",
                        subtitle: "When enabled, quota changes are synced to CloudKit so the iOS app " +
                            "can show push notifications.",
                        binding: self.$settings.notificationPushToiOSEnabled)

                    self.notificationPermissionStatus
                }

                // DEV-only test section
                if self.isDevelopmentBuild {
                    Divider()

                    SettingsSection(contentSpacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "hammer.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("DEV — iOS Push Testing")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .textCase(.uppercase)
                        }

                        Text("Simulates quota transitions and pushes to CloudKit. " +
                            "iOS should receive a local notification for each test.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        // Codex
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Codex")
                                .font(.subheadline.bold())
                            HStack(spacing: 12) {
                                Button {
                                    self.testPush(.depleted, provider: .codex)
                                } label: {
                                    Label("Depleted", systemImage: "bell.badge")
                                }
                                .controlSize(.small)

                                Button {
                                    self.testPush(.restored, provider: .codex)
                                } label: {
                                    Label("Restored", systemImage: "bell")
                                }
                                .controlSize(.small)
                            }
                        }

                        // Claude
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Claude")
                                .font(.subheadline.bold())
                            HStack(spacing: 12) {
                                Button {
                                    self.testPush(.depleted, provider: .claude)
                                } label: {
                                    Label("Depleted", systemImage: "bell.badge")
                                }
                                .controlSize(.small)

                                Button {
                                    self.testPush(.restored, provider: .claude)
                                } label: {
                                    Label("Restored", systemImage: "bell")
                                }
                                .controlSize(.small)
                            }
                        }

                        // Test result
                        if let result = self.lastTestResult {
                            HStack(spacing: 6) {
                                Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.succeeded ? .green : .red)
                                    .font(.footnote)
                                Text(result.message)
                                    .font(.footnote)
                                    .foregroundStyle(result.succeeded ? Color.secondary : Color.red)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Notification Permission

    @State private var notificationAuthorized: Bool?
    @State private var lastTestResult: (succeeded: Bool, message: String)?

    @ViewBuilder
    private var notificationPermissionStatus: some View {
        HStack(spacing: 8) {
            if let authorized = self.notificationAuthorized {
                if authorized {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                    Text("Mac notification permission granted")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mac notification permission not granted")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        Text("Push to iOS requires Mac notifications to detect quota changes.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings")!)
                    }
                    .controlSize(.small)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Checking notification permission…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            self.checkNotificationPermission()
        }
    }

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationAuthorized = settings.authorizationStatus == .authorized
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

    private func testPush(_ transition: SessionQuotaTransition, provider: UsageProvider) {
        let providerName = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
        let transitionName = transition == .depleted ? "depleted" : "restored"
        self.lastTestResult = nil

        Task {
            // 1. Post Mac-side notification
            SessionQuotaNotifier().post(transition: transition, provider: provider, badge: 1)

            // 2. Push synthetic snapshot to CloudKit → triggers iOS silent push
            let result = await self.syncCoordinator.pushTestSnapshot(
                provider: provider,
                simulatedUsedPercent: transition == .depleted ? 100.0 : 0.0)

            if result.succeeded {
                self.lastTestResult = (
                    succeeded: true,
                    message: "✓ \(providerName) \(transitionName) pushed to CloudKit. Check iOS for notification.")
            } else {
                self.lastTestResult = (
                    succeeded: false,
                    message: "✗ \(providerName) \(transitionName) failed: \(result.message ?? "Unknown error")")
            }
        }
    }

    private static func formatSyncTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
