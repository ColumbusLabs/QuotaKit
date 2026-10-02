import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIHooksWatchSleepLinuxTests {
    @Test
    func `already requested stop skips every sleep tick`() async {
        let stop = HooksWatchStopSignal()
        stop.request()

        _ = await CodexBarCLI.sleepInterruptibly(interval: 30, stop: stop, sleep: { _ in
            Issue.record("An already requested stop must not sleep")
        })
    }

    @Test
    func `stop requested during a tick prevents the next sleep`() async {
        // The signal monitor flips the flag without cancelling this task. Record the
        // requested ticks so a single full-interval sleep cannot satisfy this test.
        let stop = HooksWatchStopSignal()
        var ticks: [UInt64] = []
        _ = await CodexBarCLI.sleepInterruptibly(interval: 10, stop: stop, sleep: { nanoseconds in
            ticks.append(nanoseconds)
            stop.request()
        })

        #expect(ticks == [200_000_000])
    }

    @Test(arguments: [0.0, -1.0, 0.05, 0.4, 0.45])
    func `unsignaled sleep requests the full interval in bounded ticks`(interval: TimeInterval) async {
        let stop = HooksWatchStopSignal()
        var ticks: [UInt64] = []
        _ = await CodexBarCLI.sleepInterruptibly(interval: interval, stop: stop, sleep: { nanoseconds in
            ticks.append(nanoseconds)
        })

        let expected = UInt64((max(0, interval) * 1_000_000_000).rounded())
        #expect(ticks.reduce(0, +) == expected)
        #expect(ticks.allSatisfy { $0 > 0 && $0 <= 200_000_000 })
        #expect(ticks.count == Int((expected + 199_999_999) / 200_000_000))
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

        var ticks: [UInt64] = []
        let completed = await CodexBarCLI.sleepInterruptibly(
            interval: 10,
            stop: HooksWatchStopSignal(),
            shouldContinue: {
                CodexBarCLI.hooksWatchConfigurationIsEnabled(configStore: store)
            },
            continuationCheckNanoseconds: 50_000_000,
            sleep: { nanoseconds in
                ticks.append(nanoseconds)
                var disabled = enabled
                disabled.hooks = HooksConfig(enabled: false)
                try store.save(disabled)
            })

        #expect(!completed)
        #expect(ticks == [200_000_000])
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
