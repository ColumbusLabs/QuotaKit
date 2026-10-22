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
    func `menu bar reset cache follows formatter and app localization changes`() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetAt = now.addingTimeInterval(2 * 60 * 60)
        let data = CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            MenuBarLayoutRenderData(
                iconKey: "codex",
                providerName: "Codex",
                accountLabel: nil,
                laneLabels: MenuBarLayoutLaneLabels(provider: .codex, snapshot: nil),
                primary: nil,
                secondary: nil,
                tertiary: nil,
                session: MenuBarLayoutRenderWindow(RateWindow(
                    usedPercent: 25,
                    windowMinutes: 300,
                    resetsAt: resetAt,
                    resetDescription: nil)),
                weekly: nil,
                scopedWeekly: nil,
                scopedWeeklyTitle: nil,
                automatic: MenuBarLayoutRenderWindow(RateWindow(
                    usedPercent: 50,
                    windowMinutes: 300,
                    resetsAt: resetAt,
                    resetDescription: nil)),
                automaticText: nil,
                sessionPace: nil,
                weeklyPace: nil,
                automaticPace: nil,
                runsOut: nil,
                balance: nil,
                costToday: nil,
                cost30d: nil,
                metrics: .unavailable)
        }
        let layout = MenuBarLayout(lines: [[.resetCountdown]])
        let localizedLabelLayout = MenuBarLayout(lines: [[.percent(window: .session)]])
        let options = MenuBarLayoutRenderOptions(
            size: .regular,
            highContrast: false,
            showUsed: true,
            conditionals: [],
            appearanceName: "aqua",
            isDebugApp: false,
            now: now,
            showWindowLabels: false)
        let renderer = MenuBarLayoutRenderer()

        UsageFormatter.setLocalizationProvider { "first: \(L($0))" }
        UsageFormatter.setLocaleProvider { codexBarLocalizedLocale() }
        defer {
            UsageFormatter.clearLocalizationProvider()
            UsageFormatter.clearLocaleProvider()
        }

        let first = CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            renderer.render(layout: layout, data: data, icon: nil, options: options)
        }
        let firstLabel = CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            renderer.render(layout: localizedLabelLayout, data: data, icon: nil, options: options)
        }
        let englishSessionAccessibility = CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            L("%@ %@", L("Session"), "25%")
        }
        UsageFormatter.setLocalizationProvider { "second: \(L($0))" }
        let changedProvider = CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            renderer.render(layout: layout, data: data, icon: nil, options: options)
        }
        let changedProviderLabel = CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            renderer.render(layout: localizedLabelLayout, data: data, icon: nil, options: options)
        }
        UsageFormatter.setLocaleProvider { Locale(identifier: "fr_FR") }
        let changedLocale = CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            renderer.render(layout: layout, data: data, icon: nil, options: options)
        }
        UsageFormatter.setLocaleProvider { codexBarLocalizedLocale() }
        let changedLanguage = CodexBarLocalizationOverride.$appLanguage.withValue("uk") {
            renderer.render(layout: layout, data: data, icon: nil, options: options)
        }
        let changedLanguageLabel = CodexBarLocalizationOverride.$appLanguage.withValue("uk") {
            renderer.render(layout: localizedLabelLayout, data: data, icon: nil, options: options)
        }
        let ukrainianSessionAccessibility = CodexBarLocalizationOverride.$appLanguage.withValue("uk") {
            L("%@ %@", L("Session"), "25%")
        }

        #expect(first.attributedTitle.string == "first: in 2h")
        #expect(changedProvider.attributedTitle.string == "second: in 2h")
        #expect(changedLocale.attributedTitle !== changedProvider.attributedTitle)
        #expect(changedLanguage.attributedTitle.string == "second: через 2 год")
        #expect(firstLabel.accessibilityLabel == englishSessionAccessibility)
        #expect(changedProviderLabel.attributedTitle !== firstLabel.attributedTitle)
        #expect(changedLanguageLabel.accessibilityLabel == ukrainianSessionAccessibility)
        #expect(changedLanguageLabel.accessibilityLabel != firstLabel.accessibilityLabel)
        #expect(first.attributedTitle !== changedProvider.attributedTitle)
        #expect(changedProvider.attributedTitle !== changedLanguage.attributedTitle)
    }

    @Test
    @MainActor
    func `menu bar absolute reset cache rolls over at local midnight`() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let midnight = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let beforeMidnight = try #require(calendar.date(byAdding: .second, value: -60, to: midnight))
        let afterMidnight = try #require(calendar.date(byAdding: .minute, value: 1, to: midnight))
        let resetAt = try #require(calendar.date(byAdding: .hour, value: 2, to: midnight))
        let data = MenuBarLayoutRenderData(
            iconKey: "codex",
            providerName: "Codex",
            accountLabel: nil,
            laneLabels: MenuBarLayoutLaneLabels(provider: .codex, snapshot: nil),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            session: nil,
            weekly: nil,
            scopedWeekly: nil,
            scopedWeeklyTitle: nil,
            automatic: MenuBarLayoutRenderWindow(RateWindow(
                usedPercent: 50,
                windowMinutes: 300,
                resetsAt: resetAt,
                resetDescription: nil)),
            automaticText: nil,
            sessionPace: nil,
            weeklyPace: nil,
            automaticPace: nil,
            runsOut: nil,
            balance: nil,
            costToday: nil,
            cost30d: nil,
            metrics: .unavailable)
        let renderer = MenuBarLayoutRenderer()
        let layout = MenuBarLayout(lines: [[.resetAbsolute]])
        let before = renderer.render(
            layout: layout,
            data: data,
            icon: nil,
            options: MenuBarLayoutRenderOptions(
                size: .regular,
                highContrast: false,
                showUsed: true,
                conditionals: [],
                appearanceName: "aqua",
                isDebugApp: false,
                now: beforeMidnight))
        let after = renderer.render(
            layout: layout,
            data: data,
            icon: nil,
            options: MenuBarLayoutRenderOptions(
                size: .regular,
                highContrast: false,
                showUsed: true,
                conditionals: [],
                appearanceName: "aqua",
                isDebugApp: false,
                now: afterMidnight))

        #expect(before.attributedTitle.string != after.attributedTitle.string)
        #expect(before.attributedTitle !== after.attributedTitle)
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
        for (language, expectedRegen, expectedCountdown) in [
            ("zh-Hans", "2 小时后恢复", "2 小时后"),
            ("ja", "2時間後に再生成", "2時間後"),
            ("ko", "2시간 후에 재생성", "2시간 후"),
        ] {
            try CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                let detail = try #require(UsageMenuCardView.Model.syntheticRollingRegenDetail(
                    window: window, now: now, showUsed: true))
                #expect(detail.resetText == expectedRegen)
                let presentation = try #require(CodexResetCreditsPresentation.make(
                    snapshot: credits, resetStyle: .countdown, now: now))
                #expect(presentation.items.map(\.relativeExpiryText) == [expectedCountdown])
                let exact = CodexResetCreditsPresentation.exactExpiryTimeText(reset)
                #expect(presentation.items.map(\.exactTimeText) == [exact])
                #expect(presentation.items.map(\.expiryText) == [String(format: L("Expires %@"), exact)])
            }
        }
    }
}
