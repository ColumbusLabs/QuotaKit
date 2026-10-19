import Commander
import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct CLIUsageClaudeSwapTests {
    private actor InvocationCounter {
        private(set) var adapterReads = 0
        private(set) var ordinaryFetches = 0

        func incrementAdapterRead() {
            self.adapterReads += 1
        }

        func incrementOrdinaryFetch() {
            self.ordinaryFetches += 1
        }
    }

    private struct AdapterFailure: LocalizedError, Sendable {
        var errorDescription: String? {
            "fixture adapter failure"
        }
    }

    @Test
    func `auto usage follows the active swap slot`() async throws {
        let counter = InvocationCounter()
        let list = ClaudeSwapAccountList(activeAccountNumber: 3, accounts: [
            self.row(number: 1, active: false, email: "inactive@example.com", percent: 10),
            self.row(number: 3, active: true, email: "active@example.com", percent: 50),
        ])
        let output = try await self.fetch(list: list, counter: counter)
        let payload = try #require(output.payload.first)

        #expect(output.exitCode == .success)
        #expect(output.payload.count == 1)
        #expect(payload.source == "claude-swap")
        #expect(payload.account == "active@example.com")
        #expect(payload.usage?.identity?.accountEmail == "active@example.com")
        #expect(payload.usage?.identity?.accountID == "claude-swap:3")
        #expect(payload.usage?.primary?.usedPercent == 50)
        #expect(await counter.adapterReads == 1)
        #expect(await counter.ordinaryFetches == 0)
    }

    @Test
    func `explicit source or token account selection bypasses the active slot`() async throws {
        let counter = InvocationCounter()
        let explicitSource = try await self.fetch(
            counter: counter,
            sourceOverride: .web)
        #expect(explicitSource.payload.first?.source == "web")

        let selectedAccount = try await self.fetch(
            counter: counter,
            selection: TokenAccountCLISelection(label: "missing", index: nil, allAccounts: false))
        #expect(selectedAccount.exitCode == .failure)
        #expect(selectedAccount.payload.first?.error != nil)
        #expect(await counter.adapterReads == 0)
    }

    @Test
    func `configured web source and disabled integration keep ordinary usage`() async throws {
        let counter = InvocationCounter()
        let configuredWeb = try await self.fetch(counter: counter, configSource: .web)
        #expect(configuredWeb.payload.first?.source == "web")

        let disabled = try await self.fetch(counter: counter, enabled: false)
        #expect(disabled.payload.first?.source == "web")
        #expect(await counter.adapterReads == 0)
    }

    @Test
    func `adapter failure identifies the ordinary source fallback`() async throws {
        let counter = InvocationCounter()
        let output = try await self.fetch(counter: counter, adapterFails: true)

        #expect(output.exitCode == .success)
        #expect(output.payload.first?.source == "web (claude-swap fallback)")
        #expect(output.payload.first?.usage?.identity?.accountEmail == "browser@example.com")
        #expect(output.payload.first?.usage?.secondary?.usedPercent == 92)
        #expect(await counter.adapterReads == 1)
        #expect(await counter.ordinaryFetches == 1)
    }

    @Test
    func `adapter cancellation stops before ordinary source fallback`() async throws {
        let counter = InvocationCounter()
        let output = try await self.fetch(counter: counter, adapterCancels: true)

        #expect(output.exitCode == .failure)
        #expect(output.payload.first?.source == "claude-swap")
        #expect(output.payload.first?.error?.message == "Usage cancelled.")
        #expect(await counter.adapterReads == 1)
        #expect(await counter.ordinaryFetches == 0)
    }

    @Test
    func `inactive slot usage is not borrowed when no slot is active`() async throws {
        let counter = InvocationCounter()
        let list = ClaudeSwapAccountList(activeAccountNumber: nil, accounts: [
            self.row(number: 3, active: false, email: "inactive@example.com", percent: 50),
        ])
        let output = try await self.fetch(list: list, counter: counter)

        #expect(output.payload.first?.source == "web (claude-swap fallback)")
        #expect(output.payload.first?.usage?.identity?.accountEmail == "browser@example.com")
        #expect(await counter.adapterReads == 1)
        #expect(await counter.ordinaryFetches == 1)
    }

    private func fetch(
        list: ClaudeSwapAccountList? = nil,
        counter: InvocationCounter,
        adapterFails: Bool = false,
        adapterCancels: Bool = false,
        enabled: Bool = true,
        configSource: ProviderSourceMode = .auto,
        sourceOverride: ProviderSourceMode? = nil,
        selection: TokenAccountCLISelection = TokenAccountCLISelection(
            label: nil, index: nil, allAccounts: false)) async throws -> UsageCommandOutput
    {
        var providerConfig = ProviderConfig(id: .claude, enabled: true, source: configSource)
        providerConfig.claudeSwapEnabled = enabled
        let config = CodexBarConfig(providers: [providerConfig])
        let tokenContext = try TokenAccountCLIContext(
            selection: selection,
            config: config,
            verbose: false,
            baseEnvironment: [:])
        let browserDetection = BrowserDetection()
        let command = UsageCommandContext(
            format: .json,
            includeCredits: true,
            sourceModeOverride: sourceOverride,
            antigravityPlanDebug: false,
            augmentDebug: false,
            webDebugDumpHTML: false,
            webTimeout: 1,
            verbose: false,
            useColor: false,
            resetStyle: .countdown,
            weeklyWorkDays: nil,
            jsonOnly: true,
            includeAllCodexAccounts: false,
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection,
            followsClaudeSwapActiveSlot: true)
        let reader: CLIClaudeSwapCards.AccountListReader = { _ in
            await counter.incrementAdapterRead()
            #expect(ClaudeOpaqueOperationContext.isAllowed)
            if adapterCancels { throw CancellationError() }
            if adapterFails { throw AdapterFailure() }
            return list ?? ClaudeSwapAccountList(activeAccountNumber: nil, accounts: [])
        }
        let browserLoader: ClaudeWebFetchStrategy.UsageLoader = { _ in
            await counter.incrementOrdinaryFetch()
            return ClaudeUsageSnapshot(
                primary: RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 92, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
                opus: nil,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                accountEmail: "browser@example.com",
                accountOrganization: nil,
                loginMethod: "web",
                rawText: nil)
        }
        let availability: @Sendable (ProviderFetchContext, BrowserDetection) -> Bool = { _, _ in true }
        return await ClaudeWebFetchStrategy.$availabilityProbeOverrideForTesting.withValue(availability) {
            await ClaudeWebFetchStrategy.$usageLoaderOverrideForTesting.withValue(
                browserLoader,
                operation: {
                    await ProviderInteractionContext.$current.withValue(
                        .background,
                        operation: {
                            await CodexBarCLI.fetchUsageOutputs(
                                provider: .claude,
                                status: nil,
                                tokenContext: tokenContext,
                                command: command,
                                claudeSwapAccountListReader: reader)
                        })
                })
        }
    }

    private func row(number: Int, active: Bool, email: String, percent: Double) -> ClaudeSwapAccountRow {
        ClaudeSwapAccountRow(
            number: number,
            email: email,
            isActive: active,
            usageStatus: .ok,
            fiveHour: ClaudeSwapUsageWindow(usedPercent: percent, resetsAt: nil),
            sevenDay: ClaudeSwapUsageWindow(usedPercent: 41, resetsAt: nil))
    }
}
