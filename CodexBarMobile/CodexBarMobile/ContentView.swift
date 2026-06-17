import CodexBarSync
import SwiftUI
import UIKit

private enum MobileRootTab: Hashable {
    case usage
    case cost
    case settings
}

struct ContentView: View {
    let usageData: SyncedUsageData
    @State private var isDemoMode = false
    @State private var selectedTab: MobileRootTab
    @AppStorage("onboardingSeenVersion") private var onboardingSeenVersion = ""

    init(usageData: SyncedUsageData) {
        self.usageData = usageData
        _selectedTab = State(initialValue: UserDefaults.standard.bool(forKey: MobileSettingsKeys.openCostByDefault) ? .cost : .usage)
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var shouldShowOnboarding: Bool {
        self.onboardingSeenVersion != self.currentVersion
    }

    private var hasSyncedData: Bool {
        self.usageData.snapshot != nil
    }

    var body: some View {
        Group {
            if !self.hasSyncedData && !self.isDemoMode {
                NavigationStack {
                    OnboardingView(onDemo: {
                        self.onboardingSeenVersion = self.currentVersion
                        self.isDemoMode = true
                    })
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else {
                TabView(selection: self.$selectedTab) {
                    UsageTab(usageData: self.usageData, isDemoMode: self.$isDemoMode)
                        .tag(MobileRootTab.usage)
                        .tabItem {
                            Label("Usage", systemImage: "chart.bar.fill")
                        }

                    CostTab(usageData: self.usageData, isDemoMode: self.$isDemoMode)
                        .tag(MobileRootTab.cost)
                        .tabItem {
                            Label("Cost", systemImage: "dollarsign.circle.fill")
                        }

                    SettingsTab(
                        usageData: self.usageData,
                        isDemoMode: self.isDemoMode)
                        .tag(MobileRootTab.settings)
                        .tabItem {
                            Label("Setting", systemImage: "gearshape")
                        }
                }
                .modifier(TabBarMinimizeModifier())
                .fullScreenCover(isPresented: .init(
                    get: { self.hasSyncedData && self.shouldShowOnboarding },
                    set: { if !$0 { self.onboardingSeenVersion = self.currentVersion } }))
                {
                    OnboardingSheet(onDismiss: {
                        self.onboardingSeenVersion = self.currentVersion
                    }, onDemo: {
                        self.onboardingSeenVersion = self.currentVersion
                        self.isDemoMode = true
                    })
                }
            }
        }
    }
}

private struct OnboardingSheet: View {
    let onDismiss: () -> Void
    let onDemo: () -> Void

    var body: some View {
        NavigationStack {
            OnboardingView(onDemo: self.onDemo)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            self.onDismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }
}

/// Keeps the tab bar always visible (no auto-minimize on scroll).
private struct TabBarMinimizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.never)
        } else {
            content
        }
    }
}

// MARK: - Usage Tab

private struct UsageTab: View {
    let usageData: SyncedUsageData
    @Binding var isDemoMode: Bool

    private var displaySnapshot: SyncedUsageSnapshot? {
        if self.isDemoMode {
            return PreviewData.sampleSnapshot
        }
        return self.usageData.snapshot
    }

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = self.displaySnapshot {
                    if MockProviderDetector.filteredProviders(from: snapshot).isEmpty {
                        EmptyStateView(
                            title: "No Providers Enabled",
                            message: "Enable providers in QuotaKit on your Mac to see usage data here.",
                            systemImage: "slider.horizontal.3")
                    } else {
                        ProviderListView(
                            snapshot: snapshot,
                            usageData: self.usageData,
                            isDemoMode: self.isDemoMode)
                    }
                } else {
                    OnboardingView(onDemo: { self.isDemoMode = true })
                }
            }
            .navigationTitle(self.isDemoMode || self.displaySnapshot == nil ? "" : String(localized: "QuotaKit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if self.isDemoMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            self.isDemoMode = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Exit demo preview"))
                    }
                }
            }
        }
    }
}

// MARK: - Provider List

