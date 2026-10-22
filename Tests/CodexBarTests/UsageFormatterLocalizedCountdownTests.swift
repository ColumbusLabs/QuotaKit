import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

extension UsageFormatterTests {
    @Test(arguments: [
        (10 * 60 + 1, "11m"),
        (3 * 3600 + 31 * 60, "3h 31m"),
        (26 * 3600, "1d 2h"),
        ((24 * 3600) + (5 * 60), "1d 5m"),
        (2 * 24 * 3600, "2d"),
        (-10, "now"),
    ] as [(TimeInterval, String)])
    func `reset countdown duration omits the leading preposition`(interval: TimeInterval, expected: String) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(interval)
        #expect(UsageFormatter.resetCountdownDuration(from: reset, now: now) == expected)
    }

    @Test
    func `localized countdown keeps its own preposition out of sentence wrappers`() {
        UsageFormatter.setLocalizationProvider { key in
            switch key {
            case "in %@h": "через %@ год"
            case "%@h": "%@ год"
            case "%@d": "%@ дн."
            case "%@m": "%@ хв"
            case "Resets in %@": "Скидання через %@"
            default: key
            }
        }
        defer { UsageFormatter.clearLocalizationProvider() }

        let now = Date(timeIntervalSince1970: 1_000_000)
        let twoHours = now.addingTimeInterval(2 * 3600)
        #expect(UsageFormatter.resetCountdownDescription(from: twoHours, now: now) == "через 2 год")
        #expect(UsageFormatter.resetCountdownDuration(from: twoHours, now: now) == "2 год")

        let window = RateWindow(usedPercent: 0, windowMinutes: nil, resetsAt: twoHours, resetDescription: nil)
        #expect(UsageFormatter.resetLine(for: window, style: .countdown, now: now) == "Скидання через 2 год")

        let dayAndMinutes = now.addingTimeInterval((24 * 3600) + (5 * 60))
        #expect(UsageFormatter.resetCountdownDuration(from: dayAndMinutes, now: now) == "1 дн. 5 хв")
    }

    @Test
    func `countdowns use the selected app catalog without retaining another language`() {
        UsageFormatter.setLocalizationProvider { L($0) }
        defer { UsageFormatter.clearLocalizationProvider() }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(2 * 3600)
        CodexBarLocalizationOverride.$appLanguage.withValue("uk") {
            #expect(UsageFormatter.resetCountdownDescription(from: reset, now: now) == "через 2 год")
            #expect(UsageFormatter.resetCountdownDescription(from: now, now: now) == "зараз")
            #expect(L("usage_percent_suffix_left") == "залишилося")
            #expect(L("full") == "повний")
            #expect(L("%@m", "5") == "5 хв")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(UsageFormatter.resetCountdownDescription(from: reset, now: now) == "in 2h")
        }
    }

    @Test
    @MainActor
    func `relative time labels do not repeat localized time particles`() throws {
        UsageFormatter.setLocalizationProvider { L($0) }
        defer { UsageFormatter.clearLocalizationProvider() }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(2 * 3600)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: nil,
            resetsAt: reset,
            resetDescription: nil,
            nextRegenPercent: 10)
        let credits = GrokRateLimitResetCreditsSnapshot(expirations: [reset], updatedAt: now)
        for (language, expectedRegen, expectedExpiry) in [
            ("zh-Hans", "2 小时后恢复", "2 小时后 到期"),
            ("ja", "2時間後に再生成", "2時間後に期限切れ"),
            ("ko", "2시간 후에 재생성", "2시간 후에 만료"),
        ] {
            try CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                let detail = try #require(UsageMenuCardView.Model.syntheticRollingRegenDetail(
                    window: window, now: now, showUsed: true))
                #expect(detail.resetText == expectedRegen)
                let presentation = try #require(LimitResetCreditsPresentation.make(
                    snapshot: credits, resetStyle: .countdown, now: now))
                #expect(presentation.items.map(\.expiryText) == [expectedExpiry])
            }
        }
    }
}
