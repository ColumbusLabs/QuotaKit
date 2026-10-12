import Darwin
import Foundation
import LiteCore

/// Starts the Claude CLI just long enough for it to renew its own expired login (068 §4.1, amended), the way the
/// full app's `ClaudeOAuthDelegatedRefreshCoordinator` touches it with `/status`.
///
/// `claude` runs in a pseudo-terminal in a folder Lite owns, so it never touches a project. The first run there
/// shows Claude Code's folder-trust prompt; like the full app in its dedicated probe folder, Lite accepts it for this
/// empty folder only, and Claude Code remembers. Success is Claude Code
/// rewriting its Keychain item, seen through the attributes-only metadata read; Lite never sees the token here.
/// The CLI is then asked to quit with Ctrl-C, so it cleans up its session files, and is killed only as a last
/// resort. Nothing is parsed from its output.
struct ClaudeCLIRefresher: Sendable {
    /// Where the CLI is usually installed. A GUI app's PATH doesn't include these, so they are checked directly.
    static let candidatePaths = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "\(NSHomeDirectory())/.local/bin/claude",
        "\(NSHomeDirectory())/.claude/local/claude",
        "\(NSHomeDirectory())/.npm-global/bin/claude",
    ]

    let keychainMetadata: any ClaudeKeychainMetadataReading
    var timeout: TimeInterval = 20

    /// Returns true when Claude Code rewrote its Keychain item, meaning a fresh token is ready to read.
    func refresh() async -> Bool {
        guard let binary = Self.candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              let directory = Self.preparedWorkingDirectory()
        else { return false }
        let before = self.modifiedAt()
        return await Task.detached(priority: .utility) {
            self.run(binary: binary, directory: directory, before: before)
        }.value
    }

    private func modifiedAt() -> Date? {
        if case let .found(modifiedAt) = self.keychainMetadata.claudeCredentialsItemState() {
            return modifiedAt
        }
        return nil
    }

    private func run(binary: String, directory: URL, before: Date?) -> Bool {
        var primary: Int32 = -1
        var secondary: Int32 = -1
        var size = winsize(ws_row: 50, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primary, &secondary, nil, nil, &size) == 0 else { return false }
        _ = fcntl(primary, F_SETFL, O_NONBLOCK)
        defer { close(primary) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["/status"]
        process.currentDirectoryURL = directory
        let terminal = FileHandle(fileDescriptor: secondary, closeOnDealloc: true)
        process.standardInput = terminal
        process.standardOutput = terminal
        process.standardError = terminal
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["PWD"] = directory.path
        let binaryDirectory = URL(fileURLWithPath: binary).deletingLastPathComponent().path
        environment["PATH"] = ([binaryDirectory, "/usr/bin", "/bin"] + [environment["PATH"]].compactMap(\.self))
            .joined(separator: ":")
        process.environment = environment
        do {
            try process.run()
        } catch {
            return false
        }
        try? terminal.close()

        let deadline = Date().addingTimeInterval(self.timeout)
        var screen = Data()
        var answeredTrust = false
        var refreshed = false
        var buffer = [UInt8](repeating: 0, count: 16384)
        while Date() < deadline, process.isRunning {
            // Drain the terminal so the CLI never blocks on a full buffer. Only the trust prompt is looked for.
            var count = read(primary, &buffer, buffer.count)
            while count > 0 {
                screen.append(contentsOf: buffer[0..<count])
                if screen.count > 32768 { screen.removeFirst(screen.count - 32768) }
                count = read(primary, &buffer, buffer.count)
            }
            if let after = self.modifiedAt(), after != before {
                refreshed = true
                break
            }
            if !answeredTrust, let keys = ClaudeCLITrustPrompt.keys(forScreen: screen) {
                Self.write(keys, to: primary)
                answeredTrust = true
            }
            usleep(250_000)
        }
        Self.stop(process, primary: primary, buffer: &buffer)
        return refreshed
    }

    /// Escape closes the `/status` panel, then Ctrl-C twice is how Claude Code exits cleanly (removing its session
    /// file). SIGTERM is ignored, so SIGKILL is the last resort.
    private static func stop(_ process: Process, primary: Int32, buffer: inout [UInt8]) {
        for key in ["\u{1b}", "\u{3}", "\u{3}"] where process.isRunning {
            self.write(key, to: primary)
            usleep(key == "\u{1b}" ? 600_000 : 300_000)
            while read(primary, &buffer, buffer.count) > 0 {}
        }
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning, Date() < deadline {
            while read(primary, &buffer, buffer.count) > 0 {}
            usleep(100_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private static func write(_ text: String, to fd: Int32) {
        _ = text.utf8CString.withUnsafeBufferPointer { pointer in
            Darwin.write(fd, pointer.baseAddress, pointer.count - 1)
        }
    }

    /// `~/Library/Application Support/QuotaKit Lite/claude-cli`, with the full app's local setting that keeps the
    /// CLI from registering deep links.
    private static func preparedWorkingDirectory() -> URL? {
        let directory = LiteStateStore.defaultFileURL().deletingLastPathComponent()
            .appendingPathComponent("claude-cli", isDirectory: true)
        let settings = directory.appendingPathComponent(".claude/settings.local.json")
        do {
            try FileManager.default.createDirectory(
                at: settings.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: settings.path) {
                try Data(#"{"disableDeepLinkRegistration": "disable"}"#.utf8).write(to: settings, options: .atomic)
            }
            return directory
        } catch {
            return nil
        }
    }
}

/// Rations CLI refreshes with `ClaudeCLIRefreshGate`, persisting the last attempt so a relaunch doesn't retry at once.
actor ClaudeLoginRecovery {
    private static let lastAttemptKey = "claudeCLIRefreshLastAttempt"

    private let refresher: ClaudeCLIRefresher
    private var gate: ClaudeCLIRefreshGate

    init(refresher: ClaudeCLIRefresher) {
        self.refresher = refresher
        self.gate = ClaudeCLIRefreshGate(
            lastAttempt: UserDefaults.standard.object(forKey: Self.lastAttemptKey) as? Date)
    }

    /// Runs the CLI if the gate allows it for this failure. True when a fresh token is ready to read.
    func recover(from failure: ProbeFailure, now: Date) async -> Bool {
        guard self.gate.allowsAttempt(for: failure, at: now) else { return false }
        self.gate.recordAttempt(at: now)
        UserDefaults.standard.set(now, forKey: Self.lastAttemptKey)
        return await self.refresher.refresh()
    }
}
