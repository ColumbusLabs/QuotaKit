import Foundation

public enum CodexBarConfigStoreError: LocalizedError {
    case invalidURL
    case decodeFailed(String)
    case encodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid QuotaKit config path."
        case let .decodeFailed(details):
            "Failed to decode QuotaKit config: \(details)"
        case let .encodeFailed(details):
            "Failed to encode QuotaKit config: \(details)"
        }
    }
}

public struct CodexBarConfigStore: @unchecked Sendable {
    public static let pathEnvironmentKey = "QUOTAKIT_CONFIG"
    public static let legacyPathEnvironmentKey = "CODEXBAR_CONFIG"
    public static let xdgConfigHomeEnvironmentKey = "XDG_CONFIG_HOME"

    public let fileURL: URL
    private let fileManager: FileManager
    private let openAIWebAccessEnabledOverride: Bool?

    public init(
        fileURL: URL = Self.defaultURL(),
        fileManager: FileManager = .default,
        openAIWebAccessEnabledOverride: Bool? = nil)
    {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.openAIWebAccessEnabledOverride = openAIWebAccessEnabledOverride
    }

    public func load() throws -> CodexBarConfig? {
        if !self.fileManager.fileExists(atPath: self.fileURL.path) {
            try self.copyLegacyDefaultConfigIfNeeded()
        }
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return nil }
        let data = try Data(contentsOf: self.fileURL)
        let decoder = JSONDecoder()
        do {
            let decoded = try decoder.decode(CodexBarConfig.self, from: data)
            return self.applyingCodexCookieDenial(to: decoded.normalized())
        } catch {
            throw CodexBarConfigStoreError.decodeFailed(error.localizedDescription)
        }
    }

    private func applyingCodexCookieDenial(to config: CodexBarConfig) -> CodexBarConfig {
        // The CLI reads config independently of the Mac app. Honor a stored web-access denial
        // even while an app config save is pending or when the config file cannot be rewritten.
        let accessEnabled: Bool?
        if let override = self.openAIWebAccessEnabledOverride {
            accessEnabled = override
        } else if self.fileURL.standardizedFileURL == Self.defaultURL().standardizedFileURL {
            accessEnabled = Self.macAppOpenAIWebAccessEnabled()
        } else {
            accessEnabled = nil
        }
        guard accessEnabled == false else { return config }
        var denied = config
        var codex = denied.providerConfig(for: .codex) ?? ProviderConfig(id: .codex)
        codex.cookieSource = .off
        denied.setProviderConfig(codex)
        return denied.normalized()
    }

    private static func macAppOpenAIWebAccessEnabled() -> Bool? {
        #if os(macOS)
        for domain in ["com.columbuslabs.quotakit.mac", "com.columbuslabs.quotakit.mac.debug"] {
            guard let defaults = UserDefaults(suiteName: domain) else { continue }
            if let value = defaults.object(forKey: "openAIWebAccessEnabled") as? Bool { return value }
            if let legacy = defaults.object(forKey: "openAIWebAccess") as? Bool { return legacy }
        }
        #endif
        return nil
    }

    public func loadOrCreateDefault() throws -> CodexBarConfig {
        if let existing = try self.load() {
            return existing
        }
        let config = CodexBarConfig.makeDefault()
        try self.save(config)
        return config
    }

    public func save(_ config: CodexBarConfig) throws {
        let data = try self.encodedData(for: config)
        try self.saveEncodedData(data)
    }

    public func encodedData(for config: CodexBarConfig) throws -> Data {
        let normalized = config.normalized()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(normalized)
        } catch {
            throw CodexBarConfigStoreError.encodeFailed(error.localizedDescription)
        }
    }

    public func saveEncodedData(_ data: Data) throws {
        try CredentialFileWriter.writePrivate(data, to: self.fileURL)
    }

    public func deleteIfPresent() throws {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return }
        try self.fileManager.removeItem(at: self.fileURL)
    }

    public static func defaultURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default) -> URL
    {
        if let override = environment[pathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        if let override = environment[legacyPathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }

        if let xdgConfigHome = environment[xdgConfigHomeEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !xdgConfigHome.isEmpty
        {
            let expanded = (xdgConfigHome as NSString).expandingTildeInPath
            if (expanded as NSString).isAbsolutePath {
                return URL(fileURLWithPath: expanded, isDirectory: true)
                    .appendingPathComponent("quotakit", isDirectory: true)
                    .appendingPathComponent("config.json")
            }
        }

        let xdgDefault = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("quotakit", isDirectory: true)
            .appendingPathComponent("config.json")
        if fileManager.fileExists(atPath: xdgDefault.path) {
            return xdgDefault
        }

        return home
            .appendingPathComponent(".quotakit", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public static func legacyDefaultURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".codexbar", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private func copyLegacyDefaultConfigIfNeeded() throws {
        guard self.fileURL.lastPathComponent == "config.json",
              self.fileURL.deletingLastPathComponent().lastPathComponent == ".quotakit"
        else {
            return
        }

        let home = self.fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let legacyURL = Self.legacyDefaultURL(home: home)
        guard self.fileManager.fileExists(atPath: legacyURL.path),
              !self.fileManager.fileExists(atPath: self.fileURL.path)
        else {
            return
        }

        try CredentialFileWriter.writePrivate(Data(contentsOf: legacyURL), to: self.fileURL)
    }
}
