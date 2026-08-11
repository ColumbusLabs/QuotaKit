import CodexBarSync
import SwiftUI

/// Alibaba Token Plan (Bailian) structured credit card (parity gap G).
///
/// The generic RateWindow already conveys the % used + a "credits used" string;
/// this card adds the structured plan name + used/total/remaining credit
/// numbers + a reset countdown. Renders only when `SyncAlibabaTokenPlan` is
/// present (older Mac payloads fall back to the generic rate window).
struct AlibabaTokenPlanCard: View {
    let plan: SyncAlibabaTokenPlan
    var tintColor: Color = .orange

    private static func fmt(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// 0–100 used percent derived from used (or total − remaining) over total.
    private var usedPercent: Double? {
        let used: Double? = self.plan.usedCredits
            ?? self.plan.totalCredits.flatMap { total in self.plan.remainingCredits.map { total - $0 } }
        guard let used, let total = self.plan.totalCredits, total > 0 else { return nil }
        return min(max(used / total, 0), 1) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Token Plan")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let name = self.plan.planName, !name.isEmpty {
                    Text(name)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(self.tintColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(self.tintColor)
                }
                Spacer()
                if let reset = self.plan.resetsAt {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.caption2)
                        Text(reset, format: .relative(presentation: .named)).font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if let pct = self.usedPercent {
                ProgressView(value: pct / 100) {
                    HStack {
                        if let used = self.plan.usedCredits, let total = self.plan.totalCredits {
                            Text(String(
                                format: String(localized: "%1$@ / %2$@ credits"),
                                Self.fmt(used),
                                Self.fmt(total)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.0f%%", pct))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(self.tintColor)
            }

            if let remaining = self.plan.remainingCredits {
                Text(String(format: String(localized: "%@ credits left"), Self.fmt(remaining)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .qkCardBackground(cornerRadius: 14)
    }
}
