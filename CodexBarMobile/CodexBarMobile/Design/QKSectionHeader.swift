import SwiftUI

struct QKSectionHeader: View {
    @Environment(\.quotaKitTheme) private var theme
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(self.title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(self.theme.textMuted)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(self.theme.textMuted.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
