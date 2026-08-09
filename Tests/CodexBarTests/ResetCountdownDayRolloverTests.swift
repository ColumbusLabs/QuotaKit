import Foundation
import Testing
@testable import CodexBarCore

struct ResetCountdownDayRolloverTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func `generic countdown rolls exactly twenty four hours into one day`() {
        let reset = Self.now.addingTimeInterval(24 * 3600)

        #expect(UsageFormatter.resetCountdownDescription(from: reset, now: Self.now) == "in 1d")
    }

    @Test
    func `generic countdown includes days and hours above the boundary`() {
        let reset = Self.now.addingTimeInterval(25 * 3600)

        #expect(UsageFormatter.resetCountdownDescription(from: reset, now: Self.now) == "in 1d 1h")
    }

    @Test
    func `generic countdown stays in hours below the boundary`() {
        let reset = Self.now.addingTimeInterval(23 * 3600)

        #expect(UsageFormatter.resetCountdownDescription(from: reset, now: Self.now) == "in 23h")
    }
}
