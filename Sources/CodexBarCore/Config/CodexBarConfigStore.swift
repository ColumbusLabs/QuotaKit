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

    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = Self.defaultURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
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
            return decoded.normalized()
        } catch {
            throw CodexBarConfigStoreError.decodeFailed(error.localizedDescription)
        }
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
        let normalized = config.normalized()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(normalized)
        } catch {
            throw CodexBarConfigStoreError.encodeFailed(error.localizedDescription)
        }
        let directory = self.fileURL.deletingLastPathComponent()
        if !self.fileManager.fileExists(atPath: directory.path) {
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: self.fileURL, options: [.atomic])
        try self.applySecurePermissionsIfNeeded()
    }

    public func deleteIfPresent() throws {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return }
        try self.fileManager.removeItem(at: self.fileURL)
    }

    public static func defaultURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL
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

        let directory = self.fileURL.deletingLastPathComponent()
        if !self.fileManager.fileExists(atPath: directory.path) {
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try self.fileManager.copyItem(at: legacyURL, to: self.fileURL)
        try self.applySecurePermissionsIfNeeded()
    }

    private func applySecurePermissionsIfNeeded() throws {
        #if os(macOS) || os(Linux)
        try self.fileManager.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o600)),
        ], ofItemAtPath: self.fileURL.path)
        #endif
    }
}
