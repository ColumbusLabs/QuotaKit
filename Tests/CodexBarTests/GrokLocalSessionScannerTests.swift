import Foundation
import Testing
@testable import CodexBarCore

struct GrokLocalSessionScannerTests {
    @Test
    func `daily buckets stay local and never invent dollars`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-session-scan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cwd = root.appendingPathComponent("sessions/%2Ftmp%2Fdemo", isDirectory: true)
        let first = cwd.appendingPathComponent("session-a", isDirectory: true)
        let second = cwd.appendingPathComponent("session-b", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let calendar = Calendar.current
        let newer = Date(timeIntervalSince1970: 1_787_079_600)
        let older = try #require(calendar.date(byAdding: .day, value: -1, to: newer))
        try self.writeSignals(
            at: first.appendingPathComponent("signals.json"),
            tokens: 100,
            model: "grok-4.6",
            date: older)
        try self.writeSignals(
            at: second.appendingPathComponent("signals.json"),
            tokens: 250,
            model: "grok-4.6",
            date: newer)

        let summary = GrokLocalSessionScanner.summarize(
            env: ["GROK_HOME": root.path],
            lookbackDays: 7,
            now: newer)
        #expect(summary.sessionCount == 2)
        #expect(summary.totalTokens == 350)
        #expect(summary.daily.map(\.totalTokens) == [100, 250])
        #expect(summary.daily.map(\.sessionCount) == [1, 1])
        #expect(Set(summary.daily.map(\.date)).count == 2)

        let snapshot = try #require(summary.toCostUsageTokenSnapshot(historyDays: 7))
        #expect(snapshot.last30DaysTokens == 350)
        #expect(snapshot.last30DaysCostUSD == nil)
        #expect(snapshot.daily.allSatisfy { $0.costUSD == nil })
        #expect(snapshot.costProvenance == .unknown)
        #expect(snapshot.sessionTokens == 250)
    }

    @Test
    func `idle days do not reuse yesterday as today`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-session-idle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("sessions/%2Ftmp%2Fdemo/session-a", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let calendar = Calendar.current
        let yesterday = Date(timeIntervalSince1970: 1_787_079_600)
        let today = try #require(calendar.date(byAdding: .day, value: 1, to: yesterday))
        try self.writeSignals(
            at: session.appendingPathComponent("signals.json"),
            tokens: 100,
            model: "grok-4.6",
            date: yesterday)
        let summary = GrokLocalSessionScanner.summarize(
            env: ["GROK_HOME": root.path],
            lookbackDays: 7,
            now: today)
        let snapshot = try #require(summary.toCostUsageTokenSnapshot(historyDays: 7))
        #expect(snapshot.last30DaysTokens == 100)
        #expect(snapshot.sessionTokens == nil)
    }

    @Test
    func `only session root signals contribute to local usage`() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("grok-layout-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let session = home.appendingPathComponent("sessions/project/session")
        let nested = session.appendingPathComponent("artifacts/nested-session")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_787_079_600)
        try self.writeSignals(
            at: session.appendingPathComponent("signals.json"),
            tokens: 100,
            model: "example-model",
            date: now)
        try self.writeSignals(
            at: nested.appendingPathComponent("signals.json"),
            tokens: 900,
            model: "artifact-model",
            date: now)
        try Data("unrelated".utf8).write(to: home.appendingPathComponent("sessions/project/unrelated.txt"))

