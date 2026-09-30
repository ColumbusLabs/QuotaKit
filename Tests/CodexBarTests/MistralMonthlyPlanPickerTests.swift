import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct MistralMonthlyPlanPickerTests {
    @Test
    func `picker stores Monthly Plan while explicit layout windows remain authoritative`() {
        let settings = testSettingsStore(
            suiteName: "MistralMonthlyPlanPickerTests-metric-persistence",
            userDefaults: InMemoryUserDefaults())
        let automatic = MenuBarLayout(lines: [[.icon, .percent(window: .automatic)]])
        settings.setMenuBarLayout(automatic, for: nil)
        let view = ProviderMenuBarPercentWindowSettingsView(provider: .mistral, settings: settings)
        let picker = ProviderMenuBarPercentWindowPicker(
            provider: .mistral,
            iconStyle: .iconAndPercent,
            layout: view.layoutBinding,
            metric: view.metricBinding)

        #expect(MenuBarPercentWindowPreference.monthlyPlan.label(for: .mistral) == L("metric_mistral_monthly_plan"))
        #expect(picker.selectionBinding.wrappedValue == .automatic)
        picker.selectionBinding.wrappedValue = .monthlyPlan
        #expect(settings.menuBarMetricPreference(for: .mistral) == .monthlyPlan)
        #expect(settings.menuBarLayout(for: .mistral) == automatic)
        #expect(picker.selectionBinding.wrappedValue == .monthlyPlan)

        let includedAPI = MenuBarLayout(lines: [[.icon, .percent(window: .session)]])
        settings.setMenuBarLayout(includedAPI, for: .mistral)
        #expect(picker.selectionBinding.wrappedValue == .session)
        #expect(settings.menuBarMetricPreference(for: .mistral) == .monthlyPlan)
        #expect(settings.menuBarLayout(for: .mistral) == includedAPI)

        picker.selectionBinding.wrappedValue = .monthlyPlan
        #expect(settings.menuBarMetricPreference(for: .mistral) == .monthlyPlan)
        #expect(settings.menuBarLayout(for: .mistral) == MenuBarLayout(lines: [[
            .icon,
            .percent(window: .automatic),
        ]]))
        picker.selectionBinding.wrappedValue = .automatic
        #expect(settings.menuBarMetricPreference(for: .mistral) == .automatic)
        #expect(picker.selectionBinding.wrappedValue == .automatic)
    }

    @Test
    func `icon-only layout changes only the metric and creates no provider layout override`() {
        let settings = testSettingsStore(
            suiteName: "MistralMonthlyPlanPickerTests-icon-only",
            userDefaults: InMemoryUserDefaults())
        let iconOnly = MenuBarLayout(lines: [[.icon]])
        settings.menuBarIconStyle = .critters
        settings.setMenuBarLayout(iconOnly, for: nil)
        let view = ProviderMenuBarPercentWindowSettingsView(provider: .mistral, settings: settings)
        let picker = ProviderMenuBarPercentWindowPicker(
            provider: .mistral,
            iconStyle: settings.menuBarIconStyle,
            layout: view.layoutBinding,
            metric: view.metricBinding)

        #expect(MenuBarPercentWindowPreference.available(for: .mistral, layout: iconOnly) == [.automatic, .monthlyPlan])
        #expect(picker.selectionBinding.wrappedValue == .automatic)
        #expect(settings.menuBarLayoutOverrides[.mistral] == nil)

        picker.selectionBinding.wrappedValue = .monthlyPlan
        #expect(settings.menuBarMetricPreference(for: .mistral) == .monthlyPlan)
        #expect(settings.menuBarLayoutOverrides[.mistral] == nil)
        #expect(settings.menuBarLayout(for: .mistral) == iconOnly)

        // Window choices are not offered when there is no percent token and cannot rewrite layout.
        picker.selectionBinding.wrappedValue = .session
        #expect(settings.menuBarMetricPreference(for: .mistral) == .monthlyPlan)
        picker.selectionBinding.wrappedValue = .automatic
        #expect(settings.menuBarMetricPreference(for: .mistral) == .automatic)
        #expect(settings.menuBarLayoutOverrides[.mistral] == nil)
        #expect(settings.menuBarLayout(for: .mistral) == iconOnly)
    }

    @Test
    func `mixed window layouts retain Custom selection and stored metric`() {
        let settings = testSettingsStore(
            suiteName: "MistralMonthlyPlanPickerTests-custom",
            userDefaults: InMemoryUserDefaults())
        let mixed = MenuBarLayout(lines: [[
            .icon,
            .percent(window: .session),
            .separatorDot,
            .percent(window: .weekly),
            .runsOut,
        ]])
        settings.setMenuBarMetricPreference(.monthlyPlan, for: .mistral)
        settings.setMenuBarLayout(mixed, for: .mistral)
        let view = ProviderMenuBarPercentWindowSettingsView(provider: .mistral, settings: settings)
        let picker = ProviderMenuBarPercentWindowPicker(
            provider: .mistral,
            iconStyle: .iconAndPercent,
            layout: view.layoutBinding,
            metric: view.metricBinding)

        #expect(picker.selectionBinding.wrappedValue == nil)
        #expect(settings.menuBarMetricPreference(for: .mistral) == .monthlyPlan)
        #expect(settings.menuBarLayout(for: .mistral) == mixed)
    }
}
