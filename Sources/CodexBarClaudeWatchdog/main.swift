import Darwin
import Foundation

private enum WatchdogExitCode {
    static let usage: Int32 = 64
    static let spawnFailed: Int32 = 70
}

private nonisolated(unsafe) var globalChildPID: pid_t = 0
private nonisolated(unsafe) var globalShouldTerminate: Int32 = 0

private func usageAndExit() -> Never {
    fputs("Usage: QuotaKitClaudeWatchdog -- <binary> [args...]\n", stderr)
    Darwin.exit(WatchdogExitCode.usage)
}

private func killProcessTree(childPID: pid_t, graceSeconds: TimeInterval = 0.5) {
    let selfPgrp = getpgrp()
    let spawnedGroup = childPID
    let initialPgid = getpgid(childPID)
    if spawnedGroup > 0, spawnedGroup != selfPgrp {
        _ = kill(-spawnedGroup, SIGTERM)
    }
    if initialPgid != spawnedGroup {
        _ = kill(childPID, SIGTERM)
    }

    // Keep the child waitable for the entire grace interval. Reaping its PID early
    // permits group-ID reuse, and a child that exits on TERM may leave descendants
    // behind that need KILL. A zombie child still reserves its PID until waitpid.
    let deadline = Date().addingTimeInterval(graceSeconds)
    while Date() < deadline {
        usleep(50000)
    }

    let currentPgid = getpgid(childPID)
    if spawnedGroup > 0, spawnedGroup != selfPgrp {
        _ = kill(-spawnedGroup, SIGKILL)
    }
    if currentPgid != spawnedGroup {
        _ = kill(childPID, SIGKILL)
    }
}

private func exitCode(fromWaitStatus status: Int32) -> Int32 {
    // Swift can't import wait(2) macros (function-like macros). Use the classic encoding:
    // - low 7 bits: signal number (0 means exited)
    // - high byte: exit status (when exited)
    let low = status & 0x7F
    if low == 0 {
        return (status >> 8) & 0xFF
    }
    if low != 0x7F {
        return 128 + low
    }
    return 1
}

let argv = CommandLine.arguments
guard let sep = argv.firstIndex(of: "--") else { usageAndExit() }
let childArgs = Array(argv[(sep + 1)...])
guard !childArgs.isEmpty else { usageAndExit() }

let childBinary = childArgs[0]
let childArgv = childArgs

private func handleTerminationSignal(_ sig: Int32) {
    globalShouldTerminate = sig
}

var watchdogSignalMask = sigset_t()
sigemptyset(&watchdogSignalMask)
_ = sigprocmask(SIG_SETMASK, &watchdogSignalMask, nil)

// An inherited ignored SIGCHLD would auto-reap children and release group ownership.
signal(SIGCHLD, SIG_DFL)
signal(SIGTERM, handleTerminationSignal)
signal(SIGINT, handleTerminationSignal)
signal(SIGHUP, handleTerminationSignal)

let spawnResult: Int32 = childArgv.withUnsafeBufferPointer { buffer in
    var cStrings: [UnsafeMutablePointer<CChar>?] = buffer
        .map { strdup($0) }
    cStrings.append(nil)
    defer { cStrings.forEach { if let p = $0 { free(p) } } }

    var attributes: posix_spawnattr_t?
    guard posix_spawnattr_init(&attributes) == 0 else {
        return ENOMEM
    }
    defer { posix_spawnattr_destroy(&attributes) }

    guard posix_spawnattr_setflags(
        &attributes,
        Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK)) == 0,
        posix_spawnattr_setpgroup(&attributes, 0) == 0
    else {
        return EINVAL
    }
    var emptyMask = sigset_t()
    sigemptyset(&emptyMask)
    guard posix_spawnattr_setsigmask(&attributes, &emptyMask) == 0 else {
        return EINVAL
    }

    return cStrings.withUnsafeMutableBufferPointer { cBuffer in
        var pid: pid_t = 0
        let rc: Int32 = childBinary.withCString { childPath in
            posix_spawnp(&pid, childPath, nil, &attributes, cBuffer.baseAddress, environ)
        }
        if rc == 0, pid > 0 {
            globalChildPID = pid
        }
        return rc
    }
}

guard spawnResult == 0, globalChildPID > 0 else {
    fputs("QuotaKitClaudeWatchdog: failed to spawn child: \(childBinary) (rc=\(spawnResult))\n", stderr)
    Darwin.exit(WatchdogExitCode.spawnFailed)
}

var status: Int32 = 0
while true {
    if globalShouldTerminate != 0 || getppid() == 1 {
        let terminationSignal = globalShouldTerminate
        killProcessTree(childPID: globalChildPID)
        _ = waitpid(globalChildPID, &status, 0)
        let code = terminationSignal == 0 ? exitCode(fromWaitStatus: status) : 128 + terminationSignal
        Darwin.exit(code)
    }

    // Observe exit without releasing its PID. A termination request can arrive
    // while checking the child; keeping it waitable preserves group ownership.
    var info = siginfo_t()
    let rc = waitid(P_PID, id_t(globalChildPID), &info, WEXITED | WNOHANG | WNOWAIT)
    if rc != 0, errno != EINTR {
        // ECHILD means ownership is already gone; never signal a potentially reused PID.
        fputs("QuotaKitClaudeWatchdog: failed to observe child exit (errno=\(errno))\n", stderr)
        Darwin.exit(WatchdogExitCode.spawnFailed)
    }
    if rc == 0, info.si_pid == globalChildPID {
        let terminationSignal = globalShouldTerminate
        if terminationSignal != 0 || getppid() == 1 {
            killProcessTree(childPID: globalChildPID)
        } else if globalChildPID > 1, globalChildPID != getpgrp() {
            // A successfully exited probe cannot own useful work after it exits.
            // The unreaped leader reserves the group ID against reuse here.
            _ = kill(-globalChildPID, SIGKILL)
        }
        _ = waitpid(globalChildPID, &status, 0)
        Darwin.exit(terminationSignal == 0 ? exitCode(fromWaitStatus: status) : 128 + terminationSignal)
    }
    usleep(200_000)
}
