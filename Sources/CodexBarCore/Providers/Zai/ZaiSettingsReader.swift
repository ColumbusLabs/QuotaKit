import Foundation

public struct ZaiSettingsReader: Sendable {
    private static let log = CodexBarLog.logger("zai-settings")

    public static let apiTokenKey = "Z_AI_API_KEY"

    public static func apiToken(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        profilePaths: [String] = [
            "\(NSHomeDirectory())/.profile",
        ]) -> String?
    {
        if let token = cleaned(environment[apiTokenKey]) {
            return token
        }
        for path in profilePaths {
            if let token = Self.apiTokenFromProfile(atPath: path) {
                return token
            }
        }
        return nil
    }

    static func apiTokenFromProfile(atPath path: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            self.log.debug("No profile found at \(path)")
            return nil
        }
        return Self.parseProfile(text)
    }

    static func parseProfile(_ text: String) -> String? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard !line.hasPrefix("#") else { continue }

            if let hashIndex = line.firstIndex(of: "#") {
                line = String(line[..<hashIndex]).trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard line.hasPrefix(Self.apiTokenKey + "=") else { continue }

            let valueStart = line.index(line.startIndex, offsetBy: Self.apiTokenKey.count + 1)
            let rawValue = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
            if let token = Self.cleaned(rawValue) {
                return token
            }
        }
        return nil
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
}

public enum ZaiSettingsError: LocalizedError, Sendable {
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "z.ai API token not found. Set Z_AI_API_KEY in ~/.profile."
        }
    }
}
