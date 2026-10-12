import AppKit
import Darwin
import LiteCore

/// Finds running Antigravity language servers with kernel calls only (068 §4.3): no `ps`, no `lsof`, no
/// subprocess. `proc_pidpath` filters candidates, argv is read only for those, and listening ports come from the
/// process's own socket table. Phase 0 measured a full scan at 18–58 ms.
enum AntigravityScanner {
    static func endpoints() -> [AntigravityEndpoint] {
        self.allPIDs().flatMap { pid -> [AntigravityEndpoint] in
            guard let path = self.executablePath(pid: pid), AntigravityProcess.isCandidatePath(path),
                  let arguments = self.arguments(pid: pid)
            else { return [] }
            return AntigravityProcess.endpoints(
                pid: pid,
                commandLine: arguments.joined(separator: " "),
                listeningPorts: { self.listeningTCPPorts(pid: pid) })
        }
    }

    /// `kill(pid, 0)`: whether the cached server process still exists.
    static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Kernel calls (the full app's `DarwinProcessEnumerator`)

    private static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 32)
        let actual = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard actual > 0 else { return [] }
        return pids.prefix(Int(actual)).filter { $0 > 0 }
    }

    private static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard length > 0 else { return nil }
        return String(bytes: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }

    private static func arguments(pid: Int32) -> [String]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size >= 4 else { return nil }
        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &size, nil, 0) }
        guard result == 0 else { return nil }
        return AntigravityProcess.arguments(fromProcArgs2: data.prefix(size))
    }

    private static func listeningTCPPorts(pid: Int32) -> [Int] {
        let required = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard required > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(required) / stride + 8)
        let actual = descriptors.withUnsafeMutableBytes {
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
        }
        guard actual > 0 else { return [] }
        var ports: Set<Int> = []
        for descriptor in descriptors.prefix(Int(actual) / stride) where descriptor.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let size = proc_pidfdinfo(
                pid,
                descriptor.proc_fd,
                PROC_PIDFDSOCKETINFO,
                &info,
                Int32(MemoryLayout<socket_fdinfo>.size))
            guard size == MemoryLayout<socket_fdinfo>.size,
                  info.psi.soi_kind == SOCKINFO_TCP,
                  info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN
            else { continue }
            let port = UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)
            ports.insert(Int(UInt16(bigEndian: port)))
        }
        return ports.sorted()
    }
}

/// Notices the Antigravity app or IDE opening and quitting by observing `NSWorkspace.runningApplications`, like
/// `FullAppMonitor`. The `agy` CLI has no such signal and is found on the ordinary schedule.
@MainActor
final class AntigravityAppMonitor {
    private let onChange: @MainActor (Bool) -> Void
    private var observation: NSKeyValueObservation?
    private var isRunning = false

    /// - Parameter onChange: true when an Antigravity app launched, false when the last one quit.
    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        self.isRunning = Self.antigravityAppIsRunning()
        self.observation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.update() }
        }
    }

    private func update() {
        let running = Self.antigravityAppIsRunning()
        guard running != self.isRunning else { return }
        self.isRunning = running
        self.onChange(running)
    }

    private static func antigravityAppIsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            !app.isTerminated && (app.bundleIdentifier?.lowercased().contains("antigravity") ?? false)
        }
    }
}
