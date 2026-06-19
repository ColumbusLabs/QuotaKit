import CodexBarSync
import SwiftUI

struct AboutSyncDetailView: View {
    let usageData: SyncedUsageData
    @Environment(RemoteConfigStore.self) private var remoteConfigStore

    private var appDisplayVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section("Versions") {
                LabeledContent("iPhone App", value: self.appDisplayVersion)
                if let snapshot = self.usageData.snapshot {
                    LabeledContent("Mac App", value: snapshot.appVersion ?? String(localized: "Unknown"))
                    // When multiple Macs sync and at least one runs an older
                    // QuotaKit version than the highest, surface a subtle hint
                    // under the Mac App row. Prompts the user to update the
                    // older Mac so both sides can emit new-schema sync data
                    // (perplexityCredits, loginMethod, budget, etc. — all the
                    // `latestNonNil` fields that silently degrade when an
                    // old Mac refreshes last). Per-device detail appears in
                    // the Devices section below.
                    if self.hasOutdatedMac {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Some Mac devices are on older versions. Update them for complete sync data.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let mobileVersion = snapshot.mobileVersion {
                        LabeledContent("Synced Mobile Version", value: mobileVersion)
                    }
                } else {
                    LabeledContent("Mac App", value: String(localized: "Not synced"))
                }
            }

            Section {
                LabeledContent("Status", value: self.remoteConfigStore.configStatusSummary)
                LabeledContent("Config Version", value: self.remoteConfigStore.config.configVersion)
                if let fetchedAt = self.remoteConfigStore.lastFetchedAt {
                    LabeledContent("Last Updated", value: fetchedAt.formatted(.relative(presentation: .named)))
                }
                LabeledContent("Setup URL", value: self.remoteConfigStore.setupDisplayURL)
                LabeledContent("Disabled Features", value: self.disabledFeaturesSummary)
                if let lastError = self.remoteConfigStore.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button {
                    Task { await self.remoteConfigStore.refresh() }
                } label: {
                    if self.remoteConfigStore.isRefreshing {
                        ProgressView()
                    } else {
                        Label("Refresh Remote Config", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(self.remoteConfigStore.isRefreshing)
            } header: {
                Text("Remote Config")
            } footer: {
                Text(
                    "Public Columbus Labs configuration for safe OTA guardrails. It cannot change app code or access provider credentials.")
            }

            // MARK: Mac Update Prompt

            if self.usageData.usingKVSFallback {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.app.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Update QuotaKit on your Mac")
                                .font(.subheadline.weight(.semibold))
                            Text(
                                "Your Mac is using legacy sync. Open the setup link on your Mac to install the current QuotaKit build and enable CloudKit multi-device sync.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    MacSetupLinkActions(prominentShare: false)
                }
            }

            // MARK: Sync Status

            Section {
                TimelineView(.periodic(
                    from: .now,
                    by: SyncFreshnessTimeline.cadence(
                        since: self.syncStatusTimelineReferenceDate)))
                { timeline in
                    HStack {
                        self.syncStatusIcon
                        VStack(alignment: .leading, spacing: 2) {
                            Text(self.syncStatusTitle)
                                .font(.body)
                            if let detail = self.syncStatusDetail(now: timeline.date) {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            Task { await self.usageData.refresh() }
                        } label: {
                            if self.usageData.isRefreshing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(self.usageData.isRefreshing)
                    }
                }
            } header: {
                Text("Sync Status")
            } footer: {
                if let error = self.usageData.lastSyncError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            // MARK: Devices

            Section {
                if self.usageData.deviceSnapshots.isEmpty {
                    Text("No devices synced yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(self.usageData.deviceSnapshots.enumerated()), id: \.offset) { _, device in
                        HStack {
                            Image(systemName: "laptopcomputer")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.deviceName)
                                    .font(.body)
                                HStack(spacing: 8) {
                                    Text(device.syncTimestamp.formatted(.relative(presentation: .named)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("·")
                                        .foregroundStyle(.quaternary)
                                    Text("\(device.providers.count) providers")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let powerStatus = device.powerStatus,
                                       powerStatus.isDisplayable
                                    {
                                        Text("·")
                                            .foregroundStyle(.quaternary)
                                        DevicePowerStatusChip(status: powerStatus)
                                    }
                                }
                                // Per-device Mac version line. Appears only
                                // when the device reported a version (pre-1.1
                                // Macs left it nil — KVS fallback path). If
                                // this device lags the highest-semver Mac in
                                // the synced set, surface an orange "update
                                // available" chip so the user can identify
                                // which specific Mac to update.
                                if let version = device.appVersion {
                                    HStack(spacing: 6) {
                                        Text("QuotaKit \(version)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        if self.isDeviceOutdated(device) {
                                            Text("· Update available")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                HStack {
                    Text("Devices")
                    Spacer()
                    Text("\(self.usageData.deviceCount)")
                        .foregroundStyle(.secondary)
                }
            }

            // iOS 1.7.0 — gated by `showProviderChangelogLinks`. Mirrors
            // upstream PR #929; opt-in companion to the Mac menu's
            // changelog links so users on iPhone can jump to the
            // upstream release notes for the providers we sync.
            if self.showProviderChangelogLinks {
                Section {
                    Link(destination: URL(string: "https://github.com/openai/codex/releases")!) {
                        Label("Codex CLI", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://github.com/anthropics/claude-code/releases")!) {
                        Label("Claude Code", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://github.com/google-gemini/gemini-cli/releases")!) {
                        Label("Gemini CLI", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("provider_changelogs_section")
                } footer: {
                    Text("provider_changelogs_footer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("About & Sync")
    }

    @AppStorage(MobileSettingsKeys.showProviderChangelogLinks) private var showProviderChangelogLinks = false

    private var disabledFeaturesSummary: String {
        let knownDisabled = FeatureGate.allCases
            .filter { self.remoteConfigStore.isDisabled($0) }
            .map(\.title)
        return knownDisabled.isEmpty
            ? String(localized: "None")
            : knownDisabled.joined(separator: ", ")
    }

    private var syncStatusIcon: some View {
        Group {
            switch self.usageData.syncStatus {
            case .synced:
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(.green)
            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                    .foregroundStyle(.blue)
            case .error:
                Image(systemName: "exclamationmark.icloud.fill")
                    .foregroundStyle(.red)
            case .noData:
                Image(systemName: "icloud.slash.fill")
                    .foregroundStyle(.orange)
            case .incompatibleData:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.title2)
    }

    private var syncStatusTitle: String {
        switch self.usageData.syncStatus {
        case .synced: String(localized: "Synced")
        case .syncing: String(localized: "Syncing…")
        case .error: String(localized: "Sync Error")
        case .noData: String(localized: "No Data")
        case .incompatibleData: String(localized: "Incompatible Data")
        }
    }

    /// True when 2+ Macs are synced AND at least one runs an older
    /// `appVersion` than the highest-semver one. Drives the orange-tinted
    /// hint under the top-level "Mac App" row. Single-device setups never
    /// trip this (there's nothing to compare against).
    private var hasOutdatedMac: Bool {
        guard self.usageData.deviceSnapshots.count >= 2,
              let latestVersion = self.usageData.snapshot?.appVersion
        else { return false }
        return self.usageData.deviceSnapshots.contains { device in
            guard let deviceVersion = device.appVersion else { return false }
            return CloudSyncReader.semverLessThan(deviceVersion, latestVersion)
        }
    }

    /// True when this specific device's `appVersion` is strictly less than
    /// the highest-semver one across all synced devices. Drives the per-row
    /// "Update available" chip. Uses the same semver comparator as
    /// `CloudSyncReader.mergeSnapshots`'s `max(by:)` selection so the two
    /// views stay in lockstep — no device is both "chosen as the Mac App
    /// version shown at top" AND "flagged as outdated" simultaneously.
    private func isDeviceOutdated(_ device: SyncedUsageSnapshot) -> Bool {
        guard let deviceVersion = device.appVersion,
              let latestVersion = self.usageData.snapshot?.appVersion
        else { return false }
        return CloudSyncReader.semverLessThan(deviceVersion, latestVersion)
    }

    private var syncStatusTimelineReferenceDate: Date? {
        switch self.usageData.syncStatus {
        case let .synced(lastConfirmedSync):
            lastConfirmedSync
        case .syncing, .error:
            self.usageData.snapshot?.syncTimestamp
        case .noData, .incompatibleData:
            nil
        }
    }

    private func syncStatusDetail(now: Date) -> String? {
        switch self.usageData.syncStatus {
        case let .synced(lastConfirmedSync):
            SyncFreshnessFormatter.lastSyncedText(
                since: lastConfirmedSync,
                now: now)
        case .syncing:
            SyncFreshnessFormatter.refreshingText(
                lastConfirmedSync: self.usageData.snapshot?.syncTimestamp,
                now: now)
        case .noData: String(localized: "Waiting for Mac to push data")
        case .incompatibleData: String(localized: "Please update QuotaKit on Mac")
        case .error:
            SyncFreshnessFormatter.refreshFailedText(
                lastConfirmedSync: self.usageData.snapshot?.syncTimestamp,
                now: now)
        }
    }
}

private struct DevicePowerStatusChip: View {
    let status: SyncDevicePowerStatus

    private var percentText: String? {
        self.status.batteryPercent.map { "\($0)%" }
    }

    private var displayText: String? {
        guard let percentText else { return nil }
        switch self.status.state {
        case .charging:
            return String(format: String(localized: "%@ charging"), percentText)
        case .charged:
            return String(format: String(localized: "%@ charged"), percentText)
        case .pluggedIn:
            return String(format: String(localized: "%@ plugged in"), percentText)
        case .battery, .unknown:
            return percentText
        case .noBattery:
            return nil
        }
    }

    private var symbolName: String {
        switch self.status.state {
        case .charging:
            "battery.100.bolt"
        case .charged, .pluggedIn:
            self.status.state == .pluggedIn ? "powerplug.fill" : "battery.100"
        case .battery:
            self.batterySymbolName
        case .noBattery, .unknown:
            "battery.0"
        }
    }

    private var batterySymbolName: String {
        guard let percent = self.status.batteryPercent else { return "battery.0" }
        switch percent {
        case 76...100: return "battery.100"
        case 51...75: return "battery.75"
        case 26...50: return "battery.50"
        case 11...25: return "battery.25"
        default: return "battery.0"
        }
    }

    private var tint: Color {
        switch self.status.state {
        case .charging, .charged, .pluggedIn:
            .green
        case .battery:
            (self.status.batteryPercent ?? 100) <= 20 ? .orange : .secondary
        case .noBattery, .unknown:
            .secondary
        }
    }

    private var stateText: String {
        switch self.status.state {
        case .battery:
            String(localized: "On Battery")
        case .charging:
            String(localized: "Charging")
        case .charged:
            String(localized: "Charged")
        case .pluggedIn:
            String(localized: "Plugged In")
        case .noBattery:
            String(localized: "No Battery")
        case .unknown:
            String(localized: "Unknown")
        }
    }

    var body: some View {
        if let displayText, let percentText {
            HStack(spacing: 3) {
                Image(systemName: self.symbolName)
                    .font(.caption2.weight(.semibold))
                Text(displayText)
                    .font(.caption)
            }
            .foregroundStyle(self.tint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(String(
                    format: String(localized: "Battery %@, %@"),
                    percentText,
                    self.stateText)))
        }
    }
}
