import CodexBarSync
import SwiftUI

/// Dedicated Kiro credit-display card. Mirrors the Mac MenuCard
/// affordance added in upstream PR #933 — plan tag + primary credits
/// progress + optional bonus pool with expiry countdown.
///
/// Populated only when `ProviderUsageSnapshot.kiroCredits` is non-nil
/// (Mac 0.26.2+ on the `kiro` provider). Fall-through to the generic
/// rate-window list otherwise — see `ProviderDetailView.primaryUsageSection`.
struct KiroCreditsCard: View {
    let credits: SyncKiroCredits
    let tintColor: Color

    private var creditsFraction: Double {
        guard let total = credits.creditsTotal, total > 0 else { return 0 }
        return min(max(credits.creditsUsed / total, 0), 1)
    }

    private var bonusFraction: Double? {
        guard let used = credits.bonusUsed,
              let total = credits.bonusTotal,
              total > 0
        else { return nil }
        return min(max(used / total, 0), 1)
    }

    private var hasBonus: Bool {
        credits.bonusTotal != nil && (credits.bonusTotal ?? 0) > 0
    }

    private var hasOverage: Bool {
        (credits.overageCreditsUsed ?? 0) > 0
            || (credits.estimatedOverageCostUSD ?? 0) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header

            self.creditsRow

            if let bonusFraction = self.bonusFraction {
                Divider()
                self.bonusRow(fraction: bonusFraction)
            }

            if self.hasOverage {
                Divider()
                self.overageRow
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kiro-credits-card")
    }

    /// Overage row — only shown when Mac surfaced
    /// `overage_credits_used` (Kiro plan exhausted, user paying
    /// per-credit). Mirrors Mac's v0.27.0 "overage credits / overage
    /// cost" menu bar display modes.
    private var overageRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(localized: "kiro_overage_label", defaultValue: "Overage"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let usedCredits = credits.overageCreditsUsed, usedCredits > 0 {
                Text(String(format: String(localized: "kiro_overage_credits_format", defaultValue: "+%@ credits"),
                            Self.formatCredits(usedCredits)))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.orange)
            }
            if let costUSD = credits.estimatedOverageCostUSD, costUSD > 0 {
                Text(self.overageCostText(costUSD: costUSD))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityIdentifier("kiro-overage-row")
    }

    private func overageCostText(costUSD: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = costUSD < 10 ? 2 : 0
        return formatter.string(from: NSNumber(value: costUSD)) ?? "$\(costUSD)"
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(String(localized: "kiro_credits_title", defaultValue: "Kiro credits"))
                .font(.headline)
            if let plan = credits.planName, !plan.isEmpty {
                Text(plan)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(self.tintColor.opacity(0.16)))
                    .foregroundStyle(self.tintColor)
                    .accessibilityLabel(Text(String(localized: "kiro_plan_label", defaultValue: "Plan")) + Text(": ") + Text(plan))
            }
            Spacer()
        }
    }

    private var creditsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(self.creditsLabelText)
                    .font(.subheadline.monospacedDigit())
                Spacer()
                if let percent = credits.creditsPercent {
                    Text("\(Int(percent.rounded()))%")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(self.tintColor)
                }
            }
            ProgressView(value: self.creditsFraction)
                .progressViewStyle(.linear)
                .tint(self.tintColor)
        }
    }

    private var creditsLabelText: String {
        let used = Self.formatCredits(credits.creditsUsed)
        if let total = credits.creditsTotal, total > 0 {
            return "\(used) / \(Self.formatCredits(total))"
        }
        return used
    }

    private func bonusRow(fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "kiro_bonus_credits", defaultValue: "Bonus credits"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let days = credits.bonusExpiryDays {
                    Text(self.bonusExpiryText(days: days))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
            HStack {
                Text(self.bonusLabelText)
                    .font(.caption.monospacedDigit())
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(self.tintColor.opacity(0.7))
            }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(self.tintColor.opacity(0.7))
        }
    }

    private var bonusLabelText: String {
        let used = Self.formatCredits(credits.bonusUsed ?? 0)
        if let total = credits.bonusTotal, total > 0 {
            return "\(used) / \(Self.formatCredits(total))"
        }
        return used
    }

    private func bonusExpiryText(days: Int) -> String {
        if days <= 0 {
            return String(localized: "kiro_bonus_expired", defaultValue: "expired")
        }
        if days == 1 {
            return String(localized: "kiro_bonus_expiring_one_day", defaultValue: "expires in 1 day")
        }
        return String(format: String(localized: "kiro_bonus_expiring_days_format", defaultValue: "expires in %d days"), days)
    }

    private static func formatCredits(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value < 10 ? 2 : 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

#Preview("Standard plan") {
    KiroCreditsCard(
        credits: SyncKiroCredits(
            planName: "Pro",
            creditsUsed: 320,
            creditsTotal: 1000,
            creditsPercent: 32,
            bonusUsed: 45,
            bonusTotal: 200,
            bonusExpiryDays: 19,
            resetsAt: nil),
        tintColor: Color(red: 0.25, green: 0.62, blue: 0.49))
        .padding()
}

#Preview("Plan exhausted with overage (v0.27.0)") {
    KiroCreditsCard(
        credits: SyncKiroCredits(
            planName: "Pro",
            creditsUsed: 1000,
            creditsTotal: 1000,
            creditsPercent: 100,
            bonusUsed: 200,
            bonusTotal: 200,
            bonusExpiryDays: 7,
            resetsAt: nil,
            overageCreditsUsed: 145,
            estimatedOverageCostUSD: 2.45),
        tintColor: Color(red: 0.25, green: 0.62, blue: 0.49))
        .padding()
}
