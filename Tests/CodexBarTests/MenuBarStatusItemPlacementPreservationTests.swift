import AppKit
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct MenuBarStatusItemPlacementPreservationTests {
    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "MenuBarStatusItemPlacementPreservationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func clearDefaults(_ fixture: (defaults: UserDefaults, suiteName: String)) {
        fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
    }

    @Test
    func `preserving preferred position restores a value the body cleared`() {
        let fixture = self.makeDefaults()
        defer { self.clearDefaults(fixture) }
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-claude")
        fixture.defaults.set(845.0, forKey: key)

        let result = MenuBarStatusItemPlacementPreservation.preservingPreferredPosition(
            autosaveName: "codexbar-claude",
            defaults: fixture.defaults)
        {
            fixture.defaults.removeObject(forKey: key)
            return "done"
        }

        #expect(result == "done")
        #expect(fixture.defaults.double(forKey: key) == 845)
    }

    @Test
    func `preserving preferred position leaves a missing value unset`() {
        let fixture = self.makeDefaults()
        defer { self.clearDefaults(fixture) }
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-claude")

        MenuBarStatusItemPlacementPreservation.preservingPreferredPosition(
            autosaveName: "codexbar-claude",
            defaults: fixture.defaults) {}

        #expect(fixture.defaults.object(forKey: key) == nil)
    }

    @Test
    func `preserving preferred position keeps a value the body rewrote`() {
        let fixture = self.makeDefaults()
        defer { self.clearDefaults(fixture) }
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "codexbar-claude")
        fixture.defaults.set(845.0, forKey: key)

        MenuBarStatusItemPlacementPreservation.preservingPreferredPosition(
            autosaveName: "codexbar-claude",
            defaults: fixture.defaults)
        {
            fixture.defaults.set(900.0, forKey: key)
        }

        #expect(fixture.defaults.double(forKey: key) == 900)
    }

    @Test
    func `preserving preferred position ignores empty autosave names`() {
        let fixture = self.makeDefaults()
        defer { self.clearDefaults(fixture) }
        let key = MenuBarStatusItemPlacementPreflight.preferredPositionKey(autosaveName: "")
        fixture.defaults.set(845.0, forKey: key)

        MenuBarStatusItemPlacementPreservation.preservingPreferredPosition(
            autosaveName: "",
            defaults: fixture.defaults)
        {
            fixture.defaults.removeObject(forKey: key)
        }

        #expect(fixture.defaults.object(forKey: key) == nil)
    }
}
