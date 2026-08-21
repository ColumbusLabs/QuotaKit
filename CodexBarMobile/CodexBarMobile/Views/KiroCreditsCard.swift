import CodexBarSync
import SwiftUI

struct KiroOveragePresentation: Equatable {
    let creditsUsed: Double?
    let creditsCap: Double?
    let creditsRemaining: Double?
    let creditsFraction: Double?
    let charges: Double?
    let chargeLimit: Double?
    let currencyCode: String

    init?(_ credits: SyncKiroCredits) {
        let used = credits.overageCreditsUsed
        let cap = credits.overageCreditsCap.flatMap { $0 > 0 ? $0 : nil }
        let charges = credits.overageCharges ?? credits.estimatedOverageCostUSD
        guard (used ?? 0) > 0 || cap != nil || (charges ?? 0) > 0 else { return nil }

        self.creditsUsed = used
        self.creditsCap = cap
        self.creditsRemaining = cap.map { max(0, $0 - (used ?? 0)) }
        self.creditsFraction = cap.map { min(max((used ?? 0) / $0, 0), 1) }
        self.charges = charges
        self.chargeLimit = credits.overageChargeLimit
        self.currencyCode = credits.overageCharges != nil
            ? Self.normalizedCurrencyCode(credits.overageCurrencyCode)
            : "USD"
    }

    private static func normalizedCurrencyCode(_ code: String?) -> String {
        let normalized = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return normalized.count == 3 ? normalized : "USD"
    }
}

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
        return min(max(self.credits.creditsUsed / total, 0), 1)
    }

    private var bonusFraction: Double? {
        guard let used = credits.bonusUsed,
              let total = credits.bonusTotal,
              total > 0
        else { return nil }
        return min(max(used / total, 0), 1)
    }

    private var hasBonus: Bool {
        self.credits.bonusTotal != nil && (self.credits.bonusTotal ?? 0) > 0
    }

    private var overagePresentation: KiroOveragePresentation? {
        KiroOveragePresentation(self.credits)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.header

            self.creditsRow

            if let bonusFraction = self.bonusFraction {
                Divider()
                self.bonusRow(fraction: bonusFraction)
            }

            if let overage = self.overagePresentation {
                Divider()
                self.overageRow(overage)
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kiro-credits-card")
    }

    /// Overage row — only shown when Mac surfaced
    /// `overage_credits_used` (Kiro plan exhausted, user paying
    /// per-credit). Mirrors Mac's v0.27.0 "overage credits / overage
    /// cost" menu bar display modes.
    private func overageRow(_ overage: KiroOveragePresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(localized: "kiro_overage_label", defaultValue: "Overage"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let usedCredits = overage.creditsUsed {
                    Text(self.overageCreditsText(used: usedCredits, cap: overage.creditsCap))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }

            if let fraction = overage.creditsFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(.orange)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let remaining = overage.creditsRemaining {
                    Text(String(
                        format: String(localized: "%@ credits left"),
                        Self.formatCredits(remaining)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let charges = overage.charges {
                    Text(self.overageCostText(
                        charges: charges,
                        limit: overage.chargeLimit,
                        currencyCode: overage.currencyCode))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
        }
        .accessibilityIdentifier("kiro-overage-row")
    }

    private func overageCreditsText(used: Double, cap: Double?) -> String {
        guard let cap else {
            return String(
                format: String(localized: "kiro_overage_credits_format", defaultValue: "+%@ credits"),
                Self.formatCredits(used))
        }
        return "\(Self.formatCredits(used)) / \(Self.formatCredits(cap))"
    }

    private func overageCostText(charges: Double, limit: Double?, currencyCode: String) -> String {
        let used = Self.currencyText(charges, currencyCode: currencyCode)
        guard let limit else { return used }
        return "\(used) / \(Self.currencyText(limit, currencyCode: currencyCode))"
    }

    private static func currencyText(_ value: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = value < 10 ? 2 : 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(currencyCode) \(value)"
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
                    .accessibilityLabel(Text(String(localized: "kiro_plan_label", defaultValue: "Plan")) + Text(": ") +
                        Text(plan))
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
        let used = Self.formatCredits(self.credits.creditsUsed)
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
        let used = Self.formatCredits(self.credits.bonusUsed ?? 0)
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
        return String(
            format: String(localized: "kiro_bonus_expiring_days_format", defaultValue: "expires in %d days"),
            days)
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
            estimatedOverageCostUSD: nil,
            overageCreditsCap: 500,
            overageCharges: 18.85,
            overageChargeLimit: 65,
            overageCurrencyCode: "EUR"),
        tintColor: Color(red: 0.25, green: 0.62, blue: 0.49))
        .padding()
}
