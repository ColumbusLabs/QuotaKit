import Foundation

/// One way to reach a running Antigravity language server (068 §4.3).
public struct AntigravityEndpoint: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The Antigravity 2.0 app. Requires its `--csrf_token`.
        case app
        /// The Antigravity IDE extension. Requires its `--csrf_token`.
        case ide
        /// `agy` / `antigravity-cli`. Needs no token.
        case cli
    }

    public let pid: Int32
    public let kind: Kind
    public let scheme: String
    public let port: Int
    /// Sent as `X-Codeium-Csrf-Token` for the app and IDE. Never logged.
    public let csrfToken: String

    public init(pid: Int32, kind: Kind, scheme: String, port: Int, csrfToken: String) {
        self.pid = pid
        self.kind = kind
        self.scheme = scheme
        self.port = port
        self.csrfToken = csrfToken
    }
}

/// Classifies processes and reads their flags, following `AntigravityStatusProbe` and
/// `DarwinProcessEnumerator` in the full app. Pure, so the app's kernel scan stays a thin wrapper.
public enum AntigravityProcess {
    /// `DarwinProcessEnumerator.isAntigravityCandidatePath`: the cheap path filter applied before argv is read.
    public static func isCandidatePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        if lower.contains("antigravity") { return true }
        let name = URL(fileURLWithPath: lower).lastPathComponent
        return name.hasPrefix("language_server") || name.hasPrefix("language-server")
            || ["agy", "antigravity-cli", "antigravity_cli"].contains(name)
    }

    /// `antigravityProcessKind`: desktop language servers first, so their token requirement holds.
    public static func kind(of commandLine: String) -> AntigravityEndpoint.Kind? {
        let lower = commandLine.lowercased()
        if self.matches(lower, #"(^|[/\\])language(?:_|-)server(?:[_-][a-z0-9]+)*(?:\.exe)?(\s|$)"#),
           self.isAntigravity(lower)
        {
            return self.isIDE(lower) ? .ide : .app
        }
        if self.matches(lower, #"(^|[/\\])(antigravity-cli|antigravity_cli)([\s/\\]|$)"#)
            || self.matches(lower, #"(^|[/\\])agy(\s|$)"#)
        {
            return .cli
        }
        return nil
    }

    /// Endpoints for one classified process, in the order to try them.
    ///
    /// - A nonzero `--https_server_port` is used directly; 0 means the server chose its own port.
    /// - Otherwise each listening port is tried over HTTPS, then the extension server over HTTP.
    /// - An app or IDE process without a `--csrf_token` is skipped: it would reject every request.
    public static func endpoints(
        pid: Int32,
        commandLine: String,
        listeningPorts: () -> [Int]) -> [AntigravityEndpoint]
    {
        guard let kind = self.kind(of: commandLine) else { return [] }
        let token: String
        if let flag = self.flag("--csrf_token", in: commandLine) {
            token = flag
        } else if kind == .cli {
            token = ""
        } else {
            return []
        }
        // The 2.0 app currently passes `--https_server_port 0` (pick any port), so only a real port skips the scan.
        if let port = self.flag("--https_server_port", in: commandLine).flatMap(Int.init), port > 0 {
            return [AntigravityEndpoint(pid: pid, kind: kind, scheme: "https", port: port, csrfToken: token)]
        }
        var endpoints = listeningPorts().map {
            AntigravityEndpoint(pid: pid, kind: kind, scheme: "https", port: $0, csrfToken: token)
        }
        if let port = self.flag("--extension_server_port", in: commandLine).flatMap(Int.init) {
            let extensionToken = self.flag("--extension_server_csrf_token", in: commandLine)
            for candidate in [extensionToken, token].compactMap(\.self) where !endpoints.contains(where: {
                $0.port == port && $0.csrfToken == candidate
            }) {
                endpoints.append(AntigravityEndpoint(
                    pid: pid,
                    kind: kind,
                    scheme: "http",
                    port: port,
                    csrfToken: candidate))
            }
        }
        return endpoints
    }

    /// `parseProcArgs2Arguments`: argc, the executable path, padding, then argc NUL-terminated arguments. The
    /// environment that follows is never read.
    public static func arguments(fromProcArgs2 data: Data) -> [String]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        let argc = Int(Int32(littleEndian: bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }))
        guard argc >= 0, argc <= bytes.count else { return nil }
        var offset = 4
        guard let executableEnd = bytes[offset...].firstIndex(of: 0) else { return nil }
        offset = executableEnd + 1
        while offset < bytes.count, bytes[offset] == 0 {
            offset += 1
        }
        var arguments: [String] = []
        for _ in 0..<argc {
            guard offset < bytes.count,
                  let end = bytes[offset...].firstIndex(of: 0),
                  let argument = String(bytes: bytes[offset..<end], encoding: .utf8)
            else { return nil }
            arguments.append(argument)
            offset = end + 1
        }
        return arguments
    }

    // MARK: - Private

    private static func isAntigravity(_ lower: String) -> Bool {
        (lower.contains("--app_data_dir") && lower.contains("antigravity"))
            || lower.contains("antigravity.app/")
            || lower.contains("/gemini.app/")
            || lower.contains("antigravity ide.app/")
            || lower.contains("/antigravity/")
    }

    private static func isIDE(_ lower: String) -> Bool {
        [
            "antigravity ide.app/",
            "--app_data_dir antigravity-ide",
            "--app_data_dir=antigravity-ide",
            "/extensions/antigravity/bin/language_server",
        ].contains { lower.contains($0) }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// `extractFlag`: `--flag value` or `--flag=value`.
    static func flag(_ name: String, in commandLine: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))[=\\s]+([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(commandLine.startIndex..<commandLine.endIndex, in: commandLine)
        guard let match = regex.firstMatch(in: commandLine, range: range),
              let tokenRange = Range(match.range(at: 1), in: commandLine)
        else { return nil }
        return String(commandLine[tokenRange])
    }
}
