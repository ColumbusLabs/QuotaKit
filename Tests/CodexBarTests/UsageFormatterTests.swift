import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite
struct UsageFormatterTests {
    @Test
    func formatsUsageLine() {
        let line = UsageFormatter.usageLine(remaining: 25, used: 75)
        #expect(line == "25% left")
    }

    @Test
    func relativeUpdatedRecent() {
        let now = Date()
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        let text = UsageFormatter.updatedString(from: fiveHoursAgo, now: now)
        #expect(text.contains("Updated"))
        #expect(text.contains("ago"))
    }

    @Test
    func absoluteUpdatedOld() {
        let now = Date()
        let dayAgo = now.addingTimeInterval(-26 * 3600)
        let text = UsageFormatter.updatedString(from: dayAgo, now: now)
        #expect(text.contains("Updated"))
        #expect(!text.contains("ago"))
    }
}
