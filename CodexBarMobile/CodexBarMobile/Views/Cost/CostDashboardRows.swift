import CodexBarSync
import SwiftUI

struct CostBreakdownMetricColumn: View {
    let amountText: String
    let shareText: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(self.amountText)
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
                Text(self.shareText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .trailing, spacing: 2) {
                Text(self.amountText)
                    .font(.headline.monospacedDigit())
                    .fontWeight(.bold)
                Text(self.shareText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .layoutPriority(1)
    }
}

/// Renders one row of the Cost dashboard's contribution lists (Provider Share /
/// Model Mix / Codex Service Mix). Extracted in iOS 1.9.0 so the same row
/// design is shared between the capped section preview (top 5) and the
/// drill-down full-list view that opens when the user taps "Others".
struct CostBreakdownRowView: View {
    @Environment(\.quotaKitTheme) private var theme
    let row: CostBreakdownRow
    let total: Double
    var rank: Int?

    var body: some View {
        QKSurfaceCard(elevation: .surface, accentColor: self.row.color, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let rank, rank <= 3 {
                        Text("#\(rank)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(self.theme.textMuted)
                            .frame(width: 22, alignment: .leading)
                    }

                    Circle()
                        .fill(self.row.color)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.row.label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(self.theme.textPrimary)
                        if let subtitle = self.row.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(self.theme.textMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    CostBreakdownMetricColumn(
                        amountText: CostFormatting.usd(self.row.amountUSD),
                        shareText: Self.shareText(self.row.amountUSD, total: self.total))
                }

                UsageProgressBarView(
                    progressFraction: Self.ratio(self.row.amountUSD, total: self.total),
                    tintColor: self.row.color,
                    trackColor: self.theme.border,
                    markerPercents: [],
                    pacePercent: nil,
                    paceColor: .clear)
            }
            .padding(14)
        }
    }

    fileprivate static func ratio(_ value: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    fileprivate static func shareText(_ value: Double, total: Double) -> String {
        guard total > 0 else { return "0%" }
        return String(format: "%.0f%%", value / total * 100)
    }
}

/// Bottom row of a capped contribution list, summarising everything beyond
/// the top 5. Wrapped in a NavigationLink by the caller → drills into the
/// full list. Visually mirrors `CostBreakdownRowView` with a muted grey dot
/// and a trailing chevron to suggest tappability.
struct OthersBreakdownRowView: View {
    @Environment(\.quotaKitTheme) private var theme
    let count: Int
    let amountUSD: Double
    let total: Double

    var body: some View {
        QKSurfaceCard(elevation: .surface, cornerRadius: 16, dashedBorder: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(self.theme.textMuted.opacity(0.5))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Others")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(self.theme.textPrimary)
                        Text("+\(self.count) more")
                            .font(.caption)
                            .foregroundStyle(self.theme.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    CostBreakdownMetricColumn(
                        amountText: CostFormatting.usd(self.amountUSD),
                        shareText: CostBreakdownRowView.shareText(self.amountUSD, total: self.total))

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(self.theme.textMuted)
                }

                UsageProgressBarView(
                    progressFraction: CostBreakdownRowView.ratio(self.amountUSD, total: self.total),
                    tintColor: self.theme.textMuted.opacity(0.5),
                    trackColor: self.theme.border,
                    markerPercents: [],
                    pacePercent: nil,
                    paceColor: .clear)
            }
            .padding(14)
        }
    }
}

/// Drill-down view shown when the user taps an Others row on the Cost
/// dashboard. Lists every entry in the section (same `CostBreakdownRowView`
/// style) inside the Cost tab's existing NavigationStack.
struct FullBreakdownListView: View {
    @Environment(\.quotaKitTheme) private var theme
    let title: LocalizedStringResource
    let rows: [CostBreakdownRow]
    let total: Double

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(self.rows) { row in
                    CostBreakdownRowView(row: row, total: self.total)
                }
            }
            .padding()
        }
        .navigationTitle(Text(self.title))
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .background(self.theme.canvas)
    }
}

/// Renders one row of the Budgets section. Extracted in iOS 1.9.0 so the
/// same row design is used by the capped preview (top 5) and the drill-down
/// full list (see `FullBudgetListView`).
struct BudgetRowView: View {
    let row: CostBudgetRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.provider.providerName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let method = row.provider.loginMethod {
                    Text(method)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            BudgetProgressView(
                budget: row.budget,
                tintColor: providerTint(for: row.provider))
        }
    }
}

/// Bottom Others row of the capped Budgets section. No aggregate metric —
/// summing budgets across different limits / currencies / cycles isn't
/// meaningful — just the count and a chevron. Tappable via the parent
/// NavigationLink → FullBudgetListView.
struct OthersBudgetRowView: View {
    let count: Int

    var body: some View {
        HStack {
            Text("Others")
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text("+\(count) more")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

/// Drill-down view for the Budgets section. Shows every budget in the same
/// row design as the capped preview.
struct FullBudgetListView: View {
    @Environment(\.quotaKitTheme) private var theme
    let rows: [CostBudgetRow]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(self.rows) { row in
                    BudgetRowView(row: row)
                }
            }
            .padding()
        }
        .navigationTitle(Text("Budgets"))
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .background(self.theme.canvas)
    }
}

func providerTint(for provider: ProviderUsageSnapshot?) -> Color {
    ProviderColorPalette.color(for: provider?.providerID ?? "")
}
