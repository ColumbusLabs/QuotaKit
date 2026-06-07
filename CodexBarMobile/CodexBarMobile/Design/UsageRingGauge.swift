import SwiftUI

struct UsageRingGauge: View {
    @Environment(\.quotaKitTheme) private var theme
    let label: String
    let percent: Double
    let tintColor: Color
    var size: CGFloat = 88
    var accessibilityValue: String?

    private var clampedFraction: Double {
        min(max(self.percent / 100, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(self.theme.border, style: StrokeStyle(lineWidth: 5, lineCap: .round))

            Circle()
                .trim(from: 0.15, to: 0.15 + 0.7 * self.clampedFraction)
                .stroke(
                    self.tintColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round))

            VStack(spacing: 0) {
                Text("\(Int(self.percent.rounded()))%")
                    .font(.system(size: self.size * 0.22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(self.tintColor)
                Text(self.label)
                    .font(.system(size: self.size * 0.11, weight: .medium))
                    .foregroundStyle(self.theme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: self.size, height: self.size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(self.label))
        .accessibilityValue(Text(self.accessibilityValue ?? "\(Int(self.percent.rounded())) percent"))
    }
}
