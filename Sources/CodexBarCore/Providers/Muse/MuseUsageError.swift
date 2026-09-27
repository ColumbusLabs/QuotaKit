import Foundation

public enum MuseUsageError: LocalizedError, Sendable, Equatable {
    case missingCredentials
    case invalidCredentials
    case keychainAccessDisabled
    case keychainUnavailable
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Muse Code login not found. Run `muse login`, then refresh QuotaKit."
        case .invalidCredentials:
            "Muse Code login was rejected. Run `muse login` again."
        case .keychainAccessDisabled:
            "Muse Code login is stored in Keychain. Enable Keychain access in QuotaKit Settings, then refresh."
        case .keychainUnavailable:
            "Muse Code Keychain access is unavailable without showing a prompt. Check Keychain access, then refresh QuotaKit."
        case let .parseFailed(message):
            "Could not parse Muse Code login: \(message)"
        }
    }
}
