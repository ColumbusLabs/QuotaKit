import Darwin
import Foundation
import LiteCore

/// Reads Claude Code's secret with `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`
/// (068 §4.1 step 3).
///
/// Claude Code lists `security` in its item's ACL, and Phase 0 showed it reads silently before and after a token
/// refresh. Rules: a hard 5 s limit, then SIGKILL; stdout is read into memory only and never logged; stderr is
/// discarded. Whether to run it at all (at most once per item modification date) is decided by
/// `ClaudeCredentialResolver`.
struct ClaudeSecurityCLISecretReader: ClaudeKeychainSecretReading {
    static let executablePath = "/usr/bin/security"
    static let arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

    var timeout: TimeInterval = 5

    func readClaudeCredentialsSecret() async -> Result<Data, ClaudeSecretReadFailure> {
        let timeout = self.timeout
        // The wait blocks a thread, so keep it off Swift's cooperative pool.
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.run(timeout: timeout))
            }
        }
    }

    private static func run(timeout: TimeInterval) -> Result<Data, ClaudeSecretReadFailure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: self.executablePath)
        process.arguments = self.arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return .failure(.failed)
        }

        // Drain stdout concurrently so a full pipe can never stall the child.
        let output = OutputBuffer()
        let drained = DispatchSemaphore(value: 0)
        let reader = stdout.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            output.set(reader.readDataToEndOfFile())
            drained.signal()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + 1)
            _ = drained.wait(timeout: .now() + 1)
            output.clear()
            return .failure(.timedOut)
        }
        guard drained.wait(timeout: .now() + 1) == .success, process.terminationStatus == 0 else {
            output.clear()
            return .failure(.failed)
        }

        var data = output.take()
        while let last = data.last, last == 0x0A || last == 0x0D {
            data.removeLast()
        }
        return data.isEmpty ? .failure(.failed) : .success(data)
    }
}

/// Hands stdout from the reading thread to the waiting one.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ data: Data) {
        self.lock.withLock { self.data = data }
    }

    func take() -> Data {
        self.lock.withLock {
            let data = self.data
            self.data = Data()
            return data
        }
    }

    func clear() {
        self.lock.withLock { self.data = Data() }
    }
}
