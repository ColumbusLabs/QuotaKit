import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

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
    @ProcessEnvironment private var environment: [String: String]

    public init(
        fileURL: URL = Self.defaultURL(),
        fileManager: FileManager = .default,
        openAIWebAccessEnabledOverride: Bool? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment)
    {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.openAIWebAccessEnabledOverride = openAIWebAccessEnabledOverride
        self.environment = environment
    }

    public func load() throws -> CodexBarConfig? {
        if !self.fileManager.fileExists(atPath: self.fileURL.path) {
            try self.copyLegacyDefaultConfigIfNeeded()
        }
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return nil }
        let data = try Data(contentsOf: self.fileURL)
        guard !data.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }) else { return nil }
        do {
            let decoded = try CodexBarConfig.decode(from: data)
            return self.applyingCodexCookieDenial(to: decoded.normalized())
        } catch {
            throw CodexBarConfigStoreError.decodeFailed(error.localizedDescription)
        }
    }

    private func applyingCodexCookieDenial(to config: CodexBarConfig) -> CodexBarConfig {
        // The CLI reads config independently of the Mac app. Honor a stored web-access denial
        // even while an app config save is pending or when the config file cannot be rewritten.
        // An explicitly selected config path has separate CLI ownership.
        let hasExplicitConfigFile = [Self.pathEnvironmentKey, Self.legacyPathEnvironmentKey].contains {
            !(self.environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        let xdgHome = self.environment[Self.xdgConfigHomeEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasEffectiveXDGHome = !xdgHome.isEmpty &&
            ((xdgHome as NSString).expandingTildeInPath as NSString).isAbsolutePath
        guard !hasExplicitConfigFile, !hasEffectiveXDGHome else { return config }
        let accessEnabled: Bool? = if let override = self.openAIWebAccessEnabledOverride {
            override
        } else if self.fileURL.standardizedFileURL == Self.defaultURL().standardizedFileURL {
            Self.macAppOpenAIWebAccessEnabled()
        } else {
            nil
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
        let defaults = ClaudeOAuthKeychainPromptPreference.applicationUserDefaults
        if let value = defaults.object(forKey: "openAIWebAccessEnabled") as? Bool { return value }
        if let legacy = defaults.object(forKey: "openAIWebAccess") as? Bool { return legacy }
        #endif
        return nil
    }

    public func effectiveDefaultConfig() -> CodexBarConfig {
        self.applyingCodexCookieDenial(to: .makeDefault())
    }

    public func loadOrCreateDefault() throws -> CodexBarConfig {
        if let existing = try self.load() {
            return existing
        }
        let config = self.effectiveDefaultConfig()
        try self.save(config)
        return config
    }

    public func save(_ config: CodexBarConfig) throws {
        let data = try self.encodedData(for: config)
        try self.saveEncodedData(data)
    }

    public func encodedData(for config: CodexBarConfig) throws -> Data {
        do {
            return try config.normalized().encodedData()
        } catch {
            throw CodexBarConfigStoreError.encodeFailed(error.localizedDescription)
        }
    }

    public func saveEncodedData(_ data: Data) throws {
        try self.withWriteLock {
            try CredentialFileWriter.writePrivate(data, to: self.fileURL)
        }
    }

    /// Best-effort refreshes compare and publish under the same lock as ordinary config writes.
    /// Skip contention rather than delaying an interactive writer or publishing a stale credential.
    package func updateIfAvailable(_ update: (inout CodexBarConfig) throws -> Bool) throws {
        try self.withWriteLock(wait: false) {
            guard var config = try self.load(), try update(&config) else { return }
            try CredentialFileWriter.writePrivate(self.encodedData(for: config), to: self.fileURL)
        }
    }

    public func deleteIfPresent() throws {
        try self.withWriteLock {
            if self.fileManager.fileExists(atPath: self.fileURL.path) {
                try self.fileManager.removeItem(at: self.fileURL)
            }
        }
    }

    private func withWriteLock(wait: Bool = true, _ body: () throws -> Void) throws {
        try self.fileManager.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        // Keep this inode: unlinking the lock could give simultaneous writers different locks.
        let descriptor = open(
            self.fileURL.appendingPathExtension("lock").path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
            0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), metadata.st_uid == geteuid()
        else { throw POSIXError(.EINVAL) }
        while flock(descriptor, LOCK_EX | (wait ? 0 : LOCK_NB)) != 0 {
            if errno == EINTR { continue }
            if !wait, errno == EWOULDBLOCK { return }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        try body()
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
