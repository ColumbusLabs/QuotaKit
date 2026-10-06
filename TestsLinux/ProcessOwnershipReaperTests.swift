import Foundation
import Testing
@testable import CodexBarCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

struct ProcessOwnershipReaperTests {
    @Test(arguments: ["success", "timeout", "cancellation", "failure"])
    func `probe reaps detached grandchild and preserves unrelated process`(completion: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let pidFile = root.appendingPathComponent("owned.pid")
        let readyFile = pidFile.appendingPathExtension("ready")
        let childReadyFile = pidFile.appendingPathExtension("child-ready")
        let input = Pipe()
        defer { try? input.fileHandleForWriting.close() }
        let timeoutRelease = DispatchSemaphore(value: 0)
        defer { timeoutRelease.signal() }
        let script = """
        import os, signal, sys
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        if len(sys.argv) > 1:
            marker = os.environ['\(ProcessOwnershipReaper.environmentKey)']
            with open(sys.argv[1] + '.tmp', 'w') as handle: handle.write(marker)
            os.replace(sys.argv[1] + '.tmp', sys.argv[1])
        signal.pause()
        """
        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        unrelated.arguments = ["-c", script]
        unrelated.currentDirectoryURL = root
        unrelated.environment = [:]
        unrelated.standardOutput = FileHandle.nullDevice
        unrelated.standardError = FileHandle.nullDevice
        try unrelated.run()
        defer {
            if unrelated.isRunning { kill(unrelated.processIdentifier, SIGKILL) }
            unrelated.waitUntilExit()
            try? FileManager.default.removeItem(at: root)
        }
        // The intermediate session leader exits before the probe does. The grandchild has closed
        // stdout/stderr, a different session, and no parent relationship left for a tree scan.
        let launcher = """
        import subprocess, sys
        subprocess.run([sys.executable, '-c', '''
        import os, subprocess, sys
        child = subprocess.Popen([sys.executable, '-c', sys.argv[1], sys.argv[2] + '.child-ready'],
            start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(sys.argv[2], 'w') as f: f.write(str(child.pid))
        ''', sys.argv[1], sys.argv[2]], start_new_session=True)
        with open(sys.argv[2] + '.ready', 'w') as handle: handle.write('ready')
        sys.stdin.read(1)
        if sys.argv[3] == 'failure': sys.exit(7)
        print('usage-fixture')
        """
        let task = Task {
            try await SubprocessRunner.$timeoutWillFire.withValue({ timeoutRelease.wait() }) {
                try await SubprocessRunner.run(
                    binary: "/usr/bin/python3",
                    arguments: ["-c", launcher, script, pidFile.path, completion],
                    environment: [:],
                    timeout: completion == "timeout" ? 0 : .infinity,
                    standardInput: input,
                    currentDirectoryURL: root,
                    reapDescendants: true,
                    label: "owned-probe-fixture")
            }
        }
        defer { task.cancel() }
        let readyDeadline = Date().addingTimeInterval(60)
        while (!FileManager.default.fileExists(atPath: readyFile.path)
            || !FileManager.default.fileExists(atPath: childReadyFile.path)), Date() < readyDeadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(FileManager.default.fileExists(atPath: readyFile.path))
        try #require(FileManager.default.fileExists(atPath: childReadyFile.path))
        let text = try String(contentsOf: pidFile, encoding: .utf8)
        let childPID = try #require(pid_t(text))
        let childIdentity = try #require(TTYProcessTreeTerminator.processIdentity(for: childPID))
        defer {
            if TTYProcessTreeTerminator.isCurrent(childIdentity) { kill(childPID, SIGKILL) }
        }
        let marker = try String(contentsOf: childReadyFile, encoding: .utf8)
        #expect(!marker.isEmpty)
        // Darwin may expose a PID before its inherited environment is readable. Wait for the
        // exact ownership evidence used by the reaper, as well as the child-installed handler.
        while Self.ownerMarker(pid: childPID) != marker, Date() < readyDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let ownerReady = Self.ownerMarker(pid: childPID) == marker
        try #require(ownerReady, "Child owner marker is not observable")
        // The detached child must be ready before any completion path can trigger ownership cleanup.
        // Only the timeout case arms a timer; slow scheduling cannot turn success/failure into timeout.
        switch completion {
        case "timeout": timeoutRelease.signal()
        case "cancellation": task.cancel()
        default: try input.fileHandleForWriting.write(contentsOf: Data([1]))
        }
        switch await BoundedTaskJoin(sourceTask: task).value(joinGrace: .seconds(60)) {
        case let .value(result):
            #expect(completion == "success")
            #expect(result.stdout == "usage-fixture\n")
        case let .failure(error) where error is CancellationError:
            #expect(completion == "cancellation")
        case let .failure(error as SubprocessRunnerError):
            switch error {
            case .timedOut: #expect(completion == "timeout")
            case let .nonZeroExit(code, _):
                #expect(completion == "failure")
                #expect(code == 7)
            default: throw error
            }
        case let .failure(error): throw error
        case .timedOut: Issue.record("Probe did not finish after releasing its completion barrier")
        }
        let deadline = Date().addingTimeInterval(60)
        while kill(childPID, 0) == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let sameIdentity = TTYProcessTreeTerminator.isCurrent(childIdentity)
        let ownerObservable = Self.ownerMarker(pid: childPID) == marker
        let state = Self.processState(pid: childPID)
        #expect(
            kill(childPID, 0) == -1,
            "Child remains: same identity=\(sameIdentity), owner observable=\(ownerObservable), \(state)")
        #expect(unrelated.isRunning)
    }

    private static func ownerMarker(pid: pid_t) -> String? {
        let names: Set<String> = [ProcessOwnershipReaper.environmentKey]
        #if canImport(Darwin)
        return DarwinProcessEnumerator.environment(pid: pid, names: names)?[ProcessOwnershipReaper.environmentKey]
        #else
        return PiProcessEnvironment.readLinuxEnvironment(pid: pid, names: names)?[ProcessOwnershipReaper.environmentKey]
        #endif
    }

    private static func processState(pid: pid_t) -> String {
        #if canImport(Darwin)
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            == MemoryLayout<proc_bsdinfo>.size
        else { return "BSD state unavailable" }
        return "BSD state=\(info.pbi_status)"
        #else
        return "Linux"
        #endif
    }

    @Test
    func `reaper preserves an unmarked process sharing the owned process group`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let ownedPIDFile = root.appendingPathComponent("owned.pid")
        let unownedPIDFile = root.appendingPathComponent("unowned.pid")
        let ownedGroupFile = root.appendingPathComponent("owned.group")
        let unownedGroupFile = root.appendingPathComponent("unowned.group")
        let readyFile = root.appendingPathComponent("unowned.ready")
        let launcherReadyFile = root.appendingPathComponent("launcher.ready")
        let capturedFile = root.appendingPathComponent("captured")
        let signaledFile = root.appendingPathComponent("unowned.signaled")
        var unownedIdentity: TTYProcessTreeTerminator.ProcessIdentity?
        defer {
            if let unownedIdentity, TTYProcessTreeTerminator.isCurrent(unownedIdentity) {
                _ = kill(unownedIdentity.pid, SIGKILL)
            }
            try? FileManager.default.removeItem(at: root)
        }

        let launcher = """
        import os, signal, subprocess, sys, time
        owned = subprocess.Popen([sys.executable, '-c',
            'import os,sys,time; open(sys.argv[1], "w").write(str(os.getpgrp())); time.sleep(60)',
            sys.argv[3]],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        unowned_code = '''
        import os, signal, sys, time
        def on_term(_signum, _frame):
            with open(sys.argv[1], 'w') as handle: handle.write('signaled')
        signal.signal(signal.SIGTERM, on_term)
        with open(sys.argv[3], 'w') as handle: handle.write(str(os.getpgrp()))
        with open(sys.argv[2], 'w') as handle: handle.write('ready')
        time.sleep(60)
        '''
        unowned = subprocess.Popen([sys.executable, '-c', unowned_code,
            sys.argv[5], sys.argv[6], sys.argv[4]], env={}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for path, value in [(sys.argv[1], str(owned.pid)), (sys.argv[2], str(unowned.pid))]:
            with open(path, 'w') as handle: handle.write(value)
        deadline = time.time() + 5
        while (not os.path.exists(sys.argv[6]) or not os.path.exists(sys.argv[3]) or
               not os.path.exists(sys.argv[4])) and time.time() < deadline:
            time.sleep(0.01)
        if (not os.path.exists(sys.argv[6]) or not os.path.exists(sys.argv[3]) or
            not os.path.exists(sys.argv[4])):
            owned.kill()
            unowned.kill()
            raise RuntimeError('process group fixtures did not become ready')
        with open(sys.argv[8], 'w') as handle: handle.write('ready')
        deadline = time.time() + 5
        while not os.path.exists(sys.argv[7]) and time.time() < deadline: time.sleep(0.01)
        if not os.path.exists(sys.argv[7]):
            owned.kill()
            unowned.kill()
            raise RuntimeError('Swift fixture did not capture process identities')
        """
        let task = Task {
            try await SubprocessRunner.run(
                binary: "/usr/bin/python3",
                arguments: [
                    "-c",
                    launcher,
                    ownedPIDFile.path,
                    unownedPIDFile.path,
                    ownedGroupFile.path,
                    unownedGroupFile.path,
                    signaledFile.path,
                    readyFile.path,
                    capturedFile.path,
                    launcherReadyFile.path,
                ],
                environment: [:],
                timeout: 10,
                currentDirectoryURL: root,
                reapDescendants: true,
                label: "same-group-ownership-fixture")
        }
        defer { task.cancel() }
        let launchDeadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: launcherReadyFile.path), Date() < launchDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        let ownedPID = try #require(pid_t(String(contentsOf: ownedPIDFile, encoding: .utf8)))
        let unownedPID = try #require(pid_t(String(contentsOf: unownedPIDFile, encoding: .utf8)))
        let ownedIdentity = try #require(TTYProcessTreeTerminator.processIdentity(for: ownedPID))
        unownedIdentity = try #require(TTYProcessTreeTerminator.processIdentity(for: unownedPID))
        let ownedGroup = try #require(pid_t(String(contentsOf: ownedGroupFile, encoding: .utf8)))
        let unownedGroup = try #require(pid_t(String(contentsOf: unownedGroupFile, encoding: .utf8)))
        #expect(ownedGroup == unownedGroup)
        try Data().write(to: capturedFile)

        _ = try await task.value

        let cleanupDeadline = Date().addingTimeInterval(2)
        while TTYProcessTreeTerminator.isCurrent(ownedIdentity), Date() < cleanupDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!TTYProcessTreeTerminator.isCurrent(ownedIdentity))
        #expect(try TTYProcessTreeTerminator.isCurrent(#require(unownedIdentity)))
        #expect(kill(unownedPID, 0) == 0)
        #expect(!FileManager.default.fileExists(atPath: signaledFile.path))
    }

    @Test(arguments: [false, true])
    func `cleared environment cannot defeat timeout or cancellation`(cancel: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let ready = root.appendingPathComponent("ready")
        let input = Pipe()
        defer { try? input.fileHandleForWriting.close() }
        let task = Task {
            try await SubprocessRunner.run(
                binary: "/usr/bin/env",
                arguments: ["-i", "/bin/sh", "-c", "printf ready > \"$1\"; exec /bin/cat", "fixture", ready.path],
                environment: [:],
                timeout: cancel ? 600 : 30,
                standardInput: input,
                reapDescendants: true,
                label: "cleared-marker-fixture")
        }
        defer { task.cancel() }
        let deadline = Date().addingTimeInterval(60)
        while !FileManager.default.fileExists(atPath: ready.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(FileManager.default.fileExists(atPath: ready.path))
        if cancel { task.cancel() }
        // Stdin stays open until after the result: cat cannot rescue broken teardown by exiting naturally.
        switch await BoundedTaskJoin(sourceTask: task).value(joinGrace: .seconds(60)) {
        case let .failure(error) where error is CancellationError:
            #expect(cancel)
        case let .failure(error as SubprocessRunnerError):
            guard case .timedOut = error else { throw error }
            #expect(!cancel)
        case let .failure(error): throw error
        case .value, .timedOut: Issue.record("Expected timeout or cancellation while stdin remains open")
        }
    }

    @Test
    func `signals reject reused PIDs and lost markers before escalation`() {
        let identity = TTYProcessTreeTerminator.ProcessIdentity(pid: 42, startToken: 1)
        var marked = true
        var current = true
        var sent: [Int32] = []
        func signal(_ value: Int32) {
            ProcessOwnershipReaper.signal(
                identity,
                value,
                owns: { _ in marked },
                isCurrent: { _ in current },
                send: { _, value in sent.append(value) })
        }
        signal(SIGTERM)
        marked = false
        signal(SIGKILL)
        #expect(sent == [SIGTERM])
        marked = true
        current = false
        signal(SIGKILL)
        #expect(sent == [SIGTERM])
    }

    @Test
    func `Linux environment reader selects the marker and rejects unavailable evidence`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let process = root.appendingPathComponent("101", isDirectory: true)
        try FileManager.default.createDirectory(at: process, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = process.appendingPathComponent("environ")
        let key = ProcessOwnershipReaper.environmentKey
        let names: Set<String> = [key]
        try Data("OTHER=ignored\0\(key)=fixture\0".utf8).write(to: file)
        #expect(PiProcessEnvironment.readLinuxEnvironment(pid: 101, procRoot: root, names: names) == [key: "fixture"])
        try Data("\(key)=fixture".utf8).write(to: file)
        #expect(PiProcessEnvironment.readLinuxEnvironment(pid: 101, procRoot: root, names: names) == nil)
        #expect(PiProcessEnvironment.readLinuxEnvironment(pid: 102, procRoot: root, names: names) == nil)
    }

    @Test
    func `marker parsing requires an exact environment entry`() {
        let key = ProcessOwnershipReaper.environmentKey
        let names: Set<String> = [key]
        #expect(PiProcessEnvironment.parseNULSeparated(Data("\(key)=fixture\0".utf8), names: names)?[key] == "fixture")
        #expect(PiProcessEnvironment.parseNULSeparated(Data("OTHER=\(key)=fixture\0".utf8), names: names) == [:])
        #expect(PiProcessEnvironment.parseNULSeparated(Data("\(key)=fixture".utf8), names: names) == nil)
        #expect(PiProcessEnvironment.parseNULSeparated(
            Data("\(key)=fixture\0\(key)=different\0".utf8), names: names) == nil)
        var argc: Int32 = 2
        var data = withUnsafeBytes(of: &argc) { Data($0) }
        data.append(Data("/fixture\0\0fixture\0\(key)=argument-only\0OTHER=ok\0\0\(key)=apple-vector\0".utf8))
        #expect(DarwinProcessEnumerator.parseProcArgs2Environment(data, names: names) == [:])
        var empty = withUnsafeBytes(of: &argc) { Data($0) }
        empty.append(Data("/fixture\0\0fixture\0arg\0\0\(key)=apple-vector\0".utf8))
        #expect(DarwinProcessEnumerator.parseProcArgs2Environment(empty, names: names) == nil)
    }

    @Test(arguments: [0, 64, 128])
    func `marker parsing preserves boundaries around large unrelated values`(position: Int) {
        let key = ProcessOwnershipReaper.environmentKey
        let names: Set<String> = [key]
        var records = (0..<128).map { "FIXTURE_\($0)=\(String(repeating: "x", count: 4096))" }
        records.insert("\(key)=fixture", at: position)
        let data = Data(("\0" + records.joined(separator: "\0\0") + "\0").utf8)

        #expect(PiProcessEnvironment.parseNULSeparated(data, names: names) == [key: "fixture"])
        #expect(PiProcessEnvironment.parseNULSeparated(data.dropLast(), names: names) == nil)
        #expect(PiProcessEnvironment.parseNULSeparated(data + Data("malformed\0".utf8), names: names) == nil)
        #expect(PiProcessEnvironment.parseNULSeparated(data + Data("\(key)=different\0".utf8), names: names) == nil)
        #expect(PiProcessEnvironment.parseNULSeparated(Data(repeating: 0, count: data.count), names: names) == [:])
    }
}
