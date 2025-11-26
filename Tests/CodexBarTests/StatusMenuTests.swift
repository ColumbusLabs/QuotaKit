import AppKit
import Testing
@testable import CodexBar

@MainActor
@Suite
struct StatusMenuTests {
    @Test
    func remembersProviderWhenMenuOpens() {
        let settings = SettingsStore()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual

        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: false)
        }
        if let claudeMeta = registry.metadata[.claude] {
            settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: false)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection())

        let codexMenu = controller.makeMenu(for: .codex)
        controller.menuWillOpen(codexMenu)
        #expect(controller.lastMenuProvider == .codex)

        let claudeMenu = controller.makeMenu(for: .claude)
        controller.menuWillOpen(claudeMenu)
        #expect(controller.lastMenuProvider == .claude)

        // Unmapped menu falls back to the first enabled provider or Codex.
        let unmappedMenu = NSMenu()
        controller.menuWillOpen(unmappedMenu)
        #expect(controller.lastMenuProvider == .codex)
    }
}
