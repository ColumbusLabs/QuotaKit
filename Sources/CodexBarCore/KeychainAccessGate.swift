import Foundation
#if canImport(SweetCookieKit)
import SweetCookieKit
#endif

public enum KeychainAccessGate {
    private static let flagKey = "debugDisableKeychainAccess"
    private static let appGroupID = "group.com.steipete.codexbar"
    private nonisolated(unsafe) static var overrideValue: Bool?
    @TaskLocal private static var taskOverrideValue: Bool?

    public nonisolated(unsafe) static var isDisabled: Bool {
        get {
            if let taskOverrideValue { return taskOverrideValue }
            if let overrideValue { return overrideValue }
            if UserDefaults.standard.bool(forKey: Self.flagKey) { return true }
            if let shared = UserDefaults(suiteName: Self.appGroupID),
               shared.bool(forKey: Self.flagKey)
            {
                return true
            }
            return false
        }
        set {
            overrideValue = newValue
            #if os(macOS) && canImport(SweetCookieKit)
            BrowserCookieKeychainAccessGate.isDisabled = newValue
            #endif
        }
    }

    public static func withIsDisabled<T>(_ isDisabled: Bool, operation: () throws -> T) rethrows -> T {
        try self.$taskOverrideValue.withValue(isDisabled) {
            try operation()
        }
    }

    public static func withIsDisabled<T>(
        _ isDisabled: Bool,
        operation: () async throws -> T) async rethrows -> T
    {
        try await self.$taskOverrideValue.withValue(isDisabled) {
            try await operation()
        }
    }
}
