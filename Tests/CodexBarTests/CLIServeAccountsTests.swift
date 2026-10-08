import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct CLIServeAccountsTests {
    @Test
    func `account config reads legacy data without copying it into the resolved path`() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLIServeAccountsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let currentURL = home.appendingPathComponent(".quotakit/config.json")
        let legacyURL = home.appendingPathComponent(".codexbar/config.json")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let legacyConfig = CodexBarConfig(providers: [
            ProviderConfig(
                id: .claude,
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [Self.tokenAccount(id: UUID(), label: "Legacy", token: "synthetic-secret")],
                    activeIndex: 0)),
        ])
        try JSONEncoder().encode(legacyConfig).write(to: legacyURL)

        let config = try CLIServeAccountDiscovery.loadConfigReadOnly(
            from: CodexBarConfigStore(fileURL: currentURL))

        #expect(!FileManager.default.fileExists(atPath: currentURL.path))
        #expect(config.providerConfig(for: .claude)?.tokenAccounts?.accounts.first?.label == "Legacy")
    }

    @Test
    func `empty account set encodes as an empty list`() throws {
        let payload = CLIServeAccountDiscovery.makePayload(
            config: CodexBarConfig(providers: []),
            managedCodexAccounts: [],
            identityMode: .redacted)

        #expect(payload.schemaVersion == 1)
        #expect(payload.accounts.isEmpty)
        let object = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        #expect((object["accounts"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test
    func `discovers saved accounts across providers with stable provider scoped ids`() throws {
        let sharedTokenID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let managedID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let token = Self.tokenAccount(id: sharedTokenID, label: "Claude workspace", token: "claude-secret")
        var codex = ProviderConfig(id: .codex, enabled: false)
        codex.codexActiveSource = .managedAccount(id: managedID)
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .claude,
                enabled: false,
                tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [token], activeIndex: 0)),
            codex,
            ProviderConfig(
                id: .openai,
                enabled: false,
                tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [token], activeIndex: 0)),
        ])
        let managed = Self.managedAccount(id: managedID)

        let payload = CLIServeAccountDiscovery.makePayload(
            config: config,
            managedCodexAccounts: [managed],
            identityMode: .full)

        #expect(payload.accounts.map(\.provider) == ["claude", "codex", "openai"])
        #expect(payload.accounts.map(\.id) == [
            "token-account:claude:\(sharedTokenID.uuidString.lowercased())",
            "codex-managed:\(managedID.uuidString.lowercased())",
            "token-account:openai:\(sharedTokenID.uuidString.lowercased())",
        ])
        #expect(Set(payload.accounts.map(\.id)).count == payload.accounts.count)
        #expect(payload.accounts.map(\.active) == [true, true, true])
        #expect(payload.accounts[0].label == "Claude workspace")
        #expect(payload.accounts[1].label == "Example Workspace")
        #expect(payload.accounts[1].identity?.accountEmail == "managed@example.com")
    }

    @Test
    func `wire payload excludes credentials provider internals and managed home paths`() throws {
        let tokenID = UUID()
        let managedID = UUID()
        let token = Self.tokenAccount(
            id: tokenID,
            label: "Safe label",
            token: "TOP-SECRET-TOKEN",
            externalIdentifier: "private-login",
            organizationID: "private-org",
            workspaceID: "private-workspace",
            seatCreditEntitlement: "private-entitlement")
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .claude,
                apiKey: "TOP-SECRET-API-KEY",
                secretKey: "TOP-SECRET-SECRET-KEY",
                cookieHeader: "TOP-SECRET-COOKIE",
                tokenAccounts: ProviderTokenAccountData(version: 1, accounts: [token], activeIndex: 0)),
        ])
        let managed = Self.managedAccount(
            id: managedID,
            authFingerprint: "credential-derived-fingerprint",
            managedHomePath: "/Users/private/managed-home")

        let payload = CLIServeAccountDiscovery.makePayload(
            config: config,
            managedCodexAccounts: [managed],
            identityMode: .full)
        let data = try JSONEncoder().encode(payload)
        let json = try #require(String(data: data, encoding: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)

        for forbiddenKey in [
            "token", "apiKey", "secretKey", "cookieHeader", "authFingerprint", "managedHomePath",
            "externalIdentifier", "organizationID", "organizationId", "workspaceID", "seatCreditEntitlement",
            "providerAccountID", "workspaceAccountID",
        ] {
            #expect(!Self.containsKey(forbiddenKey, in: object))
        }
        for forbiddenValue in [
            "TOP-SECRET", "private-login", "private-org", "private-workspace", "private-entitlement",
            "credential-derived-fingerprint", "/Users/private/managed-home", "provider-account", "workspace-account",
        ] {
            #expect(!json.contains(forbiddenValue))
        }
    }

    @Test
    func `redacted identity hides arbitrary labels and email local parts`() throws {
        let tokenID = UUID()
        let managedID = UUID()
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .claude,
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [Self.tokenAccount(
                        id: tokenID,
                        label: "Alice Smith alice@example.com",
                        token: "synthetic-secret")],
                    activeIndex: 0)),
        ])
        let managed = Self.managedAccount(id: managedID, workspaceLabel: nil)

        let payload = CLIServeAccountDiscovery.makePayload(
            config: config,
            managedCodexAccounts: [managed],
            identityMode: .redacted)
        let json = try #require(String(data: JSONEncoder().encode(payload), encoding: .utf8))
        let tokenAccount = try #require(payload.accounts.first { $0.provider == "claude" })
        let codex = try #require(payload.accounts.first { $0.provider == "codex" })

        #expect(tokenAccount.label == "Account \(tokenID.uuidString.lowercased())")
        #expect(codex.label == "Account \(managedID.uuidString.lowercased())")
        #expect(codex.identity?.accountEmail == "redacted@example.com")
        #expect(!json.contains("Alice Smith"))
        #expect(!json.contains("alice@"))
        #expect(!json.contains("managed@"))
    }

    @Test
    func `identity mode changes labels but leaves opaque ids stable`() throws {
        let tokenID = UUID()
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .claude,
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [Self.tokenAccount(id: tokenID, label: "Personal Workspace", token: "secret")],
                    activeIndex: 0)),
        ])
        let redacted = CLIServeAccountDiscovery.makePayload(
            config: config, managedCodexAccounts: [], identityMode: .redacted)
        let full = CLIServeAccountDiscovery.makePayload(
            config: config, managedCodexAccounts: [], identityMode: .full)

        #expect(redacted.accounts.first?.id == full.accounts.first?.id)
        #expect(redacted.accounts.first?.label == "Account \(tokenID.uuidString.lowercased())")
        #expect(full.accounts.first?.label == "Personal Workspace")
    }

    @Test
    func `single account response returns matching entry and unknown id returns 404`() throws {
        let accountID = UUID()
        let config = CodexBarConfig(providers: [
            ProviderConfig(
                id: .claude,
                tokenAccounts: ProviderTokenAccountData(
                    version: 1,
                    accounts: [Self.tokenAccount(id: accountID, label: "Claude", token: "secret")],
                    activeIndex: 0)),
        ])
        let payload = CLIServeAccountDiscovery.makePayload(
            config: config,
            managedCodexAccounts: [],
            identityMode: .redacted)
        let wireID = "token-account:claude:\(accountID.uuidString.lowercased())"

        let found = CLIServeAccountDiscovery.response(payload: payload, requestedID: wireID)
        #expect(found.status == .ok)
        let foundObject = try #require(JSONSerialization.jsonObject(with: found.body) as? [String: Any])
        #expect(foundObject["id"] as? String == wireID)

        let missing = CLIServeAccountDiscovery.response(payload: payload, requestedID: "unknown")
        #expect(missing.status == .notFound)
        let missingObject = try #require(JSONSerialization.jsonObject(with: missing.body) as? [String: Any])
        #expect(missingObject["error"] as? String == "account not found")
    }

    private static func containsKey(_ key: String, in value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            return dictionary[key] != nil || dictionary.values.contains { self.containsKey(key, in: $0) }
        }
        if let array = value as? [Any] {
            return array.contains { self.containsKey(key, in: $0) }
        }
        return false
    }

    private static func tokenAccount(
        id: UUID,
        label: String,
        token: String,
        externalIdentifier: String? = nil,
        organizationID: String? = nil,
        workspaceID: String? = nil,
        seatCreditEntitlement: String? = nil) -> ProviderTokenAccount
    {
        ProviderTokenAccount(
            id: id,
            label: label,
            token: token,
            addedAt: 1,
            lastUsed: 2,
            externalIdentifier: externalIdentifier,
            organizationID: organizationID,
            workspaceID: workspaceID,
            seatCreditEntitlement: seatCreditEntitlement)
    }

    private static func managedAccount(
        id: UUID,
        workspaceLabel: String? = "Example Workspace",
        authFingerprint: String? = "fingerprint",
        managedHomePath: String = "/synthetic/managed-home") -> ManagedCodexAccount
    {
        ManagedCodexAccount(
            id: id,
            email: "managed@example.com",
            providerAccountID: "provider-account",
            workspaceLabel: workspaceLabel,
            workspaceAccountID: "workspace-account",
            authFingerprint: authFingerprint,
            managedHomePath: managedHomePath,
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 3)
    }
}
