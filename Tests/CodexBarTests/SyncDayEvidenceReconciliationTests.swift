import CodexBarSync
import Foundation
import Testing

struct SyncDayEvidenceReconciliationTests {
    private func dayEvidence(
        revision: Int64,
        sourceKind: String = "codexLocalLedger",
        scopeID: String = "codex-ledger-account-calendar",
        lineageID: String = "ledger-epoch-a",
        verifiedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> SyncDayEvidence
    {
        SyncDayEvidence(
            sourceKind: sourceKind,
            scopeID: scopeID,
            lineageID: lineageID,
            revision: revision,
            verifiedAt: verifiedAt)
    }

    private func evidencedSummary(
        _ daily: [SyncDailyPoint],
        coverage: Bool? = false,
        historyDays: Int? = 30,
        sinceDayKey: String? = "2026-09-01",
        untilDayKey: String? = "2026-09-30",
        updatedAt: Date? = Date(timeIntervalSince1970: 1_800_000_000)) -> SyncCostSummary
    {
        SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: daily.reduce(0) { $0 + $1.costUSD },
            last30DaysTokens: daily.reduce(0) { $0 + $1.totalTokens },
            daily: daily,
            costIsKnown: daily.contains(where: { $0.costIsKnown == false }) ? false : nil,
            historyDays: historyDays,
            historyCoverageIsEstablished: coverage,
            historySinceDayKey: sinceDayKey,
            historyUntilDayKey: untilDayKey,
            costUpdatedAt: updatedAt,
            totalCostUpdatedAt: updatedAt)
    }

