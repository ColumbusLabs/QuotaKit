import Foundation
#if canImport(Security)
import Security
#endif

public enum ProviderTokenSource: String, Sendable {
    case keychain
    case environment
}

public struct ProviderTokenResolution: Sendable {
    public let token: String
    public let source: ProviderTokenSource

    public init(token: String, source: ProviderTokenSource) {
        self.token = token
        self.source = source
    }
}

public enum ProviderTokenResolver {
    private static let log = CodexBarLog.logger("provider-token")

    private static let keychainService = "com.steipete.CodexBar"
    private static let zaiAccount = "zai-api-token"
    private static let syntheticAccount = "synthetic-api-key"
    private static let copilotAccount = "copilot-api-token"
    private static let minimaxCookieAccount = "minimax-cookie"
    private static let minimaxTokenAccount = "minimax-api-token"
    private static let kimiAuthAccount = "kimi-auth-token"
    private static let kimiK2Account = "kimi-k2-api-token"

    public static func zaiToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.zaiResolution(environment: environment)?.token
    }

    public static func syntheticToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.syntheticResolution(environment: environment)?.token
    }

    public static func copilotToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.copilotResolution(environment: environment)?.token
    }

    public static func minimaxToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.minimaxTokenResolution(environment: environment)?.token
    }

    public static func minimaxCookie(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.minimaxCookieResolution(environment: environment)?.token
    }

    public static func kimiAuthToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.kimiAuthResolution(environment: environment)?.token
    }

    public static func kimiK2Token(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.kimiK2Resolution(environment: environment)?.token
    }

    public static func zaiResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnvThenKeychain(
            envToken: ZaiSettingsReader.apiToken(environment: environment),
            keychainAccount: self.zaiAccount)
    }

    public static func syntheticResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnvThenKeychain(
            envToken: SyntheticSettingsReader.apiKey(environment: environment),
            keychainAccount: self.syntheticAccount)
    }

    public static func copilotResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnvThenKeychain(
            envToken: self.cleaned(environment["COPILOT_API_TOKEN"]),
            keychainAccount: self.copilotAccount)
    }

    public static func minimaxTokenResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnvThenKeychain(
            envToken: MiniMaxAPISettingsReader.apiToken(environment: environment),
            keychainAccount: self.minimaxTokenAccount)
    }

    public static func minimaxCookieResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnvThenKeychain(
            envToken: MiniMaxSettingsReader.cookieHeader(environment: environment),
            keychainAccount: self.minimaxCookieAccount)
    }

    public static func kimiAuthResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        if let resolution = self.resolveKeychainThenEnv(
            keychainAccount: self.kimiAuthAccount,
            envToken: KimiSettingsReader.authToken(environment: environment))
        {
            return resolution
        }
        #if os(macOS)
        do {
            let session = try KimiCookieImporter.importSession()
            if let token = session.authToken {
                return ProviderTokenResolution(token: token, source: .environment)
            }
        } catch {
            // No browser cookies found, continue to fallback
        }
        #endif
        return nil
    }

    public static func kimiK2Resolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnvThenKeychain(
            envToken: KimiK2SettingsReader.apiKey(environment: environment),
            keychainAccount: self.kimiK2Account)
    }

    private static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value.removeFirst()
            value.removeLast()
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func resolveEnvThenKeychain(
        envToken: String?,
        keychainAccount: String) -> ProviderTokenResolution?
    {
        if let token = envToken {
            return ProviderTokenResolution(token: token, source: .environment)
        }
        if let token = self.keychainToken(service: self.keychainService, account: keychainAccount) {
            return ProviderTokenResolution(token: token, source: .keychain)
        }
        return nil
    }

    private static func resolveKeychainThenEnv(
        keychainAccount: String,
        envToken: String?) -> ProviderTokenResolution?
    {
        if let token = self.keychainToken(service: self.keychainService, account: keychainAccount) {
            return ProviderTokenResolution(token: token, source: .keychain)
        }
        if let token = envToken {
            return ProviderTokenResolution(token: token, source: .environment)
        }
        return nil
    }

    private static func keychainToken(service: String, account: String) -> String? {
        #if canImport(Security)
        if KeychainAccessGate.isDisabled {
            return nil
        }
        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            self.log.error("Keychain read failed: \(status)")
            return nil
        }

        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
                  !token.isEmpty
        else {
            return nil
        }

        return token
        #else
        _ = service
        _ = account
        return nil
        #endif
    }
}