        let fileManager = GrokScanRecordingFileManager()
        let summary = GrokLocalSessionScanner.summarize(
            env: ["GROK_HOME": home.path], fileManager: fileManager, now: now)
        #expect(summary.sessionCount == 1)
        #expect(summary.totalTokens == 100)
        #expect(summary.lastSessionAt == now)
        #expect(summary.primaryModel == "example-model")
        #expect(summary.models == ["example-model"])
        #expect(summary.scannedAt == now)
        let day = try #require(GrokLocalSessionScanner.dayKey(for: now, calendar: .current))
        #expect(summary.daily == [GrokLocalDailyBucket(
            date: day, totalTokens: 100, sessionCount: 1, models: ["example-model"])])
        #expect(Set(fileManager.visitedNames) == ["project", "session", "unrelated.txt"])
    }

    @Test(arguments: ["missing", "empty", "unavailable"])
    func `empty homes do not publish a spend snapshot`(state: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-session-empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if state != "missing" {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        }
        let fileManager = GrokScanRecordingFileManager()
        fileManager.refusesEnumeration = state == "unavailable"
        let now = Date(timeIntervalSince1970: 1_787_079_600)
        let summary = GrokLocalSessionScanner.summarize(
            env: ["GROK_HOME": root.path],
            fileManager: fileManager,
            lookbackDays: 7,
            now: now)
        #expect(summary.sessionCount == 0)
        #expect(summary.totalTokens == 0)
        #expect(summary.lastSessionAt == nil)
        #expect(summary.primaryModel == nil)
        #expect(summary.models.isEmpty)
        #expect(summary.daily.isEmpty)
        #expect(summary.scannedAt == now)
        #expect(summary.toCostUsageTokenSnapshot(historyDays: 7) == nil)
    }

    @Test
    func `local scan clock wins over a stale remote snapshot`() throws {
        let calendar = Calendar.current
        let staleRemoteTime = Date(timeIntervalSince1970: 1_787_079_600)
        let localScanTime = try #require(calendar.date(byAdding: .day, value: 1, to: staleRemoteTime))
        let localDay = try #require(GrokLocalSessionScanner.dayKey(for: localScanTime, calendar: calendar))
        let summary = GrokLocalSessionSummary(
            sessionCount: 1,
            totalTokens: 250,
            lastSessionAt: localScanTime,
            primaryModel: "grok-4.6",
            models: ["grok-4.6"],
            daily: [GrokLocalDailyBucket(
                date: localDay,
                totalTokens: 250,
                sessionCount: 1,
                models: ["grok-4.6"])],
            scannedAt: localScanTime)
        let remote = GrokUsageSnapshot(
            billing: nil,
            credentials: nil,
            localSummary: summary,
            cliVersion: nil,
            updatedAt: staleRemoteTime)

        let snapshot = try #require(remote.toUsageSnapshot().costUsage)
        #expect(snapshot.sessionTokens == 250)
        #expect(snapshot.updatedAt == localScanTime)
    }

    private func writeSignals(at url: URL, tokens: Int, model: String, date: Date) throws {
        let payload: [String: Any] = [
            "contextTokensUsed": tokens,
            "totalTokensBeforeCompaction": 0,
            "primaryModelId": model,
            "modelsUsed": [model],
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}

private final class GrokScanRecordingFileManager: FileManager, @unchecked Sendable {
    var visitedNames: [String] = []
    var refusesEnumeration = false

    /// The public Swift overlay delegates to this overridable Foundation entry point.
    override func __enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = [],
        errorHandler handler: ((URL, Error) -> Bool)? = nil) -> FileManager.DirectoryEnumerator?
    {
        guard !self.refusesEnumeration else { return nil }
        guard let enumerator = super.__enumerator(
            at: url, includingPropertiesForKeys: keys, options: mask, errorHandler: handler)
        else { return nil }
        return GrokScanRecordingEnumerator(base: enumerator) { self.visitedNames.append($0.lastPathComponent) }
    }
}

private final class GrokScanRecordingEnumerator: FileManager.DirectoryEnumerator {
    let base: FileManager.DirectoryEnumerator
    let record: (URL) -> Void

    init(base: FileManager.DirectoryEnumerator, record: @escaping (URL) -> Void) {
        self.base = base
        self.record = record
    }

    override var level: Int {
        self.base.level
    }

    override func nextObject() -> Any? {
        let object = self.base.nextObject()
        if let url = object as? URL { self.record(url) }
        return object
    }

    override func skipDescendants() {
        self.base.skipDescendants()
    }
}
