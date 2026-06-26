import CodexBarSync
import SwiftUI

struct DeveloperToolsView: View {
    let usageData: SyncedUsageData

    var body: some View {
        List {
            Section {
                NavigationLink {
                    RawSyncDataView(usageData: self.usageData)
                } label: {
                    SettingSummaryRow(
                        title: "Raw Sync Data",
                        symbolName: "doc.text.magnifyingglass",
                        summary: String(localized: "Per-device unmerged data for debugging"))
                }

                NavigationLink {
                    PushSetupDiagnosticView()
                } label: {
                    SettingSummaryRow(
                        title: "Push Setup",
                        symbolName: "bell.badge.waveform",
                        summary: "Alert push subscription state")
                }
            } footer: {
                Text("These tools expose internal sync and push state to help diagnose issues.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Developer Tools")
    }
}

private struct RawSyncDataView: View {
    let usageData: SyncedUsageData

    var body: some View {
        List {
            if self.usageData.deviceSnapshots.isEmpty {
                Section {
                    Text("No device data available")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(self.usageData.deviceSnapshots.enumerated()), id: \.offset) { _, device in
                    RawDeviceSection(device: device)
                }
            }
        }
        .navigationTitle("Raw Sync Data")
    }
}

private struct RawDeviceSection: View {
    let device: SyncedUsageSnapshot

    var body: some View {
        Section {
            LabeledContent("Device ID", value: self.device.deviceID ?? "N/A")
            LabeledContent("Device Name", value: self.device.deviceName)
            LabeledContent("App Version", value: self.device.appVersion ?? "Unknown")
            LabeledContent(
                "Sync Time",
                value: self.device.syncTimestamp.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Providers", value: "\(self.device.providers.count)")

            // Use cardIdentityKey (providerID|accountEmail) so multi-account
            // and mock-vs-real entries with the SAME providerID don't get
            // collapsed by SwiftUI's diffing. Hit on user QA 2026-05-04 —
            // real `codex|msxiao113@gmail.com` and `codex|alice-mock@codex.test`
            // were rendering as a single row because both had providerID == "codex".
            ForEach(self.device.providers, id: \.cardIdentityKey) { provider in
                RawProviderRow(provider: provider)
            }
        } header: {
            HStack {
                Image(systemName: "laptopcomputer")
                Text(self.device.deviceName)
            }
        }
    }
}

private struct RawProviderRow: View {
    let provider: ProviderUsageSnapshot

    var body: some View {
        NavigationLink {
            RawProviderDetailView(provider: self.provider)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.provider.providerName)
                        .fontWeight(.medium)
                    // Email visible at a glance — distinguishes real vs mock
                    // and Codex multi-account on the spot. Hit during user QA
                    // 2026-05-04 (couldn't tell which 'Claude' row was real).
                    if let email = self.provider.accountEmail, !email.isEmpty {
                        Text(email)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(
                            "(no email)",
                            comment: "Raw Sync Data row subtitle when provider has no account email (e.g. Claude / Ollama / Copilot)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let cost = self.provider.costSummary {
                        // 30-day cost is what iPhone Cost dashboard
                        // aggregates — show it inline so multi-device sync
                        // bugs are visible at a glance instead of needing
                        // a tap into detail.
                        Text(String(
                            format: String(
                                localized: "$%.2f / 30d",
                                comment: "Raw Sync Data row trailing label — 30-day cost"),
                            cost.last30DaysCostUSD ?? 0))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(
                            format: String(
                                localized: "$%.2f / today",
                                comment: "Raw Sync Data row trailing label — today's cost"),
                            cost.sessionCostUSD ?? 0))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let window = self.provider.allRateWindows.first {
                        Text("\(window.label ?? "Usage"): \(Int(window.usedPercent))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

private struct RawProviderDetailView: View {
    let provider: ProviderUsageSnapshot

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Provider", value: self.provider.providerName)
                LabeledContent("ID", value: self.provider.providerID)
                if let email = self.provider.accountEmail {
                    LabeledContent("Account", value: email)
                }
                if let login = self.provider.loginMethod {
                    LabeledContent("Login", value: login)
                }
                LabeledContent(
                    "Last Updated",
                    value: self.provider.lastUpdated.formatted(date: .abbreviated, time: .shortened))
                if self.provider.isError {
                    LabeledContent("Status", value: self.provider.statusMessage ?? "Error")
                        .foregroundStyle(.red)
                }
            }

            if let cost = self.provider.costSummary {
                Section("Cost Summary") {
                    LabeledContent("Session", value: self.formatCost(cost.sessionCostUSD))
                    LabeledContent("Session Tokens", value: self.formatTokens(cost.sessionTokens))
                    LabeledContent("30 Days", value: self.formatCost(cost.last30DaysCostUSD))
                    LabeledContent("30 Days Tokens", value: self.formatTokens(cost.last30DaysTokens))
                }
            }

            self.rateWindowsSection

            if let cost = self.provider.costSummary, !cost.daily.isEmpty {
                self.dailyCostSection(cost.daily)
            }
        }
        .navigationTitle(self.provider.providerName)
    }

    @ViewBuilder
    private var rateWindowsSection: some View {
        let windows = self.provider.allRateWindows
        if !windows.isEmpty {
            Section("Rate Limits") {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    RawRateWindowRow(window: window)
                }
            }
        }
    }

    @ViewBuilder
    private func dailyCostSection(_ daily: [SyncDailyPoint]) -> some View {
        let sorted = daily.sorted { $0.dayKey > $1.dayKey }
        Section("Daily Cost (\(sorted.count) days)") {
            ForEach(sorted, id: \.dayKey) { day in
                RawDailyPointRow(day: day)
            }
        }
    }

    private func formatCost(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "$%.2f", value)
    }

    private func formatTokens(_ value: Int?) -> String {
        guard let value else { return "N/A" }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000)
        }
        return "\(value)"
    }
}

private struct RawRateWindowRow: View {
    let window: SyncRateWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(self.window.label ?? "Rate Limit")
                Spacer()
                Text("\(Int(self.window.usedPercent))% used")
                    .foregroundStyle(self.window.usedPercent > 80 ? .red : .secondary)
            }
            ProgressView(value: min(self.window.usedPercent, 100), total: 100)
                .tint(self.window.usedPercent > 80 ? .red : .blue)
            if let reset = self.window.resetDescription {
                Text("Resets \(reset)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RawDailyPointRow: View {
    let day: SyncDailyPoint

    var body: some View {
        DisclosureGroup {
            self.breakdownContent
        } label: {
            HStack {
                Text(self.day.dayKey)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "$%.2f", self.day.costUSD))
                        .font(.body.monospacedDigit())
                    Text(self.formatTokens(self.day.totalTokens))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var breakdownContent: some View {
        if !self.day.modelBreakdowns.isEmpty {
            ForEach(self.day.modelBreakdowns, id: \.label) { item in
                VStack(alignment: .leading, spacing: 1) {
                    LabeledContent(item.label, value: String(format: "$%.2f", item.costUSD))
                    if let split = CodexCostSplit.subtitle(
                        standardCostUSD: item.standardCostUSD,
                        priorityCostUSD: item.priorityCostUSD)
                    {
                        Text(split)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !self.day.serviceBreakdowns.isEmpty {
            ForEach(self.day.serviceBreakdowns, id: \.label) { item in
                LabeledContent(item.label, value: String(format: "$%.2f", item.costUSD))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatTokens(_ value: Int) -> String {
        CostFormatting.tokens(value)
    }
}

private struct PushSetupDiagnosticView: View {
    @State private var diag = PushSetupDiagnostic.shared
    @State private var persistenceTestResult: String?
    @Environment(ProEntitlementStore.self) private var proEntitlementStore

    var body: some View {
        List {
            Section("Setup Status") {
                self.row("Zone", self.diag.zoneStatus)
                self.row("Depleted Sub", self.diag.depletedSubStatus)
                self.row("Restored Sub", self.diag.restoredSubStatus)
                self.row("Permission", self.diag.notificationPermission)
                self.row("APNs Registration", self.diag.remoteRegistration)
            }

            Section("Subscription List (from iOS)") {
                Text(self.diag.subscriptionList)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)

                Button("Refresh") {
                    Task {
                        await PushSetupDiagnostic.shared.refreshSubscriptionList()
                    }
                }
                .controlSize(.small)
            }

            if let error = self.diag.lastError {
                Section("Last Error") {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("Actions") {
                Button("Force Re-run Setup") {
                    Task { @MainActor in
                        await ProNotificationCoordinator.shared.reconcile(
                            isProUnlocked: self.proEntitlementStore.isProUnlocked)
                    }
                }

                Button("Verify Subscription Persistence") {
                    self.persistenceTestResult = "Running…"
                    Task { @MainActor in
                        let result = await QuotaTransitionSubscriptions.shared.runPersistenceTest()
                        self.persistenceTestResult = result
                    }
                }

                if let result = self.persistenceTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                        .textSelection(.enabled)
                }
            }

            #if DEBUG
            // NSE invocation log was added in build 122 to diagnose the
            // mutable-content / staleness chain. Useful for developers; not
            // shown in RELEASE builds (TestFlight + App Store) — the storage
            // backing (`NSEInvocationLog` → `NSUbiquitousKeyValueStore`) is
            // still active so a future DEBUG build can read prior entries.
            Section("Recent NSE Invocations") {
                NSEInvocationLogSection(entries: self.nseEntries)
                HStack {
                    Button("Refresh") {
                        self.nseEntries = NSEInvocationLog.shared.loadAll()
                    }
                    .controlSize(.small)
                    Button("Clear") {
                        NSEInvocationLog.shared.clear()
                        self.nseEntries = []
                    }
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            #endif

            if let ts = self.diag.lastUpdated {
                Section {
                    Text("Last updated: \(ts.formatted(.dateTime))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .navigationTitle("Push Setup")
        .onAppear {
            self.nseEntries = NSEInvocationLog.shared.loadAll()
        }
    }

    @State private var nseEntries: [NSEInvocationEntry] = []

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.bold())
            Text(value)
                .font(.caption)
                .foregroundStyle(value.hasPrefix("✓") ? .green :
                    (value.hasPrefix("✗") ? .red : .secondary))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

/// Renders the NSE invocation log (newest first) so a developer can verify
/// end-to-end the warning push pipeline without reading device logs in
/// Console.app. Empty state hints the user how to populate it.
private struct NSEInvocationLogSection: View {
    let entries: [NSEInvocationEntry]

    var body: some View {
        if self.entries.isEmpty {
            Text("No NSE invocations recorded. Trigger a push from the Mac DEV menu, then tap Refresh.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(self.entries.reversed().enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.event.rawValue.uppercased())
                            .font(.caption.bold())
                            .foregroundStyle(self.color(for: entry.event))
                        Spacer()
                        Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    if let zone = entry.zoneName {
                        Text(zone)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.detail)
                        .font(.caption2)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func color(for event: NSEInvocationEvent) -> Color {
        switch event {
        case .ok: .green
        case .woke: .blue
        case .zoneNil, .fetchNil: .orange
        case .fetchError: .red
        }
    }
}
