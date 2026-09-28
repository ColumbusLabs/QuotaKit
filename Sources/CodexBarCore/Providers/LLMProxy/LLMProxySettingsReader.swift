import Foundation

public enum LLMProxySettingsReader {
    public static let apiKeyEnvironmentKey = "LLM_PROXY_API_KEY"
    public static let baseURLEnvironmentKey = "LLM_PROXY_BASE_URL"

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        SettingsValue.cleaned(environment[self.apiKeyEnvironmentKey])
    }

    public static func baseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL?
    {
        guard let raw = SettingsValue.cleaned(environment[self.baseURLEnvironmentKey]) else { return nil }
        // The API key is sent to this URL as a bearer token, so validate it like every other
        // provider override. HTTP stays allowed for loopback and private-network proxies; public
        // hosts must use HTTPS, and no endpoint may carry embedded credentials.
        return ProviderEndpointOverrideValidator().validatedURLAllowingPrivateNetworkHTTP(raw)
    }
}
