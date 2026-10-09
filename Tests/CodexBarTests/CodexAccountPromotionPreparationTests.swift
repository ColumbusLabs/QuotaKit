import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized, CodexCredentialFixtures())
@MainActor
struct CodexAccountPromotionPreparationTests {
    @Test
    func `builder carries direct auth identities for target and live`() async throws {
        let container = try CodexAccountPromotionTestContainer(
            suiteName: "CodexAccountPromotionPreparationTests-direct-identities",
            workspaceIdentities: [
                "acct-alpha": CodexOpenAIWorkspaceIdentity(
                    workspaceAccountID: "acct-alpha",
                    workspaceLabel: "Personal"),
                "acct-beta": CodexOpenAIWorkspaceIdentity(
                    workspaceAccountID: "acct-beta",
                    workspaceLabel: "Team"),
            ])
        defer { container.tearDown() }

        let target = try container.createManagedAccount(
            persistedEmail: "beta@example.com",
            authAccountID: "acct-beta")
        try container.persistAccounts([target])
        _ = try container.writeLiveOAuthAuthFile(email: "alpha@example.com", accountID: "acct-alpha")

        let builder = PreparedPromotionContextBuilder(
            store: container.fileStore,
            workspaceResolver: container.workspaceResolver,
            snapshotLoader: SettingsStoreCodexAccountReconciliationSnapshotLoader(settingsStore: container.settings),
            authMaterialReader: DefaultCodexAuthMaterialReader(),
            baseEnvironment: container.baseEnvironment,
            fileManager: .default)

        let context = try await builder.build(targetID: target.id)

        #expect(context.target.authIdentity?.identity == .providerAccount(id: "acct-beta"))
        #expect(context.target.authIdentity?.workspaceLabel == "Team")
        #expect(context.live.authIdentity?.identity == .providerAccount(id: "acct-alpha"))
        #expect(context.live.authIdentity?.workspaceLabel == "Personal")
    }

    @Test
    func `builder preserves target missing auth as degraded home state`() async throws {
        let container = try CodexAccountPromotionTestContainer(
            suiteName: "CodexAccountPromotionPreparationTests-target-missing-auth")
        defer { container.tearDown() }

        let target = try container.createManagedAccount(
            persistedEmail: "beta@example.com",
            authAccountID: "acct-beta")
        try container.persistAccounts([target])
        try FileManager.default.removeItem(
            at: URL(fileURLWithPath: target.managedHomePath, isDirectory: true)
                .appendingPathComponent("auth.json", isDirectory: false))

        let builder = PreparedPromotionContextBuilder(
            store: container.fileStore,
            workspaceResolver: container.workspaceResolver,
            snapshotLoader: SettingsStoreCodexAccountReconciliationSnapshotLoader(settingsStore: container.settings),
            authMaterialReader: DefaultCodexAuthMaterialReader(),
            baseEnvironment: container.baseEnvironment,
            fileManager: .default)

        let context = try await builder.build(targetID: target.id)

        switch context.target.homeState {
        case let .missing(homeURL):
            #expect(homeURL.path == target.managedHomePath)
        case .readable, .unreadable:
            Issue.record("Expected target auth to be represented as missing")
        }
        #expect(context.target.authIdentity == nil)
        #expect(context.target.persistedIdentity.identity == .providerAccount(id: "acct-beta"))
    }

