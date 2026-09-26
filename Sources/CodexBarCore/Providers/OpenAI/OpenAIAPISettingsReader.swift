import Foundation

public enum OpenAIAPISettingsReader {
    public static let adminAPIKeyEnvironmentKey = "OPENAI_ADMIN_KEY"
    public static let apiKeyEnvironmentKey = "OPENAI_API_KEY"
    public static let projectIDEnvironmentKey = "OPENAI_PROJECT_ID"
    public static let apiKeyEnvironmentKeys = [
        Self.adminAPIKeyEnvironmentKey,
        Self.apiKeyEnvironmentKey,
    ]

    public static func apiKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        SettingsValue.first(in: environment, keys: self.apiKeyEnvironmentKeys)
    }

    public static func adminAPIKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        SettingsValue.cleaned(environment[self.adminAPIKeyEnvironmentKey])
    }

    public static func projectID(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        SettingsValue.cleaned(environment[self.projectIDEnvironmentKey])
    }

    static func cleaned(_ raw: String?) -> String? {
        SettingsValue.cleaned(raw)
    }
}

public enum OpenAIAPISettingsError: LocalizedError, Sendable {
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "OpenAI API key not configured. Set OPENAI_API_KEY or configure an API key in Settings."
        }
    }
}
