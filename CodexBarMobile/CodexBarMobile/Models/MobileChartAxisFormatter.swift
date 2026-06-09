import Foundation

/// Computes "nice" Y-axis tick values for mobile charts.
///
/// Uses a Wilkinson-style rounding algorithm: given a max value and a target
/// tick count, picks a step size from {1, 2, 5, 10} × 10^k so the resulting
/// ticks land on round numbers that readers mentally parse easily (e.g. "$0,
/// $20, $40, $60" rather than "$0, $17.3, $34.6, $51.9"). See
/// https://rdrr.io/cran/labeling/src/R/wilkinson.R for the reference.
enum MobileChartAxisFormatter {
    /// Default 4 ticks balances readability vs. space on a 220pt-tall mobile
    /// chart — 3 feels sparse on tall charts, 5+ crowds labels into each
    /// other at the narrow device width. Caller can override for wider-screen
    /// share card rendering.
    static func axisValues(for values: [Double], targetTickCount: Int = 4) -> [Double] {
        let maxValue = max(values.max() ?? 0, 0)
        let step = self.axisStep(for: maxValue, targetTickCount: targetTickCount)
        let upperBound = max(step, ceil(maxValue / step) * step)
        let tickCount = Int((upperBound / step).rounded())
        return (0...tickCount).map { Double($0) * step }
    }

    static func axisLabel(for value: Double) -> String {
        Int(value.rounded()).formatted()
    }

    /// Selects a "nice" step size from the Wilkinson {1, 2, 5, 10} family.
    ///
    /// The switch thresholds `1.5 / 3 / 7` are the *breakpoints*, not the
    /// step sizes themselves. They're the canonical Wilkinson values chosen
    /// because each maps a `normalizedStep` bucket to whichever nice value
    /// (1, 2, 5, or 10) is closest on a log scale:
    ///   - `normalizedStep < 1.5` → 1 (raw step was closer to 1 than 2)
    ///   - `1.5 ≤ normalizedStep < 3` → 2 (closer to 2 than 5)
    ///   - `3 ≤ normalizedStep < 7` → 5 (closer to 5 than 10)
    ///   - `normalizedStep ≥ 7` → 10 (closer to 10 than next order of magnitude's 1)
    /// Changing these thresholds shifts the rounding bias and can make chart
    /// axes read as "ugly" numbers (e.g. "$17", "$34") to users.
    private static func axisStep(for maxValue: Double, targetTickCount: Int) -> Double {
        guard maxValue > 0 else { return 1 }

        let clampedTickCount = max(targetTickCount, 1)
        let rawStep = maxValue / Double(clampedTickCount)
        let magnitude = pow(10, floor(log10(rawStep)))
        let normalizedStep = rawStep / magnitude
        let niceStep: Double

        switch normalizedStep {
        case ..<1.5:
            niceStep = 1
        case ..<3:
            niceStep = 2
        case ..<7:
            niceStep = 5
        default:
            niceStep = 10
        }

        return max(1, niceStep * magnitude)
    }
}
