#if os(macOS)
import Foundation
import Testing
@testable import CodexBarCore

@MainActor
struct WidgetExtensionRecoveryTests {
    private let installedAt = Date(timeIntervalSince1970: 200)
    private let path = "/synthetic/QuotaKitWidget.appex/Contents/MacOS/QuotaKitWidget"

    @Test
    func `unchanged version performs no recovery work`() {
        let defaults = InMemoryUserDefaults(values: [WidgetExtensionRecovery.versionKey: "101"])
        let count = WidgetExtensionRecovery.recover(
            version: "101",
            defaults: defaults,
            processes: { Issue.record("enumerated processes"); return [] },
            installedAt: { Issue.record("read installation"); return nil },
            owns: { _ in Issue.record("checked signing requirement"); return true },
            exists: { _ in Issue.record("checked executable"); return true },
            terminate: { _ in Issue.record("sent signal"); return true },
            reload: { Issue.record("reloaded timelines") })
        #expect(count == nil)
    }

    @Test
    func `changed version terminates only owned extension processes that are stale`() {
        let defaults = InMemoryUserDefaults(values: [WidgetExtensionRecovery.versionKey: "100"])
        let old = self.process(1, startedAt: 100)
        let current = self.process(2, startedAt: 201)
        let foreign = self.process(3, startedAt: 100)
        let deleted = self.process(4, startedAt: 201, path: "/deleted/QuotaKitWidget")
        let startedAtInstall = self.process(5, startedAt: 200)
        var events: [String] = []
        func recover() -> Int? {
            WidgetExtensionRecovery.recover(
                version: "101",
                defaults: defaults,
                processes: { [old, current, foreign, deleted, startedAtInstall] },
                installedAt: { self.installedAt },
                owns: { $0.pid != foreign.pid },
                exists: { $0 != deleted.executablePath },
                terminate: { events.append("term:\($0.pid)"); return true },
                reload: { events.append("reload") })
        }

        #expect(recover() == 2)
        #expect(events == ["term:1", "term:4", "reload"])
        #expect(defaults.string(forKey: WidgetExtensionRecovery.versionKey) == "101")
        #expect(recover() == nil)
        #expect(events == ["term:1", "term:4", "reload"])
    }

    @Test
    func `unknown installation time does not classify an existing extension as stale`() {
        var signaled = false
        var reloaded = false
        let count = WidgetExtensionRecovery.recover(
            version: "101",
            defaults: InMemoryUserDefaults(),
            processes: { [self.process(1, startedAt: 100)] },
            installedAt: { nil },
            owns: { _ in true },
            exists: { _ in true },
            terminate: { _ in signaled = true; return true },
            reload: { reloaded = true })

        #expect(count == 0)
        #expect(!signaled)
        #expect(reloaded)
    }

    @Test
    func `signal revalidation rejects a reused PID`() {
        let expected = self.process(7, startedAt: 100)
        let replacement = self.process(7, startedAt: 300)
        var checkedRequirement = false
        var signaled = false
        let result = WidgetExtensionRecovery.signalIfCurrent(
            expected,
            current: { replacement },
            owns: { _ in checkedRequirement = true; return true },
            signal: { _ in signaled = true; return true })

        #expect(!result)
        #expect(!checkedRequirement)
        #expect(!signaled)
    }

    @Test
    func `signal revalidation rejects a changed signing requirement`() {
        let process = self.process(8, startedAt: 100)
        var signaled = false
        let result = WidgetExtensionRecovery.signalIfCurrent(
            process,
            current: { process },
            owns: { _ in false },
            signal: { _ in signaled = true; return true })

        #expect(!result)
        #expect(!signaled)
    }

    @Test
    func `widget identifier keeps QuotaKit release and debug suffixes`() {
        #expect(
            WidgetExtensionRecovery.widgetBundleIdentifier(for: "com.columbuslabs.quotakit.mac") ==
                "com.columbuslabs.quotakit.mac.widget")
        #expect(
            WidgetExtensionRecovery.widgetBundleIdentifier(for: "com.columbuslabs.quotakit.mac.debug") ==
                "com.columbuslabs.quotakit.mac.debug.widget")
    }

    private func process(_ pid: Int32, startedAt: TimeInterval, path: String? = nil)
        -> WidgetExtensionRecovery.Process
    {
        .init(pid: pid, startedAt: Date(timeIntervalSince1970: startedAt), executablePath: path ?? self.path)
    }
}
#endif
