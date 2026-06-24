import CodexBarSync
import Foundation
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

    @Test("Reset countdown rounds up to the next minute")
    func resetCountdownRoundsUpToNextMinute() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval((10 * 60) + 1)

        #expect(MobileResetCountdownFormatter.countdownDescription(from: reset, now: now) == "in 11m")
    }

    @Test("Reset countdown includes hours and minutes")
    func resetCountdownIncludesHoursAndMinutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval((3 * 3600) + (31 * 60))

        #expect(MobileResetCountdownFormatter.countdownDescription(from: reset, now: now) == "in 3h 31m")
        #expect(MobileResetCountdownFormatter.resetLine(from: reset, now: now) == "Resets in 3h 31m")
    }

    @Test("Reset countdown omits zero minutes for exact hours")
    func resetCountdownExactHour() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(60 * 60)

        #expect(MobileResetCountdownFormatter.countdownDescription(from: reset, now: now) == "in 1h")
    }

    @Test("Reset countdown includes days and hours")
    func resetCountdownIncludesDaysAndHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval((26 * 3600) + 10)

        #expect(MobileResetCountdownFormatter.countdownDescription(from: reset, now: now) == "in 1d 2h")
    }

    @Test("Reset countdown handles past dates")
    func resetCountdownPastDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(-10)

        #expect(MobileResetCountdownFormatter.countdownDescription(from: reset, now: now) == "now")
        #expect(MobileResetCountdownFormatter.resetLine(from: reset, now: now) == "Resets now")
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
