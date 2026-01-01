import Foundation
import XCTest

#if canImport(Darwin)
import Darwin
#endif

final class TestProcessCleanupObserver: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared = TestProcessCleanupObserver()

    override private init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        // Belt+suspenders: when a test forgets to tear down Codex RPC (app-server),
        // don't leave a daemon-ish CLI process around after the test run.
        self.terminateLeakedCodexAppServers()
    }

    private func terminateLeakedCodexAppServers() {
        #if canImport(Darwin)
        let pids = Self.pids(matchingFullCommandRegex: "codex.*app-server")
            .filter { $0 > 0 && $0 != getpid() }
        guard !pids.isEmpty else { return }

        for pid in pids {
            _ = kill(pid, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            let stillRunning = pids.contains(where: { kill($0, 0) == 0 })
            if !stillRunning { return }
            usleep(50000)
        }

        for pid in pids where kill(pid, 0) == 0 {
            _ = kill(pid, SIGKILL)
        }
        #endif
    }

    private static func pids(matchingFullCommandRegex regex: String) -> [pid_t] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-f", regex]

        let stdout = Pipe()
        proc.standardOutput = stdout
        proc.standardError = Pipe()
        proc.standardInput = nil

        do {
            try proc.run()
        } catch {
            return []
        }
        proc.waitUntilExit()

        // Exit code 1 = "no processes matched".
        if proc.terminationStatus != 0 { return [] }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0) }
            .map { pid_t($0) }
    }
}

// Ensure observer registers when the test bundle is loaded.
private let _testProcessCleanupObserver = TestProcessCleanupObserver.shared
