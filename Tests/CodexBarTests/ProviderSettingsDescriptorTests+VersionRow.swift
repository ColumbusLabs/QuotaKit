import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Version-row regressions for web-only providers that have no version detector (#4769).
///
/// These providers used to leave `showsVersionInSettings` at its default, so the Settings card
/// rendered `Version: not detected` for a detection that never ran.
@MainActor
extension ProviderSettingsDescriptorTests {
    @Test
    func `cursor hides the unsupported version row while keeping its web source`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-cursor-version-row")
        let metadata = try #require(ProviderDescriptorRegistry.metadata[.cursor])
        let context = fixture.presentationContext(provider: .cursor, metadata: metadata)
        let implementation = try #require(ProviderCatalog.implementation(for: .cursor))

        let presentation = implementation.presentation(context: context)

        // Web-only source with versionDetector: nil — a Version row can only ever read "not detected".
        #expect(presentation.detailLine(context) == context.store.sourceLabel(for: .cursor))
        #expect(presentation.showsVersionInSettings == false)
        #expect(!ProviderPresentation.showsVersionRow(provider: .cursor, presentation: presentation))
    }

    @Test
    func `raycast hides the unsupported version row while keeping its web source`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-raycast-version-row")
        let metadata = try #require(ProviderDescriptorRegistry.metadata[.raycast])
        let context = fixture.presentationContext(provider: .raycast, metadata: metadata)
        let implementation = try #require(ProviderCatalog.implementation(for: .raycast))

        let presentation = implementation.presentation(context: context)

        // Bundled web-cookie plugin with versionDetector: nil — a Version row can only read "not detected".
        #expect(presentation.detailLine(context) == "web")
        #expect(presentation.showsVersionInSettings == false)
        #expect(!ProviderPresentation.showsVersionRow(provider: .raycast, presentation: presentation))
    }

    @Test
    func `cursor account controls remain visible for manual cookies or saved accounts`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-cursor-accounts")
        let context = fixture.settingsContext(provider: .cursor)
        let implementation = CursorProviderImplementation()
        let support = try #require(TokenAccountSupportCatalog.support(for: .cursor))
        fixture.settings.cursorCookieSource = .auto
        #expect(!implementation.tokenAccountsVisibility(context: context, support: support))
        fixture.settings.cursorCookieSource = .manual
        #expect(implementation.tokenAccountsVisibility(context: context, support: support))
        fixture.settings.addTokenAccount(provider: .cursor, label: "Fixture", token: "fixture-cookie")
        fixture.settings.cursorCookieSource = .auto
        #expect(implementation.tokenAccountsVisibility(context: context, support: support))
    }

    @Test
    func `version-capable providers keep the shared version row`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-version-row-control")
        for provider in [UsageProvider.codex, .gemini] {
            let metadata = try #require(ProviderDescriptorRegistry.metadata[provider])
            let context = fixture.presentationContext(provider: provider, metadata: metadata)
            let implementation = try #require(ProviderCatalog.implementation(for: provider))
            #expect(ProviderPresentation.showsVersionRow(
                provider: provider, presentation: implementation.presentation(context: context)))
        }
    }
}
