import Foundation

public struct CodeRabbitCLIProbe: Sendable {
    private let arguments: [String]

    private struct AuthStatusResponse: Decodable {
        let authenticated: Bool
    }

    public init(usageArguments: [String] = ["usage"]) {
        self.arguments = usageArguments
    }

    public func fetch(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()) async throws -> CodeRabbitUsageSnapshot
    {
        let loginPATH = LoginShellPathCache.shared.current
        guard let executable = Self.executable(environment: environment, loginPATH: loginPATH) else {
            throw SubprocessRunnerError.binaryNotFound("coderabbit")
        }
        var commandEnvironment = environment
        commandEnvironment["NO_COLOR"] = "1"
        commandEnvironment["PATH"] = PathBuilder.effectivePATH(
            purposes: [.tty, .nodeTooling], env: environment, loginPATH: loginPATH)

        let authStatusOutput: String
        do {
            authStatusOutput = try await SubprocessRunner.run(
                binary: executable,
                arguments: ["auth", "status", "--agent"],
                environment: commandEnvironment,
                timeout: 15,
                maxOutputBytes: 128 * 1024,
                standardInput: FileHandle.nullDevice,
                label: "coderabbit-auth-status").stdout
        } catch let SubprocessRunnerError.nonZeroExit(_, stderr)
            where CodeRabbitUsageParser.looksSignedOut(stderr)
        {
            throw CodeRabbitUsageError.notLoggedIn
        } catch {
            // Usage can open browser login, so any unavailable or ambiguous
            // status must stop the probe before that command is attempted.
            throw CodeRabbitUsageError.parseFailed
        }
        guard let authStatus = Self.authStatus(from: authStatusOutput) else {
            throw CodeRabbitUsageError.parseFailed
        }
        guard authStatus else { throw CodeRabbitUsageError.notLoggedIn }

        do {
            let result = try await SubprocessRunner.run(
                binary: executable,
                arguments: self.arguments,
                environment: commandEnvironment,
                timeout: 15,
                maxOutputBytes: 128 * 1024,
                standardInput: FileHandle.nullDevice,
                label: "coderabbit-usage")
            return try CodeRabbitUsageParser.parse(usageText: result.stdout + "\n" + result.stderr, now: now)
        } catch let SubprocessRunnerError.nonZeroExit(code, stderr) {
            if CodeRabbitUsageParser.looksSignedOut(stderr) { throw CodeRabbitUsageError.notLoggedIn }
            throw CodeRabbitUsageError.cliFailed(code)
        }
    }

    private static func authStatus(from output: String) -> Bool? {
        guard let data = output.data(using: .utf8),
              let response = try? JSONDecoder().decode(AuthStatusResponse.self, from: data)
        else {
            return nil
        }
        return response.authenticated
    }

    static func executable(environment: [String: String], loginPATH: [String]?) -> String? {
        let override = environment["CODERABBIT_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty {
            return FileManager.default.isExecutableFile(atPath: override) ? override : nil
        }
        let home = NSHomeDirectory()
        return BinaryLocator.resolveBinary(
            name: "coderabbit",
            overrideKey: "CODERABBIT_CLI_PATH",
            env: environment,
            loginPATH: loginPATH,
            commandV: ShellCommandLocator.commandV,
            aliasResolver: ShellCommandLocator.resolveAlias,
            wellKnownPaths: [
                "\(home)/.local/bin/coderabbit",
                "/opt/homebrew/bin/coderabbit",
                "/usr/local/bin/coderabbit",
            ],
            fileManager: .default,
            home: home)
    }
}
