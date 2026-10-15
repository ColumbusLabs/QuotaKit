import Foundation

public enum MuseUsageError: LocalizedError, Sendable, Equatable {
    case missingCredentials
    case invalidCredentials
    case keychainAccessDisabled
    case keychainAccessNotGranted
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
        case .keychainAccessNotGranted:
            "Muse Code credentials are in Keychain, but QuotaKit is not allowed to read them. "
                + "In Keychain Access, open “\(MuseCredentials.keychainService)” → Access Control, "
                + "add QuotaKit (for CLI use, also Contents/Helpers/QuotaKitCLI in QuotaKit.app), then refresh."
        case .keychainUnavailable:
            "Muse Code credentials could not be read from Keychain right now. "
                + "If the login Keychain is locked, unlock it, then refresh QuotaKit."
        case let .parseFailed(message):
            "Could not parse Muse Code login: \(message)"
        }
    }
}
