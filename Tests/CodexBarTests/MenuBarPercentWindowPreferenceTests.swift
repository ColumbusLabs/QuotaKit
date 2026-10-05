import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuBarPercentWindowPreferenceTests {
    @Test
    func `a uniform layout maps to a single preference`() {
        #expect(MenuBarPercentWindowPreference.current(
            in: MenuBarLayout(lines: [[.icon, .percent(window: .automatic)]])) == .automatic)
        #expect(MenuBarPercentWindowPreference.current(
            in: MenuBarLayout(lines: [[.icon, .percent(window: .weekly)]])) == .weekly)
        // Repeated percents that agree still map to one option.
        #expect(MenuBarPercentWindowPreference.current(in: MenuBarLayout(lines: [
            [.icon, .percent(window: .session)],
            [.percent(window: .session)],
        ])) == .session)
    }

    @Test
    func `mixed or absent percents have no single preference`() {
        // Session · Weekly is only describable in the layout editor.
        #expect(MenuBarPercentWindowPreference.current(in: MenuBarLayout(lines: [[
            .icon,
            .percent(window: .session),
            .separatorDot,
            .percent(window: .weekly),
        ]])) == nil)

        let iconOnly = MenuBarLayout(lines: [[.icon]])
        #expect(MenuBarPercentWindowPreference.current(in: iconOnly) == nil)
        #expect(MenuBarPercentWindowPreference.hasPercentToken(in: iconOnly) == false)
        #expect(MenuBarPercentWindowPreference.hasPercentToken(
            in: MenuBarLayout(lines: [[.icon, .percent(window: .weekly)]])))
    }

    @Test
    func `stored Monthly Plan follows automatic layouts but not explicit or mixed windows`() {
        let iconOnly = MenuBarLayout(lines: [[.icon]])
        let automatic = MenuBarLayout(lines: [[.icon, .percent(window: .automatic)]])
        let session = MenuBarLayout(lines: [[.icon, .percent(window: .session)]])
        let mixed = MenuBarLayout(lines: [[
            .icon,
            .percent(window: .session),
            .separatorDot,
            .percent(window: .weekly),
        ]])

        #expect(MenuBarPercentWindowPreference.current(in: iconOnly, metric: .monthlyPlan) == .monthlyPlan)
        #expect(MenuBarPercentWindowPreference.current(in: automatic, metric: .monthlyPlan) == .monthlyPlan)
        #expect(MenuBarPercentWindowPreference.current(in: session, metric: .monthlyPlan) == .session)
        #expect(MenuBarPercentWindowPreference.current(in: mixed, metric: .monthlyPlan) == nil)
        #expect(MenuBarPercentWindowPreference.current(in: iconOnly) == nil)
    }

    @Test
    func `applying a preference rewrites only the percent tokens`() {
        let layout = MenuBarLayout(lines: [
            [.icon, .percent(window: .weekly), .separatorDot, .runsOut],
            [.percent(window: .automatic), .costToday],
        ])

        let session = MenuBarPercentWindowPreference.session.applied(to: layout)

        #expect(session.lines == [
            [.icon, .percent(window: .session), .separatorDot, .runsOut],
            [.percent(window: .session), .costToday],
        ])
        #expect(MenuBarPercentWindowPreference.current(in: session) == .session)
    }

    @Test
    func `switching between preferences round-trips`() {
        let original = MenuBarLayout(lines: [[.icon, .percent(window: .automatic)]])

        let weekly = MenuBarPercentWindowPreference.weekly.applied(to: original)
        let backToAutomatic = MenuBarPercentWindowPreference.automatic.applied(to: weekly)

        #expect(backToAutomatic == original)
    }

    @Test
    func `picker stays hidden unless the global style is icon and percent`() {
        let layout = MenuBarLayout(lines: [[.icon, .percent(window: .automatic)]])
        let options = MenuBarPercentWindowPreference.standardChoices.filter { $0 != .monthlyPlan }

        #expect(MenuBarPercentWindowPreference.isVisible(
            iconStyle: .iconAndPercent,
            layout: layout,
            available: options))
        #expect(MenuBarPercentWindowPreference.isVisible(
            iconStyle: .critters,
            layout: layout,
            available: options) == false)
        #expect(MenuBarPercentWindowPreference.isVisible(
            iconStyle: .bars,
            layout: layout,
            available: options) == false)
        #expect(MenuBarPercentWindowPreference.isVisible(
            iconStyle: .iconAndPercent,
            layout: MenuBarLayout(lines: [[.icon]]),
            available: options) == false)
    }

    @Test
    func `picker hides when session and weekly cannot apply`() {
        let layout = MenuBarLayout(lines: [[.icon, .percent(window: .automatic)]])
        let automaticOnly = MenuBarPercentWindowPreference.available(
            metrics: ProviderMenuBarMetricCapabilities(supported: [.automatic]))

        #expect(automaticOnly == [.automatic])
        #expect(MenuBarPercentWindowPreference.isVisible(
            iconStyle: .iconAndPercent,
            layout: layout,
            available: automaticOnly) == false)
        #expect(MenuBarPercentWindowPreference.isVisible(
            iconStyle: .iconAndPercent,
            layout: layout,
            available: [.automatic, .session]))
    }

    @Test
    func `Monthly Plan stays available across icon styles without a percent token`() {
        let layout = MenuBarLayout(lines: [[.icon]])

        #expect(MenuBarPercentWindowPreference.available(for: .mistral, layout: layout) == [.automatic, .monthlyPlan])
        for iconStyle in MenuBarIconStyle.allCases {
            #expect(MenuBarPercentWindowPreference.isVisible(
                iconStyle: iconStyle,
                layout: layout,
                provider: .mistral))
            #expect(!MenuBarPercentWindowPreference.isVisible(
                iconStyle: iconStyle,
                layout: layout,
                provider: .codex))
        }
    }

    @Test
    func `available options follow provider percent-window capabilities`() {
        let mistralLike = ProviderMenuBarMetricCapabilities(supported: [.automatic, .monthlyPlan])
        #expect(MenuBarPercentWindowPreference.available(metrics: mistralLike) == [.automatic, .monthlyPlan])

        let sessionOnlyPrimary = ProviderMenuBarMetricCapabilities(supported: [.automatic, .primary])
        #expect(MenuBarPercentWindowPreference.available(metrics: sessionOnlyPrimary) == [.automatic, .session])

        let weeklyPrimary = ProviderMenuBarMetricCapabilities(supported: [.automatic, .primary])
        #expect(MenuBarPercentWindowPreference.available(
            metrics: weeklyPrimary,
            primarySemanticWindow: .weekly) == [.automatic, .weekly])

        #expect(MenuBarPercentWindowPreference.available(
            metrics: .standard) == [.automatic, .session, .weekly])
        #expect(MenuBarPercentWindowPreference.available(for: .mistral) == [.automatic, .session, .monthlyPlan])
        #expect(MenuBarPercentWindowPreference.available(for: .openrouter) == [.automatic, .session])
        #expect(MenuBarPercentWindowPreference.available(for: .codex) == [.automatic, .session, .weekly])
        #expect(MenuBarPercentWindowPreference.isVisible(
            iconStyle: .iconAndPercent,
            layout: MenuBarLayout(lines: [[.icon, .percent(window: .automatic)]]),
            provider: .mistral))
    }

    @Test
    @MainActor
    func `persisting a provider window does not flip the global icon style`() {
        let settings = testSettingsStore(
            suiteName: "MenuBarPercentWindowPreferenceTests-preserve-style")
        settings.menuBarIconStyle = .critters
        let layout = MenuBarLayout(lines: [[.icon, .percent(window: .automatic)]])
        settings.setMenuBarLayout(layout, for: .claude)

        MenuBarPercentWindowPreference.persist(
            .session,
            appliedTo: layout,
            for: .claude,
            settings: settings)

        #expect(settings.menuBarIconStyle == .critters)
        #expect(MenuBarPercentWindowPreference.current(in: settings.menuBarLayout(for: .claude)) == .session)
        #expect(settings.menuBarLayoutOverrides[.claude] == MenuBarLayout(lines: [[
            .icon,
            .percent(window: .session),
        ]]))
    }

    @Test
    @MainActor
    func `setting a provider metric rejects unsupported Monthly Plan`() {
        let settings = testSettingsStore(
            suiteName: "MenuBarPercentWindowPreferenceTests-unsupported-monthly-plan",
            userDefaults: InMemoryUserDefaults())

        settings.setMenuBarMetricPreference(.monthlyPlan, for: .codex)

        #expect(settings.menuBarMetricPreference(for: .codex) == .automatic)
        #expect(!MenuBarPercentWindowPreference.available(for: .codex).contains(.monthlyPlan))
    }
}
