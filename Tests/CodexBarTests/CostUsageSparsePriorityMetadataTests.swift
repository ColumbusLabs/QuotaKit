import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageSparsePriorityMetadataTests {
    @Test
    func `priority merge visits occupied days and reconciles pre-2020 entries`() throws {
        let calendar = CostUsageScanner.CostUsageDayRange.localGregorianCalendar(matching: .current)
        let range = try CostUsageScanner.CostUsageDayRange(
            since: Self.date(year: 2015, month: 1, day: 1, calendar: calendar),
            until: Self.date(year: 2025, month: 12, day: 31, calendar: calendar),
            calendar: calendar)
        let recorder = CostUsageScanner.CodexScanWorkRecorder()
        let oldValues = [
            "2015-03-04": "old-hash",
            "2021-07-08": "removed-hash",
            "2000-01-01": "outside-window",
        ]
        let newValues = [
            "2015-03-04": "new-hash",
            "2024-09-10": "added-hash",
        ]

        let merged = CostUsageScanner.mergePriorityDayValues(
            existing: oldValues,
            new: newValues,
            range: range,
            retainedSinceKey: "2000-01-01",
            retainedUntilKey: "2030-01-01",
            workRecorder: recorder)

        #expect(merged == [
            "2000-01-01": "outside-window",
            "2015-03-04": "new-hash",
            "2024-09-10": "added-hash",
        ])
        #expect(recorder.snapshot().codexPriorityMetadataDayVisits == 4)
    }

    @Test
    func `priority ID merge removes stale entries without creating empty days`() throws {
        let calendar = CostUsageScanner.CostUsageDayRange.localGregorianCalendar(matching: .current)
        let range = try CostUsageScanner.CostUsageDayRange(
            since: Self.date(year: 2019, month: 1, day: 1, calendar: calendar),
            until: Self.date(year: 2025, month: 12, day: 31, calendar: calendar),
            calendar: calendar)
        let existing = [
            "2019-02-03": ["turn-old"],
            "2022-04-05": ["turn-removed"],
        ]
        let current = [
            "2019-02-03": ["turn-current"],
            "2024-06-07": ["turn-new"],
        ]

        let merged = CostUsageScanner.mergePriorityDayValues(
            existing: existing,
            new: current,
            range: range,
            retainedSinceKey: "2018-01-01",
            retainedUntilKey: "2026-12-31")

        #expect(merged == [
            "2019-02-03": ["turn-current"],
            "2024-06-07": ["turn-new"],
        ])
    }

    @Test
    func `priority key changes include old-only and new-only sparse days`() throws {
        let calendar = CostUsageScanner.CostUsageDayRange.localGregorianCalendar(matching: .current)
        let range = try CostUsageScanner.CostUsageDayRange(
            since: Self.date(year: 2018, month: 1, day: 1, calendar: calendar),
            until: Self.date(year: 2025, month: 12, day: 31, calendar: calendar),
            calendar: calendar)
        let oldOnly = ["2019-02-03": "old-only"]
        let newOnly = ["2024-06-07": "new-only"]

        #expect(CostUsageScanner.codexPriorityTurnKeysChanged(old: oldOnly, new: [:], range: range))
        #expect(CostUsageScanner.codexPriorityTurnKeysChanged(old: [:], new: newOnly, range: range))

        let hashOnlyRecorder = CostUsageScanner.CodexScanWorkRecorder()
        let hashOnlyChanges = CostUsageScanner.changedPriorityTurnIDs(
            old: [:],
            new: [:],
            oldKeys: oldOnly,
            newKeys: newOnly,
            range: range,
            workRecorder: hashOnlyRecorder)
        #expect(hashOnlyChanges.isEmpty)
        #expect(hashOnlyRecorder.snapshot().codexPriorityMetadataDayVisits == 2)

        let changedIDs = CostUsageScanner.changedPriorityTurnIDs(
            old: ["2019-02-03": ["turn-old"]],
            new: ["2024-06-07": ["turn-new"]],
            oldKeys: oldOnly,
            newKeys: newOnly,
            range: range)
        #expect(changedIDs == ["turn-old", "turn-new"])
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
