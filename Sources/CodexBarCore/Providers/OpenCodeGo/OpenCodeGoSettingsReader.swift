import Foundation

public enum OpenCodeGoSettingsReader {
    public static let apiKeyEnvironmentKey = "OPENCODE_API_KEY"

    public static func apiKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard var value = environment[self.apiKeyEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }

        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value = String(value.dropFirst().dropLast())
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func tokenAccountAPIKey(_ raw: String) -> String? {
        guard let value = self.apiKey(environment: [self.apiKeyEnvironmentKey: raw]),
              !value.contains(where: { $0.isWhitespace || $0 == "=" || $0 == ":" })
        else { return nil }
        return value
    }
}
