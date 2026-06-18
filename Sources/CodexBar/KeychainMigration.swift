import CodexBarCore
import Foundation
import Security

/// Migrates keychain items to use kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
/// to prevent permission prompts on every rebuild during development.
enum KeychainMigration {
    private static let log = CodexBarLog.logger(LogCategories.keychainMigration)
    private static let migrationKey = "KeychainMigrationV1Completed"

    struct MigrationItem: Hashable {
        let service: String
        let account: String?

        var label: String {
            let accountLabel = self.account ?? "<any>"
            return "\(self.service):\(accountLabel)"
        }
    }

    enum MigrationOutcome: Equatable {
        case migrated
        case missing
        case alreadyCurrent
        case skippedInteractionRequired
    }

    struct MigrationSummary: Equatable {
        var migrated = 0
        var missing = 0
        var alreadyCurrent = 0
        var skippedInteractionRequired = 0
        var failed = 0

        var isComplete: Bool {
            self.skippedInteractionRequired == 0 && self.failed == 0
        }

        mutating func record(_ outcome: MigrationOutcome) {
            switch outcome {
            case .migrated:
                self.migrated += 1
            case .missing:
                self.missing += 1
            case .alreadyCurrent:
                self.alreadyCurrent += 1
            case .skippedInteractionRequired:
                self.skippedInteractionRequired += 1
            }
        }
    }

    struct SecurityClient: @unchecked Sendable {
        var copyMatching: ([String: Any], inout CFTypeRef?) -> OSStatus
        var update: ([String: Any], [String: Any]) -> OSStatus

        static let live = SecurityClient(
            copyMatching: { query, result in
                SecItemCopyMatching(query as CFDictionary, &result)
            },
            update: { query, attributes in
                SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            })
    }

    static let itemsToMigrate: [MigrationItem] = [
        MigrationItem(service: "com.steipete.CodexBar", account: "codex-cookie"),
        MigrationItem(service: "com.steipete.CodexBar", account: "claude-cookie"),
        MigrationItem(service: "com.steipete.CodexBar", account: "cursor-cookie"),
        MigrationItem(service: "com.steipete.CodexBar", account: "factory-cookie"),
        MigrationItem(service: "com.steipete.CodexBar", account: "minimax-cookie"),
        MigrationItem(service: "com.steipete.CodexBar", account: "minimax-api-token"),
        MigrationItem(service: "com.steipete.CodexBar", account: "augment-cookie"),
        MigrationItem(service: "com.steipete.CodexBar", account: "copilot-api-token"),
        MigrationItem(service: "com.steipete.CodexBar", account: "zai-api-token"),
        MigrationItem(service: "com.steipete.CodexBar", account: "synthetic-api-key"),
    ]

    /// Run migration once per installation
    @discardableResult
    static func migrateIfNeeded() -> MigrationSummary {
        self.migrateIfNeeded(items: self.itemsToMigrate, client: .live)
    }

    @discardableResult
    static func migrateIfNeeded(
        items: [MigrationItem],
        client: SecurityClient) -> MigrationSummary
    {
        guard !KeychainAccessGate.isDisabled else {
            self.log.info("Keychain access disabled; skipping migration")
            return MigrationSummary()
        }

        if !UserDefaults.standard.bool(forKey: self.migrationKey) {
            self.log.info("Starting keychain migration to reduce permission prompts")

            let summary = self.migrateItems(items, client: client)

            self.log.info(
                """
                Keychain migration complete: \(summary.migrated) migrated, \(summary.alreadyCurrent) already current, \
                \(summary.missing) missing, \(summary.skippedInteractionRequired) skipped for interaction, \
                \(summary.failed) errors
                """)
            if summary.isComplete {
                UserDefaults.standard.set(true, forKey: self.migrationKey)

                if summary.migrated > 0 {
                    self.log.info("✅ Future rebuilds will not prompt for keychain access")
                }
            } else {
                self.log.info("Keychain migration incomplete; will retry later without showing prompts")
            }
            return summary
        } else {
            self.log.debug("Keychain migration already completed, skipping")
            return MigrationSummary()
        }
    }

    static func migrateItems(
        _ items: [MigrationItem],
        client: SecurityClient = .live) -> MigrationSummary
    {
        var summary = MigrationSummary()
        for item in items {
            do {
                let outcome = try self.migrateItem(item, client: client)
                summary.record(outcome)
            } catch {
                summary.failed += 1
                self.log.error("Failed to migrate \(item.label): \(String(describing: error))")
            }
        }
        return summary
    }

    /// Migrate a single keychain item to the new accessibility level
    /// Returns a non-interactive migration outcome. Items that would require
    /// a macOS prompt are skipped so launch never triggers credential dialogs.
    static func migrateItem(_ item: MigrationItem, client: SecurityClient = .live) throws -> MigrationOutcome {
        // First, try to read the existing item
        var result: CFTypeRef?
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        if let account = item.account {
            query[kSecAttrAccount as String] = account
        }
        KeychainNoUIQuery.apply(to: &query)

        let status = client.copyMatching(query, &result)

        if status == errSecItemNotFound {
            // Item doesn't exist, nothing to migrate
            return .missing
        }

        if status == errSecInteractionNotAllowed {
            self.log.info("Skipping \(item.label); migration would require Keychain interaction")
            return .skippedInteractionRequired
        }

        guard status == errSecSuccess else {
            throw KeychainMigrationError.readFailed(status)
        }

        guard let rawItem = result as? [String: Any],
              let accessible = rawItem[kSecAttrAccessible as String] as? String
        else {
            throw KeychainMigrationError.invalidItemFormat
        }

        // Check if already using the correct accessibility
        if accessible == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String) {
            self.log.debug("\(item.label) already using correct accessibility")
            return .alreadyCurrent
        }

        var updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
        ]
        if let account = item.account {
            updateQuery[kSecAttrAccount as String] = account
        }
        KeychainNoUIQuery.apply(to: &updateQuery)

        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = client.update(updateQuery, attributes)
        if updateStatus == errSecInteractionNotAllowed {
            self.log.info("Skipping \(item.label); update would require Keychain interaction")
            return .skippedInteractionRequired
        }
        guard updateStatus == errSecSuccess else {
            throw KeychainMigrationError.updateFailed(updateStatus)
        }

        self.log.info("Migrated \(item.label) to new accessibility level")
        return .migrated
    }

    /// Reset migration flag (for testing)
    static func resetMigrationFlag() {
        UserDefaults.standard.removeObject(forKey: self.migrationKey)
    }
}

enum KeychainMigrationError: Error {
    case readFailed(OSStatus)
    case updateFailed(OSStatus)
    case invalidItemFormat
}
