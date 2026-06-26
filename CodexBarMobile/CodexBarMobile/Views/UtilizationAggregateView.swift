import Charts
import CodexBarSync
import SwiftUI

/// Independent Subscription Utilization section for the Cost tab.
/// Uses **calendar days** (matches the cost chart's daily granularity).
/// Includes: 4 period summary cards, daily trend chart, provider share breakdown.
struct UtilizationAggregateView: View {
    let providers: [ProviderUsageSnapshot]

    @State private var selectedIndex: Int?
    @State private var cachedKey: String = ""
    @State private var cachedModel: UtilizationAggregateModel?

    /// Honor the Usage tab's "Show remaining usage" toggle here too — pre-fix
    /// the share row always rendered "86% avg use" even when the user had
    /// flipped the toggle and every other card on the Usage tab was showing
    /// "14% remaining". Matches `UsageCardView`'s own @AppStorage declaration
    /// (including the legacy-key migration default) so we toggle in lockstep.
    @AppStorage(MobileSettingsKeys.showRemainingUsage) private var showRemainingUsage =
        UserDefaults.standard.string(forKey: MobileSettingsKeys.usagePercentDisplayMode) == UsagePercentDisplayMode
            .remaining.rawValue

    /// Bar width in points. Tuned with `windowSize` so 30 bars + their
    /// inter-bar padding fit within the Cost tab's card width on a 390pt
    /// iPhone screen. Narrower than `UtilizationHistoryView`'s 10pt because
    /// this chart shares vertical space with 4 summary cards above it and
    /// a provider list below it, so the plot area is more constrained.
    /// Changing this without re-tuning `windowSize` can make labels overlap
    /// or leave excessive empty padding.
    private let barWidth: CGFloat = 8
    /// 30-day window — matches Cost tab's daily-spend chart so the two
    /// sections read as a coherent 30-day story. Also pins the axis
    /// `dateFormat` to compact `"M/d"` (see `dayLabelFormatter` below),
    /// because 8pt-wide bars can't accommodate locale-aware labels like
    /// Simplified Chinese's `"4月23日"`.
    private let windowSize = 30

    private var identityKey: String {
        UtilizationAggregateModelBuilder.identityKey(for: self.providers, windowSize: self.windowSize)
    }

    var body: some View {
        // Synchronous cache resolution:
        // - Cache hit (identity stable, e.g. hover) → return cached model, ZERO compute
        // - Cache miss → compute synchronously so the view has data on THIS frame.
        //   `.onChange(initial: true)` fires just after to persist the result into
        //   @State so subsequent renders hit the cache.
        // Previous `.task(id:)` pattern rendered empty on first frame while the async
        // task populated the cache — user reported the entire Subscription Utilization
        // section disappearing. Sync fallback fixes that without sacrificing hover
        // performance (identity is stable during hover, so cache stays warm).
        let currentKey = self.identityKey
        let model: UtilizationAggregateModel? = (self.cachedKey == currentKey)
            ? self.cachedModel
            : UtilizationAggregateModelBuilder.buildModel(from: self.providers, windowSize: self.windowSize)

        return Group {
            if let m = model {
                self.content(m)
            }
        }
        .onChange(of: currentKey, initial: true) { _, newKey in
            if self.cachedKey != newKey {
                self.cachedModel = UtilizationAggregateModelBuilder.buildModel(
                    from: self.providers,
                    windowSize: self.windowSize)
                self.cachedKey = newKey
            }
        }
    }

    private func content(_ m: UtilizationAggregateModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title — matches other Cost-tab section headers (.headline)
            Text("Subscription Utilization")
                .font(.headline)
                .padding(.top, 4)

            Text("Session quota usage trend across synced providers.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // 4 Summary Cards
            self.summaryCards(m)

            // Daily Trend Chart + Detail Line
            if !m.dayBars.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    self.dailyChart(m)
                        .frame(height: 120)
                    self.detailLine(m)
                        .frame(height: 16)
                }
            }

