import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
import LocalAuthentication
import Security

@Suite(.serialized, ClaudeOAuthDefaultsFixtures())
struct ClaudeExternalLoginFreshnessTests {
    private static let failureDate = Date(timeIntervalSince1970: 1_600_000_000)
    private static let loginDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func `new consented Keychain metadata replaces stale missing credentials guidance`() throws {
        try self.withFixture { _, environment, key in
            let firstError = self.loadError(environment)
            guard case .notFound = firstError else {
                Issue.record("The initial missing credential should keep its existing guidance")
                return
            }
            #expect(ClaudeOAuthDefaultsFixtures.defaults.object(forKey: key) is Date)
            ClaudeOAuthDefaultsFixtures.defaults.set(Self.failureDate, forKey: key)

            let capture = QueryCapture()
            self.withMetadata(Self.loginDate, capture: capture) {
                ClaudeOAuthDirectKeychainReadConsent.withTaskOverrideForTesting(true) {
                    ProviderInteractionContext.$current.withValue(.userInitiated) {
                        let error = self.loadError(environment)
                        #expect(error.localizedDescription.contains("Claude Code credentials changed"))
                        #expect(error.localizedDescription.contains("Refresh"))
                        #expect(!error.localizedDescription.contains("Run `claude`"))
                        #expect(ClaudeOAuthDefaultsFixtures.defaults.object(forKey: key) as? Date == Self.failureDate)
                    }
                }
            }
            #expect(capture.metadataQueries.count == 1)
        }
    }

    @Test(arguments: [nil, Self.failureDate, Self.failureDate.addingTimeInterval(-1), Date.distantFuture])
    func `absent old equal and future metadata preserve missing credentials guidance`(date: Date?) throws {
        try self.withFixture { _, environment, key in
            ClaudeOAuthDefaultsFixtures.defaults.set(Self.failureDate, forKey: key)
            let capture = QueryCapture()
            self.withMetadata(date, capture: capture) {
                ClaudeOAuthDirectKeychainReadConsent.withTaskOverrideForTesting(true) {
                    ProviderInteractionContext.$current.withValue(.userInitiated) {
                        guard case .notFound = self.loadError(environment) else {
                            Issue.record("Only newer metadata from a permitted no-UI query should replace the error")
                            return
                        }
                    }
                }
            }
            #expect(capture.metadataQueries.count == 1)
        }
    }

