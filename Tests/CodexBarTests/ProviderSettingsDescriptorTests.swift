import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct ProviderSettingsDescriptorTests {
    @Test
    func `toggle identifiers are unique across supported providers`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-toggle-ids")
        var seen: Set<String> = []

        for implementation in ProviderCatalog.all {
            for toggle in implementation
                .settingsToggles(context: fixture.settingsContext(provider: implementation.id))
            {
                #expect(seen.insert(toggle.id).inserted, "Duplicate toggle ID: \(toggle.id)")
            }
        }
    }

    @Test
    func `Codex exposes OpenAI web controls as opt in`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-codex-openai-toggle")
        let toggles = CodexProviderImplementation().settingsToggles(
            context: fixture.settingsContext(provider: .codex))
        let extras = try #require(toggles.first(where: { $0.id == "codex-openai-web-extras" }))
        let batterySaver = try #require(toggles.first(where: { $0.id == "codex-openai-web-battery-saver" }))

        #expect(extras.binding.wrappedValue == false)
        #expect(batterySaver.isVisible?() == false)
        fixture.settings.openAIWebAccessEnabled = true
        #expect(batterySaver.isVisible?() == true)
    }

    @Test
    func `Claude exposes usage cookie and keychain policy pickers`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-claude")
        fixture.settings.debugDisableKeychainAccess = false
        let pickers = ClaudeProviderImplementation().settingsPickers(
            context: fixture.settingsContext(provider: .claude))

        #expect(pickers.contains(where: { $0.id == "claude-usage-source" }))
        #expect(pickers.contains(where: { $0.id == "claude-cookie-source" }))
        let keychain = try #require(pickers.first(where: { $0.id == "claude-keychain-prompt-policy" }))
        #expect(Set(keychain.options.map(\.id)) == Set(ClaudeOAuthKeychainPromptMode.allCases.map(\.rawValue)))
    }

    @Test
    func `Claude single account swap toggle follows integration visibility and persists`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-claude-swap")
        let toggles = ClaudeProviderImplementation().settingsToggles(
            context: fixture.settingsContext(provider: .claude))
        let singleAccount = try #require(toggles.first(where: { $0.id == "claude-swap-show-single-account" }))

        #expect(singleAccount.isVisible?() == false)
        fixture.settings.claudeSwapEnabled = true
        #expect(singleAccount.isVisible?() == true)
        singleAccount.binding.wrappedValue = true
        #expect(fixture.settings.claudeSwapShowSingleAccount)
        #expect(fixture.settings.providerConfig(for: .claude)?.claudeSwapShowSingleAccount == true)
    }

    @Test
    func `Claude web extras disable when leaving CLI source`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-claude-invariant")
        fixture.settings.debugMenuEnabled = true
        fixture.settings.claudeUsageDataSource = .cli
        fixture.settings.claudeWebExtrasEnabled = true

        fixture.settings.claudeUsageDataSource = .oauth

        #expect(fixture.settings.claudeWebExtrasEnabled == false)
    }

    @Test
    func `Cursor exposes auto and api source plus cookie source`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-cursor")
        let pickers = CursorProviderImplementation().settingsPickers(
            context: fixture.settingsContext(provider: .cursor))
        let usage = try #require(pickers.first(where: { $0.id == "cursor-usage-source" }))

        #expect(pickers.contains(where: { $0.id == "cursor-cookie-source" }))
        #expect(usage.options.map(\.id) == [ProviderSourceMode.auto.rawValue, ProviderSourceMode.api.rawValue])
        usage.binding.wrappedValue = ProviderSourceMode.api.rawValue
        #expect(fixture.settings.cursorUsageDataSource == .api)
    }

    private func makeSettingsFixture(suite: String) throws -> ProviderSettingsFixture {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(userDefaults: defaults, configStore: testConfigStore(suiteName: suite))
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            environmentBase: [:])
        return ProviderSettingsFixture(settings: settings, store: store)
    }

    private struct ProviderSettingsFixture {
        let settings: SettingsStore
        let store: UsageStore
        private let state = ProviderSettingsContextState()

        @MainActor
        func settingsContext(provider: UsageProvider) -> ProviderSettingsContext {
            let settings = self.settings
            let state = self.state
            return ProviderSettingsContext(
                provider: provider,
                settings: settings,
                store: self.store,
                boolBinding: { keyPath in
                    Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
                },
                stringBinding: { keyPath in
                    Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
                },
                statusText: { state.statusByID[$0] },
                setStatusText: { id, text in state.statusByID[id] = text },
                lastAppActiveRunAt: { state.lastRunAtByID[$0] },
                setLastAppActiveRunAt: { id, date in state.lastRunAtByID[id] = date },
                requestConfirmation: { _ in },
                runLoginFlow: {})
        }
    }

    private final class ProviderSettingsContextState {
        var statusByID: [String: String] = [:]
        var lastRunAtByID: [String: Date] = [:]
    }
}