    @Test
    func `newer verified daily revisions advance repeated codex ledger increments`() {
        let first = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 0.552216,
            totalTokens: 522_908,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(revision: 40))
        let second = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 0.621407,
            totalTokens: 548_117,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(
                revision: 41,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_060)))
        let third = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 0.703185,
            totalTokens: 577_940,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(
                revision: 42,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_120)))

        let firstSummary = self.evidencedSummary([first], coverage: true)
        let secondSummary = self.evidencedSummary([second], coverage: false)
        let thirdSummary = self.evidencedSummary([third], coverage: nil)
        let afterSecond = secondSummary.reconcilingHistory(with: firstSummary)
        let afterThird = thirdSummary.reconcilingHistory(with: afterSecond)

        #expect(first.costUSD == 0.552216)
        #expect(first.totalTokens == 522_908)
        #expect(afterSecond.daily.first?.costUSD == 0.621407)
        #expect(afterSecond.daily.first?.totalTokens == 548_117)
        #expect(afterThird.daily.first?.costUSD == 0.703185)
        #expect(afterThird.daily.first?.totalTokens == 577_940)
        #expect(afterThird.last30DaysCostUSD == 0.703185)
        #expect(afterThird.last30DaysTokens == 577_940)
    }

    @Test
    func `newer verified daily revision can reduce a day to zero`() {
        let previous = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 4.75,
            totalTokens: 10000,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(revision: 10))
        let correction = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 0,
            totalTokens: 0,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(
                revision: 11,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_060)))

        let reconciled = self.evidencedSummary([correction], coverage: false)
            .reconcilingHistory(with: self.evidencedSummary([previous], coverage: true))

        #expect(reconciled.daily.first?.costUSD == 0)
        #expect(reconciled.daily.first?.totalTokens == 0)
        #expect(reconciled.last30DaysCostUSD == 0)
        #expect(reconciled.last30DaysTokens == 0)
        #expect(reconciled.daily.first?.dayEvidence?.revision == 11)
    }

    @Test
    func `partial omission retains independently verified previous days`() {
        let first = SyncDailyPoint(
            dayKey: "2026-09-29",
            costUSD: 2,
            totalTokens: 200,
            dayEvidence: self.dayEvidence(revision: 10))
        let second = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 3,
            totalTokens: 300,
            dayEvidence: self.dayEvidence(revision: 10))
        let update = SyncDailyPoint(
            dayKey: "2026-09-29",
            costUSD: 2.5,
            totalTokens: 250,
            dayEvidence: self.dayEvidence(
                revision: 11,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_060)))

        let reconciled = self.evidencedSummary([update], coverage: false)
            .reconcilingHistory(with: self.evidencedSummary([first, second], coverage: true))

        #expect(reconciled.daily.map(\.dayKey) == ["2026-09-29", "2026-09-30"])
        #expect(reconciled.daily.map(\.costUSD) == [2.5, 3])
        #expect(reconciled.daily.map(\.totalTokens) == [250, 300])
    }

    @Test
    func `bounded complete omission retains a proofed day until a newer zero proof`() {
        let previousPoint = SyncDailyPoint(
            dayKey: "2026-09-29",
            costUSD: 3,
            totalTokens: 300,
            dayEvidence: self.dayEvidence(revision: 20))
        let previous = self.evidencedSummary([previousPoint], coverage: true)
        let completeOmission = self.evidencedSummary(
            [],
            coverage: true,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100))

        let retained = completeOmission.reconcilingHistory(with: previous)

        #expect(retained.daily.map(\.dayKey) == ["2026-09-29"])
        #expect(retained.daily.first?.costUSD == 3)
        #expect(retained.daily.first?.dayEvidence?.revision == 20)
    }

    @Test
    func `older per day proof cannot roll back a newer complete summary`() {
        let newest = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 7,
            totalTokens: 700,
            dayEvidence: self.dayEvidence(revision: 80))
        let oldPayload = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 5,
            totalTokens: 500,
            dayEvidence: self.dayEvidence(
                revision: 79,
                verifiedAt: Date(timeIntervalSince1970: 1_799_999_900)))
        let previous = self.evidencedSummary([newest], coverage: false)
        let incoming = self.evidencedSummary(
            [oldPayload],
            coverage: true,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100))

        let reconciled = incoming.reconcilingHistory(with: previous)

        #expect(reconciled.daily.first?.costUSD == 7)
        #expect(reconciled.daily.first?.totalTokens == 700)
        #expect(reconciled.daily.first?.dayEvidence?.revision == 80)
    }

    @Test
    func `unknown pricing advances tokens but preserves known day cost and proof`() {
        let known = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 0.552216,
            totalTokens: 522_908,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(revision: 50))
        let unpriced = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 0,
            totalTokens: 600_000,
            costIsKnown: false,
            dayEvidence: self.dayEvidence(
                revision: 51,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_060)))

        let reconciled = self.evidencedSummary([unpriced], coverage: false)
            .reconcilingHistory(with: self.evidencedSummary([known], coverage: true))

        #expect(reconciled.daily.first?.costUSD == 0.552216)
        #expect(reconciled.daily.first?.totalTokens == 600_000)
        #expect(reconciled.daily.first?.costIsKnown == false)
        #expect(reconciled.daily.first?.dayEvidence?.revision == 51)
        #expect(reconciled.costIsKnown == false)
    }

    @Test
    func `incomparable lineage fails closed until a fresh complete baseline`() {
        let previousPoint = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 8,
            totalTokens: 800,
            dayEvidence: self.dayEvidence(revision: 100, lineageID: "ledger-epoch-a"))
        let replacement = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 1,
            totalTokens: 100,
            dayEvidence: self.dayEvidence(
                revision: 1,
                lineageID: "ledger-epoch-b",
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_200)))
        let newCalendarScopeReplacement = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 0,
            totalTokens: 0,
            dayEvidence: self.dayEvidence(
                revision: 1,
                scopeID: "codex-ledger-account-new-calendar",
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_200)))
        let previous = self.evidencedSummary([previousPoint], coverage: true)
        let partialReplacement = self.evidencedSummary([replacement], coverage: false)
        let completeReplacement = self.evidencedSummary(
            [replacement],
            coverage: true,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_200))
        let partialScopeReplacement = self.evidencedSummary(
            [newCalendarScopeReplacement],
            coverage: false)
        let completeScopeReplacement = self.evidencedSummary(
            [newCalendarScopeReplacement],
            coverage: true,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_200))

        let rejected = partialReplacement.reconcilingHistory(with: previous)
        let adopted = completeReplacement.reconcilingHistory(with: previous)
        let rejectedScope = partialScopeReplacement.reconcilingHistory(with: previous)
        let adoptedScope = completeScopeReplacement.reconcilingHistory(with: previous)

        #expect(rejected.daily.first?.costUSD == 8)
        #expect(rejected.daily.first?.dayEvidence?.lineageID == "ledger-epoch-a")
        #expect(adopted.daily.first?.costUSD == 1)
        #expect(adopted.daily.first?.dayEvidence?.lineageID == "ledger-epoch-b")
        #expect(rejectedScope.daily.first?.costUSD == 8)
        #expect(rejectedScope.daily.first?.dayEvidence?.scopeID == "codex-ledger-account-calendar")
        #expect(adoptedScope.daily.first?.costUSD == 0)
        #expect(adoptedScope.daily.first?.dayEvidence?.scopeID == "codex-ledger-account-new-calendar")
    }

    @Test
    func `day evidence overlays within retained bounds and on one day rollover`() {
        let oldPoint = SyncDailyPoint(
            dayKey: "2026-10-03",
            costUSD: 1,
            totalTokens: 100,
            dayEvidence: self.dayEvidence(revision: 1))
        let overlay = SyncDailyPoint(
            dayKey: "2026-10-03",
            costUSD: 2,
            totalTokens: 200,
            dayEvidence: self.dayEvidence(revision: 2))
        let nextDay = SyncDailyPoint(
            dayKey: "2026-10-04",
            costUSD: 3,
            totalTokens: 300,
            dayEvidence: self.dayEvidence(revision: 3))
        let previous = self.evidencedSummary(
            [oldPoint],
            coverage: true,
            historyDays: 365,
            sinceDayKey: "2025-10-04",
            untilDayKey: "2026-10-03")
        let narrower = self.evidencedSummary(
            [overlay],
            coverage: false,
            historyDays: 30,
            sinceDayKey: "2026-09-04",
            untilDayKey: "2026-10-03")
        let rollover = self.evidencedSummary(
            [nextDay],
            coverage: false,
            historyDays: 30,
            sinceDayKey: "2026-09-05",
            untilDayKey: "2026-10-04")

        let retainedOverlay = narrower.reconcilingHistory(with: previous)
        let retainedRollover = rollover.reconcilingHistory(with: retainedOverlay)

        #expect(retainedOverlay.historyDays == 365)
        #expect(retainedOverlay.daily.first?.costUSD == 2)
        #expect(retainedRollover.daily.map(\.dayKey) == ["2026-10-03", "2026-10-04"])
        #expect(retainedRollover.daily.map(\.costUSD) == [2, 3])
        #expect(retainedRollover.historyDays == 365)
        #expect(retainedRollover.historySinceDayKey == "2025-10-05")
        #expect(retainedRollover.historyUntilDayKey == "2026-10-04")
    }

    @Test
    func `rollover trims expired known and unknown lower bound before totals`() {
        let expiredKnown = SyncDailyPoint(
            dayKey: "2026-09-01",
            costUSD: 10,
            totalTokens: 1000,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(revision: 10))
        let retainedUnknown = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 1,
            totalTokens: 100,
            costIsKnown: false,
            dayEvidence: self.dayEvidence(revision: 10))
        let nextDay = SyncDailyPoint(
            dayKey: "2026-10-01",
            costUSD: 2,
            totalTokens: 200,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(
                revision: 11,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_060)))
        let previous = self.evidencedSummary(
            [expiredKnown, retainedUnknown],
            coverage: true,
            historyDays: 30,
            sinceDayKey: "2026-09-01",
            untilDayKey: "2026-09-30")
        let incoming = self.evidencedSummary(
            [nextDay],
            coverage: false,
            historyDays: 30,
            sinceDayKey: "2026-09-02",
            untilDayKey: "2026-10-01",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_060))

        let reconciled = incoming.reconcilingHistory(with: previous)

        #expect(reconciled.historySinceDayKey == "2026-09-02")
        #expect(reconciled.historyUntilDayKey == "2026-10-01")
        #expect(reconciled.daily.map(\.dayKey) == ["2026-09-30", "2026-10-01"])
        #expect(reconciled.last30DaysCostUSD == 3)
        #expect(reconciled.costIsKnown == false)
    }

    @Test
    func `unknown omitted day does not hide a verified decrease to zero`() {
        let knownDay = SyncDailyPoint(
            dayKey: "2026-09-29",
            costUSD: 10,
            totalTokens: 1000,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(revision: 1))
        let unknownOmittedDay = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 0,
            totalTokens: 100,
            costIsKnown: false,
            dayEvidence: self.dayEvidence(revision: 1))
        let verifiedZero = SyncDailyPoint(
            dayKey: "2026-09-29",
            costUSD: 0,
            totalTokens: 0,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(
                revision: 2,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_060)))
        let previous = self.evidencedSummary([knownDay, unknownOmittedDay], coverage: true)
        let incoming = self.evidencedSummary([verifiedZero], coverage: false)

        let reconciled = incoming.reconcilingHistory(with: previous)

        #expect(reconciled.daily.map(\.costUSD) == [0, 0])
        #expect(reconciled.daily.last?.costIsKnown == false)
        #expect(reconciled.last30DaysCostUSD == 0)
        #expect(reconciled.costIsKnown == false)
    }

    @Test
    func `invalid day evidence cannot replace proof or seed future authority`() {
        let invalidEvidence = [
            self.dayEvidence(revision: 100, sourceKind: "unsupportedSource"),
            self.dayEvidence(revision: 0),
            self.dayEvidence(revision: -1),
            self.dayEvidence(revision: 100, scopeID: "  \n"),
            self.dayEvidence(revision: 100, lineageID: "  "),
            self.dayEvidence(revision: 100, verifiedAt: Date(timeIntervalSince1970: .nan)),
        ]
        #expect(invalidEvidence.allSatisfy { !$0.isValid })

        let previousPoint = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 8,
            totalTokens: 800,
            dayEvidence: self.dayEvidence(revision: 1))
        let previous = self.evidencedSummary([previousPoint], coverage: true)
        for evidence in invalidEvidence {
            let invalidPoint = SyncDailyPoint(
                dayKey: "2026-09-30",
                costUSD: 100,
                totalTokens: 10000,
                dayEvidence: evidence)
            let invalidSummary = self.evidencedSummary(
                [invalidPoint],
                coverage: true,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_100))
            let reconciled = invalidSummary.reconcilingHistory(with: previous)
            #expect(reconciled.daily.first?.costUSD == 8)
            #expect(reconciled.daily.first?.totalTokens == 800)
            #expect(reconciled.daily.first?.dayEvidence?.revision == 1)
        }

        let invalidFirstPoint = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 1,
            totalTokens: 100,
            dayEvidence: self.dayEvidence(revision: 999, sourceKind: "unsupportedSource"))
        let invalidFirst = self.evidencedSummary([invalidFirstPoint], coverage: false)
            .reconcilingHistory(with: nil)
        #expect(invalidFirst.daily.first?.dayEvidence == nil)

        let validAfterInvalidPoint = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 2,
            totalTokens: 200,
            dayEvidence: self.dayEvidence(
                revision: 1,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_060)))
        let validAfterInvalid = self.evidencedSummary([validAfterInvalidPoint], coverage: false)
            .reconcilingHistory(with: invalidFirst)
        #expect(validAfterInvalid.daily.first?.costUSD == 2)
        #expect(validAfterInvalid.daily.first?.dayEvidence?.revision == 1)
    }

    @Test
    func `proof bootstrap cannot roll back retained cost but a fresh zero can`() {
        let legacyPoint = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 10,
            totalTokens: 1000,
            costIsKnown: true)
        let retained = self.evidencedSummary(
            [legacyPoint],
            coverage: true,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100))

        let stalePoint = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 2,
            totalTokens: 200,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(
                revision: 1,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_050)))
        let stale = self.evidencedSummary(
            [stalePoint],
            coverage: false,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_050))
            .reconcilingHistory(with: retained)

        let freshZeroPoint = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 0,
            totalTokens: 0,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(
                revision: 1,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_101)))
        let freshZero = self.evidencedSummary(
            [freshZeroPoint],
            coverage: false,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_101))
            .reconcilingHistory(with: retained)

        #expect(stale.daily.first?.costUSD == 10)
        #expect(stale.daily.first?.dayEvidence == nil)
        #expect(freshZero.daily.first?.costUSD == 0)
        #expect(freshZero.daily.first?.dayEvidence?.revision == 1)
    }

    @Test
    func `legacy fallback cost time gates proof bootstrap without trusting incoming time`() {
        let legacyPoint = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 10,
            totalTokens: 1000,
            costIsKnown: true)
        let retained = self.evidencedSummary(
            [legacyPoint],
            coverage: true,
            updatedAt: nil)
        let retainedFallback = Date(timeIntervalSince1970: 1_800_000_100)
        let incomingQuotaFallback = Date(timeIntervalSince1970: 1_800_000_200)

        let stalePoint = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 2,
            totalTokens: 200,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(
                revision: 1,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_050)))
        let stale = self.evidencedSummary([stalePoint], coverage: false, updatedAt: nil)
            .reconcilingHistory(
                with: retained,
                incomingFallbackUpdatedAt: incomingQuotaFallback,
                previousFallbackUpdatedAt: retainedFallback)

        let freshZeroPoint = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 0,
            totalTokens: 0,
            costIsKnown: true,
            dayEvidence: self.dayEvidence(
                revision: 1,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_101)))
        let freshZero = self.evidencedSummary([freshZeroPoint], coverage: false, updatedAt: nil)
            .reconcilingHistory(
                with: retained,
                incomingFallbackUpdatedAt: incomingQuotaFallback,
                previousFallbackUpdatedAt: retainedFallback)

        #expect(stale.daily.first?.costUSD == 10)
        #expect(stale.daily.first?.dayEvidence == nil)
        #expect(freshZero.daily.first?.costUSD == 0)
        #expect(freshZero.daily.first?.dayEvidence?.revision == 1)
    }

    @Test
    func `same revision with newer verification time refreshes proof metadata only`() {
        let originalBreakdown = SyncCostBreakdown(label: "GPT-4o", costUSD: 0.552216, totalTokens: 522_908)
        let changedBreakdown = SyncCostBreakdown(label: "GPT-4.1", costUSD: 0.9, totalTokens: 900_000)
        let previousPoint = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 0.552216,
            totalTokens: 522_908,
            modelBreakdowns: [originalBreakdown],
            costIsKnown: true,
            dayEvidence: self.dayEvidence(revision: 7))
        let reverifiedPoint = SyncDailyPoint(
            dayKey: "2026-09-30",
            costUSD: 0.9,
            totalTokens: 900_000,
            modelBreakdowns: [changedBreakdown],
            costIsKnown: true,
            dayEvidence: self.dayEvidence(
                revision: 7,
                verifiedAt: Date(timeIntervalSince1970: 1_800_000_060)))

        let reconciled = self.evidencedSummary([reverifiedPoint], coverage: false)
            .reconcilingHistory(with: self.evidencedSummary([previousPoint], coverage: true))

        #expect(reconciled.daily.first?.costUSD == 0.552216)
        #expect(reconciled.daily.first?.totalTokens == 522_908)
        #expect(reconciled.daily.first?.modelBreakdowns == [originalBreakdown])
        #expect(reconciled.daily.first?.dayEvidence?.revision == 7)
        #expect(reconciled.daily.first?.dayEvidence?.verifiedAt == Date(timeIntervalSince1970: 1_800_000_060))
        #expect(reconciled.last30DaysCostUSD == 0.552216)
    }
}
