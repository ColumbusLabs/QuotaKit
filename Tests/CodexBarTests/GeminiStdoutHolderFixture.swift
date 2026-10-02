import Foundation
import Testing
@testable import CodexBarCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The test owns the holder Process before the producer can hand it a stdout descriptor.
/// No descendant discovery or PID file is needed to clean up a failed producer.
final class GeminiStdoutHolderFixture {
    let process = Process()
    let pidFile: URL
    private let helper: URL
    private let socketPath: String
    private let control = Pipe()
    private let exited = DispatchSemaphore(value: 0)
    private var started = false
    private var cleanedUp = false

    private let environment = [
        "PATH": "/usr/bin:/bin",
        "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1",
    ]

    init(root: URL) throws {
        self.helper = root.appendingPathComponent("stdout-holder.py")
        self.socketPath = root.appendingPathComponent("s").path
        self.pidFile = root.appendingPathComponent("holder.pid")
        try Self.script.write(to: self.helper, atomically: true, encoding: .utf8)

        let output = Pipe()
        let capture = ProcessPipeCapture(pipe: output)
        // Use the system interpreter directly and isolate its module search from user configuration.
        self.process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        self.process.arguments = ["-I", self.helper.path, "hold", self.socketPath]
        self.process.environment = self.environment
        self.process.standardInput = self.control
        self.process.standardOutput = output
        self.process.standardError = FileHandle.standardError
        let exited = self.exited
        self.process.terminationHandler = { _ in exited.signal() }
        try self.process.run()
        self.started = true
        self.control.fileHandleForReading.closeFile()
        output.fileHandleForWriting.closeFile()
        capture.start()
        do {
            // The first system Python launch can be slow on a busy CI runner.
            // This is fixture startup, separate from the producer's two-second deadline.
            let ready = capture.finishFirstLineSynchronously(timeout: 10)
            try #require(String(data: ready, encoding: .utf8) == "ready\n")
        } catch {
            self.cleanup()
            throw error
        }
    }

    func runProducer(pidFile: URL? = nil, blockAfterAcknowledgment: Bool = false) -> String? {
        let mode = blockAfterAcknowledgment ? "produce-timeout" : "produce"
        return GeminiStatusProbe.runProcess(
            executable: "/usr/bin/python3",
            arguments: ["-I", self.helper.path, mode, self.socketPath, (pidFile ?? self.pidFile).path],
            environment: self.environment,
            timeout: 2)
    }

    func installProducer(at executable: URL, blockAfterAcknowledgment: Bool = false) throws {
        let mode = blockAfterAcknowledgment ? "produce-timeout" : "produce"
        let arguments = ["/usr/bin/python3", "-I", self.helper.path, mode, self.socketPath, self.pidFile.path]
        let command = arguments.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        try "#!/bin/sh\nexec \(command)\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    var producerDiagnostics: String {
        (try? String(contentsOfFile: self.socketPath + ".error", encoding: .utf8)) ?? ""
    }

    func cleanup() {
        guard !self.cleanedUp else { return }
        self.cleanedUp = true
        self.control.fileHandleForWriting.closeFile()
        guard self.started else { return }
        if self.exited.wait(timeout: .now() + 2) == .timedOut {
            Issue.record("Stdout holder did not exit after its owner closed the control pipe")
            if self.process.isRunning {
                _ = kill(self.process.processIdentifier, SIGKILL)
            }
        }
        self.process.waitUntilExit()
        #expect(self.process.terminationStatus == 0)
    }

    deinit {
        self.cleanup()
    }

    private static let script = #"""
    import array
    import os
    import select
    import socket
    import stat
    import sys
    import traceback

    mode, path = sys.argv[1:3]
    if mode in ("produce", "produce-timeout"):
        def record_failure(kind, error, stack):
            with open(path + ".error", "w") as handle:
                traceback.print_exception(kind, error, stack, file=handle)
        sys.excepthook = record_failure

    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as channel:
        if mode == "hold":
            channel.bind(path)
            print("ready", flush=True)
            held = []
            try:
                while True:
                    readable, _, _ = select.select([channel, sys.stdin], [], [])
                    if sys.stdin in readable:
                        assert os.read(0, 1) == b""
                        break
                    _, ancillary, flags, sender = channel.recvmsg(1, socket.CMSG_SPACE(array.array("i").itemsize))
                    assert flags == 0 and len(ancillary) == 1
                    level, kind, data = ancillary[0]
                    assert (level, kind) == (socket.SOL_SOCKET, socket.SCM_RIGHTS)
                    descriptors = array.array("i")
                    descriptors.frombytes(data)
                    held.extend(descriptors)
                    assert len(descriptors) == 1 and stat.S_ISFIFO(os.fstat(descriptors[0]).st_mode)
                    channel.sendto(str(os.getpid()).encode(), sender)
            finally:
                for descriptor in held:
                    os.close(descriptor)
        else:
            assert mode in ("produce", "produce-timeout")
            channel.bind(path + ".p")
            channel.settimeout(2)
            channel.connect(path)
            channel.sendmsg([b"x"], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", [1]))])
            holder_pid = channel.recv(32).decode()
            # The acknowledgement proves the owned holder has the writer before any output is printed.
            with open(sys.argv[3], "w") as handle:
                handle.write(holder_pid)
            if mode == "produce-timeout":
                # The probe deadline is the event under test; process cleanup owns termination.
                select.select([], [], [])
            print("/tmp/gemini-package", flush=True)
            print("ignored trailing output", flush=True)
    """#
}
