import CodexBarSync
import Testing
@testable import CodexBarMobile

@Suite("Mobile Display Formatting")
struct MobileDisplayFormattingTests {
    @Test("Used mode shows used percent and fill")
    func usedModeValues() {
        let window = SyncRateWindow(usedPercent: 78, windowMinutes: 300, resetsAt: nil, resetDescription: nil)

        #expect(UsagePercentDisplayMode.used.displayedPercent(for: window) == 78)
        #expect(UsagePercentDisplayMode.used.progressFraction(for: window) == 0.78)
        #expect(UsagePercentDisplayMode.used.percentageValueText(for: window) == "78%")
        #expect(UsagePercentDisplayMode.used.percentageText(for: window) == "78% \(String(localized: "used"))")
    }

    @Test("Remaining mode shows inverse percent and fill")
    func remainingModeValues() {
        let window = SyncRateWindow(usedPercent: 78, windowMinutes: 300, resetsAt: nil, resetDescription: nil)

        #expect(UsagePercentDisplayMode.remaining.displayedPercent(for: window) == 22)
        #expect(UsagePercentDisplayMode.remaining.progressFraction(for: window) == 0.22)
        #expect(UsagePercentDisplayMode.remaining.percentageValueText(for: window) == "22%")
        #expect(UsagePercentDisplayMode.remaining.percentageText(for: window) == "22% \(String(localized: "left"))")
    }

    @Test("Pace marker uses expected used percent in used mode")
    func paceMarkerUsedMode() {
        let pace = SyncUsagePace(
            stage: .ahead,
            deltaPercent: 8,
            expectedUsedPercent: 42,
            actualUsedPercent: 50,
            leftLabel: "8% in deficit",
            rightLabel: nil)

        #expect(UsageCardView.paceDisplayPercent(for: pace, displayMode: .used) == 42)
    }

    @Test("Pace marker uses inverse expected percent in remaining mode")
    func paceMarkerRemainingMode() {
        let pace = SyncUsagePace(
            stage: .behind,
            deltaPercent: -8,
            expectedUsedPercent: 42,
            actualUsedPercent: 34,
            leftLabel: "8% in reserve",
            rightLabel: nil)

        #expect(UsageCardView.paceDisplayPercent(for: pace, displayMode: .remaining) == 58)
    }

    @Test("On-track pace has no marker")
    func onTrackPaceMarkerHidden() {
        let pace = SyncUsagePace(
            stage: .onTrack,
            deltaPercent: 0,
            expectedUsedPercent: 42,
            actualUsedPercent: 42,
            leftLabel: "On pace",
            rightLabel: nil)

        #expect(UsageCardView.paceDisplayPercent(for: pace, displayMode: .used) == nil)
    }

    @Test("Axis formatter uses clean integer ticks for large values")
    func axisFormatterLargeValues() {
        #expect(MobileChartAxisFormatter.axisValues(for: [12.4, 64.3, 152.71]) == [0, 50, 100, 150, 200])
    }

    @Test("Axis formatter avoids decimal tick labels for small values")
    func axisFormatterSmallValues() {
        #expect(MobileChartAxisFormatter.axisValues(for: [0.18, 1.42, 2.48]) == [0, 1, 2, 3])
        #expect(MobileChartAxisFormatter.axisLabel(for: 3) == "3")
    }
}
