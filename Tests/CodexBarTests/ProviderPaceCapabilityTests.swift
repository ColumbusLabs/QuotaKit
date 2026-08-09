import CodexBarCore
import Foundation
import Testing

struct ProviderPaceCapabilityTests {
    @Test
    func `supported provider pace capabilities remain descriptor owned`() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let withoutDuration = Self.window(minutes: nil, resetsAt: now.addingTimeInterval(3600))
        let weekly = Self.window(minutes: 7 * 24 * 60, resetsAt: now.addingTimeInterval(4 * 86400))

        #expect(!ProviderDescriptorRegistry.descriptor(for: .codex).pace
            .supportsResetWindowPace(window: weekly, now: now))
        #expect(!ProviderDescriptorRegistry.descriptor(for: .claude).pace
            .supportsResetWindowPace(window: weekly, now: now))
        #expect(ProviderDescriptorRegistry.descriptor(for: .cursor).pace
            .supportsResetWindowPace(window: weekly, now: now))
        #expect(!ProviderDescriptorRegistry.descriptor(for: .cursor).pace
            .supportsResetWindowPace(window: withoutDuration, now: now))
        #expect(ProviderDescriptorRegistry.descriptor(for: .grok).pace
            .supportsResetWindowPace(window: weekly, now: now))
    }

    @Test
    func `Grok pace rejects expired and missing billing periods`() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let capability = ProviderDescriptorRegistry.descriptor(for: .grok).pace

        #expect(!capability.supportsResetWindowPace(
            window: Self.window(minutes: nil, resetsAt: now.addingTimeInterval(3600)),
            now: now))
        #expect(!capability.supportsResetWindowPace(
            window: Self.window(minutes: 7 * 24 * 60, resetsAt: now.addingTimeInterval(-60)),
            now: now))
    }

    @Test
    func `calendar month pace resolves the real cycle duration`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let resetsAt = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 3,
            day: 1)))
        let window = Self.window(minutes: 30 * 24 * 60, resetsAt: resetsAt)

        let resolved = ProviderPaceCapability.calendarMonthResetWindow.resolvedResetWindowForPace(window)

        #expect(resolved.windowMinutes == 28 * 24 * 60)
        #expect(resolved.resetsAt == resetsAt)
    }

    private static func window(minutes: Int?, resetsAt: Date?) -> RateWindow {
        RateWindow(usedPercent: 50, windowMinutes: minutes, resetsAt: resetsAt, resetDescription: nil)
    }
}
