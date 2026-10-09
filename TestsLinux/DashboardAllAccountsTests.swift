import Commander
import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct DashboardAllAccountsTests {
    @Test
    func `all account expansion is an explicit serve only option`() throws {
        let program = Program(descriptors: CodexBarCLI.commandDescriptors())
        let ordinary = try program.resolve(argv: ["serve"])
        let expanded = try program.resolve(argv: ["serve", "--all-accounts"])
        #expect(!ordinary.parsedValues.flags.contains("allAccounts"))
        #expect(expanded.parsedValues.flags.contains("allAccounts"))
        #expect(throws: (any Error).self) { try program.resolve(argv: ["dashboard", "--all-accounts"]) }
    }

    @Test
    func `expanded snapshots default to private identity while explicit mode wins`() {
        #expect(CodexBarCLI.resolveDashboardIdentityMode(
            configured: nil,
            hidesPersonalInfo: false,
            allAccounts: true) == .none)
        #expect(CodexBarCLI.resolveDashboardIdentityMode(
            configured: nil,
            hidesPersonalInfo: false,
            allAccounts: false) == .full)
        #expect(CodexBarCLI.resolveDashboardIdentityMode(
            configured: nil,
            hidesPersonalInfo: true,
            allAccounts: false) == .redacted)
        #expect(CodexBarCLI.resolveDashboardIdentityMode(
            configured: .full,
            hidesPersonalInfo: true,
            allAccounts: true) == .full)
    }

    @Test
    func `expanded Codex rows preserve saved managed snapshots and hide private diagnostics`() throws {
        let managedID = "codex-managed:saved-account"
        let savedUsage = self.codexPayload(
            id: managedID,
            label: "new fetched label",
            active: false,
            error: ProviderErrorPayload(
                code: 1,
                message: "credential error at /private/location",
                kind: .provider))
        var profileUsage = self.codexPayload(
            id: "codex:profile-hash",
            label: "profile@example.test",
            active: true,
            error: ProviderErrorPayload(
                code: 1,
                message: "private path /Users/example/.codex/profile",
                kind: .provider))
        profileUsage.dashboardAccountsIncomplete = true

        let savedAccount = ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(source: "codex-managed", opaqueID: "saved-account"),
            provider: .codex,
            displayLabel: "owner@example.test — Private workspace",
            accountEmail: "owner@example.test",
            isActive: false,
            usesLastKnownUsage: true,
            snapshot: self.usage(),
            error: "credential error at /private/location",
            sourceLabel: nil)
        let snapshot = DashboardSnapshotBuilder.makeSnapshot(
            usagePayloads: [savedUsage, profileUsage],
            costPayloads: [],
            config: CodexBarConfig(providers: [ProviderConfig(id: .codex, enabled: true)]),
            identityMode: .none,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            refreshInterval: 60,
            codexBarVersion: nil,
            accountCollections: [.codex: DashboardAccountsInput(
                accounts: [savedAccount],
                adapterError: nil,
                weeklyWorkDays: nil)],
            allAccounts: true)

        let provider = try #require(snapshot.providers.first)
        #expect(provider.accounts?.map(\.id) == [managedID, "codex:profile-hash"])
        #expect(provider.accounts?.map(\.label) == ["Account 1", "Account 2"])
        #expect(provider.accounts?.map(\.active) == [false, true])
        #expect(provider.accounts?.first?.error == "Account usage unavailable")
        #expect(provider.error?.message == "Account usage unavailable")
        #expect(provider.accountsError == "Account list incomplete")

        let encoded = try #require(CodexBarCLI.encodeJSON(snapshot, pretty: false))
        #expect(!encoded.contains("owner@example.test"))
        #expect(!encoded.contains("profile@example.test"))
        #expect(!encoded.contains("Private workspace"))
        #expect(!encoded.contains("credential error"))
        #expect(!encoded.contains("/Users/example"))
    }

    @Test(arguments: [true, false])
    func `live system selection stays active on its matched managed account`(fetchSucceeds: Bool) throws {
        let managedID = UUID(uuidString: "9e122a52-b3db-4a7e-a7a7-c3b8fc9d01e9")!
        let visibleAccount = CodexVisibleAccount(
            id: "live:workspace",
            email: "current@example.test",
            workspaceLabel: "Current workspace",
            workspaceAccountID: "workspace-123",
            storedAccountID: managedID,
            selectionSource: .liveSystem,
            isActive: true,
            isLive: true,
            canReauthenticate: true,
            canRemove: false)
        let currentAccount = DashboardUsageAccount.codex(visibleAccount)
        #expect(currentAccount.id == "codex-managed:\(managedID.uuidString.lowercased())")

        let savedLabel = "saved@example.test — Saved workspace"
        let savedError = "saved refresh error"
        let savedAccount = ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(source: "codex-managed", opaqueID: managedID.uuidString.lowercased()),
            provider: .codex,
            displayLabel: savedLabel,
            accountEmail: "saved@example.test",
            isActive: false,
            usesLastKnownUsage: true,
            snapshot: self.usage(primaryUsedPercent: 20, updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            error: savedError,
            sourceLabel: nil)

        var currentPayload = ProviderPayload(
            provider: .codex,
            account: nil,
            version: nil,
            source: "fixture",
            status: nil,
            usage: fetchSucceeds
                ? self.usage(primaryUsedPercent: 65, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
                : nil,
            credits: nil,
            antigravityPlanInfo: nil,
            openaiDashboard: nil,
            error: fetchSucceeds ? nil : ProviderErrorPayload(
                code: 1,
                message: "current refresh failed",
                kind: .provider))
        currentPayload.dashboardAccount = currentAccount

        let snapshot = DashboardSnapshotBuilder.makeSnapshot(
            usagePayloads: [currentPayload],
            costPayloads: [],
            config: CodexBarConfig(providers: [ProviderConfig(id: .codex, enabled: true)]),
            identityMode: .full,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            refreshInterval: 60,
            codexBarVersion: nil,
            accountCollections: [.codex: DashboardAccountsInput(
                accounts: [savedAccount],
                adapterError: nil,
                weeklyWorkDays: nil)],
            allAccounts: true)

        let account = try #require(snapshot.providers.first?.accounts?.first)
        #expect(account.active)
        #expect(account.label == savedLabel)
        if fetchSucceeds {
            #expect(account.windows.first?.usedPercent == 65)
            #expect(account.error == nil)
        } else {
            #expect(account.windows.first?.usedPercent == 20)
            #expect(account.error == savedError)
            #expect(account.updatedAt == Date(timeIntervalSince1970: 1_700_000_000))
        }
    }

    @Test
    func `all account response cache keys remain separate from ordinary dashboard snapshots`() throws {
        let ordinary = try CodexBarCLI.serveDashboardOperationKey(
            identityMode: .redacted,
            usageBarsShowUsed: false,
            provider: "codex")
        let expanded = try CodexBarCLI.serveDashboardOperationKey(
            identityMode: .redacted,
            usageBarsShowUsed: false,
            provider: "codex",
            allAccounts: true)
        #expect(ordinary != expanded)
        #expect(CodexBarCLI.serveUsageOperationFingerprint(
            configFingerprint: "fixture",
            includeAllCodexAccounts: true) != CodexBarCLI.serveUsageOperationFingerprint(
                configFingerprint: "fixture",
                includeAllCodexAccounts: true,
                includeAllAccounts: true))
    }

    @Test
    func `Claude Swap adapter remains authoritative in expanded snapshots`() throws {
        let account = ClaudeSwapAccountProjection.accountSnapshots(from: ClaudeSwapAccountList(
            activeAccountNumber: 7,
            accounts: [ClaudeSwapAccountRow(
                number: 7,
                email: "private@example.test",
                isActive: true,
                usageStatus: .ok,
                fiveHour: nil,
                sevenDay: nil)]))
        var tokenPayload = ProviderPayload(
            provider: .claude,
            account: nil,
            version: nil,
            source: "fixture",
            status: nil,
            usage: self.usage(),
            credits: nil,
            antigravityPlanInfo: nil,
            openaiDashboard: nil,
            error: nil)
        tokenPayload.dashboardAccount = DashboardUsageAccount(
            id: "token:synthetic",
            label: "Token fallback",
            active: true)
        let snapshot = DashboardSnapshotBuilder.makeSnapshot(
            usagePayloads: [tokenPayload],
            costPayloads: [],
            config: CodexBarConfig(providers: [ProviderConfig(id: .claude, enabled: true)]),
            identityMode: .none,
            generatedAt: Date(timeIntervalSince1970: 0),
            refreshInterval: 60,
            codexBarVersion: nil,
            accountCollections: [.claude: DashboardAccountsInput(
                accounts: account,
                adapterError: nil,
                weeklyWorkDays: nil,
                showSingleAccount: true)],
            allAccounts: true)
        let rows = try #require(snapshot.providers.first?.accounts)
        #expect(rows.map(\.id) == ["claude-swap:7"])
        #expect(rows.map(\.label) == ["Account 1"])
        #expect(!rows[0].id.contains("token:"))
        let encoded = try #require(CodexBarCLI.encodeJSON(snapshot, pretty: false))
        #expect(!encoded.contains("private@example.test"))
    }

    private func codexPayload(
        id: String,
        label: String,
        active: Bool,
        error: ProviderErrorPayload? = nil) -> ProviderPayload
    {
        var payload = ProviderPayload(
            provider: .codex,
            account: nil,
            version: nil,
            source: "fixture",
            status: nil,
            usage: self.usage(),
            credits: nil,
            antigravityPlanInfo: nil,
            openaiDashboard: nil,
            error: error)
        payload.dashboardAccount = DashboardUsageAccount(id: id, label: label, active: active)
        return payload
    }

    private func usage() -> UsageSnapshot {
        UsageSnapshot(
            primary: nil,
            secondary: nil,
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            identity: nil)
    }

    private func usage(primaryUsedPercent: Double, updatedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: primaryUsedPercent,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: updatedAt,
            identity: nil)
    }
}
