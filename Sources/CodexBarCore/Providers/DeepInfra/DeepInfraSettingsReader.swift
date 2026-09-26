import Foundation

public struct DeepInfraSettingsReader: Sendable {
    public static let apiKeyEnvironmentKey = DeepInfraProviderDescriptor.spec.environmentKey
    public static let apiKeyEnvironmentKeys = [Self.apiKeyEnvironmentKey, "DEEPINFRA_TOKEN"]

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        DeepInfraProviderDescriptor.spec.apiKey(environment: environment)
    }
}
