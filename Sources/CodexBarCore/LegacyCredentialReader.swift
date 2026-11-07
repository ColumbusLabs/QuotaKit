#if os(macOS)
import Foundation
import Security

/// Reads old provider credentials without allowing background Keychain prompts.
package enum LegacyCredentialReader {
    struct Operations {
        let preflight: (KeychainPromptContext) -> KeychainAccessPreflight.Outcome
        let read: ([String: Any], KeychainSecurity.InteractionPolicy) -> (OSStatus, CFTypeRef?)
        let claim: (String) -> Bool
        let notify: (KeychainPromptContext) -> Bool
        let denial: (String) -> Void

        static let live = Operations(
            preflight: { KeychainAccessPreflight.checkGenericPassword(service: $0.service, account: $0.account) },
            read: { query, policy in
                var result: CFTypeRef?
                let status = KeychainSecurity.copyMatching(query as CFDictionary, &result, interactionPolicy: policy)
                return (status, result)
            },
            claim: { BrowserCookieAccessGate.claimCredentialRead(service: $0) },
            notify: { KeychainPromptHandler.notifyIfHandled($0) },
            denial: { BrowserCookieAccessGate.recordCredentialDenial(service: $0) })
    }

    package static func read(service: String, account: String, kind: KeychainPromptContext.Kind)
        -> (OSStatus, CFTypeRef?)
    {
        self.read(service: service, account: account, kind: kind, operations: .live)
    }

    static func read(
        service: String,
        account: String,
        kind: KeychainPromptContext.Kind,
        operations: Operations) -> (OSStatus, CFTypeRef?)
    {
        guard !Task.isCancelled else { return (errSecInteractionNotAllowed, nil) }
        let context = KeychainPromptContext(kind: kind, service: service, account: account)
        let preflight = operations.preflight(context)
        switch preflight {
        case .notFound: return (errSecItemNotFound, nil)
        case .temporarilyUnavailable: return (errSecInteractionNotAllowed, nil)
        case let .failure(status): return (OSStatus(status), nil)
        case .allowed, .interactionRequired: break
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        if preflight == .allowed {
            var noUIQuery = query
            KeychainNoUIQuery.apply(to: &noUIQuery)
            let result = operations.read(noUIQuery, .nonInteractive)
            guard !Task.isCancelled else { return (errSecInteractionNotAllowed, nil) }
            if result.0 != errSecInteractionNotAllowed { return result }
        }
        guard !Task.isCancelled, operations.claim(service), operations.notify(context), !Task.isCancelled
        else { return (errSecInteractionNotAllowed, nil) }
        let result = operations.read(query, .userInitiatedPrompt)
        if [errSecUserCanceled, errSecAuthFailed, errSecNoAccessForItem, errSecInteractionNotAllowed]
            .contains(result.0)
        {
            operations.denial(service)
        }
        return result
    }
}
#endif
