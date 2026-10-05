import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuBarExtraMetricPickerTests {
    @Test
    func `picker lists each provider owned named allowance`() {
        for descriptor in ProviderDescriptorRegistry.all {
            let labels = MenuBarPercentWindowPreference.available(for: descriptor.id)
                .map { $0.label(for: descriptor.id) }
            for title in descriptor.menuBarMetrics.namedExtras.values {
                #expect(labels.contains(L(title)))
            }
        }
        #expect(!MenuBarPercentWindowPreference.available(for: .codex)
            .map { $0.label(for: .codex) }.contains("Grok Bot"))
    }

    @Test
    @MainActor
    func `named allowance choice persists as a provider layout override`() throws {
        let settings = testSettingsStore(
            suiteName: "MenuBarExtraMetricPickerTests-persistence",
            userDefaults: InMemoryUserDefaults())
        settings.menuBarIconStyle = .iconAndPercent
        let original = MenuBarLayout(lines: [[
            .icon, .percent(window: .automatic), .balance, .windowResetCountdown(window: .weekly),
        ]])
        settings.setMenuBarLayout(original, for: nil)
        let view = ProviderMenuBarPercentWindowSettingsView(provider: .cursor, settings: settings)
        let picker = ProviderMenuBarPercentWindowPicker(
            provider: .cursor, iconStyle: .iconAndPercent, layout: view.layoutBinding)
        let extra = try #require(MenuBarPercentWindowPreference.available(for: .cursor)
            .first { $0.label(for: .cursor) == "Grok Bot" })

        picker.selectionBinding.wrappedValue = extra

        let expected = MenuBarLayout(lines: [[
            .icon, .extraPercent(id: "cursor-grok-bot"), .balance, .windowResetCountdown(window: .weekly),
        ]])
        #expect(settings.menuBarLayoutResolution(for: .cursor).layout == expected)
        #expect(settings.menuBarLayoutResolution(for: .claude).layout == original)
        #expect(picker.selectionBinding.wrappedValue == extra)
        #expect(MenuBarPercentWindowPreference.isVisible(
            iconStyle: .iconAndPercent, layout: expected, provider: .cursor))

        picker.selectionBinding.wrappedValue = .automatic
        #expect(settings.menuBarLayoutResolution(for: .cursor).layout == original)
    }

    @Test
    func `independent metrics remain under layout editor control`() throws {
        let cursorExtra = try #require(MenuBarPercentWindowPreference.available(for: .cursor)
            .first { $0.label(for: .cursor) == "Grok Bot" })
        let mixed = MenuBarLayout(lines: [[
            .percent(window: .session), .extraPercent(id: "cursor-grok-bot"),
        ]])
        #expect(MenuBarPercentWindowPreference.current(in: mixed) == .session)
        #expect(!MenuBarPercentWindowPreference.available(for: .cursor, layout: mixed).contains(cursorExtra))
        #expect(cursorExtra.applied(to: mixed) == mixed)
        #expect(MenuBarPercentWindowPreference.weekly.applied(to: mixed).lines == [[
            .percent(window: .weekly), .extraPercent(id: "cursor-grok-bot"),
        ]])

        let twoAntigravityExtras = MenuBarLayout(lines: [[
            .extraPercent(id: "antigravity-quota-summary-gemini-weekly"),
            .extraPercent(id: "antigravity-quota-summary-3p-weekly"),
        ]])
        #expect(MenuBarPercentWindowPreference.current(in: twoAntigravityExtras) == nil)
        #expect(MenuBarPercentWindowPreference.available(for: .antigravity, layout: twoAntigravityExtras).isEmpty)
        #expect(MenuBarPercentWindowPreference.automatic.applied(to: twoAntigravityExtras) == twoAntigravityExtras)
    }
}
