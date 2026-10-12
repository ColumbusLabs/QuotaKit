import Darwin
import Foundation
import LocalAuthentication
import Security

/// Port of the full app's `KeychainNoUIQuery` (`Sources/CodexBarCore/KeychainNoUIQuery.swift`).
///
/// Adds the "no UI" flags to a Keychain query. Phase 0 (068 §10) showed these flags do **not** stop the dialog when
/// reading the data of Claude Code's item, so Lite only uses them on attributes-only queries and on its own item,
/// never as a licence to read Claude Code's secret through `SecItem`.
enum LiteKeychainNoUIQuery {
    private static let uiFailPolicy = Self.resolveUIFailPolicy()

    static func apply(to query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        // Keep the explicit UI-fail policy for the legacy keychain, where `interactionNotAllowed` alone can still
        // surface Allow/Deny prompts.
        query[kSecUseAuthenticationUI as String] = self.uiFailPolicy as CFString
    }

    private static func resolveUIFailPolicy() -> String {
        // Resolve the Security symbol at runtime to get the true constant value without referencing the deprecated
        // API at compile time.
        let securityPath = "/System/Library/Frameworks/Security.framework/Security"
        guard let handle = dlopen(securityPath, RTLD_NOW) else {
            return "u_AuthUIF"
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "kSecUseAuthenticationUIFail") else {
            return "u_AuthUIF"
        }
        let valuePointer = symbol.assumingMemoryBound(to: CFString?.self)
        return (valuePointer.pointee as String?) ?? "u_AuthUIF"
    }
}
