import SwiftUI

/// Static progress fill with no implicit animations, used inside the menu card.
struct UsageProgressBar: View {
    let percent: Double
    let tint: Color
    let accessibilityLabel: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    private var clamped: Double {
        min(100, max(0, self.percent))
    }

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = proxy.size.width * self.clamped / 100
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MenuHighlightStyle.progressTrack(self.isHighlighted))
                Capsule()
                    .fill(MenuHighlightStyle.progressTint(self.isHighlighted, fallback: self.tint))
                    .frame(width: fillWidth)
            }
        }
        .frame(height: 6)
        .accessibilityLabel(self.accessibilityLabel)
        .accessibilityValue("\(Int(self.clamped)) percent")
        .drawingGroup()
    }
}