    @Test
    func `builder keeps persisted and direct home identity views separate`() async throws {
        let container = try CodexAccountPromotionTestContainer(
            suiteName: "CodexAccountPromotionPreparationTests-persisted-vs-direct",
            workspaceIdentities: [
                "acct-alpha": CodexOpenAIWorkspaceIdentity(
                    workspaceAccountID: "acct-alpha",
                    workspaceLabel: "Personal"),
            ])
        defer { container.tearDown() }

        let target = try container.createManagedAccount(
            persistedEmail: "beta@example.com",
            authAccountID: "acct-beta")
        let legacy = try container.createManagedAccount(
            persistedEmail: "legacy@example.com",
            authEmail: "alpha@example.com",
            authAccountID: "acct-alpha",
            persistedProviderAccountID: nil,
            useAuthAccountIDAsPersistedProviderAccountID: false)
        try container.persistAccounts([target, legacy])

        let builder = PreparedPromotionContextBuilder(
            store: container.fileStore,
            workspaceResolver: container.workspaceResolver,
            snapshotLoader: SettingsStoreCodexAccountReconciliationSnapshotLoader(settingsStore: container.settings),
            authMaterialReader: DefaultCodexAuthMaterialReader(),
            baseEnvironment: container.baseEnvironment,
            fileManager: .default)

        let context = try await builder.build(targetID: target.id)
        let preparedLegacy = try #require(context.storedManagedAccounts.first(where: { $0.persisted.id == legacy.id }))

        #expect(preparedLegacy.persistedIdentity.email == "legacy@example.com")
        #expect(preparedLegacy.persistedIdentity.identity == .providerAccount(id: "acct-alpha"))
        #expect(preparedLegacy.authIdentity?.email == "alpha@example.com")
        #expect(preparedLegacy.authIdentity?.identity == .providerAccount(id: "acct-alpha"))
        #expect(preparedLegacy.authIdentity?.workspaceLabel == "Personal")
        #expect(preparedLegacy.remoteIdentity.email == "alpha@example.com")
    }

    @Test
    func `runtime account preserves historical email precedence`() throws {
        for candidate in Self.emailPrecedenceCases {
            var payload: [String: Any] = [:]
            if let topLevel = candidate.topLevel.value {
                payload["email"] = topLevel
            }
            if let profile = candidate.profile.value {
                payload["https://api.openai.com/profile"] = ["email": profile]
            }
            let rawData = try Self.authData(idToken: Self.jwt(payload: payload))
            let account = try PreparedPromotionContextBuilder.runtimeAccount(from: rawData)
            #expect(account.email == candidate.expectedEmail, "Scenario: \(candidate.name)")
        }
    }

    private static let emailPrecedenceCases: [PromotionEmailCase] = [
        .init(
            name: "top-level email only",
            topLevel: .string(" Top@Example.COM "),
            profile: .absent,
            expectedEmail: "top@example.com"),
        .init(
            name: "profile email only",
            topLevel: .absent,
            profile: .string(" Profile@Example.COM "),
            expectedEmail: "profile@example.com"),
        .init(
            name: "matching claims",
            topLevel: .string(" Match@Example.COM "),
            profile: .string("match@example.com"),
            expectedEmail: "match@example.com"),
        .init(
            name: "conflicting claims preserve top-level precedence",
            topLevel: .string("top@example.com"),
            profile: .string("profile@example.com"),
            expectedEmail: "top@example.com"),
        .init(
            name: "malformed top-level claim falls back to profile",
            topLevel: .number,
            profile: .string("profile@example.com"),
            expectedEmail: "profile@example.com"),
        .init(
            name: "malformed profile claim does not override valid top-level",
            topLevel: .string("top@example.com"),
            profile: .number,
            expectedEmail: "top@example.com"),
        .init(
            name: "missing top-level claim uses profile",
            topLevel: .absent,
            profile: .string("profile@example.com"),
            expectedEmail: "profile@example.com"),
        .init(
            name: "missing profile claim preserves top-level",
            topLevel: .string("top@example.com"),
            profile: .absent,
            expectedEmail: "top@example.com"),
        .init(name: "missing claims", topLevel: .absent, profile: .absent, expectedEmail: nil),
        .init(
            name: "case and whitespace normalize after top-level selection",
            topLevel: .string(" Top@Example.COM "),
            profile: .string(" top@example.com "),
            expectedEmail: "top@example.com"),
    ]

    private struct PromotionEmailCase {
        let name: String
        let topLevel: Claim
        let profile: Claim
        let expectedEmail: String?
    }

    private enum Claim {
        case absent
        case string(String)
        case number

        var value: Any? {
            switch self {
            case .absent: nil
            case let .string(value): value
            case .number: 42
            }
        }
    }

    private static func authData(idToken: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tokens": ["id_token": idToken]])
    }

    private static func jwt(payload: [String: Any]) throws -> String {
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let encoded = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "synthetic.\(encoded).signature"
    }
}
