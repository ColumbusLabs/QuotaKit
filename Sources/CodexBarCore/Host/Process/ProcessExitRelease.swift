import Foundation

package enum ProcessExitRelease {
    #if os(Linux)
    private static let queue = DispatchQueue(label: "com.columbuslabs.quotakit.process-exit-release", qos: .utility)
    private static let maximumRetryDelay: TimeInterval = 2
    #endif

    /// Lets Foundation drop a launched `Process` after its child exits, without blocking the caller.
    ///
    /// swift-corelibs-foundation retains each launched process through a run-loop source until
    /// `waitUntilExit()` clears it. A termination handler alone therefore does not release the
    /// process or its output pipes on Linux. Queue the wait until the child has exited so process
    /// teardown remains nonblocking and serialized across repeated requests.
    package static func afterExit(_ process: Process) {
        #if os(Linux)
        self.queue.async {
            self.release(process, retryDelay: 0.05)
        }
        #endif
    }

    #if os(Linux)
    private static func release(_ process: Process, retryDelay: TimeInterval) {
        guard process.isRunning else {
            process.waitUntilExit()
            return
        }
        self.queue.asyncAfter(deadline: .now() + retryDelay) {
            self.release(process, retryDelay: min(retryDelay * 2, self.maximumRetryDelay))
        }
    }
    #endif
}
