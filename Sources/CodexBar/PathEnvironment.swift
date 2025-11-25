import Foundation

enum PathPurpose: Hashable {
    case rpc
    case tty
    case nodeTooling
}

struct PathDebugSnapshot: Equatable {
    let codexBinary: String?
    let effectivePATH: String
    let loginShellPATH: String?

    static let empty = PathDebugSnapshot(codexBinary: nil, effectivePATH: "", loginShellPATH: nil)
}

enum BinaryLocator {
    static func resolveCodexBinary(
        env: [String: String] = ProcessInfo.processInfo.environment,
        loginPATH: [String]? = LoginShellPathCache.shared.current,
        fileManager: FileManager = .default,
        home: String = NSHomeDirectory()) -> String?
    {
        // 1) Explicit override
        if let override = env["CODEX_CLI_PATH"], fileManager.isExecutableFile(atPath: override) {
            return override
        }

        // 2) Existing PATH
        if let existingPATH = env["PATH"],
           let pathHit = self.find(
               "codex",
               in: existingPATH.split(separator: ":").map(String.init),
               fileManager: fileManager)
        {
            return pathHit
        }

        // 3) Login-shell PATH (captured once per launch)
        if let loginPATH,
           let pathHit = self.find("codex", in: loginPATH, fileManager: fileManager)
        {
            return pathHit
        }

        // 4) Deterministic candidates
        let directCandidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/bin/codex",
            "\(home)/.bun/bin/codex",
            "\(home)/.npm-global/bin/codex",
        ]
        if let hit = directCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return hit
        }

        // 5) Version managers (bounded scan)
        if let nvmHit = self.scanManagedVersions(
            root: "\(home)/.nvm/versions/node",
            binary: "codex",
            fileManager: fileManager)
        {
            return nvmHit
        }
        if let fnmHit = self.scanManagedVersions(
            root: "\(home)/.local/share/fnm",
            binary: "codex",
            fileManager: fileManager)
        {
            return fnmHit
        }

        return nil
    }

    static func directories(
        for purposes: Set<PathPurpose>,
        env: [String: String],
        loginPATH: [String]?,
        fileManager: FileManager = .default,
        home: String = NSHomeDirectory()) -> [String]
    {
        guard purposes.contains(.rpc) || purposes.contains(.tty) else { return [] }
        if let codex = self.resolveCodexBinary(
            env: env,
            loginPATH: loginPATH,
            fileManager: fileManager,
            home: home)
        {
            return [URL(fileURLWithPath: codex).deletingLastPathComponent().path]
        }
        return []
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
        for version in versions.sorted(by: >) { // newest first
            let candidate = "\(root)/\(version)/bin/\(binary)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

enum PathBuilder {
    static func effectivePATH(
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
        parts.append("\(home)/.local/share/fnm")
        parts.append("\(home)/.fnm")

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

    static func debugSnapshot(
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
        let loginString = login?.joined(separator: ":")
        return PathDebugSnapshot(
            codexBinary: codex,
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

final class LoginShellPathCache: @unchecked Sendable {
    static let shared = LoginShellPathCache()

    private let lock = NSLock()
    private var captured: [String]?
    private var isCapturing = false
    private var callbacks: [([String]?) -> Void] = []

    var current: [String]? {
        self.lock.lock()
        let value = self.captured
        self.lock.unlock()
        return value
    }

    func captureOnce(
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