    @Test
    func `user-initiated metadata checks still require direct-read consent`() throws {
        try self.withFixture { _, environment, key in
            ClaudeOAuthDefaultsFixtures.defaults.set(Self.failureDate, forKey: key)
            let capture = QueryCapture()
            self.withMetadata(Self.loginDate, capture: capture) {
                ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                    ClaudeOAuthDirectKeychainReadConsent.withTaskOverrideForTesting(false) {
                        ProviderInteractionContext.$current.withValue(.userInitiated) {
                            guard case .notFound = self.loadError(environment) else {
                                Issue.record("Without direct-read consent the credential error must remain unchanged")
                                return
                            }
                        }
                    }
                }
            }
            #expect(capture.queries.isEmpty)
        }
    }

    @Test
    func `background metadata checks stay closed even when direct-read consent is granted`() throws {
        try self.withFixture { _, environment, key in
            ClaudeOAuthDefaultsFixtures.defaults.set(Self.failureDate, forKey: key)
            let capture = QueryCapture()
            self.withMetadata(Self.loginDate, capture: capture) {
                ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                    ClaudeOAuthDirectKeychainReadConsent.withTaskOverrideForTesting(true) {
                        ProviderInteractionContext.$current.withValue(.background) {
                            guard case .notFound = self.loadError(environment) else {
                                Issue.record("Background reads must remain blocked by the interaction policy")
                                return
                            }
                        }
                    }
                }
            }
            #expect(capture.queries.isEmpty)
        }
    }

    @Test
    func `never-prompt policy blocks user-initiated metadata checks`() throws {
        try self.withFixture { _, environment, key in
            ClaudeOAuthDefaultsFixtures.defaults.set(Self.failureDate, forKey: key)
            let capture = QueryCapture()
            self.withMetadata(Self.loginDate, capture: capture) {
                ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.never) {
                    ClaudeOAuthDirectKeychainReadConsent.withTaskOverrideForTesting(true) {
                        ProviderInteractionContext.$current.withValue(.userInitiated) {
                            guard case .notFound = self.loadError(environment) else {
                                Issue.record("Never prompt must preserve the missing-credentials guidance")
                                return
                            }
                        }
                    }
                }
            }
            #expect(capture.queries.isEmpty)
        }
    }

    @Test
    func `successful file credential load clears the previous missing failure`() throws {
        try self.withFixture { file, environment, key in
            ClaudeOAuthDefaultsFixtures.defaults.set(Self.failureDate, forKey: key)
            try Data("""
            {"claudeAiOauth":{"accessToken":"synthetic-external-login",
            "expiresAt":4102444800000,"scopes":["user:profile"]}}
            """.utf8).write(to: file)

            let record = try ClaudeOAuthCredentialsStore.loadRecord(
                environment: environment,
                allowKeychainPrompt: false)
            #expect(record.credentials.accessToken == "synthetic-external-login")
            #expect(ClaudeOAuthDefaultsFixtures.defaults.object(forKey: key) == nil)
        }
    }

    @Test
    func `custom Claude profiles use only their own file modification date`() throws {
        try self.withFixture(customProfile: true) { file, environment, _ in
            try Data("synthetic metadata only".utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Self.loginDate], ofItemAtPath: file.path)
            let capture = QueryCapture()
            self.withMetadata(Self.loginDate.addingTimeInterval(60), capture: capture) {
                ClaudeOAuthDirectKeychainReadConsent.withTaskOverrideForTesting(true) {
                    ProviderInteractionContext.$current.withValue(.userInitiated) {
                        #expect(ClaudeOAuthCredentialsStore.latestCredentialModificationDate(environment: environment)
                            == Self.loginDate)
                    }
                }
            }
            #expect(capture.queries.isEmpty)
        }
    }

    @Test
    func `fallback errors keep refresh guidance while cancellation remains terminal`() {
        let changed = ClaudeOAuthCredentialsError.credentialsChanged(Self.loginDate)
        let fallback = ClaudeUsageError.oauthFailed("synthetic CLI failure")
        #expect(
            ClaudeProviderDescriptor.resolveFallbackError(changed, fallback).localizedDescription
                == changed.localizedDescription)
        let cancelled = ClaudeProviderDescriptor.resolveFallbackError(changed, CancellationError())
        #expect(ClaudeOAuthFetchError.isCancellation(cancelled))
    }

    private func withFixture(
        customProfile: Bool = false,
        operation: (URL, [String: String], String) throws -> Void) throws
    {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent(customProfile ? "custom" : ".claude")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = directory.appendingPathComponent(".credentials.json")
        var environment = ["HOME": root.path]
        if customProfile { environment[ClaudeConfigPaths.configDirectoryEnvironmentKey] = directory.path }
        let deniedUntilStore = ClaudeOAuthKeychainAccessGate.DeniedUntilStore()

        try KeychainCacheStore.withServiceOverrideForTesting("synthetic-login-\(UUID())") {
            KeychainCacheStore.setTestStoreForTesting(true)
            defer { KeychainCacheStore.setTestStoreForTesting(false) }
            try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(file) {
                let profile = ClaudeOAuthCredentialsStore.credentialsProfileIdentifier(environment: environment)
                let failureKey = "ClaudeOAuthLastCredentialFailure." + profile
                ClaudeOAuthDefaultsFixtures.defaults.removeObject(forKey: failureKey)
                defer { ClaudeOAuthDefaultsFixtures.defaults.removeObject(forKey: failureKey) }
                try KeychainAccessGate.withTaskOverrideForTesting(false) {
                    try ClaudeOAuthKeychainAccessGate.withDeniedUntilStoreOverrideForTesting(deniedUntilStore) {
                        try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                            try ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                                try ClaudeOAuthDirectKeychainReadConsent.withTaskOverrideForTesting(false) {
                                    try ClaudeOAuthKeychainPromptPreference
                                        .withTaskOverrideForTesting(.onlyOnUserAction) {
                                            try ProviderInteractionContext.$current.withValue(.background) {
                                                try ClaudeOAuthCredentialsStore
                                                    .withClaudeKeychainFingerprintStoreOverrideForTesting(.init()) {
                                                        try operation(file, environment, failureKey)
                                                    }
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadError(_ environment: [String: String]) -> ClaudeOAuthCredentialsError {
        do {
            _ = try ClaudeOAuthCredentialsStore.loadRecord(environment: environment, allowKeychainPrompt: false)
            Issue.record("Missing credentials must remain a failure until credentials become readable")
        } catch let error as ClaudeOAuthCredentialsError {
            return error
        } catch {
            Issue.record("Unexpected credential failure type")
        }
        return .notFound
    }

    private func withMetadata(
        _ date: Date?,
        capture: QueryCapture,
        operation: () throws -> Void) rethrows
    {
        let override: @Sendable ([String: Any]) -> (OSStatus, AnyObject?, Double) = { query in
            capture.record(query)
            let isMetadataQuery = query[kSecMatchLimit as String] as? String == kSecMatchLimitAll as String
                && query[kSecReturnData as String] == nil
                && query[kSecReturnPersistentRef as String] == nil
            guard isMetadataQuery else { return (errSecItemNotFound, nil, 0) }

            #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
            #expect(query[kSecAttrService as String] as? String == "Claude Code-credentials")
            #expect(query[kSecReturnAttributes as String] as? Bool == true)
            #expect(query[kSecReturnRef as String] == nil)
            #expect((query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true)
            #expect(query[kSecUseAuthenticationUI as String] as? String == KeychainNoUIQuery.uiFailPolicyForTesting())
            let rows: [[String: Any]] = date.map { [[kSecAttrModificationDate as String: $0]] } ?? []
            return (errSecSuccess, rows as NSArray, 0)
        }
        try ClaudeOAuthKeychainQueryTiming.$copyMatchingOverride.withValue(override, operation: operation)
    }

    private final class QueryCapture: @unchecked Sendable {
        private let lock = NSLock()
        private var storedQueries: [[String: Any]] = []

        var queries: [[String: Any]] {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.storedQueries
        }

        var metadataQueries: [[String: Any]] {
            self.queries.filter {
                $0[kSecMatchLimit as String] as? String == kSecMatchLimitAll as String
                    && $0[kSecReturnData as String] == nil
                    && $0[kSecReturnPersistentRef as String] == nil
            }
        }

        func record(_ query: [String: Any]) {
            self.lock.lock()
            defer { self.lock.unlock() }
            self.storedQueries.append(query)
        }
    }
}
#endif
