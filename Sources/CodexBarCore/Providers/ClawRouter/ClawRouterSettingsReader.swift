import Foundation

public enum ClawRouterSettingsError: LocalizedError, Equatable, Sendable {
    case invalidEndpointOverride(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidEndpointOverride(key):
            "ClawRouter endpoint override \(key) is invalid. Use an HTTPS URL without embedded credentials."
        }
    }
}

public enum ClawRouterSettingsReader {
    public static let apiKeyEnvironmentKey = "CLAWROUTER_API_KEY"
    public static let baseURLEnvironmentKey = "CLAWROUTER_BASE_URL"
    public static let defaultBaseURL = URL(string: "https://clawrouter.openclaw.ai")!
    public static let missingCredentialsMessage =
        "Missing ClawRouter API key. Add one in Settings or set CLAWROUTER_API_KEY."

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.cleaned(environment[self.apiKeyEnvironmentKey])
    }

    public static func baseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL
    {
        guard let raw = self.cleaned(environment[self.baseURLEnvironmentKey]) else {
            return self.defaultBaseURL
        }
        guard let url = ProviderEndpointOverrideValidator.normalizedHTTPSURL(from: raw),
              url.query == nil,
              url.fragment == nil
        else { return self.defaultBaseURL }
        return url
    }

    public static func validateEndpointOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment) throws
    {
        guard let raw = self.cleaned(environment[self.baseURLEnvironmentKey]) else { return }
        guard let url = ProviderEndpointOverrideValidator.normalizedHTTPSURL(from: raw),
              url.query == nil,
              url.fragment == nil
        else {
            throw ClawRouterSettingsError.invalidEndpointOverride(self.baseURLEnvironmentKey)
        }
    }

    static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value = String(value.dropFirst().dropLast())
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
