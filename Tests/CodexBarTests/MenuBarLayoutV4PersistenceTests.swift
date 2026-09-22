import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuBarLayoutV4PersistenceTests {
    @Test
    func `V4 named extras are omitted from V3 and V2 projections`() throws {
        let layout = MenuBarLayout(lines: [[
            .icon,
            .percent(window: .weekly),
            .extraPercent(id: "cursor-grok-bot"),
        ]])
        let blobs = try MenuBarLayoutPersistence.encoded(layout)
        let decoder = JSONDecoder()

        #expect(try decoder.decode(MenuBarLayout.self, from: blobs.current) == layout)
        #expect(try decoder.decode(PreExtraMenuBarLayout.self, from: blobs.v3)
            == PreExtraMenuBarLayout(lines: [[.icon, .percent(window: .weekly)]]))
        #expect(try decoder.decode(PreExtraMenuBarLayout.self, from: blobs.released)
            == PreExtraMenuBarLayout(lines: [[.icon, .percent(window: .weekly)]]))
        #expect(throws: DecodingError.self) {
            try decoder.decode(PreExtraMenuBarLayout.self, from: blobs.current)
        }
    }

    @Test
    func `startup migration materializes V4 while preserving existing V2 layouts`() throws {
        let suiteName = "MenuBarLayoutV4PersistenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let oldLayout = MenuBarLayout(lines: [[.icon, .lanePercent(lane: .primary)]])
        let oldOverrides = ["cursor": oldLayout]
        let oldLibrary = [Self.conditional(name: "Older rule", thenToken: .percent(window: .weekly))]
        let layout = MenuBarLayoutPersistence.loadLayout(
            current: nil,
            v3: nil,
            released: oldLayout,
            legacy: oldLayout.legacyCompatible(),
            into: defaults)
        let overrides = MenuBarLayoutPersistence.loadOverrides(
            current: nil,
            v3: nil,
            released: oldOverrides,
            legacy: oldOverrides.mapValues { $0.legacyCompatible(for: .cursor) },
            into: defaults)
        let library = MenuBarLayoutPersistence.loadLibrary(
            current: nil,
            v3: nil,
            released: oldLibrary,
            legacy: MenuBarLayoutPersistence.legacyCompatibleLibrary(oldLibrary),
            into: defaults)

        #expect(layout == oldLayout)
        #expect(overrides == oldOverrides)
        #expect(library == oldLibrary)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.layoutCurrent) != nil)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.layoutV3) != nil)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.layoutReleased) != nil)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.overridesCurrent) != nil)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.overridesV3) != nil)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.overridesReleased) != nil)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.conditionalsCurrent) != nil)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.conditionalsV3) != nil)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.conditionalsReleased) != nil)
    }

    @Test
    func `V3-only startup migration materializes V4 layout overrides and conditionals`() throws {
        let suiteName = "MenuBarLayoutV4V3MigrationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let layout = MenuBarLayout(lines: [[.icon, .percent(window: .weekly)]])
        let overrides = ["cursor": layout]
        let library = [Self.conditional(name: "V3 rule", thenToken: .percent(window: .weekly))]

        #expect(MenuBarLayoutPersistence.loadLayout(
            current: nil,
            v3: layout,
            released: nil,
            legacy: nil,
            into: defaults) == layout)
        #expect(MenuBarLayoutPersistence.loadOverrides(
            current: nil,
            v3: overrides,
            released: nil,
            legacy: nil,
            into: defaults) == overrides)
        #expect(MenuBarLayoutPersistence.loadLibrary(
            current: nil,
            v3: library,
            released: nil,
            legacy: nil,
            into: defaults) == library)

        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.layoutCurrent) != nil)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.overridesCurrent) != nil)
        #expect(defaults.data(forKey: MenuBarLayoutUserDefaultsKey.conditionalsCurrent) != nil)
    }

    @Test
    func `unchanged V3 projections retain V4 layouts and overrides`() {
        let full = MenuBarLayout(lines: [[
            .icon,
            .percent(window: .weekly),
            .extraPercent(id: "cursor-grok-bot"),
        ]])

        #expect(MenuBarLayoutPersistence.preferredLayout(
            current: full,
            v3: full.v3Compatible(),
            released: full.releasedCompatible(),
            legacy: full.legacyCompatible()) == full)
        #expect(MenuBarLayoutPersistence.preferredOverrides(
            current: ["cursor": full],
            v3: ["cursor": full.v3Compatible()],
            released: ["cursor": full.releasedCompatible()],
            legacy: ["cursor": full.legacyCompatible(for: .cursor)]) == ["cursor": full])
    }

    @Test
    func `V3 edits win and unrelated V4-only conditionals survive`() {
        let full = MenuBarLayout(lines: [[
            .icon,
            .percent(window: .weekly),
            .extraPercent(id: "cursor-grok-bot"),
        ]])
        let olderEdit = MenuBarLayout(lines: [[.icon, .percent(window: .session)]])
        #expect(MenuBarLayoutPersistence.preferredLayout(
            current: full,
            v3: olderEdit,
            released: olderEdit,
            legacy: olderEdit.legacyCompatible()) == olderEdit)
        #expect(MenuBarLayoutPersistence.preferredOverrides(
            current: ["cursor": full, "claude": full],
            v3: ["cursor": olderEdit],
            released: ["cursor": olderEdit],
            legacy: ["cursor": olderEdit.legacyCompatible(for: .cursor)]) == ["cursor": olderEdit])

        let readable = Self.conditional(name: "Readable", thenToken: .percent(window: .weekly))
        let namedExtra = Self.conditional(
            name: "Grok Bot",
            thenToken: .extraPercent(id: "cursor-grok-bot"))
        let olderConditionalEdit = Self.conditional(
            id: readable.id,
            name: "Edited in V3",
            thenToken: .percent(window: .session))
        let merged = MenuBarLayoutPersistence.preferredLibrary(
            current: [readable, namedExtra],
            v3: [olderConditionalEdit],
            released: [olderConditionalEdit],
            legacy: MenuBarLayoutPersistence.legacyCompatibleLibrary([olderConditionalEdit]))

        #expect(merged == [olderConditionalEdit, namedExtra])
        #expect(MenuBarLayoutPersistence.preferredLibrary(
            current: [readable, namedExtra],
            v3: [],
            released: [],
            legacy: []) == [])
    }

    private static func conditional(
        id: UUID = UUID(),
        name: String,
        thenToken: MenuBarLayoutToken) -> MenuBarLayoutConditional
    {
        MenuBarLayoutConditional(
            id: id,
            name: name,
            clauses: [MenuBarConditionalClause(
                combinator: nil,
                predicate: MenuBarConditionalPredicate(
                    metric: .session,
                    comparison: .greaterThan,
                    threshold: 50))],
            thenToken: thenToken,
            elseToken: .hidden)
    }
}

private enum PreExtraMenuBarLayoutToken: Codable, Equatable {
    case icon
    case percent(window: PercentWindow)
}

private struct PreExtraMenuBarLayout: Codable, Equatable {
    let lines: [[PreExtraMenuBarLayoutToken]]
}
