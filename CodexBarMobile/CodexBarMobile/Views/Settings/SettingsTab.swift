import SwiftUI

struct SettingsTab: View {
    let usageData: SyncedUsageData
    let isDemoMode: Bool
    @Environment(\.quotaKitTheme) private var theme
    @Environment(ProEntitlementStore.self) private var proEntitlementStore
    @Environment(RemoteConfigStore.self) private var remoteConfigStore
    @AppStorage(MobileSettingsKeys.appearanceMode) private var appearanceModeRaw =
        AppearanceMode.dark.rawValue
    @State private var showingSetupGuide = false

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: self.appearanceModeRaw) ?? .dark },
            set: { self.appearanceModeRaw = $0.rawValue })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    QKSectionHeader(title: "Appearance")
                    QKSurfaceCard {
                        QKSettingsPickerRow(
                            title: "Theme",
                            selection: self.appearanceMode,
                            options: AppearanceMode.allCases.map { ($0, $0.title) })
                            .padding(16)
                    }

                    QKSurfaceCard {
                        QuotaKitProSettingsView(store: self.proEntitlementStore)
                            .padding(16)
                    }

                    if let announcement = self.remoteConfigStore.activeAnnouncement {
                        QKSectionHeader(title: "Announcement")
                        QKSurfaceCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(announcement.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(self.theme.textPrimary)
                                Text(announcement.body)
                                    .font(.caption)
                                    .foregroundStyle(self.theme.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                        }
                    }

                    QKSectionHeader(title: "Setup")
                    QKSurfaceCard {
                        VStack(spacing: 0) {
                            Button {
                                self.showingSetupGuide = true
                            } label: {
                                SettingSummaryRow(
                                    title: "Setup Guide",
                                    symbolName: "sparkles",
                                    summary: String(localized: "Walk through how QuotaKit syncs from Mac to iPhone"))
                            }
                            .buttonStyle(.plain)

                            Divider().opacity(0.3)

                            NavigationLink {
                                AboutSyncDetailView(usageData: self.usageData)
                            } label: {
                                SettingSummaryRow(
                                    title: "About & Sync",
                                    symbolName: "iphone.and.arrow.forward",
                                    summary: "\(String(localized: "iPhone")) \(self.mobileVersionSummary) · \(String(localized: "Mac")) \(self.macVersionSummary)")
                            }

                            Divider().opacity(0.3)

                            NavigationLink {
                                ReleaseNotesView()
                            } label: {
                                SettingSummaryRow(
                                    title: "Release Notes",
                                    symbolName: "text.document",
                                    summary: String(localized: "Latest updates and version history"))
                            }
                        }
                        .padding(16)
                    }

                    QKSectionHeader(title: "Pages")
                    QKSurfaceCard {
                        VStack(spacing: 0) {
                            NavigationLink {
                                UsageSettingsView()
                            } label: {
                                SettingSummaryRow(
                                    title: "Usage Setting",
                                    symbolName: "chart.bar.fill",
                                    summary: String(localized: "Configure the Usage page"))
                            }

                            Divider().opacity(0.3)

                            NavigationLink {
                                CostSettingsView(isDemoMode: self.isDemoMode)
                            } label: {
                                SettingSummaryRow(
                                    title: "Cost Setting",
                                    symbolName: "dollarsign.circle.fill",
                                    summary: String(localized: "Configure the Cost page"))
                            }
                        }
                        .padding(16)
                    }

                    QKSectionHeader(title: "Company")
                    QKSurfaceCard {
                        Link(destination: URL(string: "https://github.com/ColumbusLabs")!) {
                            SettingSummaryRow(
                                title: "Columbus Labs",
                                symbolName: "building.2.fill",
                                summary: "github.com/ColumbusLabs")
                        }
                        .padding(16)
                    }

                    #if DEBUG
                    QKSectionHeader(title: "Developer")
                    QKSurfaceCard {
                        NavigationLink {
                            DeveloperToolsView(usageData: self.usageData)
                        } label: {
                            SettingSummaryRow(
                                title: "Developer Tools",
                                symbolName: "wrench.and.screwdriver",
                                summary: String(localized: "Sync inspector, push diagnostic, and more"))
                        }
                        .padding(16)
                    }
                    #endif

                    if MockProviderDetector.hasAnyMock(in: self.usageData.snapshot) {
                        QKSectionHeader(title: "Diagnostics")
                        QKSurfaceCard {
                            QKStatusChip(
                                text: String(
                                    format: String(localized: "Mock · %lld synthetic providers active"),
                                    MockProviderDetector.mockCount(in: self.usageData.snapshot)),
                                style: .mock,
                                systemImage: "testtube.2")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                    }

                    QKSectionHeader(title: "Open Source")
                    QKSurfaceCard {
                        VStack(spacing: 0) {
                            Link(destination: URL(string: "https://github.com/ColumbusLabs/QuotaKit")!) {
                                SettingSummaryRow(
                                    title: "ColumbusLabs/QuotaKit",
                                    symbolName: "chevron.left.forwardslash.chevron.right",
                                    summary: "Official QuotaKit repository")
                            }

                            Divider().opacity(0.3)

                            Link(destination: URL(string: "https://github.com/steipete/CodexBar")!) {
                                SettingSummaryRow(
                                    title: "steipete/CodexBar",
                                    symbolName: "arrow.triangle.branch",
                                    summary: "Original Mac app — MIT License")
                            }
                        }
                        .padding(16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(self.theme.canvas)
            .navigationTitle("Setting")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: self.$showingSetupGuide) {
                NavigationStack {
                    OnboardingView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    self.showingSetupGuide = false
                                }
                                .fontWeight(.semibold)
                            }
                        }
                }
            }
        }
    }

    private var mobileVersionSummary: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        return version
    }

    private var macVersionSummary: String {
        guard let snapshot = self.usageData.snapshot else { return String(localized: "Not synced") }
        return snapshot.appVersion ?? String(localized: "Unknown")
    }
}

struct SettingSummaryRow: View {
    @Environment(\.quotaKitTheme) private var theme
    let title: LocalizedStringResource
    let symbolName: String
    let summary: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: self.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(self.theme.accent)
                .frame(width: 32, height: 32)
                .background(self.theme.surfaceElevated, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(self.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(self.theme.textPrimary)

                Text(self.summary)
                    .font(.caption)
                    .foregroundStyle(self.theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
