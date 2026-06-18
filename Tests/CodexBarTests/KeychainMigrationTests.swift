import Foundation
import LocalAuthentication
import Security
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
struct KeychainMigrationTests {
    @Test
    func `migration list covers known keychain items`() {
        let items = Set(KeychainMigration.itemsToMigrate.map(\.label))
        let expected: Set = [
            "com.steipete.CodexBar:codex-cookie",
            "com.steipete.CodexBar:claude-cookie",
            "com.steipete.CodexBar:cursor-cookie",
            "com.steipete.CodexBar:factory-cookie",
            "com.steipete.CodexBar:minimax-cookie",
            "com.steipete.CodexBar:minimax-api-token",
            "com.steipete.CodexBar:augment-cookie",
            "com.steipete.CodexBar:copilot-api-token",
            "com.steipete.CodexBar:zai-api-token",
            "com.steipete.CodexBar:synthetic-api-key",
        ]

        let missing = expected.subtracting(items)
        #expect(missing.isEmpty, "Missing migration entries: \(missing.sorted())")
    }

    @Test
    func `migration skips item when no UI read would require interaction`() {
        final class Calls {
            var updateCount = 0
        }

        let calls = Calls()
        let item = KeychainMigration.MigrationItem(service: "svc", account: "acct")
        let client = KeychainMigration.SecurityClient(
            copyMatching: { query, _ in
                Self.expectNoUIPolicy(on: query)
                #expect(query[kSecAttrService as String] as? String == "svc")
                #expect(query[kSecAttrAccount as String] as? String == "acct")
                return errSecInteractionNotAllowed
            },
            update: { _, _ in
                calls.updateCount += 1
                return errSecSuccess
            })

        let summary = KeychainMigration.migrateItems([item], client: client)

        #expect(summary.migrated == 0)
        #expect(summary.skippedInteractionRequired == 1)
        #expect(summary.failed == 0)
        #expect(calls.updateCount == 0)
    }

    @Test
    func `migration applies no UI policy to read and update queries`() {
        final class Calls {
            var copyCount = 0
            var updateCount = 0
        }

        let calls = Calls()
        let item = KeychainMigration.MigrationItem(service: "svc", account: "acct")
        let client = KeychainMigration.SecurityClient(
            copyMatching: { query, result in
                calls.copyCount += 1
                Self.expectNoUIPolicy(on: query)
                #expect(query[kSecReturnData as String] == nil)
                result = [
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked as String,
                ] as CFDictionary
                return errSecSuccess
            },
            update: { query, attributes in
                calls.updateCount += 1
                Self.expectNoUIPolicy(on: query)
                #expect(query[kSecAttrService as String] as? String == "svc")
                #expect(query[kSecAttrAccount as String] as? String == "acct")
                #expect(
                    attributes[kSecAttrAccessible as String] as? String
                        == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
                return errSecSuccess
            })

        let summary = KeychainMigration.migrateItems([item], client: client)

        #expect(summary.migrated == 1)
        #expect(summary.skippedInteractionRequired == 0)
        #expect(summary.failed == 0)
        #expect(calls.copyCount == 1)
        #expect(calls.updateCount == 1)
        #expect(summary.isComplete)
    }

    @Test
    func `migration skips item when no UI update would require interaction`() {
        let item = KeychainMigration.MigrationItem(service: "svc", account: "acct")
        let client = KeychainMigration.SecurityClient(
            copyMatching: { _, result in
                result = [
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked as String,
                ] as CFDictionary
                return errSecSuccess
            },
            update: { query, attributes in
                Self.expectNoUIPolicy(on: query)
                #expect(attributes[kSecValueData as String] == nil)
                return errSecInteractionNotAllowed
            })

        let summary = KeychainMigration.migrateItems([item], client: client)

        #expect(summary.migrated == 0)
        #expect(summary.skippedInteractionRequired == 1)
        #expect(summary.failed == 0)
        #expect(!summary.isComplete)
    }

    @Test
    func `migration records update failure without completing`() {
        let item = KeychainMigration.MigrationItem(service: "svc", account: "acct")
        let client = KeychainMigration.SecurityClient(
            copyMatching: { _, result in
                result = [
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked as String,
                ] as CFDictionary
                return errSecSuccess
            },
            update: { _, _ in
                errSecAuthFailed
            })

        let summary = KeychainMigration.migrateItems([item], client: client)

        #expect(summary.migrated == 0)
        #expect(summary.failed == 1)
        #expect(!summary.isComplete)
    }

    @Test
    func `migration retries later when skipped items remain`() {
        final class Calls {
            var copyCount = 0
        }

        let calls = Calls()
        let item = KeychainMigration.MigrationItem(service: "svc", account: "acct")
        let client = KeychainMigration.SecurityClient(
            copyMatching: { _, _ in
                calls.copyCount += 1
                return errSecInteractionNotAllowed
            },
            update: { _, _ in
                errSecSuccess
            })

        KeychainMigration.resetMigrationFlag()
        defer { KeychainMigration.resetMigrationFlag() }

        KeychainAccessGate.withTaskOverrideForTesting(false) {
            _ = KeychainMigration.migrateIfNeeded(items: [item], client: client)
            _ = KeychainMigration.migrateIfNeeded(items: [item], client: client)
        }

        #expect(calls.copyCount == 2)
    }

    @Test
    func `migration completion flag is set when all items are handled`() {
        final class Calls {
            var copyCount = 0
        }

        let calls = Calls()
        let item = KeychainMigration.MigrationItem(service: "svc", account: "acct")
        let client = KeychainMigration.SecurityClient(
            copyMatching: { _, result in
                calls.copyCount += 1
                result = [
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
                ] as CFDictionary
                return errSecSuccess
            },
            update: { _, _ in
                Issue.record("Already-current items must not be updated")
                return errSecSuccess
            })

        KeychainMigration.resetMigrationFlag()
        defer { KeychainMigration.resetMigrationFlag() }

        KeychainAccessGate.withTaskOverrideForTesting(false) {
            _ = KeychainMigration.migrateIfNeeded(items: [item], client: client)
            _ = KeychainMigration.migrateIfNeeded(items: [item], client: client)
        }

        #expect(calls.copyCount == 1)
    }

    private static func expectNoUIPolicy(on query: [String: Any]) {
        #expect(query[kSecUseAuthenticationUI as String] as? String == KeychainNoUIQuery.uiFailPolicyForTesting())
        let context = query[kSecUseAuthenticationContext as String] as? LAContext
        #expect(context?.interactionNotAllowed == true)
    }
}
