import Foundation
import Testing
@testable import CodexBarCore

struct GrokBillingCadenceStoreTests {
    private static let day = TimeInterval(86400)
    private static let weeklyMinutes = 7 * 24 * 60
    private static let monthlyMinutes = 31 * 24 * 60

    @Test
    func `infers an unambiguous weekly cadence before any rollover is observed`() throws {
        let store = try Self.makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resetsAt = now.addingTimeInterval(6 * Self.day)

        #expect(store.resolveWindowMinutes(resetsAt: resetsAt, now: now) == Self.weeklyMinutes)
        #expect(store.learnedWindowMinutes() == Self.weeklyMinutes)

        // A repeated fetch inside the same cycle is not a rollover.
        #expect(store.resolveWindowMinutes(resetsAt: resetsAt, now: now) == Self.weeklyMinutes)
        #expect(store.learnedWindowMinutes() == Self.weeklyMinutes)
    }

    @Test
    func `infers an unambiguous monthly cadence on the first fetch`() throws {
        let store = try Self.makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(store.resolveWindowMinutes(
            resetsAt: now.addingTimeInterval(30 * Self.day),
            now: now) == 30 * 24 * 60)
        #expect(store.learnedWindowMinutes() == 30 * 24 * 60)
    }

    @Test
    func `keeps ambiguous late cycle cadence unknown on the first fetch`() throws {
        let store = try Self.makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(store.resolveWindowMinutes(
            resetsAt: now.addingTimeInterval(2 * Self.day),
            now: now) == nil)
        #expect(store.learnedWindowMinutes() == nil)
    }

    @Test
    func `learns the real period from an observed rollover`() throws {
        let store = try Self.makeStore()
        let first = Date(timeIntervalSince1970: 1_800_000_000)

        _ = store.resolveWindowMinutes(resetsAt: first, now: first.addingTimeInterval(-6 * Self.day))
        let next = first.addingTimeInterval(31 * Self.day)
        let resolved = store.resolveWindowMinutes(resetsAt: next, now: next.addingTimeInterval(-30 * Self.day))

        #expect(resolved == Self.monthlyMinutes)
        #expect(store.learnedWindowMinutes() == Self.monthlyMinutes)
    }

    @Test
    func `ignores sub-day drift in the reset timestamp`() throws {
        // xAI nudges the reset timestamp by minutes or hours within a cycle; that is not a period.
        let store = try Self.makeStore()
        let first = Date(timeIntervalSince1970: 1_800_000_000)

        _ = store.resolveWindowMinutes(resetsAt: first, now: first.addingTimeInterval(-6 * Self.day))
        let resolved = store.resolveWindowMinutes(
            resetsAt: first.addingTimeInterval(3 * 3600),
            now: first.addingTimeInterval(-5 * Self.day))

        #expect(resolved == Self.weeklyMinutes)
        #expect(store.learnedWindowMinutes() == Self.weeklyMinutes)
    }

    @Test
    func `ignores gaps too long to be a billing period`() throws {
        // The app was closed for months: the gap spans several cycles, so it says nothing.
        let store = try Self.makeStore()
        let first = Date(timeIntervalSince1970: 1_800_000_000)

        _ = store.resolveWindowMinutes(resetsAt: first, now: first.addingTimeInterval(-6 * Self.day))
        let next = first.addingTimeInterval(120 * Self.day)
        let resolved = store.resolveWindowMinutes(resetsAt: next, now: next.addingTimeInterval(-2 * Self.day))

        #expect(resolved == Self.weeklyMinutes)
        #expect(store.learnedWindowMinutes() == Self.weeklyMinutes)
    }

    @Test
    func `missed weekly cycles do not become a false monthly cadence`() throws {
        let store = try Self.makeStore()
        var resetsAt = Date(timeIntervalSince1970: 1_800_000_000)

        _ = store.resolveWindowMinutes(resetsAt: resetsAt, now: resetsAt.addingTimeInterval(-6 * Self.day))
        for missedDays in [14, 21, 28] {
            let next = resetsAt.addingTimeInterval(TimeInterval(missedDays) * Self.day)
            #expect(store.resolveWindowMinutes(
                resetsAt: next,
                now: next.addingTimeInterval(-6 * Self.day)) == Self.weeklyMinutes)
            #expect(store.learnedWindowMinutes() == Self.weeklyMinutes)
            resetsAt = next
        }
    }

    @Test
    func `a plan change replaces the older cadence on the first clear rollover`() throws {
        let store = try Self.makeStore()
        var resetsAt = Date(timeIntervalSince1970: 1_800_000_000)

        _ = store.resolveWindowMinutes(resetsAt: resetsAt, now: resetsAt.addingTimeInterval(-6 * Self.day))
        resetsAt = resetsAt.addingTimeInterval(7 * Self.day)
        #expect(store.resolveWindowMinutes(
            resetsAt: resetsAt,
            now: resetsAt.addingTimeInterval(-6 * Self.day)) == Self.weeklyMinutes)

        resetsAt = resetsAt.addingTimeInterval(31 * Self.day)
        let resolved = store.resolveWindowMinutes(
            resetsAt: resetsAt,
            now: resetsAt.addingTimeInterval(-30 * Self.day))

        #expect(resolved == Self.monthlyMinutes)
    }

    @Test
    func `state survives across store instances`() throws {
        let fileURL = try Self.makeFileURL()
        let first = Date(timeIntervalSince1970: 1_800_000_000)

        _ = GrokBillingCadenceStore(fileURL: fileURL).resolveWindowMinutes(
            resetsAt: first,
            now: first.addingTimeInterval(-6 * Self.day))
        let resolved = GrokBillingCadenceStore(fileURL: fileURL)
            .resolveWindowMinutes(
                resetsAt: first.addingTimeInterval(7 * Self.day),
                now: first.addingTimeInterval(Self.day))

        #expect(resolved == Self.weeklyMinutes)
    }

    @Test
    func `a different account scope does not reuse the previous cadence`() throws {
        let store = try Self.makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(store.resolveWindowMinutes(
            resetsAt: now.addingTimeInterval(30 * Self.day),
            now: now,
            accountScope: "account-a") == 30 * 24 * 60)
        #expect(store.resolveWindowMinutes(
            resetsAt: now.addingTimeInterval(2 * Self.day),
            now: now,
            accountScope: "account-b") == nil)
        #expect(store.learnedWindowMinutes() == nil)
    }

    @Test
    func `a missing reset timestamp keeps the current estimate`() throws {
        let store = try Self.makeStore()
        let first = Date(timeIntervalSince1970: 1_800_000_000)

        _ = store.resolveWindowMinutes(resetsAt: first, now: first.addingTimeInterval(-6 * Self.day))
        let next = first.addingTimeInterval(31 * Self.day)
        _ = store.resolveWindowMinutes(resetsAt: next, now: next.addingTimeInterval(-30 * Self.day))

        #expect(store.resolveWindowMinutes(resetsAt: nil) == Self.monthlyMinutes)
    }

    private static func makeStore() throws -> GrokBillingCadenceStore {
        try GrokBillingCadenceStore(fileURL: self.makeFileURL())
    }

    private static func makeFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokBillingCadenceStoreTests-\(UUID().uuidString)", isDirectory: true)
        return directory.appendingPathComponent("grok-billing-cadence.json")
    }
}
