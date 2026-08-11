import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIHooksWatchSleepLinuxTests {
    @Test
    func `returns quickly when stop already requested`() async {
        let stop = HooksWatchStopSignal()
        stop.request()

        let start = DispatchTime.now()
        await CodexBarCLI.sleepInterruptibly(interval: 30, stop: stop)
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9

        #expect(elapsedSeconds < 1)
    }

    @Test
    func `stops promptly when signaled mid sleep`() async {
        // Regression: CLITerminationSignalMonitor only flips a flag, it does not
        // cancel the running task. A single long Task.sleep would leave `hooks
        // watch` appearing hung on SIGINT until the full interval elapsed.
        let stop = HooksWatchStopSignal()
        Task.detached {
            try? await Task.sleep(nanoseconds: 300_000_000)
            stop.request()
        }

        let start = DispatchTime.now()
        await CodexBarCLI.sleepInterruptibly(interval: 10, stop: stop)
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9

        // The 0.3s signal must interrupt the 10s interval promptly; allow headroom for loaded
        // CI runners (observed 2.02s on x64 under contention).
        #expect(elapsedSeconds < 5)
    }

    @Test
    func `sleeps the full interval when never signaled`() async {
        let stop = HooksWatchStopSignal()
        let start = DispatchTime.now()
        await CodexBarCLI.sleepInterruptibly(interval: 0.4, stop: stop)
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9

        #expect(elapsedSeconds >= 0.35)
    }

    @Test
    func `stops promptly when hooks are disabled during sleep`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLIHooksWatchSleepLinuxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
        var enabled = CodexBarConfig.makeDefault()
        enabled.hooks = HooksConfig(enabled: true)
        try store.save(enabled)

        let mutation = Task.detached {
            try await Task.sleep(nanoseconds: 150_000_000)
            var disabled = enabled
            disabled.hooks = HooksConfig(enabled: false)
            try store.save(disabled)
        }

        let start = DispatchTime.now()
        let completed = await CodexBarCLI.sleepInterruptibly(
            interval: 10,
            stop: HooksWatchStopSignal(),
            shouldContinue: {
                CodexBarCLI.hooksWatchConfigurationIsEnabled(configStore: store)
            },
            continuationCheckNanoseconds: 50_000_000)
        try await mutation.value
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9

        #expect(!completed)
        #expect(elapsedSeconds < 2)
    }

    @Test
    func `configuration revision changes only when normalized config changes`() throws {
        let store = CodexBarConfigStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("unused-config.json"))
        var tracker = HooksWatchConfigurationRevisionTracker()
        var config = CodexBarConfig.makeDefault()
        config.hooks = HooksConfig(enabled: true)

        let first = try store.encodedData(for: config)
        #expect(tracker.revision(for: first) == 1)
        #expect(tracker.revision(for: first) == 1)

        config.hooks = HooksConfig(enabled: false)
        let changed = try store.encodedData(for: config)
        #expect(tracker.revision(for: changed) == 2)
        #expect(tracker.revision(for: changed) == 2)
    }
}
