import CodexBarCore
import Darwin
import XCTest
@testable import CodexBar

final class TTYCommandRunnerTests: XCTestCase {
    func testKillsProcessGroupChildren() throws {
        // Spawn a helper script that launches a long-lived child (sleep 60) and waits for it.
        // Without process-group termination, the background sleep would survive after the parent dies.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tty-runner-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let scriptURL = tmp.appendingPathComponent("spawn_child.sh")
        let script = """
        #!/bin/bash
        set -e
        sleep 60 &
        child=$!
        echo CHILD_PID=$child
        wait $child
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let runner = TTYCommandRunner()
        let result = try runner.run(
            binary: scriptURL.path,
            send: "",
            options: .init(rows: 5, cols: 40, timeout: 1.5, extraArgs: []))

        guard let childPID = Self.extractChildPID(result.text) else {
            XCTFail("Did not capture child PID from PTY output. Output: \(result.text)")
            return
        }

        // Give the termination path a brief moment to deliver signals.
        usleep(150_000)

        let stillAlive = kill(childPID, 0) == 0
        XCTAssertFalse(stillAlive, "Child process (pid: \(childPID)) is still alive; process-group kill failed")
    }

    private static func extractChildPID(_ text: String) -> pid_t? {
        let pattern = #"CHILD_PID=([0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges >= 2,
              let pidRange = Range(match.range(at: 1), in: text) else { return nil }
        return pid_t(text[pidRange])
    }
}
