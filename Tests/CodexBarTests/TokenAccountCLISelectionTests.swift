import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct TokenAccountCLISelectionTests {
    @Test
    func `cli token updater writes refreshed credential when stored token is unchanged`() async throws {
        let account = Self.account(token: "original-token")
        let config = Self.config(with: account)
        let store = try Self.configStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        try store.save(config)
        let context = try Self.writebackContext(config: config, store: store)
        let updater = try #require(context.tokenUpdater(for: account))

        await updater(.antigravity, account.id, "refreshed-token")

        #expect(try Self.storedToken(store: store, accountID: account.id) == "refreshed-token")
    }

    @Test
    func `cli token updater preserves external reauthorization during fetch`() async throws {
        let account = Self.account(token: "original-token")
        let config = Self.config(with: account)
        let store = try Self.configStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        try store.save(config)
        let context = try Self.writebackContext(config: config, store: store)
        let updater = try #require(context.tokenUpdater(for: account))

        try store.save(Self.config(with: Self.account(id: account.id, token: "reauthorized-token")))
        await updater(.antigravity, account.id, "stale-refresh")

        #expect(try Self.storedToken(store: store, accountID: account.id) == "reauthorized-token")
    }

    @Test
    func `cli token updater accepts successive owned updates`() async throws {
        let account = Self.account(token: "original-token")
        let config = Self.config(with: account)
        let store = try Self.configStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        try store.save(config)
        let updater = try #require(try Self.writebackContext(config: config, store: store).tokenUpdater(for: account))

        await updater(.antigravity, account.id, "refreshed-token")
        await updater(.antigravity, account.id, "refreshed-token-with-project")

        #expect(try Self.storedToken(store: store, accountID: account.id) == "refreshed-token-with-project")
    }

    @Test
    func `Antigravity CLI rejects saved account selection`() throws {
        let account = ProviderTokenAccount(
            id: UUID(),
            label: "Personal",
            token: "synthetic-google-credential",
            addedAt: 0,
            lastUsed: nil)
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .antigravity,
                source: .cli,
                tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0)),
        ])
        let context = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: "Personal", index: nil, allAccounts: false),
            config: config,
            verbose: false,
            baseEnvironment: [:])

        #expect(throws: TokenAccountCLIError.self) {
            try context.resolvedAccounts(for: .antigravity)
        }
        #expect(try context.resolvedAccounts(for: .antigravity, sourceMode: .oauth).map(\.id) == [account.id])

        let ambientCLI = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: config,
            verbose: false,
            baseEnvironment: [:])
        #expect(try ambientCLI.resolvedAccounts(for: .antigravity).isEmpty)
        #expect(try ambientCLI.resolvedAccounts(for: .antigravity, sourceMode: .oauth).map(\.id) == [account.id])
    }

    @Test
    func `saved account label remains separate from provider identity`() throws {
        let context = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: CodexBarConfig(providers: []),
            verbose: false,
            baseEnvironment: [:])
        let account = ProviderTokenAccount(
            id: UUID(),
            label: "Work profile",
            token: "synthetic-provider-token",
            addedAt: 0,
            lastUsed: nil)
        let usageWithoutIdentity = UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date())
        let cliUsageWithoutIdentity = context.applyAccountLabel(
            usageWithoutIdentity,
            provider: .claude,
            account: account)
        let payloadWithoutIdentity = Self.payload(account: account.label, usage: cliUsageWithoutIdentity)
        let encoded = try JSONEncoder().encode(payloadWithoutIdentity)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let encodedUsage = try #require(object["usage"] as? [String: Any])

        #expect(object["account"] as? String == "Work profile")
        #expect(cliUsageWithoutIdentity.accountEmail(for: .claude) == nil)
        #expect(encodedUsage["identity"] == nil || encodedUsage["identity"] is NSNull)

        let genuineIdentity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: "person@example.com",
            accountOrganization: nil,
            loginMethod: "OAuth")
        let usageWithIdentity = usageWithoutIdentity.withIdentity(genuineIdentity)
        let cliUsageWithIdentity = context.applyAccountLabel(
            usageWithIdentity,
            provider: .claude,
            account: account)
        let payloadWithIdentity = Self.payload(account: account.label, usage: cliUsageWithIdentity)

        #expect(payloadWithIdentity.account == account.label)
        #expect(payloadWithIdentity.usage?.accountEmail(for: .claude) == "person@example.com")
    }

    private static func payload(account: String, usage: UsageSnapshot) -> ProviderPayload {
        ProviderPayload(
            provider: .claude,
            account: account,
            version: nil,
            source: "oauth",
            status: nil,
            usage: usage,
            credits: nil,
            antigravityPlanInfo: nil,
            openaiDashboard: nil,
            error: nil)
    }

    private static func account(id: UUID = UUID(), token: String) -> ProviderTokenAccount {
        ProviderTokenAccount(id: id, label: "Primary", token: token, addedAt: 0, lastUsed: nil)
    }

    private static func config(with account: ProviderTokenAccount) -> CodexBarConfig {
        CodexBarConfig(providers: [ProviderConfig(
            id: UsageProvider.antigravity.instanceID,
            tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0))])
    }

    private static func configStore() throws -> CodexBarConfigStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-account-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
    }

    private static func writebackContext(
        config: CodexBarConfig,
        store: CodexBarConfigStore) throws -> TokenAccountCLIContext
    {
        try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: config,
            verbose: false,
            baseEnvironment: [:],
            configStore: store)
    }

    private static func storedToken(store: CodexBarConfigStore, accountID: UUID) throws -> String? {
        try store.load()?
            .providerConfig(for: UsageProvider.antigravity.instanceID)?
            .tokenAccounts?.accounts
            .first(where: { $0.id == accountID })?.token
    }
}