struct ProviderListView: View {
    let snapshot: SyncedUsageSnapshot
    let usageData: SyncedUsageData
    let isDemoMode: Bool
    @Environment(\.quotaKitTheme) private var theme
    @Environment(ProEntitlementStore.self) private var proEntitlementStore
    @Environment(RemoteConfigStore.self) private var remoteConfigStore
    @AppStorage(MobileSettingsKeys.freeSelectedProviderID) private var freeSelectedProviderID = ""
    @AppStorage(MobileSettingsKeys.freeSelectedProviderLockedUntil) private var freeSelectedProviderLockedUntil = 0.0
    /// Local per-launch suppression of linkage prompts the user clicked
    /// "Keep separate" on. Persisted only across the current session —
    /// next launch re-evaluates so a user who reconsidered can confirm.
    /// Long-term persistence isn't needed since the candidate goes away
    /// the moment the legacy Mac upgrades (Research/019 §9 logic).
    @State private var dismissedCandidateKeys = Set<String>()
    /// Filters the Usage provider list by name / ID. Helps when many
    /// providers are synced (20+) and scrolling to find one is tedious.
    @State private var searchText = ""
    @State private var providerOrderIDs = QuotaKitWidgetProviderPreferencesStore.loadProviderOrderIDs()
    @State private var widgetProviderID = QuotaKitWidgetProviderPreferencesStore.loadSelectedProviderID() ?? ""
    @State private var isReorderingProviders = false

