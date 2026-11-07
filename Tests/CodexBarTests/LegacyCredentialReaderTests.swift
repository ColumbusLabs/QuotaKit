#if os(macOS)
import Foundation
import Security
import Testing
@testable import CodexBarCore

struct LegacyCredentialReaderTests {
    @Test
    func `locked or missing legacy credentials never open a prompt`() {
        for preflight in [KeychainAccessPreflight.Outcome.temporarilyUnavailable, .notFound] {
            var reads = 0
            var claims = 0
            let operations = LegacyCredentialReader.Operations(
                preflight: { _ in preflight },
                read: { _, _ in reads += 1; return (errSecSuccess, nil) },
                claim: { _ in claims += 1; return true },
                notify: { _ in true },
                denial: { _ in })
            let result = LegacyCredentialReader.read(
                service: "fixture", account: "fixture", kind: .zaiToken, operations: operations)
            #expect(result.0 == (preflight == .notFound ? errSecItemNotFound : errSecInteractionNotAllowed))
            #expect(reads == 0)
            #expect(claims == 0)
        }
    }

    @Test
    func `denied silent read escalates only through the retry allowance`() {
        var policies: [String] = []
        var notified = 0
        var denied = 0
        let operations = LegacyCredentialReader.Operations(
            preflight: { _ in .allowed },
            read: { query, policy in
                if policy == .nonInteractive {
                    policies.append("silent")
                    #expect(query[kSecUseAuthenticationContext as String] != nil)
                    return (errSecInteractionNotAllowed, nil)
                }
                policies.append("interactive")
                return (errSecUserCanceled, nil)
            },
            claim: { _ in true },
            notify: { _ in notified += 1; return true },
            denial: { _ in denied += 1 })
        let result = LegacyCredentialReader.read(
            service: "fixture", account: "fixture", kind: .zaiToken, operations: operations)
        #expect(result.0 == errSecUserCanceled)
        #expect(policies == ["silent", "interactive"])
        #expect(notified == 1)
        #expect(denied == 1)
    }

    @Test
    func `denied allowance never invokes an interactive read`() {
        var reads = 0
        let operations = LegacyCredentialReader.Operations(
            preflight: { _ in .interactionRequired },
            read: { _, _ in reads += 1; return (errSecSuccess, nil) },
            claim: { _ in false },
            notify: { _ in Issue.record("unexpected prompt"); return true },
            denial: { _ in })
        let result = LegacyCredentialReader.read(
            service: "fixture", account: "fixture", kind: .zaiToken, operations: operations)
        #expect(result.0 == errSecInteractionNotAllowed)
        #expect(reads == 0)
    }
}
#endif
