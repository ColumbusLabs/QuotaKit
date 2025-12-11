import Foundation

public enum PathPurpose: Hashable, Sendable {
    case rpc
    case tty
    case nodeTooling
}

public struct PathDebugSnapshot: Equatable, Sendable {
    public let codexBinary: String?
    public let claudeBinary: String?
    public let effectivePATH: String
    public let loginShellPATH: String?

    public static let empty = PathDebugSnapshot(
        codexBinary: nil,
        claudeBinary: nil,
        effectivePATH: "",
        loginShellPATH: nil)

    public init(codexBinary: String?, claudeBinary: String?, effectivePATH: String, loginShellPATH: String?) {
        self.codexBinary = codexBinary
        self.claudeBinary = claudeBinary
        self.effectivePATH = effectivePATH
        self.loginShellPATH = loginShellPATH
    }
}

public enum BinaryLocator {
    public static func resolveClaudeBinary(
        env: [String: String] = ProcessInfo.processInfo.environment,
        loginPATH: [String]? = LoginShellPathCache.shared.current,
        fileManager: FileManager = .default,
        home: String = NSHomeDirectory()) -> String?
    {
        self.resolveBinary(
            name: "claude",
            overrideKey: "CLAUDE_CLI_PATH",
            env: env,
            loginPATH: loginPATH,
            fileManager: fileManager,
            home: home)
    }

    public static func resolveCodexBinary(
        env: [String: String] = ProcessInfo.processInfo.environment,
        loginPATH: [String]? = LoginShellPathCache.shared.current,
        fileManager: FileManager = .default,
        home: String = NSHomeDirectory()) -> String?
    {
        self.resolveBinary(
            name: "codex",
            overrideKey: "CODEX_CLI_PATH",
            env: env,
            loginPATH: loginPATH,
            fileManager: fileManager,
            home: home)
    }

