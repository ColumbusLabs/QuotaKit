import SwiftUI

/// Shared quota bar: provider-tinted fill, optional warning-threshold
/// ticks, and the triple-stripe pace marker showing deficit/buffer.
/// Compiled into both the app and the widget extension (see project.yml)
/// so the widgets render the exact same bar as the main app.
struct UsageProgressBarView: View {
    let progressFraction: Double
    let tintColor: Color
    var trackColor: Color = .secondary.opacity(0.18)
    let markerPercents: [Double]
    let pacePercent: Double?
    let paceColor: Color

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(self.trackColor)
                Capsule()
                    .fill(self.tintColor)
                    .frame(width: geo.size.width * self.progressFraction.clamped(to: 0...1))

                ForEach(self.markerPercents, id: \.self) { percent in
                    Rectangle()
                        .fill(Color.secondary)
                        .frame(width: 1.5, height: height + 4)
                        .offset(x: geo.size.width * percent.clamped(to: 0...100) / 100.0 - 0.75)
                        .accessibilityHidden(true)
                }

                if let pacePercent {
                    HStack(spacing: 1) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(self.paceColor)
                                .frame(width: 1.5, height: height + 5)
                        }
                    }
                    .offset(x: geo.size.width * pacePercent.clamped(to: 0...100) / 100.0 - 2.75)
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
