import CodexBarSync
import SwiftUI

/// Stacked 3-segment credit card for Perplexity's detail page.
///
/// Perplexity's backend exposes three distinct credit pools (recurring /
/// promo / purchased) that a flat `SyncRateWindow` list can't faithfully
/// represent. This view stacks them into a single horizontal bar whose
/// segment widths are proportional to each pool's `*TotalCents` — so a user
/// with a big recurring Pro plan but tiny promo top-up sees the recurring
/// segment dominate. The used portion of each segment fills `tintColor`;
/// remaining capacity fills `tintColor.opacity(0.18)`.
///
/// Renders only when `SyncPerplexityCreditSummary` is non-nil. Old Mac
/// payloads (pre-0.20.3) omit the field and `ProviderDetailView` falls back
/// to the generic rate-window rendering.
struct PerplexityCreditsCard: View {
    let credits: SyncPerplexityCreditSummary
    var tintColor: Color = .teal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            self.header
            self.stackedBar
            self.legend
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
    }

    // MARK: - Header (title + Pro/Max badge + renewal countdown)

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Credits")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let plan = self.credits.planName, !plan.isEmpty {
                Text(plan)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(self.tintColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(self.tintColor)
                    .accessibilityIdentifier("perplexity-plan-badge")
            }

            Spacer()

            if let renewal = self.credits.renewalAt {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                    Text(renewal, format: .relative(presentation: .named))
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("perplexity-renewal-countdown")
            }
        }
    }

    // MARK: - Stacked bar

    private var stackedBar: some View {
        GeometryReader { geo in
            let totalCents = self.pools.reduce(0.0) { $0 + $1.total }
            let safeTotal = max(totalCents, 1) // avoid /0 on free tier
            HStack(spacing: 2) {
                ForEach(self.pools) { pool in
                    let share = pool.total / safeTotal
                    let width = geo.size.width * share
                    ZStack(alignment: .leading) {
                        Capsule().fill(self.tintColor.opacity(0.18))
                        Capsule()
                            .fill(self.tintColor)
                            .frame(width: width * pool.usedFraction)
                    }
                    .frame(width: width)
                }
            }
        }
        .frame(height: 10)
        .accessibilityIdentifier("perplexity-stacked-bar")
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(self.pools) { pool in
                HStack {
                    Circle()
                        .fill(self.tintColor.opacity(Self.legendDotOpacity(for: pool.kind)))
                        .frame(width: 8, height: 8)
                    Text(Self.poolLabel(pool.kind))
                        .font(.caption)
                    Spacer()
                    Text(Self.formatCreditsUsed(pool.used, pool.total))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if pool.kind == .promo, let exp = self.credits.promoExpiresAt {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(String(localized: "exp.")) \(exp, format: .dateTime.month(.abbreviated).day())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Pool computation

    private struct PoolSegment: Identifiable, Equatable {
        enum Kind: String, Equatable { case recurring, promo, purchased }

        let kind: Kind
        let total: Double
        let used: Double

        var usedFraction: Double {
            self.total > 0 ? min(1, self.used / self.total) : 0
        }

        var id: String { self.kind.rawValue }
    }

    /// Non-nil, positive-total pools in display order (recurring → promo → purchased).
    private var pools: [PoolSegment] {
        var out: [PoolSegment] = []
        if let total = self.credits.recurringTotalCents, total > 0 {
            out.append(.init(kind: .recurring, total: total, used: self.credits.recurringUsedCents ?? 0))
        }
        if let total = self.credits.promoTotalCents, total > 0 {
            out.append(.init(kind: .promo, total: total, used: self.credits.promoUsedCents ?? 0))
        }
        if let total = self.credits.purchasedTotalCents, total > 0 {
            out.append(.init(kind: .purchased, total: total, used: self.credits.purchasedUsedCents ?? 0))
        }
        return out
    }

    // MARK: - Formatting helpers
    //
    // `private` is mandatory here: the `PoolSegment.Kind` parameter is a
    // private nested type, so any caller with broader visibility would be
    // referencing a symbol it can't see. Swift's archive compiler rejects
    // mixed-access signatures even when `swift test`/`swift build` on the
    // Mac Package target doesn't (Xcode iOS archive surfaces it).

    private static func poolLabel(_ kind: PoolSegment.Kind) -> String {
        switch kind {
        case .recurring: String(localized: "Monthly credits")
        case .promo: String(localized: "Bonus credits")
        case .purchased: String(localized: "Purchased credits")
        }
    }

    /// Legend dot opacity encodes a **consumption-priority signal**:
    /// Perplexity depletes the three credit pools in order — recurring first
    /// (use-it-or-lose-it monthly plan), then promo (bonus/time-limited),
    /// then purchased (pay-as-you-go, no expiration). The opacity ramp makes
    /// this reading order visually obvious at a glance: the brightest dot
    /// (1.0) = "spent first", dimmest (0.55) = "saved for last".
    ///
    /// The exact values (1.0 / 0.78 / 0.55) are tuned so each step is visibly
    /// distinct on a `.ultraThinMaterial` card in both light + dark mode
    /// without any step fading into the card background — narrower ramps
    /// (e.g. 1.0/0.9/0.8) lose the semantic reading.
    private static func legendDotOpacity(for kind: PoolSegment.Kind) -> Double {
        switch kind {
        case .recurring: 1.0
        case .promo: 0.78
        case .purchased: 0.55
        }
    }

    /// Cents → human-readable credit count: `"12,345 / 50,000"`. Perplexity's
    /// API uses "cents" as the raw credit count (1 credit == 1 cent
    /// internally) — we display the integer without a currency symbol.
    private static func formatCreditsUsed(_ used: Double, _ total: Double) -> String {
        let u = Int(used.rounded())
        let t = Int(total.rounded())
        return "\(u.formatted(.number)) / \(t.formatted(.number))"
    }
}
