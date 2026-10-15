import CodexBarCore
import Foundation
import Observation
import Testing
@testable import CodexBar

@MainActor
struct MenuBarLayoutV5PersistenceTests {
    @Test
    func `monospaced digit preference refreshes menu observation`() async {
        let settings = testSettingsStore(suiteName: "layout-digit-observation", userDefaults: InMemoryUserDefaults())
        await confirmation { changed in
            withObservationTracking {
                _ = settings.menuObservationToken
            } onChange: {
                changed()
            }
            settings.menuBarLayoutMonospacedDigits = true
        }
    }

    @Test
    func `typography preferences preserve every saved layout generation`() {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: "typography-generations", userDefaults: defaults)
        #expect(settings.menuBarLayoutSize == .regular)
        #expect(!settings.menuBarLayoutMonospacedDigits)
        #expect(defaults.object(forKey: "menuBarLayoutMonospacedDigits") == nil)

        let layout = MenuBarLayout(lines: [[.icon, .progressBar(window: .session)]])
        var rule = MenuBarLayoutConditional.makeDefault()
        rule.thenToken = .progressBar(window: .session)
        settings.setMenuBarLayout(layout, for: nil)
        settings.setMenuBarLayout(layout, for: .codex)
        settings.menuBarLayoutConditionals = [rule]
        let keys = [
            MenuBarLayoutUserDefaultsKey.layoutCurrent,
            MenuBarLayoutUserDefaultsKey.layoutV4,
            MenuBarLayoutUserDefaultsKey.layoutV3,
            MenuBarLayoutUserDefaultsKey.layoutReleased,
            MenuBarLayoutUserDefaultsKey.layout,
            MenuBarLayoutUserDefaultsKey.overridesCurrent,
            MenuBarLayoutUserDefaultsKey.overridesV4,
            MenuBarLayoutUserDefaultsKey.overridesV3,
            MenuBarLayoutUserDefaultsKey.overridesReleased,
            MenuBarLayoutUserDefaultsKey.overrides,
            MenuBarLayoutUserDefaultsKey.conditionalsCurrent,
            MenuBarLayoutUserDefaultsKey.conditionalsV4,
            MenuBarLayoutUserDefaultsKey.conditionalsV3,
            MenuBarLayoutUserDefaultsKey.conditionalsReleased,
            MenuBarLayoutUserDefaultsKey.conditionals,
        ]
        let before = keys.map { defaults.data(forKey: $0) }
        #expect(before.allSatisfy { $0 != nil })

        settings.menuBarLayoutSize = .large
        settings.menuBarLayoutMonospacedDigits = true
        #expect(keys.map { defaults.data(forKey: $0) } == before)

