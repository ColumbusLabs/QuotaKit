import SwiftUI

/// Canonical 70% / 90% quota-warning colors shared across usage bars,
/// budget progress, and any future quota-shaped UI.
enum QuotaUsageColor {
    static func color(usedPercent: Double, tint: Color) -> Color {
        if usedPercent >= 90 { return .red }
        if usedPercent >= 70 { return .orange }
        return tint
    }

    static func color(usedFraction: Double, tint: Color) -> Color {
        self.color(usedPercent: usedFraction * 100, tint: tint)
    }
}
