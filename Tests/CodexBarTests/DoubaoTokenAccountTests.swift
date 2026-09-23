import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

@Suite(.serialized)
struct DoubaoTokenAccountTests {
    private let accounts = ["Personal", "Work"].enumerated().map { index, label in
        ProviderTokenAccount(
            id: UUID(),
            label: label,
            token: "ark-\(label.lowercased())-fixture",
            addedAt: TimeInterval(index),
            lastUsed: nil)
    }

    private var ambientEnvironment: [String: String] {
        var environment = Dictionary(uniqueKeysWithValues: (
            DoubaoSettingsReader.apiKeyEnvironmentKeys +
                DoubaoSettingsReader.accessKeyIDEnvironmentKeys +
                DoubaoSettingsReader.secretAccessKeyEnvironmentKeys).map { ($0, "ambient-fixture") })
        environment["ARKCLI_PATH"] = "/synthetic/arkcli"
        environment["UNRELATED"] = "preserved"
        return environment
    }

    @Test @MainActor
    func `settings expose Ark key accounts and preserve legacy Doubao preferences`() throws {
        let settings = testSettingsStore(
            suiteName: "DoubaoTokenAccountTests-settings-\(UUID().uuidString)",
            tokenAccountStore: InMemoryTokenAccountStore())
        settings.configFileWatcher?.stop()
        settings.doubaoAPIToken = "AKLT-legacy-fixture"
        settings.doubaoSecretAccessKey = "legacy-secret-fixture"
        settings.doubaoRegion = "cn-shanghai"
        settings.updateProviderConfig(provider: .doubao) { $0.source = .cli }

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let pane = ProvidersPane(settings: settings, store: store)
        let editor = try #require(pane._test_tokenAccountDescriptor(for: .doubao))
        let support = try #require(TokenAccountSupportCatalog.support(for: .doubao))
        #expect(editor.title == support.title)
        #expect(editor.isVisible?() == true)
        #expect(editor.accounts().isEmpty)

        for account in self.accounts {
            settings.addTokenAccount(provider: .doubao, label: account.label, token: account.token)
        }
        #expect(editor.accounts().map(\.displayName) == ["Personal", "Work"])
        settings.setActiveTokenAccountIndex(1, for: .doubao)
        let selected = try #require(settings.effectiveSelectedTokenAccount(for: .doubao))
        #expect(selected.label == "Work")

        let appEnvironment = ProviderRegistry.makeEnvironment(
            base: self.ambientEnvironment,
            provider: .doubao,
            settings: settings,
            tokenOverride: nil)
        #expect(appEnvironment[DoubaoSettingsReader.apiKeyEnvironmentKeys[0]] == selected.token)
        for key in DoubaoSettingsReader.apiKeyEnvironmentKeys.dropFirst() +
            DoubaoSettingsReader.accessKeyIDEnvironmentKeys +
            DoubaoSettingsReader.secretAccessKeyEnvironmentKeys
        {
            #expect(appEnvironment[key] == nil, "Selected account must scrub competing alias \(key)")
        }
        #expect(ProviderRegistry.resolvedSourceMode(provider: .doubao, settings: settings, account: selected) == .api)

        for account in settings.tokenAccounts(for: .doubao) {
            settings.removeTokenAccount(provider: .doubao, accountID: account.id)
        }

        #expect(settings.tokenAccounts(for: .doubao).isEmpty)
        #expect(settings.doubaoAPIToken == "AKLT-legacy-fixture")
        #expect(settings.doubaoSecretAccessKey == "legacy-secret-fixture")
        #expect(settings.doubaoRegion == "cn-shanghai")
        #expect(settings.providerConfig(for: .doubao)?.source == .cli)
    }