            // Provider cards — merged directly into this section (no sub-header).
            // iOS 1.9.0+: cap to top 5 + Others when 6 or more providers
            // contributed; otherwise show all. The Others row aggregates the
            // tail's sharePercent (additive across providers, so the sum is
            // meaningful) and is wrapped in a NavigationLink that drills
            // into FullProviderUtilizationListView listing every provider
            // in the same row style.
            if !m.providerShares.isEmpty {
                let cap = 5
                let usesOthers = m.providerShares.count >= cap + 1
                let visibleShares = usesOthers
                    ? Array(m.providerShares.prefix(cap))
                    : m.providerShares
                let tailShares = usesOthers
                    ? Array(m.providerShares.dropFirst(cap))
                    : []
                let tailShareSum = tailShares.reduce(0.0) { $0 + $1.sharePercent }

                VStack(spacing: 12) {
                    ForEach(visibleShares) { row in
                        self.providerShareRow(row)
                    }
                    if usesOthers {
                        NavigationLink {
                            FullProviderUtilizationListView(
                                shares: m.providerShares)
                        } label: {
                            self.othersUtilizationRow(
                                count: tailShares.count,
                                sharePercent: tailShareSum)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Summary Cards (4 periods)

    private func summaryCards(_ m: UtilizationAggregateModel) -> some View {
        HStack(spacing: 6) {
            self.periodCard(title: "Today", value: m.todayAvg, delta: m.todayDelta)
            self.periodCard(title: "This Week", value: m.thisWeekAvg, delta: m.thisWeekDelta)
            self.periodCard(title: "14 Days", value: m.last14Avg, delta: m.last14Delta)
            self.periodCard(title: "30 Days", value: m.last30Avg, delta: m.last30Delta)
        }
    }

    private func periodCard(
        title: LocalizedStringKey,
        value: Double?,
        delta: Double?) -> some View
    {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(.title3.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let delta {
                let sign = delta >= 0 ? "+" : ""
                Text(String(format: "%@%.0f%%", sign, delta))
                    .font(.caption2.bold())
                    .foregroundStyle(delta >= 0 ? .orange : .green)
                    .lineLimit(1)
            } else {
                // Reserve vertical space so all 4 cards align
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .qkCardBackground(cornerRadius: 10)
    }

    // MARK: - Daily Chart

    private func dailyChart(_ m: UtilizationAggregateModel) -> some View {
        Chart {
            ForEach(m.dayBars) { bar in
                if !bar.isPadding {
                    ForEach(bar.segments, id: \.providerID) { seg in
                        BarMark(
                            x: .value("D", bar.id),
                            y: .value("V", seg.avgPercent),
                            width: .fixed(self.barWidth))
                            .foregroundStyle(seg.color)
                    }
                }
            }

            if let si = self.selectedIndex, si >= 0, si < m.dayBars.count, !m.dayBars[si].isPadding {
                RuleMark(x: .value("S", si))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel {
                    if let idx = value.as(Int.self), idx >= 0, idx < m.dayBars.count,
                       let label = m.dayBars[idx].dayLabel
                    {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: 0...max(m.dayBars.count - 1, self.windowSize - 1))
        .chartXSelection(value: self.$selectedIndex)
    }

    // MARK: - Detail Line

    @ViewBuilder
    private func detailLine(_ m: UtilizationAggregateModel) -> some View {
        if let si = self.selectedIndex, si >= 0, si < m.dayBars.count, !m.dayBars[si].isPadding {
            let bar = m.dayBars[si]
            let avg = bar.segments.isEmpty ? 0.0
                : bar.segments.reduce(0.0) { $0 + $1.avgPercent } / Double(bar.segments.count)
            HStack {
                Text(bar.dayLabel ?? "")
                Spacer()
                Text(String(format: "%.0f%% avg", avg))
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack {
                Text("\(m.providerShares.count) providers")
                Spacer()
                if let last30 = m.last30Avg {
                    Text(String(format: "%.0f%% 30-day avg", last30))
                        .fontWeight(.medium)
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Provider Share Row

    /// Subtitle under each provider name on the share rows. Respects the
    /// "Show remaining usage" setting so every place on the Cost tab agrees
    /// on which direction the number runs. `rawAvgPercent` is the 30-day
    /// average of daily peaks (so "% remaining" is `100 - avg`, not inverse
    /// on a per-day basis — the right interpretation when the underlying
    /// number is already an average over days).
    private func averageUsageSubtitle(for rawAvgPercent: Double) -> String {
        if self.showRemainingUsage {
            let remaining = max(0, 100 - rawAvgPercent)
            return String(format: String(localized: "%.0f%% avg remaining"), remaining)
        }
        return String(format: String(localized: "%.0f%% avg use"), rawAvgPercent)
    }

    private func providerShareRow(_ row: UtilizationProviderShare) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ProviderBrandMark(
                    providerID: row.providerID,
                    size: 14,
                    tint: row.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(self.averageUsageSubtitle(for: row.rawAvgPercent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(format: "%.0f%%", row.sharePercent))
                    .font(.title3.monospacedDigit().bold())
            }

            ProgressView(value: row.sharePercent / 100)
                .tint(row.color)
                .scaleEffect(y: 1.8, anchor: .center)
        }
        .padding(14)
        .qkCardBackground(cornerRadius: 16)
    }

    /// "Others" row at the bottom of the capped Subscription Utilization
    /// section. iOS 1.9.0+ — aggregates the tail's `sharePercent` (additive
    /// across providers, so the sum is meaningful — unlike averaging
    /// individual `rawAvgPercent` averages) and shows a trailing chevron to
    /// suggest tappability. Caller wraps in a NavigationLink to
    /// FullProviderUtilizationListView.
    private func othersUtilizationRow(
        count: Int,
        sharePercent: Double) -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Others")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("+\(count) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(format: "%.0f%%", sharePercent))
                    .font(.title3.monospacedDigit().bold())

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            ProgressView(value: sharePercent / 100)
                .tint(Color.secondary.opacity(0.5))
                .scaleEffect(y: 1.8, anchor: .center)
        }
        .padding(14)
        .qkCardBackground(cornerRadius: 16)
    }

    /// Drill-down view shown when the user taps the Others row of the
    /// Subscription Utilization section. Lists every provider in the same row
    /// design as the capped section preview. Uses the static
    /// `"%.0f%% avg use"` subtitle — deliberately does NOT honor the
    /// `SubscriptionDisplayMode` "inverted / remaining" toggle, since the
    /// inverted view is still accessible from the section preview and
    /// duplicating the @AppStorage logic here would risk drift.
    private struct FullProviderUtilizationListView: View {
        @Environment(\.quotaKitTheme) private var theme
        let shares: [UtilizationProviderShare]

        var body: some View {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(self.shares) { row in
                        Self.shareRow(row)
                    }
                }
                .padding()
            }
            .navigationTitle(Text("Subscription Utilization"))
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .background(self.theme.canvas)
        }

        private static func shareRow(_ row: UtilizationProviderShare) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(row.color)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(String(
                            format: String(localized: "%.0f%% avg use"),
                            row.rawAvgPercent))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(String(format: "%.0f%%", row.sharePercent))
                        .font(.title3.monospacedDigit().bold())
                }

                ProgressView(value: row.sharePercent / 100)
                    .tint(row.color)
                    .scaleEffect(y: 1.8, anchor: .center)
            }
            .padding(14)
            .qkCardBackground(cornerRadius: 16)
        }
    }
}
