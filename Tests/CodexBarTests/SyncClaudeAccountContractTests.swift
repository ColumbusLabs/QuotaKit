import CodexBarCore
import Foundation
import Testing

struct SyncClaudeAccountContractTests {
    @Test
    func `outgoing account secrets omit local Claude history directories`() throws {
        let account = Self.account(directory: "/sender/private/claude")
        let config = ProviderConfig(
            id: .claude,
            tokenAccounts: .init(version: 1, accounts: [account], activeIndex: 0))
        let fields = try ProviderIntentPayload.secretFields(for: config, includeSecrets: true)
        let encoded = try #require(fields["tokenAccounts"])
        let decoded = try CanonicalSyncJSON.decode(ProviderTokenAccountData.self, from: encoded)

        #expect(!encoded.contains("/sender/private/claude"))
        #expect(!encoded.contains("claudeConfigDirectory"))
        #expect(decoded.accounts.first?.claudeConfigDirectory == nil)
        #expect(decoded.accounts.first?.token == account.token)
        #expect(decoded.accounts.first?.id == account.id)
        #expect(decoded.activeIndex == 0)
        #expect(try ProviderIntentPayload.secretFields(for: config, includeSecrets: false).isEmpty)
    }

    @Test
    func `incoming account paths never replace receiver mappings or initialize new mappings`() throws {
        let local = Self.account(directory: "/receiver/claude")
        let foreign = local.withClaudeConfigDirectory("/sender/foreign")
        let added = Self.account(directory: "/sender/new-account")
        let incoming = ProviderTokenAccountData(version: 1, accounts: [added, foreign], activeIndex: 1)
        let config = ProviderConfig(
            id: .claude,
            tokenAccounts: .init(version: 1, accounts: [local], activeIndex: 0))
        let applied = try ProviderIntentPayload(config: config).applying(
            to: config,
            secretFields: ["tokenAccounts": CanonicalSyncJSON.string(incoming)]) { _, _ in true }
        let accounts = try #require(applied.tokenAccounts)

        #expect(accounts.accounts.map(\.id) == [added.id, local.id])
        #expect(accounts.activeIndex == 1)
        #expect(accounts.accounts[0].claudeConfigDirectory == nil)
        #expect(accounts.accounts[1].claudeConfigDirectory == "/receiver/claude")
    }

    @Test
    func `directory preservation retains older sender limits and accepts explicit limit clears`() throws {
        let limits = [ProviderModelRateLimit(model: "fixture-model", tokensPerMinute: 100)]
        let account = Self.account(directory: "/receiver/claude").withModelRateLimits(limits)
        let config = ProviderConfig(
            id: .claude,
            tokenAccounts: .init(version: 1, accounts: [account], activeIndex: 0))
        let payload = ProviderIntentPayload(config: config)
        let incomingStates: [[ProviderModelRateLimit]?] = [nil, []]
        for incomingLimits in incomingStates {
            let incoming = ProviderTokenAccountData(
                version: 1,
                accounts: [account.withClaudeConfigDirectory(nil).withModelRateLimits(incomingLimits)],
                activeIndex: 0)
            let applied = try payload.applying(
                to: config,
                secretFields: ["tokenAccounts": CanonicalSyncJSON.string(incoming)]) { _, _ in true }
            let merged = try #require(applied.tokenAccounts?.accounts.first)
            #expect(merged.claudeConfigDirectory == "/receiver/claude")
            #expect(merged.modelRateLimits == (incomingLimits == nil ? limits : []))
        }
    }

    @Test
    func `tcr snapshots retire only email records belonging to their source namespace`() throws {
        let tcr = Self.snapshot(source: .tcr, accountID: "tcr:2")
        let predecessor = try #require(tcr.emailKeyedPredecessorRecordName())
        let emailKey = AccountSnapshotSyncPayload.accountKey(for: "owner@example.com")
        #expect(predecessor == "snap-claude-\(emailKey)-device-id")
        #expect(tcr.recordName != predecessor)
        #expect(AccountSnapshotSyncPayload.obsoleteEmailKeyedRecordNames(
            liveSnapshots: [tcr], knownRecordNames: [predecessor]) == [predecessor])
        #expect(Self.snapshot(source: .tcr, accountID: "claude-swap:2").emailKeyedPredecessorRecordName() == nil)
        #expect(Self.snapshot(source: .claudeSwap, accountID: "tcr:2").emailKeyedPredecessorRecordName() == nil)
    }

    private static func account(directory: String) -> ProviderTokenAccount {
        ProviderTokenAccount(
            id: UUID(),
            label: "Fixture",
            token: "fixture-token",
            addedAt: 1,
            lastUsed: nil,
            claudeConfigDirectory: directory)
    }

    private static func snapshot(source: ClaudeSwapAccountSource, accountID: String) -> AccountSnapshotSyncPayload {
        let usage = UsageSnapshot(
            primary: nil,
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 100),
            identity: ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: "Owner@Example.com",
                accountOrganization: nil,
                loginMethod: source.label,
                accountID: accountID))
        return AccountSnapshotSyncPayload(
            provider: .claude,
            deviceID: "device-id",
            accountIdentity: accountID,
            displayLabel: "Owner@Example.com",
            usage: usage)
    }
}