    @Test(arguments: [ProviderSourceMode.auto, .api, .cli])
    func `selected app and CLI accounts scrub competitors and force the API route`(
        source: ProviderSourceMode) async throws
    {
        let config = CodexBarConfig(providers: [ProviderConfig(
            id: .doubao,
            source: source,
            apiKey: "configured-ark-fixture",
            secretKey: "configured-secret-fixture",
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: self.accounts, activeIndex: 1))])
        let allAccounts = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: true),
            config: config,
            verbose: false,
            baseEnvironment: self.ambientEnvironment)
        #expect(try allAccounts.resolvedAccounts(for: .doubao).map(\.id) == self.accounts.map(\.id))

        for account in self.accounts {
            let environment = allAccounts.environment(
                base: self.ambientEnvironment,
                provider: .doubao,
                account: account)
            #expect(environment["UNRELATED"] == "preserved")
            #expect(environment["ARKCLI_PATH"] == "/synthetic/arkcli")
            for key in DoubaoSettingsReader.apiKeyEnvironmentKeys.dropFirst() +
                DoubaoSettingsReader.accessKeyIDEnvironmentKeys +
                DoubaoSettingsReader.secretAccessKeyEnvironmentKeys
            {
                #expect(environment[key] == nil, "Selected account must scrub competing alias \(key)")
            }
            #expect(environment[DoubaoSettingsReader.apiKeyEnvironmentKeys[0]] == account.token)

            let mode = allAccounts.effectiveSourceMode(base: source, provider: .doubao, account: account)
            #expect(mode == .api)
            let strategies = await DoubaoProviderDescriptor.resolveStrategies(
                context: Self.makeContext(environment: environment, source: mode))
            #expect(strategies.map(\.id) == ["doubao.api"])

            let strategy = DoubaoAPIFetchStrategy(
                signedUsageLoader: { _ in
                    Issue.record("A selected Ark key must not inherit ambient AK/SK credentials")
                    throw DoubaoUsageError.missingCredentials
                },
                arkUsageLoader: { token in
                    #expect(token == account.token)
                    return DoubaoUsageSnapshot(
                        remainingRequests: account.label == "Personal" ? 75 : 25,
                        limitRequests: 100,
                        resetTime: nil,
                        updatedAt: Date(timeIntervalSince1970: 0),
                        apiKeyValid: true)
                })
            let result = try await strategy.fetch(Self.makeContext(environment: environment, source: mode))
            #expect(result.usage.primary?.usedPercent == (account.label == "Personal" ? 25 : 75))
        }
    }

    @Test
    func `failed selected Ark key does not fall back to another credential source`() async throws {
        let config = ProviderConfig(id: .doubao, source: .cli, apiKey: "configured-ark-fixture")
        let account = self.accounts[0]
        let environment = ProviderEnvironmentResolver.resolve(
            base: self.ambientEnvironment,
            provider: .doubao,
            config: config,
            selectedAccount: account)
        let strategy = DoubaoAPIFetchStrategy(
            signedUsageLoader: { _ in
                Issue.record("A selected Ark key must not inherit ambient AK/SK credentials")
                throw DoubaoUsageError.missingCredentials
            },
            arkUsageLoader: { token in
                #expect(token == account.token)
                throw DoubaoUsageError.apiError(401, "fixture")
            })
        let context = Self.makeContext(environment: environment, source: .api)

        await #expect {
            try await strategy.fetch(context)
        } throws: { error in
            guard case DoubaoUsageError.apiError(401, "fixture") = error else { return false }
            return true
        }
        #expect(!strategy.shouldFallback(on: DoubaoUsageError.apiError(401, "fixture"), context: context))
        #expect(await DoubaoProviderDescriptor.resolveStrategies(context: context).map(\.id) == ["doubao.api"])
    }

    @Test @MainActor
    func `generic provider intent sync retains Doubao account data`() throws {
        let config = ProviderConfig(
            id: .doubao,
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: self.accounts, activeIndex: 1))
        let secrets = try ProviderIntentPayload.secretFields(for: config, includeSecrets: true)
        let payload = ProviderIntentPayload(config: config)
        let restored = try payload.applying(
            to: ProviderConfig(id: .doubao),
            secretFields: secrets,
            canEnable: { _, _ in true })

        #expect(restored.id == .doubao)
        #expect(restored.tokenAccounts?.accounts.map(\.id) == self.accounts.map(\.id))
        #expect(restored.tokenAccounts?.accounts.map(\.token) == self.accounts.map(\.token))
        #expect(restored.tokenAccounts?.activeIndex == 1)
        #expect(TokenAccountSupportCatalog.allProviders.contains(.doubao))
        #expect(SyncCoordinator.tokenBasedMultiAccountProvidersForTesting.contains(.doubao))
    }

    private static func makeContext(environment: [String: String], source: ProviderSourceMode) -> ProviderFetchContext {
        ProviderFetchContext(
            runtime: .cli,
            sourceMode: source,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: nil,
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: DoubaoTokenAccountClaudeStub(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }
}

private struct DoubaoTokenAccountClaudeStub: ClaudeUsageFetching {
    func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
        throw DoubaoUsageError.missingCredentials
    }

    func debugRawProbe(model _: String) async -> String {
        "fixture"
    }

    func detectVersion() -> String? {
        nil
    }
}
