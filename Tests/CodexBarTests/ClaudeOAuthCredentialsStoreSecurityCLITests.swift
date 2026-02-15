import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeOAuthCredentialsStoreSecurityCLITests {
    private func makeCredentialsData(accessToken: String, expiresAt: Date, refreshToken: String? = nil) -> Data {
        let millis = Int(expiresAt.timeIntervalSince1970 * 1000)
        let refreshField: String = {
            guard let refreshToken else { return "" }
            return ",\n            \"refreshToken\": \"\(refreshToken)\""
        }()
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "\(accessToken)",
            "expiresAt": \(millis),
            "scopes": ["user:profile"]\(refreshField)
          }
        }
        """
        return Data(json.utf8)
    }

    @Test
    func experimentalReader_prefersSecurityCLIForNonInteractiveLoad() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                ClaudeOAuthCredentialsStore.invalidateCache()
                ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                defer {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    ClaudeOAuthCredentialsStore.setClaudeKeychainDataOverrideForTesting(nil)
                    ClaudeOAuthCredentialsStore.setClaudeKeychainFingerprintOverrideForTesting(nil)
                }

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let fileURL = tempDir.appendingPathComponent("credentials.json")

                try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                    let securityData = self.makeCredentialsData(
                        accessToken: "security-token",
                        expiresAt: Date(timeIntervalSinceNow: 3600),
                        refreshToken: "security-refresh")

                    let creds = try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                        .securityCLIExperimental,
                        operation: {
                            try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                                .onlyOnUserAction,
                                operation: {
                                    try ProviderInteractionContext.$current.withValue(.userInitiated) {
                                        try ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(
                                            .data(securityData))
                                        {
                                            try ClaudeOAuthCredentialsStore.load(
                                                environment: [:],
                                                allowKeychainPrompt: false)
                                        }
                                    }
                                })
                        })

                    #expect(creds.accessToken == "security-token")
                    #expect(creds.refreshToken == "security-refresh")
                    #expect(creds.scopes.contains("user:profile"))
                }
            }
        }
    }

    @Test
    func experimentalReader_fallsBackWhenSecurityCLIThrows() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                ClaudeOAuthCredentialsStore.invalidateCache()
                ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                defer {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    ClaudeOAuthCredentialsStore.setClaudeKeychainDataOverrideForTesting(nil)
                    ClaudeOAuthCredentialsStore.setClaudeKeychainFingerprintOverrideForTesting(nil)
                }

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let fileURL = tempDir.appendingPathComponent("credentials.json")

                try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                    let fallbackData = self.makeCredentialsData(
                        accessToken: "fallback-token",
                        expiresAt: Date(timeIntervalSinceNow: 3600),
                        refreshToken: "fallback-refresh")

                    let creds = try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                        .securityCLIExperimental,
                        operation: {
                            try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                                .onlyOnUserAction,
                                operation: {
                                    try ProviderInteractionContext.$current.withValue(.userInitiated) {
                                        try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                            data: fallbackData,
                                            fingerprint: nil)
                                        {
                                            try ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(
                                                .timedOut)
                                            {
                                                try ClaudeOAuthCredentialsStore.load(
                                                    environment: [:],
                                                    allowKeychainPrompt: false)
                                            }
                                        }
                                    }
                                })
                        })

                    #expect(creds.accessToken == "fallback-token")
                }
            }
        }
    }

    @Test
    func experimentalReader_fallsBackWhenSecurityCLIOutputMalformed() throws {
        let service = "com.steipete.codexbar.cache.tests.\(UUID().uuidString)"
        try KeychainCacheStore.withServiceOverrideForTesting(service) {
            try KeychainAccessGate.withTaskOverrideForTesting(false) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }

                ClaudeOAuthCredentialsStore.invalidateCache()
                ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                defer {
                    ClaudeOAuthCredentialsStore.invalidateCache()
                    ClaudeOAuthCredentialsStore._resetCredentialsFileTrackingForTesting()
                    ClaudeOAuthCredentialsStore.setClaudeKeychainDataOverrideForTesting(nil)
                    ClaudeOAuthCredentialsStore.setClaudeKeychainFingerprintOverrideForTesting(nil)
                }

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let fileURL = tempDir.appendingPathComponent("credentials.json")

                try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(fileURL) {
                    let fallbackData = self.makeCredentialsData(
                        accessToken: "fallback-token",
                        expiresAt: Date(timeIntervalSinceNow: 3600))

                    let creds = try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                        .securityCLIExperimental,
                        operation: {
                            try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                                .onlyOnUserAction,
                                operation: {
                                    try ProviderInteractionContext.$current.withValue(.userInitiated) {
                                        try ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                            data: fallbackData,
                                            fingerprint: nil)
                                        {
                                            try ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(
                                                .data(Data("not-json".utf8)))
                                            {
                                                try ClaudeOAuthCredentialsStore.load(
                                                    environment: [:],
                                                    allowKeychainPrompt: false)
                                            }
                                        }
                                    }
                                })
                        })

                    #expect(creds.accessToken == "fallback-token")
                }
            }
        }
    }

    @Test
    func experimentalReader_loadFromClaudeKeychainUsesSecurityCLI() throws {
        let securityData = self.makeCredentialsData(
            accessToken: "security-direct",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            refreshToken: "security-refresh")

        let loaded = try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
            .securityCLIExperimental,
            operation: {
                try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                    .always,
                    operation: {
                        try ProviderInteractionContext.$current.withValue(.userInitiated) {
                            try ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(
                                .data(securityData))
                            {
                                try ClaudeOAuthCredentialsStore.loadFromClaudeKeychain()
                            }
                        }
                    })
            })

        let creds = try ClaudeOAuthCredentials.parse(data: loaded)
        #expect(creds.accessToken == "security-direct")
        #expect(creds.refreshToken == "security-refresh")
    }

    @Test
    func experimentalReader_hasClaudeKeychainCredentialsWithoutPrompt_usesSecurityCLI() throws {
        let securityData = self.makeCredentialsData(
            accessToken: "security-available",
            expiresAt: Date(timeIntervalSinceNow: 3600))

        let hasCredentials = try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
            .securityCLIExperimental,
            operation: {
                try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                    .always,
                    operation: {
                        ProviderInteractionContext.$current.withValue(.userInitiated) {
                            ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(
                                .data(securityData))
                            {
                                ClaudeOAuthCredentialsStore.hasClaudeKeychainCredentialsWithoutPrompt()
                            }
                        }
                    })
            })

        #expect(hasCredentials == true)
    }

    @Test
    func experimentalReader_hasClaudeKeychainCredentialsWithoutPrompt_fallsBackWhenSecurityCLIFails() throws {
        let fallbackData = self.makeCredentialsData(
            accessToken: "fallback-available",
            expiresAt: Date(timeIntervalSinceNow: 3600))

        let hasCredentials = try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
            .securityCLIExperimental,
            operation: {
                try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                    .always,
                    operation: {
                        ProviderInteractionContext.$current.withValue(.userInitiated) {
                            ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                data: fallbackData,
                                fingerprint: nil)
                            {
                                ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(
                                    .nonZeroExit)
                                {
                                    ClaudeOAuthCredentialsStore.hasClaudeKeychainCredentialsWithoutPrompt()
                                }
                            }
                        }
                    })
            })

        #expect(hasCredentials == true)
    }

    @Test
    func experimentalReader_ignoresPromptPolicyAndCooldownForBackgroundSilentCheck() throws {
        let securityData = self.makeCredentialsData(
            accessToken: "security-background",
            expiresAt: Date(timeIntervalSinceNow: 3600))

        let hasCredentials = try KeychainAccessGate.withTaskOverrideForTesting(false) {
            try ClaudeOAuthKeychainAccessGate.withShouldAllowPromptOverrideForTesting(false) {
                try ClaudeOAuthKeychainReadStrategyPreference.withTaskOverrideForTesting(
                    .securityCLIExperimental,
                    operation: {
                        try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(
                            .never,
                            operation: {
                                ProviderInteractionContext.$current.withValue(.background) {
                                    ClaudeOAuthCredentialsStore.withSecurityCLIReadOverrideForTesting(
                                        .data(securityData))
                                    {
                                        ClaudeOAuthCredentialsStore.hasClaudeKeychainCredentialsWithoutPrompt()
                                    }
                                }
                            })
                    })
            }
        }

        #expect(hasCredentials == true)
    }
}
