import CodexBarSync
import SwiftUI

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
                            ProviderListHeaderRow(
                                snapshot: self.usageData.snapshot,
                                syncStatus: self.usageData.syncStatus,
                                showsProviderOrderButton: access.visibleGroups.count > 1,
                                refreshAction: {
                                    Task { await self.usageData.refresh() }
                                },
                                providerOrderAction: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        self.isReorderingProviders = true
                                    }
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
            if self.isReorderingProviders, access.visibleGroups.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            self.isReorderingProviders = false
                        }
                    } label: {
                        Label(String(localized: "Done"), systemImage: "checkmark")
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

private struct ProviderListHeaderRow: View {
    @Environment(\.quotaKitTheme) private var theme
    let snapshot: SyncedUsageSnapshot?
    let syncStatus: SyncStatus
    let showsProviderOrderButton: Bool
    let refreshAction: () -> Void
    let providerOrderAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SyncStatusChipView(
                placement: .header,
                isDemoMode: false,
                snapshot: self.snapshot,
                syncStatus: self.syncStatus,
                refreshAction: self.refreshAction)
                .layoutPriority(1)

            if self.showsProviderOrderButton {
                Button(action: self.providerOrderAction) {
                    Label(String(localized: "Provider order"), systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(self.theme.accent)
                        .background(self.theme.accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("provider-reorder-toggle")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            self.selectedProviderMark
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

    @ViewBuilder
    private var selectedProviderMark: some View {
        if let selectedGroup {
            ProviderBrandMark(
                providerID: selectedGroup.providerID,
                size: 18,
                tint: ProviderColorPalette.color(for: selectedGroup.providerID))
        } else {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.body.weight(.semibold))
                .foregroundStyle(self.theme.accent)
        }
    }

    private var selectedGroup: ProviderAccountGroup? {
        self.groups.first { $0.providerID == self.selectedProviderID } ?? self.groups.first
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
                Text(
                    "Drag providers into the order you want in the app. Widgets use this order when no provider is selected.")
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
            ProviderBrandMark(
                providerID: self.group.providerID,
                size: 18,
                tint: ProviderColorPalette.color(for: self.group.providerID))

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
