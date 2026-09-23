import AppKit
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

@Suite(.serialized)
struct KimiTokenAccountTests {
    private let ambient = [
        "KIMI_AUTH_TOKEN": "kimi-auth=ambient",
        "kimi_auth_token": "lowercase-ambient",
        "KIMI_MANUAL_COOKIE": "kimi-auth=manual-ambient",
        "KIMI_CODE_API_KEY": "api-ambient",
        "UNRELATED": "kept",
    ]

    private func account(_ token: String, label: String = "Fixture") -> ProviderTokenAccount {
        ProviderTokenAccount(id: UUID(), label: label, token: token, addedAt: 0, lastUsed: nil)
    }

    private func cli(region: KimiRegion = .china, accounts: [ProviderTokenAccount] = []) throws
        -> TokenAccountCLIContext
    {
        try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: true),
            config: CodexBarConfig(providers: [ProviderConfig(
                id: .kimi,
                apiKey: "configured-api",
                cookieHeader: "kimi-auth=configured-cookie",
                cookieSource: .off,
                region: region.rawValue,
                tokenAccounts: ProviderTokenAccountData(version: 1, accounts: accounts, activeIndex: 0))]),
            verbose: false,
            baseEnvironment: [:])
    }

    @Test(arguments: KimiRegion.allCases, [ProviderSourceMode.auto, .api, .web])
    func `CLI selects labeled web accounts with isolated credentials in the configured region`(
        region: KimiRegion, source: ProviderSourceMode) throws
    {
        let accounts = [
            self.account("eyJ.first.fixture", label: "Personal"),
            self.account("Cookie: kimi-auth=second; unrelated=value", label: "Work"),
        ]
        let cli = try self.cli(region: region, accounts: accounts)
        #expect(try cli.resolvedAccounts(for: .kimi).map(\.displayName) == ["Personal", "Work"])
        for (index, account) in accounts.enumerated() {
            let environment = cli.environment(base: self.ambient, provider: .kimi, account: account)
            #expect(environment == ["UNRELATED": "kept"])
            let snapshot = try #require(cli.settingsSnapshot(for: .kimi, account: account))
            #expect(snapshot.kimi?.region == region)
            #expect(snapshot.kimi?.cookieSource == .manual)
            let mode = cli.effectiveSourceMode(base: source, provider: .kimi, account: account)
            #expect(mode == .web)
            #expect(!CodexBarCLI.sourceModeRequiresWebSupport(
                mode, provider: .kimi, environment: environment, settings: snapshot))
            #expect(KimiCookieHeader.override(from: snapshot.kimi?.manualCookieHeader)?.token ==
                (index == 0 ? "eyJ.first.fixture" : "second"))
        }
        #expect(cli.effectiveSourceMode(base: source, provider: .kimi, account: nil) == source)
    }

    @Test(arguments: [ProviderSourceMode.auto, .web], [ProviderCookieSource.auto, .off])
    func `automatic Kimi cookies still require browser support`(
        source: ProviderSourceMode, cookies: ProviderCookieSource)
    {
        #expect(CodexBarCLI.sourceModeRequiresWebSupport(
            source,
            provider: .kimi,
            environment: ["KIMI_CODE_HOME": "/dev/null/quotakit-test-credentials"],
            settings: .make(kimi: .init(cookieSource: cookies, manualCookieHeader: nil))) == true)
    }

    @Test(arguments: KimiRegion.allCases)
    func `saved account cookies fetch usage in their configured region without discovery`(
        region: KimiRegion) async throws
    {
        let accounts = [self.account("kimi-auth=first"), self.account("kimi-auth=second")]
        let cli = try self.cli(region: region, accounts: accounts)
        let strategy = KimiWebFetchStrategy(
            fetchUsage: { token, selectedRegion in
                #expect(selectedRegion == region)
                #expect(["first", "second"].contains(token))
                return KimiUsageSnapshot(
                    weekly: .init(
                        limit: "100",
                        used: token == "first" ? "25" : "75",
                        remaining: nil,
                        resetTime: nil),
                    rateLimit: nil,
                    updatedAt: Date(timeIntervalSince1970: 100))
            },
            desktopToken: { _ in Issue.record("Unexpected desktop import"); return nil },
            browserTokens: { _ in Issue.record("Unexpected browser import"); return [] })
        for (index, account) in accounts.enumerated() {
            let snapshot = try #require(cli.settingsSnapshot(for: .kimi, account: account))
            let environment = cli.environment(base: self.ambient, provider: .kimi, account: account)
            let context = self.context(environment: environment, settings: snapshot)
            let result = try await strategy.fetch(context)
            #expect(result.usage.primary?.usedPercent == (index == 0 ? 25 : 75))
        }
    }

    @Test(arguments: ["Cookie: unrelated=value", "kimi-auth=expired"])
    func `invalid saved cookie fails without falling back to other credentials`(token: String) async throws {
        let account = self.account(token)
        let cli = try self.cli(accounts: [account])
        let settings = try #require(cli.settingsSnapshot(for: .kimi, account: account))
        let environment = cli.environment(base: self.ambient, provider: .kimi, account: account)
        let expectedToken = KimiCookieHeader.override(from: settings.kimi?.manualCookieHeader)?.token
        let strategy = KimiWebFetchStrategy(
            fetchUsage: { authToken, _ in
                #expect(authToken == expectedToken)
                throw KimiAPIError.invalidToken
            },
            desktopToken: { _ in Issue.record("Unexpected desktop import"); return nil },
            browserTokens: { _ in Issue.record("Unexpected browser import"); return [] })
        let context = self.context(environment: environment, settings: settings)
        #expect(await strategy.isAvailable(context) == (expectedToken != nil))
        do {
            _ = try await strategy.fetch(context)
            Issue.record("Expected saved credential failure")
        } catch KimiAPIError.invalidToken {
            #expect(expectedToken != nil)
            #expect(expectedToken == "expired")
            #expect(environment == ["UNRELATED": "kept"])
        } catch KimiAPIError.missingToken {
            #expect(expectedToken == nil)
            #expect(environment == ["UNRELATED": "kept"])
        }
    }

    @Test(arguments: [ProviderSourceMode.auto, .api, .web], [ProviderCookieSource.auto, .manual, .off])
    @MainActor
    func `app account snapshots keep region and preferences while overriding only the cookie`(
        source: ProviderSourceMode, cookies: ProviderCookieSource) throws
    {
        let settings = self.settings()
        settings.kimiRegion = .international
        settings.kimiUsageDataSource = source
        settings.kimiCookieSource = cookies
        settings.kimiManualCookieHeader = "kimi-auth=original"
        settings[providerConfig: .kimi, field: .apiKey] = "configured-api"
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            environmentBase: [:])
        let context = Self.settingsContext(settings: settings, store: store)
        let support = try #require(TokenAccountSupportCatalog.support(for: .kimi))
        #expect(settings.tokenAccounts(for: .kimi).isEmpty)
        #expect(KimiProviderImplementation().tokenAccountsVisibility(context: context, support: support))

        settings.addTokenAccount(provider: .kimi, label: "Personal", token: "eyJ.first.fixture")
        let first = try #require(settings.selectedTokenAccount(for: .kimi))
        settings.addTokenAccount(provider: .kimi, label: "Work", token: "kimi-auth=second")
        let second = try #require(settings.selectedTokenAccount(for: .kimi))
        #expect(KimiProviderImplementation().tokenAccountsVisibility(context: context, support: support))

        for account in [first, second] {
            let override = TokenAccountOverride(provider: .kimi, account: account)
            let contribution = try #require(KimiProviderImplementation().settingsSnapshot(context: .init(
                settings: settings,
                tokenOverride: override)))
            let snapshot = ProviderSettingsSnapshot(contributions: [contribution])
            #expect(snapshot.kimi?.region == .international)
            #expect(snapshot.kimi?.cookieSource == .manual)
            #expect(snapshot.kimi?.manualCookieHeader == (account.id == first.id
                    ? "kimi-auth=eyJ.first.fixture" : "kimi-auth=second"))
            #expect(ProviderRegistry.resolvedSourceMode(provider: .kimi, settings: settings, account: account) == .web)
            #expect(ProviderRegistry.makeEnvironment(
                base: self.ambient,
                provider: .kimi,
                settings: settings,
                tokenOverride: override) == ["UNRELATED": "kept"])
        }

        #expect(settings.kimiUsageDataSource == source)
        #expect(settings.kimiCookieSource == cookies)
        #expect(settings.kimiManualCookieHeader == "kimi-auth=original")

        settings.removeTokenAccount(provider: .kimi, accountID: first.id)
        settings.removeTokenAccount(provider: .kimi, accountID: second.id)
        #expect(settings.tokenAccounts(for: .kimi).isEmpty)
        #expect(settings.kimiUsageDataSource == source)
        #expect(settings.kimiCookieSource == cookies)
        #expect(settings.kimiManualCookieHeader == "kimi-auth=original")
    }

    @MainActor
    private func settings() -> SettingsStore {
        let settings = testSettingsStore(suiteName: "KimiTokenAccountTests-\(UUID().uuidString)")
        settings.configFileWatcher?.stop()
        return settings
    }

    @MainActor
    private static func settingsContext(settings: SettingsStore, store: UsageStore) -> ProviderSettingsContext {
        ProviderSettingsContext(
            provider: .kimi,
            settings: settings,
            store: store,
            boolBinding: { keyPath in
                Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
            },
            stringBinding: { keyPath in
                Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
            },
            statusText: { _ in nil },
            setStatusText: { _, _ in },
            lastAppActiveRunAt: { _ in nil },
            setLastAppActiveRunAt: { _, _ in },
            requestConfirmation: { _ in })
    }

    private func context(
        environment: [String: String],
        settings: ProviderSettingsSnapshot) -> ProviderFetchContext
    {
        ProviderFetchContext(
            runtime: .cli,
            sourceMode: .web,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: settings,
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: KimiTokenAccountClaudeStub(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }
}

private struct KimiTokenAccountClaudeStub: ClaudeUsageFetching {
    func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
        throw ClaudeUsageError.parseFailed("fixture")
    }

    func debugRawProbe(model _: String) async -> String {
        "fixture"
    }

    func detectVersion() -> String? {
        nil
    }
}
