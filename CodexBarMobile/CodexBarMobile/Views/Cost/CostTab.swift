import CodexBarSync
import SwiftData
import SwiftUI

struct CostTab: View {
    let usageData: SyncedUsageData
    @Binding var isDemoMode: Bool
    @Environment(ProEntitlementStore.self) private var proEntitlementStore
    @Environment(RemoteConfigStore.self) private var remoteConfigStore
    @State private var showShareSheet = false

    // Round 6 / P4b — Cost Window Ledger dispatch. When `cwlEnabled` and not
    // in demo mode, the dashboard reads the ledger (re-windowed by
    // `cwlWindowDays`) instead of the blob path. Both default to the historical
    // behavior (OFF / 30d) so untouched users are unaffected.
    @Environment(\.modelContext) private var modelContext
    @AppStorage(MobileSettingsKeys.cwlEnabled) private var cwlEnabled = false
    @AppStorage(MobileSettingsKeys.cwlWindowDays) private var cwlWindowDays = 30

    private var displaySnapshot: SyncedUsageSnapshot? {
        if self.isDemoMode {
            return PreviewData.sampleSnapshot
        }
        return self.usageData.snapshot
    }

    /// Memo cache for `resolvedInsights()`. `CostDashboardInsights.init` is
    /// O(providers × daily × breakdowns), and the CWL path adds a SwiftData
    /// ledger fetch + re-aggregation on the main thread — the old computed
    /// property re-ran all of that 2–3× per body evaluation (content +
    /// toolbar + share sheet) and again on every unrelated state change.
    /// Cached with the same synchronous-resolve + `.onChange(initial:)`
    /// store pattern as `UtilizationHistoryView` so the first frame still
    /// renders with data (UI-test contract) while repeat renders hit the
    /// cache. `cachedInsights` may legitimately be nil (no display data);
    /// `cachedInsightsKey` alone decides cache validity.
    @State private var cachedInsightsKey = ""
    @State private var cachedInsights: CostDashboardInsights?

    /// The expensive aggregation. Callers go through `resolvedInsights()`.
    private func computeInsights() -> CostDashboardInsights? {
        guard let snapshot = self.displaySnapshot else { return nil }
        let insights
            // CWL path only outside demo mode (demo uses a synthetic snapshot with
            // no ledger). `try?` falls back to the blob path on any ledger error.
            = if self.cwlEnabled,
            !self.isDemoMode,
            let aggregation = try? CostLedgerService.aggregate(
                windowDays: self.cwlWindowDays, in: self.modelContext)
        {
            CostDashboardInsights.fromLedger(
                aggregation: aggregation, snapshot: snapshot)
        } else {
            CostDashboardInsights(snapshot: snapshot)
        }
        return insights.hasDisplayData ? insights : nil
    }

    /// Inputs that can change what `computeInsights()` returns:
    /// - demo mode renders a static sample snapshot (snapshot identity is
    ///   irrelevant while it's on),
    /// - `SnapshotIdentityKey` covers provider set + data freshness (the
    ///   ledger is written in lockstep with snapshot publication inside
    ///   `applyFullFetchResults`, so it needs no separate key component),
    /// - the CWL toggle + window change the aggregation source,
    /// - `todayKey` flips the "Today" totals at midnight.
    static func insightsCacheKey(
        isDemoMode: Bool,
        snapshotKey: SnapshotIdentityKey?,
        cwlEnabled: Bool,
        cwlWindowDays: Int,
        todayKey: String) -> String
    {
        CostInsightsCacheKey.make(
            isDemoMode: isDemoMode,
            snapshotKey: snapshotKey,
            cwlEnabled: cwlEnabled,
            cwlWindowDays: cwlWindowDays,
            todayKey: todayKey)
    }

    private var insightsCacheKey: String {
        Self.insightsCacheKey(
            isDemoMode: self.isDemoMode,
            snapshotKey: self.usageData.snapshotIdentityKey,
            cwlEnabled: self.cwlEnabled,
            cwlWindowDays: self.cwlWindowDays,
            todayKey: CostDashboardInsights.todayDayKey())
    }

    /// Cache hit → stored value; miss → synchronous compute so the current
    /// frame is never empty. The `.onChange(initial: true)` in `body`
    /// stores the value right after, so a miss costs at most one extra
    /// compute per data change instead of one per render.
    private func resolvedInsights() -> CostDashboardInsights? {
        if self.cachedInsightsKey == self.insightsCacheKey {
            return self.cachedInsights
        }
        return self.computeInsights()
    }

    private var isCostDashboardUnlocked: Bool {
        ProFeatureAccess.isUnlocked(
            .fullCostDashboard,
            isDemoMode: self.isDemoMode,
            isProUnlocked: self.proEntitlementStore.isProUnlocked,
            isRemotelyDisabled: self.remoteConfigStore.isDisabled(.fullCostDashboard))
    }

    private var isShareUnlocked: Bool {
        ProFeatureAccess.isUnlocked(
            .shareCards,
            isDemoMode: self.isDemoMode,
            isProUnlocked: self.proEntitlementStore.isProUnlocked,
            isRemotelyDisabled: self.remoteConfigStore.isDisabled(.shareCards))
    }

    var body: some View {
        // Resolve ONCE per body evaluation — content, toolbar, and share
        // sheet all read this local instead of re-running the aggregation.
        let insights = self.resolvedInsights()
        NavigationStack {
            Group {
                if self.displaySnapshot != nil {
                    if let insights {
                        if self.isCostDashboardUnlocked {
                            CostDashboardView(
                                insights: insights,
                                usageData: self.usageData,
                                isDemoMode: self.isDemoMode)
                        } else {
                            ProFeatureLockedStateView(
                                store: self.proEntitlementStore,
                                feature: .fullCostDashboard,
                                message: String(
                                    localized: "Unlock QuotaKit Pro to view the full cost dashboard, history charts, and share cards for synced provider data."))
                        }
                    } else {
                        EmptyStateView(
                            title: "No Cost Data Yet",
                            message: "Enable cost collection in QuotaKit on your Mac to see provider spend, breakdowns, and budgets here.",
                            systemImage: "dollarsign.gauge.chart.lefthalf.righthalf")
                    }
                } else {
                    OnboardingView(onDemo: { self.isDemoMode = true })
                }
            }
            .navigationTitle(self.isDemoMode || self.displaySnapshot == nil ? "" : String(localized: "Cost"))
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
                if insights != nil, self.isCostDashboardUnlocked, self.isShareUnlocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            self.showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: self.$showShareSheet) {
                if let insights, self.isShareUnlocked {
                    CostShareSheet(insights: insights)
                }
            }
        }
        .onChange(of: self.insightsCacheKey, initial: true) { _, newKey in
            guard self.cachedInsightsKey != newKey else { return }
            self.cachedInsightsKey = newKey
            self.cachedInsights = self.computeInsights()
        }
    }
}

struct ProFeatureLockedStateView: View {
    let store: ProEntitlementStore
    let feature: FeatureGate
    let message: String

    var body: some View {
        ScrollView {
            ProFeatureLockedCard(
                store: self.store,
                feature: self.feature,
                message: self.message)
                .padding(.horizontal, 20)
                .padding(.top, 24)
        }
        .accessibilityIdentifier("pro-feature-locked-state-\(self.feature.rawValue)")
    }
}
