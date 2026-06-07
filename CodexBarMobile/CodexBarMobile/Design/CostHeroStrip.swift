import SwiftUI

struct CostHeroStrip: View {
    @Environment(\.quotaKitTheme) private var theme
    let total30DayCost: String
    let tokenSubtitle: String
    let todayValue: String
    let todaySubtitle: String
    let topDriverValue: String
    let topDriverSubtitle: String
    let activeDaysValue: String
    let activeDaysSubtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QKSurfaceCard(elevation: .elevated, cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("30-day spend", comment: "Cost dashboard hero label")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(self.theme.textMuted)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    QKMetricDisplay(
                        value: self.total30DayCost,
                        subtitle: self.tokenSubtitle,
                        tintColor: self.theme.spendWarm,
                        valueFont: .system(size: 36, weight: .bold, design: .rounded))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    self.chip(title: String(localized: "Today"), value: self.todayValue, subtitle: self.todaySubtitle, tint: self.theme.spendWarm)
                    self.chip(
                        title: String(localized: "Top driver"),
                        value: self.topDriverValue,
                        subtitle: self.topDriverSubtitle,
                        tint: self.theme.spendWarm)
                    self.chip(
                        title: String(localized: "Active days"),
                        value: self.activeDaysValue,
                        subtitle: self.activeDaysSubtitle,
                        tint: self.theme.accent)
                }
            }
        }
    }

    private func chip(title: String, value: String, subtitle: String, tint: Color) -> some View {
        QKSurfaceCard(elevation: .surface, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(self.theme.textMuted)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundStyle(tint)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(self.theme.textMuted)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(width: 132, alignment: .leading)
        }
    }
}
