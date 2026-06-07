import SwiftUI

struct QKMetricDisplay: View {
    @Environment(\.quotaKitTheme) private var theme
    let value: String
    var subtitle: String?
    var tintColor: Color?
    var valueFont: Font = .system(size: 36, weight: .bold, design: .rounded)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(self.value)
                .font(self.valueFont)
                .monospacedDigit()
                .fontWeight(.bold)
                .foregroundStyle(self.tintColor ?? self.theme.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(self.theme.textMuted)
            }
        }
    }
}
