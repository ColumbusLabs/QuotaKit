import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeExternalLoginDiscoveryTests {
    @Test
    func `next background availability check discovers a newly created credential file`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("credentials.json")
        let environment = ["HOME": root.path]

        try KeychainAccessGate.withTaskOverrideForTesting(true) {
            try ClaudeOAuthCredentialsStore.withKeychainAccessOverrideForTesting(true) {
                try ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(file) {
                    try ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                        try ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                            try ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                                try ProviderInteractionContext.$current.withValue(.background) {
                                    try ClaudeOAuthFetchStrategy.$claudeCLIAvailableOverride.withValue(false) {
                                        #expect(!ClaudeOAuthPlanningAvailability.isAvailable(
                                            runtime: .app, sourceMode: .auto, environment: environment))
                                        try Data("""
                                        {"claudeAiOauth":{"accessToken":"synthetic-external-login",
                                        "expiresAt":4102444800000,"scopes":["user:profile"]}}
                                        """.utf8).write(to: file)
                                        #expect(ClaudeOAuthPlanningAvailability.isAvailable(
                                            runtime: .app, sourceMode: .auto, environment: environment))
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