    // swiftlint:disable function_parameter_count
    private static func resolveBinary(
        name: String,
        overrideKey: String,
        env: [String: String],
        loginPATH: [String]?,
        fileManager: FileManager,
        home: String) -> String?
    {
        // swiftlint:enable function_parameter_count
        // 1) Explicit override
        if let override = env[overrideKey], fileManager.isExecutableFile(atPath: override) {
            return override
        }

        // 2) Existing PATH
        if let existingPATH = env["PATH"],
           let pathHit = self.find(
               name,
               in: existingPATH.split(separator: ":").map(String.init),
               fileManager: fileManager)
        {
            return pathHit
        }

        // 3) Login-shell PATH (captured once per launch)
        if let loginPATH,
           let pathHit = self.find(name, in: loginPATH, fileManager: fileManager)
        {
            return pathHit
        }

        // 4) Deterministic candidates
        var directCandidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.local/bin/\(name)",
            "\(home)/bin/\(name)",
            "\(home)/.bun/bin/\(name)",
            "\(home)/.npm-global/bin/\(name)",
        ]
        if name == "claude" {
            directCandidates.append(contentsOf: [
                "\(home)/.claude/local/\(name)",
                "\(home)/.claude/bin/\(name)",
            ])
        }
        if let hit = directCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return hit
        }

        // 5) Version managers (bounded scan)
        if let nvmHit = self.scanManagedVersions(
            root: "\(env["NVM_DIR"] ?? "\(home)/.nvm")/versions/node",
            binary: name,
            fileManager: fileManager)
        {
            return nvmHit
        }
        if let fnmHit = self.scanFnm(
            roots: [
                env["FNM_DIR"] ?? "\(home)/.local/share/fnm",
                "\(home)/Library/Application Support/fnm",
                "\(home)/.fnm",
            ],
            binary: name,
            fileManager: fileManager)
        {
            return fnmHit
        }

        if let miseHit = self.scanMise(
            roots: [
                env["MISE_DATA_DIR"] ?? env["RTX_DATA_DIR"] ?? "\(home)/.local/share/mise",
                "\(home)/.mise",
            ],
            binary: name,
            fileManager: fileManager)
        {
            return miseHit
        }

        return nil
    }

    public static func directories(
        for purposes: Set<PathPurpose>,
        env: [String: String],
        loginPATH: [String]?,
        fileManager: FileManager = .default,
        home: String = NSHomeDirectory()) -> [String]
    {
        guard purposes.contains(.rpc) || purposes.contains(.tty) else { return [] }
        var dirs: [String] = []
        if let codex = self.resolveCodexBinary(
            env: env,
            loginPATH: loginPATH,
            fileManager: fileManager,
            home: home)
        {
            dirs.append(URL(fileURLWithPath: codex).deletingLastPathComponent().path)
        }
        if let claude = self.resolveClaudeBinary(
            env: env,
            loginPATH: loginPATH,
            fileManager: fileManager,
            home: home)
        {
            dirs.append(URL(fileURLWithPath: claude).deletingLastPathComponent().path)
        }
        return dirs
    }

    private static func find(_ binary: String, in paths: [String], fileManager: FileManager) -> String? {
        for path in paths where !path.isEmpty {
            let candidate = "\(path.hasSuffix("/") ? String(path.dropLast()) : path)/\(binary)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func scanManagedVersions(root: String, binary: String, fileManager: FileManager) -> String? {
        guard let versions = try? fileManager.contentsOfDirectory(atPath: root) else { return nil }
        for version in versions.sorted(by: self.semverDescending) {
            let candidate = "\(root)/\(version)/bin/\(binary)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// fnm installs live under node-versions/<ver>/installation/bin and aliases/<name>/bin.
    private static func scanFnm(roots: [String], binary: String, fileManager: FileManager) -> String? {
        for root in roots {
            // 1) node-versions/<ver>/installation/bin/<binary>
            let nodeVersions = "\(root)/node-versions"
            if let versions = try? fileManager.contentsOfDirectory(atPath: nodeVersions) {
                for version in versions.sorted(by: self.semverDescending) {
                    let candidate = "\(nodeVersions)/\(version)/installation/bin/\(binary)"
                    if fileManager.isExecutableFile(atPath: candidate) {
                        return candidate
                    }
                }
            }

            // 2) aliases/default|current/bin/<binary> (then other aliases)
            let aliasesDir = "\(root)/aliases"
            if let aliases = try? fileManager.contentsOfDirectory(atPath: aliasesDir) {
                let preferred = ["default", "current"]
                let ordered = preferred + aliases.filter { !preferred.contains($0) }.sorted()
                for name in ordered {
                    let candidate = "\(aliasesDir)/\(name)/bin/\(binary)"
                    if fileManager.isExecutableFile(atPath: candidate) {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    private static func scanMise(roots: [String], binary: String, fileManager: FileManager) -> String? {
        for root in roots {
            // Shims directory is the primary lookup for mise-managed tools.
            let shim = "\(root)/shims/\(binary)"
            if fileManager.isExecutableFile(atPath: shim) {
                return shim
            }

            // Fallback to installed tool locations: installs/<tool>/<version>/bin/<binary>
            let installsRoot = "\(root)/installs"
            guard let tools = try? fileManager.contentsOfDirectory(atPath: installsRoot) else { continue }
            for tool in tools {
                let toolRoot = "\(installsRoot)/\(tool)"
                if let versions = try? fileManager.contentsOfDirectory(atPath: toolRoot) {
                    for version in versions.sorted(by: self.semverDescending) {
                        let candidate = "\(toolRoot)/\(version)/bin/\(binary)"
                        if fileManager.isExecutableFile(atPath: candidate) {
                            return candidate
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func semverDescending(_ lhs: String, _ rhs: String) -> Bool {
        func parse(_ string: String) -> [Int] {
            let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
            return trimmed.split(separator: ".").compactMap { Int($0) }
        }
        let a = parse(lhs)
        let b = parse(rhs)
        let maxCount = max(a.count, b.count)
        for idx in 0..<maxCount {
            let av = idx < a.count ? a[idx] : 0
            let bv = idx < b.count ? b[idx] : 0
            if av == bv { continue }
            return av > bv // descending
        }
        return lhs < rhs // stable tie-breaker
    }
}

public enum PathBuilder {
    public static func effectivePATH(
        purposes: Set<PathPurpose>,
        env: [String: String] = ProcessInfo.processInfo.environment,
        loginPATH: [String]? = LoginShellPathCache.shared.current,
        resolvedBinaryPaths: [String]? = nil,
        home: String = NSHomeDirectory()) -> String
    {
        var parts: [String] = []

        if let existing = env["PATH"], !existing.isEmpty {
            parts.append(contentsOf: existing.split(separator: ":").map(String.init))
        } else {
            parts.append(contentsOf: ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
        }

        // Minimal static baseline
        parts.append("/opt/homebrew/bin")
        parts.append("/usr/local/bin")
        parts.append("\(home)/.local/bin")
        parts.append("\(home)/bin")
        parts.append("\(home)/.bun/bin")
        parts.append("\(home)/.npm-global/bin")

        // Directories for resolved binaries
        let binaries = resolvedBinaryPaths
            ?? BinaryLocator.directories(for: purposes, env: env, loginPATH: loginPATH, home: home)
        parts.append(contentsOf: binaries)

        // Optional login-shell PATH captured once per launch
        if let loginPATH {
            parts.append(contentsOf: loginPATH)
        }

        var seen = Set<String>()
        let deduped = parts.compactMap { part -> String? in
            guard !part.isEmpty else { return nil }
            if seen.insert(part).inserted {
                return part
            }
            return nil
        }

        return deduped.joined(separator: ":")
    }

    public static func debugSnapshot(
        purposes: Set<PathPurpose>,
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()) -> PathDebugSnapshot
    {
        let login = LoginShellPathCache.shared.current
        let effective = self.effectivePATH(
            purposes: purposes,
            env: env,
            loginPATH: login,
            home: home)
        let codex = BinaryLocator.resolveCodexBinary(env: env, loginPATH: login, home: home)
        let claude = BinaryLocator.resolveClaudeBinary(env: env, loginPATH: login, home: home)
        let loginString = login?.joined(separator: ":")
        return PathDebugSnapshot(
            codexBinary: codex,
            claudeBinary: claude,
            effectivePATH: effective,
            loginShellPATH: loginString)
    }
}

enum LoginShellPathCapturer {
    static func capture(
        shell: String? = ProcessInfo.processInfo.environment["SHELL"],
        timeout: TimeInterval = 2.0) -> [String]?
    {
        let shellPath = (shell?.isEmpty == false) ? shell! : "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else { return nil }
        return text.split(separator: ":").map(String.init)
    }
}

public final class LoginShellPathCache: @unchecked Sendable {
    public static let shared = LoginShellPathCache()

    private let lock = NSLock()
    private var captured: [String]?
    private var isCapturing = false
    private var callbacks: [([String]?) -> Void] = []

    public var current: [String]? {
        self.lock.lock()
        let value = self.captured
        self.lock.unlock()
        return value
    }

    public func captureOnce(
        shell: String? = ProcessInfo.processInfo.environment["SHELL"],
        timeout: TimeInterval = 2.0,
        onFinish: (([String]?) -> Void)? = nil)
    {
        self.lock.lock()
        if let captured {
            self.lock.unlock()
            onFinish?(captured)
            return
        }

        if let onFinish {
            self.callbacks.append(onFinish)
        }

        if self.isCapturing {
            self.lock.unlock()
            return
        }

        self.isCapturing = true
        self.lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = LoginShellPathCapturer.capture(shell: shell, timeout: timeout)
            guard let self else { return }

            self.lock.lock()
            self.captured = result
            self.isCapturing = false
            let callbacks = self.callbacks
            self.callbacks.removeAll()
            self.lock.unlock()

            callbacks.forEach { $0(result) }
        }
    }
}