    var body: some View {
        // Drop extinct mock zombies before any rendering so duplicate
        // cards (OLD vs NEW mock-injector designs) don't appear on the
        // Usage list. iOS 1.5.2+: see `MockProviderDetector.extinctMockProviderIDs`.
        let liveProviders = MockProviderDetector.filteredProviders(from: self.snapshot)
        // Compute linkage candidates ONCE per render. The detector handles
        // ambiguity rules (skips multi-account-named scenarios where we
        // can't tell which named card a legacy entry belongs to).
        let allCandidates = MultiAccountLinkageDetector.candidates(
            among: liveProviders,
            appVersionForProvider: { provider in
                // Find which device-snapshot this provider came from to
                // report its QuotaKit version in the §9 hint. Falls back
                // to the merged snapshot's appVersion (the highest across
                // devices) — that's at least the "ceiling" of what other
                // Mac versions could be in play.
                let devices = self.usageData.deviceSnapshots
                if let device = devices.first(where: { snap in
                    snap.providers.contains { $0.cardIdentityKey == provider.cardIdentityKey }
                }) {
                    return device.appVersion
                }
                return nil
            })
        let candidatesByLegacyKey = Dictionary(
            uniqueKeysWithValues: allCandidates.map { ($0.legacy.cardIdentityKey, $0) })
        // Live linkages — used to expose an Unmerge context menu on cards
        // that originated from a confirmed merge group.
        let activeLinkagesByProviderID = Dictionary(
            grouping: self.usageData.providerLinkages.filter { !$0.unmerge },
            by: \.providerID)
        // Phase G — group by providerID so multi-account providers
        // (Codex × 3, OpenAI × 2 admins, Claude × 2 sessions, etc.) show
        // as ONE row in the Usage list instead of N. Tapping the row
        // navigates to ProviderDetailView which renders the segmented
        // account tab bar at the top, matching Mac UX. Cross-Mac
        // same-account merging already happened in `mergeSnapshots`
        // upstream of this grouping, so each group's accounts are all
        // distinct (no duplicates within).
        let groups = QuotaKitWidgetProviderPreferencesStore.orderedItems(
            liveProviders.groupedByProvider(),
            preferences: self.providerPreferences,
            providerID: \.providerID,
            providerName: \.providerName)
        let access = ProviderAccessGate.resolve(
            groups: groups,
            isDemoMode: self.isDemoMode,
            isProUnlocked: self.proEntitlementStore.isProUnlocked,
            selectedProviderID: self.freeSelectedProviderID.isEmpty ? nil : self.freeSelectedProviderID,
            isRemotelyDisabled: self.remoteConfigStore.isDisabled(.unlimitedProviders))
        let advancedMergeUnlocked = ProFeatureAccess.isUnlocked(
            .advancedMergeViews,
            isDemoMode: self.isDemoMode,
            isProUnlocked: self.proEntitlementStore.isProUnlocked,
            isRemotelyDisabled: self.remoteConfigStore.isDisabled(.advancedMergeViews))
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredGroups = query.isEmpty ? access.visibleGroups : access.visibleGroups.filter { group in
            group.representative.providerName.localizedCaseInsensitiveContains(query)
                || group.providerID.localizedCaseInsensitiveContains(query)
        }
        return Group {
            if self.isReorderingProviders, access.visibleGroups.count > 1 {
                ProviderOrderModeView(
                    groups: filteredGroups,
                    availableGroups: access.visibleGroups,
                    selectedWidgetProviderID: self.resolvedWidgetProviderID(availableGroups: access.visibleGroups),
                    widgetProviderSelection: self.widgetProviderBinding(availableGroups: access.visibleGroups),
                    onMove: { source, destination in
                        self.moveProviderOrder(
                            from: source,
                            to: destination,
                            visibleGroups: filteredGroups,
                            allGroups: access.visibleGroups)
                    })
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if self.isDemoMode {
                            DemoPreviewBanner(snapshot: self.snapshot)
                        } else {
                            SyncStatusChipView(
                                placement: .header,
                                isDemoMode: false,
                                snapshot: self.usageData.snapshot,
                                syncStatus: self.usageData.syncStatus,
                                refreshAction: {
                                    Task { await self.usageData.refresh() }
                                })
                        }

                        if access.isLimited {
                            FreeProviderSelectorView(
                                groups: groups,
                                selectedProviderID: self.$freeSelectedProviderID,
                                selectedProviderLockedUntil: self.$freeSelectedProviderLockedUntil,
                                effectiveSelectedProviderID: access.effectiveSelectedProviderID)
                        }

                        if access.visibleGroups.count > 1 {
                            WidgetProviderPickerCard(
                                groups: access.visibleGroups,
                                selectedProviderID: self.widgetProviderBinding(
                                    availableGroups: access.visibleGroups))
                        }

                        ForEach(filteredGroups) { group in
                            // Within-group linkage candidate: surface on the
                            // group row if ANY account in the group has one
                            // (typically the legacy/missing-identity card).
                            // User confirms once, the underlying union-find
                            // collapses the candidate pair into one snapshot,
                            // and on next render the group shrinks by one.
                            let candidate: MultiAccountLinkageCandidate? = {
                                for account in group.accounts {
                                    if let c = candidatesByLegacyKey[account.cardIdentityKey],
                                       !self.dismissedCandidateKeys.contains(c.hashKey)
                                    {
                                        return c
                                    }
                                }
                                return nil
                            }()
                            let activeLinkage = activeLinkagesByProviderID[group.providerID]?.first
                            NavigationLink {
                                ProviderDetailView(
                                    group: group,
                                    isDemoMode: self.isDemoMode)
                            } label: {
                                ProviderUsageView(
                                    provider: group.representative,
                                    duplicateOrdinal: nil,
                                    accountCount: group.hasMultipleAccounts ? group.accounts.count : nil,
                                    linkageCandidate: advancedMergeUnlocked ? candidate : nil,
                                    activeLinkage: advancedMergeUnlocked ? activeLinkage : nil,
                                    showsSyntheticDataIndicator: !self.isDemoMode,
                                    onConfirmMerge: advancedMergeUnlocked ? { c in
                                        Task { @MainActor in
                                            await self.usageData.confirmLinkage(
                                                providerID: c.named.providerID,
                                                linkedIdentifiers: c.linkedIdentifiers)
                                        }
                                    } : nil,
                                    onDismissMergeCandidate: advancedMergeUnlocked ? { c in
                                        self.dismissedCandidateKeys.insert(c.hashKey)
                                    } : nil,
                                    onRevokeLinkage: advancedMergeUnlocked ? { linkage in
                                        Task { @MainActor in
                                            await self.usageData.revokeLinkage(
                                                providerID: linkage.providerID,
                                                linkedIdentifiers: linkage.linkedIdentifiers)
                                        }
                                    } : nil)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("provider-group-\(group.providerID)")
                        }

                        if access.isLimited, access.lockedCount > 0 {
                            QuotaKitProLockedSummaryView(
                                store: self.proEntitlementStore,
                                lockedProviderCount: access.lockedCount)
                        }

                        if filteredGroups.isEmpty {
                            EmptyStateView(
                                title: "No matching providers",
                                message: "No provider matches your search. Try a different name.",
                                systemImage: "magnifyingglass")
                                .padding(.vertical, 32)
                        }

                        SyncStatusChipView(
                            placement: .footer,
                            isDemoMode: self.isDemoMode,
                            snapshot: self.usageData.snapshot,
                            syncStatus: self.usageData.syncStatus,
                            refreshAction: self.isDemoMode ? nil : {
                                Task { await self.usageData.refresh() }
                            })
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(self.theme.canvas)
        .refreshable {
            await self.usageData.refresh()
        }
        .modifier(SoftScrollEdgeModifier())
        .searchable(
            text: self.$searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Search providers"))
        .toolbar {
            if access.visibleGroups.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            self.isReorderingProviders.toggle()
                        }
                    } label: {
                        Label(
                            self.isReorderingProviders ? String(localized: "Done") : String(localized: "Reorder"),
                            systemImage: self.isReorderingProviders ? "checkmark" : "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("provider-reorder-toggle")
                }
            }
        }
    }

    private var providerPreferences: QuotaKitWidgetProviderPreferences {
        QuotaKitWidgetProviderPreferences(
            providerOrderIDs: self.providerOrderIDs,
            selectedProviderID: self.widgetProviderID.isEmpty ? nil : self.widgetProviderID)
    }

    private func widgetProviderBinding(availableGroups: [ProviderAccountGroup]) -> Binding<String> {
        Binding(
            get: { self.resolvedWidgetProviderID(availableGroups: availableGroups) ?? "" },
            set: { self.saveWidgetProviderID($0.isEmpty ? nil : $0) })
    }

    private func resolvedWidgetProviderID(availableGroups: [ProviderAccountGroup]) -> String? {
        QuotaKitWidgetProviderPreferencesStore.selectedProviderID(
            availableProviderIDs: availableGroups.map(\.providerID),
            preferences: self.providerPreferences)
    }

    private func saveWidgetProviderID(_ providerID: String?) {
        let trimmed = providerID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed?.isEmpty == false) ? trimmed : nil
        guard normalized != (self.widgetProviderID.isEmpty ? nil : self.widgetProviderID) else {
            return
        }

        self.widgetProviderID = normalized ?? ""
        QuotaKitWidgetProviderPreferencesStore.saveSelectedProviderID(normalized)
        WidgetTimelineRefresher.reloadAllTimelines()
    }

    private func saveProviderOrder(_ providerIDs: [String]) {
        let sanitized = QuotaKitWidgetProviderPreferencesStore.sanitizedProviderIDs(providerIDs)
        guard sanitized != self.providerOrderIDs else { return }
        self.providerOrderIDs = sanitized
        QuotaKitWidgetProviderPreferencesStore.saveProviderOrderIDs(sanitized)
        WidgetTimelineRefresher.reloadAllTimelines()
    }

    private func moveProviderOrder(
        from source: IndexSet,
        to destination: Int,
        visibleGroups: [ProviderAccountGroup],
        allGroups: [ProviderAccountGroup])
    {
        var visibleIDs = visibleGroups.map(\.providerID)
        visibleIDs.move(fromOffsets: source, toOffset: destination)

        let visibleSet = Set(visibleGroups.map(\.providerID))
        var replacementIndex = 0
        let orderedIDs = allGroups.map { group in
            guard visibleSet.contains(group.providerID),
                  replacementIndex < visibleIDs.count
            else {
                return group.providerID
            }
            defer { replacementIndex += 1 }
            return visibleIDs[replacementIndex]
        }
        self.saveProviderOrder(orderedIDs)
    }
}

private struct WidgetProviderPickerCard: View {
    let groups: [ProviderAccountGroup]
    @Binding var selectedProviderID: String

