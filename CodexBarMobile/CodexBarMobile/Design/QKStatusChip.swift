import SwiftUI

enum QKStatusChipStyle {
    case live
    case stale
    case demo
    case mock
    case neutral
}

struct QKStatusChip: View {
    @Environment(\.quotaKitTheme) private var theme
    let text: String
    var style: QKStatusChipStyle = .neutral
    var systemImage: String?
    var accentColor: Color?

    private var tint: Color {
        if let accentColor { return accentColor }
        switch self.style {
        case .live: return Color.green
        case .stale: return Color.orange
        case .demo: return self.theme.accent
        case .mock: return Color.purple
        case .neutral: return self.theme.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(self.text)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        }
        .foregroundStyle(self.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(self.tint.opacity(0.12), in: Capsule())
        .overlay(alignment: .leading) {
            Capsule()
                .fill(self.tint)
                .frame(width: 3)
                .padding(.vertical, 4)
        }
    }
}