        let returned = testSettingsStore(suiteName: "typography-generations-return", userDefaults: defaults)
        #expect(returned.menuBarLayout == layout)
        #expect(returned.menuBarLayoutOverrides[.codex] == layout)
        #expect(returned.menuBarLayoutSize == .large)
        #expect(returned.menuBarLayoutMonospacedDigits)
    }

    @Test
    func `V4 downgrade and reupgrade preserve bars while older edits win`() throws {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: "progress-generation", userDefaults: defaults)
        let layout = MenuBarLayout(lines: [
            [.icon, .progressBar(window: .session), .extraPercent(id: "cursor-grok-bot")],
            [.progressBar(window: .weekly)],
        ])
        let projected = MenuBarLayout(lines: [
            [.icon, .percent(window: .session), .extraPercent(id: "cursor-grok-bot")],
            [.percent(window: .weekly)],
        ])
        var rule = MenuBarLayoutConditional.makeDefault()
        rule.thenToken = .progressBar(window: .scopedWeekly)
        settings.setMenuBarLayout(layout, for: nil)
        settings.setMenuBarLayout(layout, for: .codex)
        settings.setMenuBarLayout(layout, for: .claude)
        settings.menuBarLayoutConditionals = [rule]
        let decoder = JSONDecoder()
        let full = try #require(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.layoutCurrent))
        let fullRules = try #require(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.conditionalsCurrent))

        // A frozen strict decoder rejects any discriminator unknown to the V4 app.
        let v4 = try #require(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.layoutV4))
        let strict = try decoder.decode(V4Layout.self, from: v4)
        #expect(strict.lines == [
            [.icon, .percent(window: .session), .extraPercent(id: "cursor-grok-bot")],
            [.percent(window: .weekly)],
        ])
        let v3Layout = try decoder.decode(
            V3Layout.self,
            from: #require(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.layoutV3)))
        #expect(v3Layout.lines == [
            [.icon, .percent(window: .session)],
            [.percent(window: .weekly)],
        ])
        let releasedLayout = try decoder.decode(
            V3Layout.self,
            from: #require(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.layoutReleased)))
        #expect(releasedLayout == v3Layout)
        let overrides = try decoder.decode(
            [String: V4Layout].self,
            from: #require(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.overridesV4)))
        #expect(overrides[UsageProvider.codex.rawValue] == strict)
        let strictRules = try decoder.decode(
            [V4Rule].self,
            from: #require(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.conditionalsV4)))
        #expect(strictRules.first?.thenToken == .percent(window: .scopedWeekly))

        // A V4 app writes its current schema and older projections, leaving unknown V5 keys untouched.
        var olderRule = rule
        olderRule.thenToken = .percent(window: .scopedWeekly)
        try self.saveV4(
            layout: projected,
            overrides: [UsageProvider.codex.rawValue: projected, UsageProvider.claude.rawValue: projected],
            rules: [olderRule],
            defaults: defaults)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.layoutCurrent) == full)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.conditionalsCurrent) == fullRules)
        let returned = testSettingsStore(suiteName: "progress-return", userDefaults: defaults)
        #expect(returned.menuBarLayout == layout)
        #expect(returned.menuBarLayoutOverrides[.codex] == layout)
        #expect(returned.menuBarLayoutConditionals == [rule])

        let edited = MenuBarLayout(lines: [[.usageBar]])
        olderRule.thenToken = .usageBar
        try self.saveV4(
            layout: edited,
            overrides: [UsageProvider.codex.rawValue: edited, UsageProvider.claude.rawValue: projected],
            rules: [olderRule],
            defaults: defaults)
        let editedReturn = testSettingsStore(suiteName: "progress-edited-return", userDefaults: defaults)
        #expect(editedReturn.menuBarLayout == edited)
        #expect(editedReturn.menuBarLayoutOverrides[.codex] == edited)
        #expect(editedReturn.menuBarLayoutOverrides[.claude] == layout)
        #expect(editedReturn.menuBarLayoutConditionals == [olderRule])
    }

    @Test
    func `V4 data takes precedence over V3 while preserving reset tokens`() throws {
        let defaults = InMemoryUserDefaults()
        let layout = MenuBarLayout(lines: [[.icon, .separatorDot, .windowResetCountdown(window: .session)]])
        let historical = MenuBarLayout(lines: [[.icon, .separatorDot]])
        for (key, value) in [
            (MenuBarLayoutUserDefaultsKey.layoutV4, layout),
            (MenuBarLayoutUserDefaultsKey.layoutV3, historical),
            (MenuBarLayoutUserDefaultsKey.layoutReleased, historical),
            (MenuBarLayoutUserDefaultsKey.layout, historical),
        ] {
            try defaults.set(JSONEncoder().encode(value), forKey: key)
        }

        let returned = testSettingsStore(suiteName: "historical-separators", userDefaults: defaults)
        #expect(returned.menuBarLayout == layout)
    }

    private func saveV4(
        layout: MenuBarLayout,
        overrides: [String: MenuBarLayout],
        rules: [MenuBarLayoutConditional],
        defaults: UserDefaults) throws
    {
        let layoutBlobs = try MenuBarLayoutPersistence.encoded(layout)
        let overrideBlobs = try MenuBarLayoutPersistence.encodedOverrides(overrides)
        let ruleBlobs = try MenuBarLayoutPersistence.encodedLibrary(rules)
        for (prefix, blobs) in [
            ("menuBarLayout", layoutBlobs),
            ("menuBarLayoutOverrides", overrideBlobs),
            ("menuBarLayoutConditionals", ruleBlobs),
        ] {
            defaults.set(blobs.current, forKey: prefix + "V4")
            defaults.set(blobs.v3, forKey: prefix + "V3")
            defaults.set(blobs.released, forKey: prefix + "V2")
            defaults.set(blobs.legacy, forKey: prefix)
        }
    }
}

private enum V4Token: Codable, Equatable {
    case icon
    case percent(window: PercentWindow)
    case usageBar
    case extraPercent(id: String)
    case hidden
}

private struct V4Layout: Decodable, Equatable {
    let lines: [[V4Token]]
}

private enum V3Token: Codable, Equatable {
    case icon
    case percent(window: PercentWindow)
}

private struct V3Layout: Decodable, Equatable {
    let lines: [[V3Token]]
}

private struct V4Rule: Decodable {
    let thenToken: V4Token
    let elseToken: V4Token
}