    var body: some View {
        QKSurfaceCard {
            WidgetProviderPickerContent(
                groups: self.groups,
                selectedProviderID: self.$selectedProviderID)
                .padding(16)
        }
        .accessibilityIdentifier("widget-provider-picker-card")
    }
}

private struct WidgetProviderPickerContent: View {
    @Environment(\.quotaKitTheme) private var theme
    let groups: [ProviderAccountGroup]
    @Binding var selectedProviderID: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.body.weight(.semibold))
                .foregroundStyle(self.theme.accent)
                .frame(width: 32, height: 32)
                .background(self.theme.surfaceElevated, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Widget provider")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(self.theme.textPrimary)
                Text("Choose which provider appears in QuotaKit widgets.")
                    .font(.caption)
                    .foregroundStyle(self.theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Widget provider", selection: self.$selectedProviderID) {
                ForEach(self.groups) { group in
                    Text(group.providerName).tag(group.providerID)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("widget-provider-picker")
        }
    }
}

private struct ProviderOrderModeView: View {
    @Environment(\.quotaKitTheme) private var theme
    let groups: [ProviderAccountGroup]
    let availableGroups: [ProviderAccountGroup]
    let selectedWidgetProviderID: String?
    @Binding var widgetProviderSelection: String
    let onMove: (IndexSet, Int) -> Void

