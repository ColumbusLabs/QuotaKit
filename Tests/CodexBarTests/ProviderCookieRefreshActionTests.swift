import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct ProviderCookieRefreshActionTests {
    @Test
    func `cache backed refresh requires a saved cookie even when another credential succeeds`() async {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let outcome = await CookieHeaderCache.withLegacyBaseURLOverrideForTesting(storage) {
            await ProviderCookieRefreshAction.refresh(provider: .opencode) { true }
        }
        #expect(outcome == .failed)
    }

    @Test
    func `validated nonpersistent plugin refresh succeeds without saving cookies`() async throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: #function)
        let implementation = try #require(ProviderCatalog.implementation(for: .lithosai))
        let picker = try #require(implementation.settingsPickers(
            context: fixture.settingsContext(provider: .lithosai)).first)
        let action = try #require(picker.trailingActions.first)
        fixture.store._test_providerRefreshOverride = { provider in
            CookieHeaderCache.markNonpersistentRefreshValidated(provider: provider)
            fixture.store.snapshots[provider.instanceID] = UsageSnapshot(
                primary: nil, secondary: nil, updatedAt: Date())
            fixture.store.lastSourceLabels[provider.instanceID] = "web"
        }
        defer { fixture.store._test_providerRefreshOverride = nil }
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        await CookieHeaderCache.withLegacyBaseURLOverrideForTesting(storage) {
            await action.perform()
            #expect(picker.trailingText?() != L("Failed"))
            #expect(CookieHeaderCache.load(provider: .lithosai) == nil)
        }
    }

    @Test
    func `Gemini app refresh accepts its source label and rejects the OAuth API`() async throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: #function)
        fixture.settings.updateProviderConfig(provider: .gemini) { $0.source = .web }
        let implementation = try #require(ProviderCatalog.implementation(for: .gemini))
        let picker = try #require(implementation.settingsPickers(
            context: fixture.settingsContext(provider: .gemini)).first { $0.id == "gemini-cookie-source" })
        let action = try #require(picker.trailingActions.first)
        #expect(picker.isVisible?() == true)
        #expect(action.isVisible?() == true)

        var sourceLabel = "Gemini app"
        var updatedAt = Date()
        fixture.store._test_providerRefreshOverride = { provider in
            CookieHeaderCache.markNonpersistentRefreshValidated(provider: provider)
            updatedAt.addTimeInterval(1)
            fixture.store.snapshots[provider.instanceID] = UsageSnapshot(
                primary: nil, secondary: nil, updatedAt: updatedAt)
            fixture.store.lastSourceLabels[provider.instanceID] = sourceLabel
        }
        defer { fixture.store._test_providerRefreshOverride = nil }
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        await CookieHeaderCache.withLegacyBaseURLOverrideForTesting(storage) {
            await action.perform()
            #expect(picker.trailingText?() != L("Failed"))
            #expect(CookieHeaderCache.load(provider: .gemini) == nil)

            sourceLabel = "oauth-api"
            await action.perform()
            #expect(picker.trailingText?() == L("Failed"))
            #expect(CookieHeaderCache.load(provider: .gemini) == nil)
        }
    }
}
