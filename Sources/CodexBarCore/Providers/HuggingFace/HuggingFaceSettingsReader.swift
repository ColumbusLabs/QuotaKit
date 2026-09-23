import Foundation

/// Reads the Hugging Face access token from QuotaKit config projection, the official
/// environment variables, or the token file written by `hf auth login`.
public struct HuggingFaceSettingsReader: Sendable {
    public static let configAPIKeyEnvironmentKey = "QUOTAKIT_HUGGINGFACE_API_KEY"
    public static let apiKeyEnvironmentKeys = [
        "HF_TOKEN",
        "HUGGING_FACE_HUB_TOKEN",
    ]
    public static let tokenPathEnvironmentKey = "HF_TOKEN_PATH"
    public static let homeEnvironmentKey = "HF_HOME"
    public static let cacheHomeEnvironmentKey = "XDG_CACHE_HOME"
    static let maximumTokenFileBytes = 4 * 1024

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String?
    {
        for key in [self.configAPIKeyEnvironmentKey] + self.apiKeyEnvironmentKeys {
            if let token = self.cleaned(environment[key]) {
                return token
            }
        }
        return self.cliToken(environment: environment, homeDirectory: homeDirectory)
    }

    static func cliToken(environment: [String: String], homeDirectory: URL) -> String? {
        let url = self.tokenFileURL(environment: environment, homeDirectory: homeDirectory)
        guard let raw = self.readTokenFile(at: url) else { return nil }
        return self.cleaned(raw.split(whereSeparator: \.isNewline).first.map(String.init))
    }

    private static func readTokenFile(at url: URL) -> String? {
        // O_NONBLOCK avoids waiting forever if an overridden token path points at a FIFO;
        // O_NOFOLLOW keeps a leaf symlink from redirecting this credential read.
        let descriptor = url.path.withCString { open($0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW) }
        guard descriptor >= 0 else { return nil }
        defer { _ = close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_size >= 0,
              metadata.st_size <= off_t(self.maximumTokenFileBytes)
        else {
            return nil
        }

        // Read into a fixed-size buffer so a concurrent growth after fstat is still bounded.
        var bytes = [UInt8](repeating: 0, count: self.maximumTokenFileBytes + 1)
        let count = bytes.withUnsafeMutableBytes { buffer -> Int? in
            guard let baseAddress = buffer.baseAddress else { return nil }
            var count = 0
            while count < buffer.count {
                let readCount = read(descriptor, baseAddress.advanced(by: count), buffer.count - count)
                if readCount > 0 {
                    count += Int(readCount)
                    continue
                }
                if readCount == 0 { return count }
                if errno == EINTR { continue }
                return nil
            }
            return count
        }
        guard let count, count > 0, count <= self.maximumTokenFileBytes else { return nil }
        return String(bytes: bytes.prefix(count), encoding: .utf8)
    }

    static func tokenFileURL(environment: [String: String], homeDirectory: URL) -> URL {
        if let path = self.cleaned(environment[self.tokenPathEnvironmentKey]) {
            return self.expandedPath(path, homeDirectory: homeDirectory)
        }
        if let hfHome = self.cleaned(environment[self.homeEnvironmentKey]) {
            return self.expandedPath(hfHome, homeDirectory: homeDirectory)
                .appendingPathComponent("token", isDirectory: false)
        }
        // huggingface_hub derives its default home from XDG_CACHE_HOME before ~/.cache.
        let cacheRoot: URL = if let xdgCacheHome = self.cleaned(environment[self.cacheHomeEnvironmentKey]) {
            self.expandedPath(xdgCacheHome, homeDirectory: homeDirectory)
        } else {
            homeDirectory.appendingPathComponent(".cache", isDirectory: true)
        }
        return cacheRoot
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("token", isDirectory: false)
    }

    private static func expandedPath(_ path: String, homeDirectory: URL) -> URL {
        if path == "~" { return homeDirectory }
        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }

    private static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value = String(value.dropFirst().dropLast())
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
