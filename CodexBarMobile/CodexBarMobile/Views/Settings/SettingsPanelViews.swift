import SwiftUI

struct QKSettingsToggleRow: View {
    @Environment(\.quotaKitTheme) private var theme
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    @Binding var isOn: Bool
    var accessibilityIdentifier: String?

    var body: some View {
        Toggle(isOn: self.$isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(self.theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(self.theme.textMuted)
                }
            }
        }
        .toggleStyle(.switch)
        .modifier(SettingsAccessibilityIdentifierModifier(identifier: self.accessibilityIdentifier))
    }
}

private struct SettingsAccessibilityIdentifierModifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

struct QKSettingsPickerRow<SelectionValue: Hashable>: View {
    @Environment(\.quotaKitTheme) private var theme
    let title: LocalizedStringResource
    @Binding var selection: SelectionValue
    let options: [(SelectionValue, String)]

    var body: some View {
        HStack {
            Text(self.title)
                .font(.body.weight(.medium))
                .foregroundStyle(self.theme.textPrimary)
            Spacer()
            Picker(self.title, selection: self.$selection) {
                ForEach(self.options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

struct UsageSettingsView: View {
    @Environment(\.quotaKitTheme) private var theme
    @AppStorage(MobileSettingsKeys.usageCostChartStyle) private var usageCostChartStyleRawValue = CostChartStyle.bars
        .rawValue
    @AppStorage(MobileSettingsKeys.showRemainingUsage) private var showRemainingUsage =
        UserDefaults.standard.string(forKey: MobileSettingsKeys.usagePercentDisplayMode) == UsagePercentDisplayMode.remaining.rawValue
    @AppStorage(MobileSettingsKeys.hidePersonalInfo) private var hidePersonalInfo = false
    @AppStorage(MobileSettingsKeys.hideQuotaWarningMarkers) private var hideQuotaWarningMarkers = false
    @AppStorage(MobileSettingsKeys.showProviderChangelogLinks) private var showProviderChangelogLinks = false
    @AppStorage(MobileSettingsKeys.usageCardDensity) private var usageCardDensityRaw =
        UsageCardDensity.comfortable.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                QKSectionHeader(title: "Usage")
                QKSurfaceCard {
                    QKSettingsToggleRow(
                        title: "Show remaining usage",
                        subtitle: "Display the quota you have left instead of the quota you have used on usage cards.",
                        isOn: self.$showRemainingUsage,
                        accessibilityIdentifier: "show-remaining-usage-toggle")
                        .padding(16)
                }

                QKSectionHeader(title: "Layout")
                QKSurfaceCard {
                    QKSettingsPickerRow(
                        title: "Card density",
                        selection: self.usageCardDensity,
                        options: UsageCardDensity.allCases.map { ($0, $0.title) })
                        .padding(16)
                }

                QKSectionHeader(
                    title: "Charts",
                    subtitle: "Press and hold on the chart to inspect the exact value for a given day.")
                QKSurfaceCard {
                    QKSettingsPickerRow(
                        title: "Chart Style",
                        selection: self.usageChartStyle,
                        options: CostChartStyle.allCases.map { ($0, $0.title) })
                        .padding(16)
                }

                QKSectionHeader(title: "Warnings & links")
                QKSurfaceCard {
                    VStack(spacing: 16) {
                        QKSettingsToggleRow(
                            title: "setting_hide_quota_markers_title",
                            subtitle: "setting_hide_quota_markers_subtitle",
                            isOn: self.$hideQuotaWarningMarkers,
                            accessibilityIdentifier: "hide-quota-warning-markers-toggle")
                        QKSettingsToggleRow(
                            title: "setting_show_changelog_links_title",
                            subtitle: "setting_show_changelog_links_subtitle",
                            isOn: self.$showProviderChangelogLinks,
                            accessibilityIdentifier: "show-provider-changelog-links-toggle")
                    }
                    .padding(16)
                }

                QKSectionHeader(title: "Privacy")
                QKSurfaceCard {
                    QKSettingsToggleRow(
                        title: "Hide personal information",
                        subtitle: "Obscure email addresses in the Usage page.",
                        isOn: self.$hidePersonalInfo)
                        .padding(16)
                }
            }
            .padding(20)
        }
        .background(self.theme.canvas)
        .navigationTitle("Usage Setting")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var usageChartStyle: Binding<CostChartStyle> {
        Binding(
            get: { CostChartStyle(rawValue: self.usageCostChartStyleRawValue) ?? .bars },
            set: { self.usageCostChartStyleRawValue = $0.rawValue })
    }

    private var usageCardDensity: Binding<UsageCardDensity> {
        Binding(
            get: { UsageCardDensity(rawValue: self.usageCardDensityRaw) ?? .comfortable },
            set: { self.usageCardDensityRaw = $0.rawValue })
    }
}

struct CostSettingsView: View {
    @Environment(\.quotaKitTheme) private var theme
    let isDemoMode: Bool

    @AppStorage(MobileSettingsKeys.dashboardCostChartStyle) private var dashboardCostChartStyleRawValue =
        CostChartStyle.line.rawValue
    @AppStorage(MobileSettingsKeys.openCostByDefault) private var openCostByDefault = false
    @Environment(ProEntitlementStore.self) private var proEntitlementStore
    @Environment(\.modelContext) private var modelContext
    @AppStorage(MobileSettingsKeys.cwlEnabled) private var cwlEnabled = false
    @AppStorage(MobileSettingsKeys.cwlWindowDays) private var cwlWindowDays = 30
    @State private var showClearLedgerConfirm = false

    private var isCostHistoryUnlocked: Bool {
        ProFeatureAccess.isUnlocked(
            .usageHistory,
            isDemoMode: self.isDemoMode,
            isProUnlocked: self.proEntitlementStore.isProUnlocked)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                QKSectionHeader(title: "Cost History")
                QKSurfaceCard {
                    VStack(alignment: .leading, spacing: 16) {
                        QKSettingsToggleRow(
                            title: "Local cost history",
                            subtitle: "Keep a longer cost history on this iPhone, independent of the Mac's window. Builds up as the Mac keeps syncing.",
                            isOn: self.$cwlEnabled)
                            .disabled(!self.isCostHistoryUnlocked)

                        if self.cwlEnabled, self.isCostHistoryUnlocked {
                            QKSettingsPickerRow(
                                title: "History window",
                                selection: self.$cwlWindowDays,
                                options: [(7, "7 Days"), (30, "30 Days"), (90, "90 Days"), (365, "365 Days")])
                        }

                        if !self.isCostHistoryUnlocked {
                            ProFeatureLockedCard(
                                store: self.proEntitlementStore,
                                feature: .usageHistory,
                                message: String(localized: "Unlock QuotaKit Pro to keep extended local cost history and choose longer history windows on this iPhone."))
                        }
                    }
                    .padding(16)
                }

                if let diagnostics = self.ledgerDiagnostics, diagnostics.rowCount > 0 {
                    QKSectionHeader(title: "Local Ledger")
                    QKSurfaceCard {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Days collected", value: "\(diagnostics.dayCount)")
                            LabeledContent("Providers", value: "\(diagnostics.providerCount)")
                            if diagnostics.deviceCount > 1 {
                                LabeledContent("Devices", value: "\(diagnostics.deviceCount)")
                            }
                            if let earliest = diagnostics.earliestDayKey {
                                LabeledContent("Since", value: earliest)
                            }
                        }
                        .padding(16)
                    }

                    Button(role: .destructive) {
                        self.showClearLedgerConfirm = true
                    } label: {
                        Text("Clear local cost history")
                            .frame(maxWidth: .infinity)
                    }
                    .confirmationDialog(
                        Text("Clear local cost history?"),
                        isPresented: self.$showClearLedgerConfirm,
                        titleVisibility: .visible)
                    {
                        Button("Clear", role: .destructive) {
                            try? CostLedgerService.clearAll(in: self.modelContext)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Deletes the on-device cost ledger only. Synced data is unaffected; history rebuilds as the Mac keeps syncing.")
                    }
                }

                QKSectionHeader(
                    title: "Charts",
                    subtitle: "Press and hold on the chart to inspect the exact value for a given day.")
                QKSurfaceCard {
                    QKSettingsPickerRow(
                        title: "Chart Style",
                        selection: self.dashboardChartStyle,
                        options: CostChartStyle.allCases.map { ($0, $0.title) })
                        .padding(16)
                }

                QKSurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        QKSettingsToggleRow(
                            title: "Open Cost by default",
                            subtitle: "Launch the app on the Cost tab next time.",
                            isOn: self.$openCostByDefault)
                            .disabled(!self.isCostHistoryUnlocked)
                        if !self.isCostHistoryUnlocked {
                            Text("QuotaKit Pro is required to launch directly into the Cost dashboard.")
                                .font(.caption)
                                .foregroundStyle(self.theme.textMuted)
                        }
                    }
                    .padding(16)
                }
            }
            .padding(20)
        }
        .background(self.theme.canvas)
        .navigationTitle("Cost Setting")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: self.cwlEnabled) { _, isOn in
            guard isOn else { return }
            do {
                try CostLedgerService.seedFromExistingBlobs(in: self.modelContext)
            } catch {
                self.cwlEnabled = false
            }
        }
    }

    private var ledgerDiagnostics: CostLedgerDiagnostics? {
        try? CostLedgerService.diagnostics(in: self.modelContext)
    }

    private var dashboardChartStyle: Binding<CostChartStyle> {
        Binding(
            get: { CostChartStyle(rawValue: self.dashboardCostChartStyleRawValue) ?? .line },
            set: { self.dashboardCostChartStyleRawValue = $0.rawValue })
    }
}