    var body: some View {
        List {
            Section {
                WidgetProviderPickerContent(
                    groups: self.availableGroups,
                    selectedProviderID: self.$widgetProviderSelection)
            }

            Section {
                if self.groups.isEmpty {
                    Text("No matching providers")
                        .foregroundStyle(self.theme.textMuted)
                } else {
                    ForEach(self.groups) { group in
                        ProviderOrderRow(
                            group: group,
                            isWidgetProvider: group.providerID == self.selectedWidgetProviderID)
                    }
                    .onMove(perform: self.onMove)
                }
            } header: {
                Text("Provider order")
            } footer: {
                Text("Drag providers into the order you want in the app. Widgets use this order when no provider is selected.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        .background(self.theme.canvas)
        .accessibilityIdentifier("provider-order-list")
    }
}

private struct ProviderOrderRow: View {
    @Environment(\.quotaKitTheme) private var theme
    let group: ProviderAccountGroup
    let isWidgetProvider: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(ProviderColorPalette.color(for: self.group.providerID))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.group.providerName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(self.theme.textPrimary)
                if self.group.hasMultipleAccounts {
                    Text(
                        String(
                            format: String(localized: "%lld accounts"),
                            Int64(self.group.accounts.count)))
                        .font(.caption)
                        .foregroundStyle(self.theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if self.isWidgetProvider {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(self.theme.accent)
                    .accessibilityLabel(Text("Widget provider"))
            }
        }
        .accessibilityIdentifier("provider-order-row-\(self.group.providerID)")
    }
}

/// Applies `.scrollEdgeEffectStyle(.soft)` on iOS 26+, no-op on older systems.
struct SoftScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

// MARK: - Setting Tab

private struct SettingsTab: View {
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

private struct SettingSummaryRow: View {
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

private struct AboutSyncDetailView: View {
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
                Text("Public Columbus Labs configuration for safe OTA guardrails. It cannot change app code or access provider credentials.")
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
                            Text("Your Mac is using legacy sync. Open the setup link on your Mac to install the current QuotaKit build and enable CloudKit multi-device sync.")
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
        case .synced(let lastConfirmedSync):
            lastConfirmedSync
        case .syncing, .error:
            self.usageData.snapshot?.syncTimestamp
        case .noData, .incompatibleData:
            nil
        }
    }

    private func syncStatusDetail(now: Date) -> String? {
        switch self.usageData.syncStatus {
        case .synced(let lastConfirmedSync):
            return SyncFreshnessFormatter.lastSyncedText(
                since: lastConfirmedSync,
                now: now)
        case .syncing:
            return SyncFreshnessFormatter.refreshingText(
                lastConfirmedSync: self.usageData.snapshot?.syncTimestamp,
                now: now)
        case .noData: return String(localized: "Waiting for Mac to push data")
        case .incompatibleData: return String(localized: "Please update QuotaKit on Mac")
        case .error:
            return SyncFreshnessFormatter.refreshFailedText(
                lastConfirmedSync: self.usageData.snapshot?.syncTimestamp,
                now: now)
        }
    }
}

// MARK: - Raw Sync Data (Developer Debug View)

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
            LabeledContent("Sync Time", value: self.device.syncTimestamp.formatted(date: .abbreviated, time: .shortened))
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
                        Text("(no email)", comment: "Raw Sync Data row subtitle when provider has no account email (e.g. Claude / Ollama / Copilot)")
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
                            format: String(localized: "$%.2f / 30d", comment: "Raw Sync Data row trailing label — 30-day cost"),
                            cost.last30DaysCostUSD ?? 0))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(
                            format: String(localized: "$%.2f / today", comment: "Raw Sync Data row trailing label — today's cost"),
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
                LabeledContent("Last Updated", value: self.provider.lastUpdated.formatted(date: .abbreviated, time: .shortened))
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
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
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

    private func formatTokens(_ value: Int) -> String { CostFormatting.tokens(value) }
}

// MARK: - Developer Tools (container listing all dev tools)

private struct DeveloperToolsView: View {
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

// MARK: - Push Setup Diagnostic View

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
        if entries.isEmpty {
            Text("No NSE invocations recorded. Trigger a push from the Mac DEV menu, then tap Refresh.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(entries.reversed().enumerated()), id: \.offset) { _, entry in
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

// MARK: - Previews

#Preview("With Data") {
    ContentView(usageData: PreviewData.makeSyncedUsageData())
        .environment(ProEntitlementStore.preview(state: .locked))
        .environment(RemoteConfigStore())
        .quotaKitThemed()
}

#Preview("Empty State") {
    ContentView(usageData: PreviewData.makeEmptyUsageData())
        .environment(ProEntitlementStore.preview(state: .locked))
        .environment(RemoteConfigStore())
        .quotaKitThemed()
}
