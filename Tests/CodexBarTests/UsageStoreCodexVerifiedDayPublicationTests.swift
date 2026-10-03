import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct UsageStoreCodexVerifiedDayPublicationTests {
    @Test
    func `verified current day overlays established history without adopting partial coverage`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let establishedAt = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 30,
            hour: 10)))
        let candidateAt = establishedAt.addingTimeInterval(60)
        let historical = CostUsageDailyReport.Entry(
            date: "2026-07-29",
            inputTokens: 2,
            outputTokens: 2,
            totalTokens: 4,
            costUSD: 4,
            modelsUsed: nil,
            modelBreakdowns: nil)
        let establishedToday = CostUsageDailyReport.Entry(
            date: "2026-07-30",
            inputTokens: 4,
            outputTokens: 6,
            totalTokens: 10,
            costUSD: 3,
            modelsUsed: nil,
            modelBreakdowns: nil)
        let established = CostUsageTokenSnapshot(
            sessionTokens: 10,
            sessionCostUSD: 3,
            last30DaysTokens: 14,
            last30DaysCostUSD: 7,
            historyCoverageIsEstablished: true,
            daily: [historical, establishedToday],
            updatedAt: establishedAt)
        let candidate = Self.tokenSnapshot(
            cost: 9,
            now: candidateAt,
            historyCoverageIsEstablished: false,
            dayEvidence: Self.dayEvidence(revision: 2, verifiedAt: candidateAt))

        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            candidate,
            onto: established,
            calendar: calendar))

        #expect(overlaid.historyCoverageIsEstablished)
        #expect(overlaid.sessionCostUSD == 9)
        #expect(overlaid.last30DaysCostUSD == 13)
        #expect(overlaid.last30DaysTokens == 14)
        #expect(overlaid.daily.first { $0.date == "2026-07-29" }?.costUSD == 4)
        #expect(overlaid.daily.first { $0.date == "2026-07-30" }?.costUSD == 9)
        #expect(overlaid.updatedAt == candidateAt)

        let staleCandidate = Self.tokenSnapshot(
            cost: 12,
            now: establishedAt.addingTimeInterval(-1),
            historyCoverageIsEstablished: false,
            dayEvidence: Self.dayEvidence(revision: 3, verifiedAt: establishedAt.addingTimeInterval(-1)))
        #expect(UsageStore.codexCostSnapshotOverlayingVerifiedCurrentDay(
            staleCandidate,
            onto: established,
            calendar: calendar) == nil)
    }

    @Test
    func `newer proof advances today's established row repeatedly without a global maximum`() throws {
        let calendar = Self.utcCalendar
        let previousDay = "2026-10-02"
        let today = "2026-10-03"
        let establishedAt = try Self.date(today, hour: 10, calendar: calendar)
        let established = Self.codexSnapshot(
            entries: [
                Self.entry(
                    previousDay,
                    tokens: 40,
                    cost: 4,
                    evidence: Self.dayEvidence(revision: 4, verifiedAt: establishedAt)),
                Self.entry(
                    today,
                    tokens: 100,
                    cost: 10,
                    evidence: Self.dayEvidence(revision: 10, verifiedAt: establishedAt)),
            ],
            fixture: .init(
                since: previousDay,
                until: today,
                historyDays: 2,
                updatedAt: establishedAt,
                established: true))

        let firstAt = try Self.date(today, hour: 11, calendar: calendar)
        let first = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedDays(
            Self.codexSnapshot(
                entries: [Self.entry(
                    today,
                    tokens: 60,
                    cost: 6,
                    evidence: Self.dayEvidence(revision: 11, verifiedAt: firstAt))],
                fixture: .init(
                    since: previousDay,
                    until: today,
                    historyDays: 2,
                    updatedAt: firstAt,
                    established: false)),
            onto: established,
            calendar: calendar))

        #expect(first.last30DaysCostUSD == 10)
        #expect(first.last30DaysTokens == 100)
        #expect(first.daily.first { $0.date == today }?.dayEvidence?.revision == 11)

        let secondAt = try Self.date(today, hour: 12, calendar: calendar)
        let second = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedDays(
            Self.codexSnapshot(
                entries: [Self.entry(
                    today,
                    tokens: 10,
                    cost: 1,
                    evidence: Self.dayEvidence(revision: 12, verifiedAt: secondAt))],
                fixture: .init(
                    since: previousDay,
                    until: today,
                    historyDays: 2,
                    updatedAt: secondAt,
                    established: false)),
            onto: first,
            calendar: calendar))

        #expect(second.last30DaysCostUSD == 5)
        #expect(second.last30DaysTokens == 50)
        #expect(second.daily.first { $0.date == previousDay }?.costUSD == 4)
        #expect(second.daily.first { $0.date == today }?.dayEvidence?.revision == 12)
    }

    @Test
    func `newer proof corrects yesterday while preserving today's session values`() throws {
        let calendar = Self.utcCalendar
        let yesterday = "2026-10-02"
        let today = "2026-10-03"
        let establishedAt = try Self.date(today, hour: 10, calendar: calendar)
        let established = Self.codexSnapshot(
            entries: [
                Self.entry(
                    yesterday,
                    tokens: 80,
                    cost: 8,
                    evidence: Self.dayEvidence(revision: 20, verifiedAt: establishedAt)),
                Self.entry(
                    today,
                    tokens: 30,
                    cost: 3,
                    evidence: Self.dayEvidence(revision: 50, verifiedAt: establishedAt)),
            ],
            fixture: .init(
                since: yesterday,
                until: today,
                historyDays: 2,
                updatedAt: establishedAt,
                established: true))
        let candidateAt = try Self.date(today, hour: 11, calendar: calendar)
        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedDays(
            Self.codexSnapshot(
                entries: [Self.entry(
                    yesterday,
                    tokens: 20,
                    cost: 2,
                    evidence: Self.dayEvidence(revision: 21, verifiedAt: candidateAt))],
                fixture: .init(
                    since: yesterday,
                    until: today,
                    historyDays: 2,
                    updatedAt: candidateAt,
                    established: false)),
            onto: established,
            calendar: calendar))

        #expect(overlaid.daily.first { $0.date == yesterday }?.costUSD == 2)
        #expect(overlaid.daily.first { $0.date == yesterday }?.dayEvidence?.revision == 21)
        #expect(overlaid.daily.first { $0.date == today }?.costUSD == 3)
        #expect(overlaid.sessionCostUSD == 3)
        #expect(overlaid.sessionTokens == 30)
        #expect(overlaid.last30DaysCostUSD == 5)
    }

    @Test
    func `verified zero day replaces a previously positive amount`() throws {
        let calendar = Self.utcCalendar
        let today = "2026-10-03"
        let establishedAt = try Self.date(today, hour: 10, calendar: calendar)
        let established = Self.codexSnapshot(
            entries: [Self.entry(
                today,
                tokens: 80,
                cost: 8,
                evidence: Self.dayEvidence(revision: 4, verifiedAt: establishedAt))],
            fixture: .init(
                since: today,
                until: today,
                historyDays: 1,
                updatedAt: establishedAt,
                established: true))
        let candidateAt = try Self.date(today, hour: 11, calendar: calendar)
        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedDays(
            Self.codexSnapshot(
                entries: [Self.entry(
                    today,
                    tokens: 0,
                    cost: 0,
                    requests: 0,
                    evidence: Self.dayEvidence(revision: 5, verifiedAt: candidateAt))],
                fixture: .init(
                    since: today,
                    until: today,
                    historyDays: 1,
                    updatedAt: candidateAt,
                    established: false)),
            onto: established,
            calendar: calendar))

        #expect(overlaid.sessionCostUSD == 0)
        #expect(overlaid.last30DaysCostUSD == 0)
        #expect(overlaid.sessionTokens == 0)
        #expect(overlaid.last30DaysTokens == 0)
    }

    @Test
    func `verified unpriced correction clears stale cost while retaining known tokens`() throws {
        let calendar = Self.utcCalendar
        let yesterday = "2026-10-02"
        let today = "2026-10-03"
        let establishedAt = try Self.date(today, hour: 10, calendar: calendar)
        let established = Self.codexSnapshot(
            entries: [
                Self.entry(yesterday, tokens: 40, cost: 4),
                Self.entry(
                    today,
                    tokens: 80,
                    cost: 8,
                    evidence: Self.dayEvidence(revision: 10, verifiedAt: establishedAt)),
            ],
            fixture: .init(
                since: yesterday,
                until: today,
                historyDays: 2,
                updatedAt: establishedAt,
                established: true))
        let candidateAt = try Self.date(today, hour: 11, calendar: calendar)
        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedDays(
            Self.codexSnapshot(
                entries: [Self.entry(
                    today,
                    tokens: 120,
                    cost: nil,
                    unpricedRequests: 1,
                    evidence: Self.dayEvidence(revision: 11, verifiedAt: candidateAt))],
                fixture: .init(
                    since: yesterday,
                    until: today,
                    historyDays: 2,
                    updatedAt: candidateAt,
                    established: false)),
            onto: established,
            calendar: calendar))

        #expect(overlaid.daily.first { $0.date == today }?.costUSD == nil)
        #expect(overlaid.daily.first { $0.date == today }?.totalTokens == 120)
        #expect(overlaid.last30DaysCostUSD == nil)
        #expect(overlaid.sessionCostUSD == nil)
        #expect(overlaid.last30DaysTokens == 160)
    }

    @Test
    func `partial proof does not erase omitted established days`() throws {
        let calendar = Self.utcCalendar
        let first = "2026-10-01"
        let second = "2026-10-02"
        let today = "2026-10-03"
        let establishedAt = try Self.date(today, hour: 10, calendar: calendar)
        let established = Self.codexSnapshot(
            entries: [
                Self.entry(first, tokens: 10, cost: 1),
                Self.entry(second, tokens: 20, cost: 2),
                Self.entry(
                    today,
                    tokens: 30,
                    cost: 3,
                    evidence: Self.dayEvidence(revision: 30, verifiedAt: establishedAt)),
            ],
            fixture: .init(
                since: first,
                until: today,
                historyDays: 3,
                updatedAt: establishedAt,
                established: true))
        let candidateAt = try Self.date(today, hour: 11, calendar: calendar)
        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedDays(
            Self.codexSnapshot(
                entries: [Self.entry(
                    today,
                    tokens: 35,
                    cost: 3.5,
                    evidence: Self.dayEvidence(revision: 31, verifiedAt: candidateAt))],
                fixture: .init(
                    since: first,
                    until: today,
                    historyDays: 3,
                    updatedAt: candidateAt,
                    established: false)),
            onto: established,
            calendar: calendar))

        #expect(overlaid.daily.map(\.date) == [first, second, today])
        #expect(overlaid.last30DaysCostUSD == 6.5)
        #expect(overlaid.historyCoverageIsEstablished)
    }

    @Test(arguments: [30, 365])
    func `verified one day rollover trims only the expired boundary`(historyDays: Int) throws {
        let calendar = Self.utcCalendar
        let establishedUntil = "2026-10-03"
        let establishedSince = try #require(CostUsageDayWindow.dayKey(
            establishedUntil,
            advancedBy: -(historyDays - 1),
            calendar: calendar))
        let candidateSince = try #require(CostUsageDayWindow.dayKey(
            establishedSince,
            advancedBy: 1,
            calendar: calendar))
        let candidateUntil = "2026-10-04"
        let establishedAt = try Self.date(establishedUntil, hour: 10, calendar: calendar)
        let established = Self.codexSnapshot(
            entries: [
                Self.entry(establishedSince, tokens: 100, cost: 10),
                Self.entry(establishedUntil, tokens: 20, cost: 2),
            ],
            fixture: .init(
                since: establishedSince,
                until: establishedUntil,
                historyDays: historyDays,
                updatedAt: establishedAt,
                established: true))
        let candidateAt = try Self.date(candidateUntil, hour: 10, calendar: calendar)
        let overlaid = try #require(UsageStore.codexCostSnapshotOverlayingVerifiedDays(
            Self.codexSnapshot(
                entries: [Self.entry(
                    candidateUntil,
                    tokens: 10,
                    cost: 1,
                    evidence: Self.dayEvidence(revision: 1, verifiedAt: candidateAt))],
                fixture: .init(
                    since: candidateSince,
                    until: candidateUntil,
                    historyDays: historyDays,
                    updatedAt: candidateAt,
                    established: false)),
            onto: established,
            calendar: calendar))

        #expect(overlaid.historyCoverageIsEstablished)
        #expect(overlaid.historySinceDayKey == candidateSince)
        #expect(overlaid.historyUntilDayKey == candidateUntil)
        #expect(overlaid.daily.contains { $0.date == establishedSince } == false)
        #expect(overlaid.daily.contains { $0.date == establishedUntil })
        #expect(overlaid.daily.contains { $0.date == candidateUntil })
        #expect(overlaid.last30DaysCostUSD == 3)
    }

    @Test
    func `partial proof cannot cross account scope or adopt a new ledger lineage`() throws {
        let calendar = Self.utcCalendar
        let today = "2026-10-03"
        let establishedAt = try Self.date(today, hour: 10, calendar: calendar)
        let established = Self.codexSnapshot(
            entries: [Self.entry(
                today,
                tokens: 10,
                cost: 1,
                evidence: Self.dayEvidence(revision: 8, verifiedAt: establishedAt))],
            fixture: .init(
                since: today,
                until: today,
                historyDays: 1,
                updatedAt: establishedAt,
                established: true,
                credentialScopeFingerprint: "account-a"))
        let candidateAt = try Self.date(today, hour: 11, calendar: calendar)

        func candidate(
            scopeID: String = "root-a",
            lineageID: String = "epoch-a",
            credentialScopeFingerprint: String? = "account-a") -> CostUsageTokenSnapshot
        {
            Self.codexSnapshot(
                entries: [Self.entry(
                    today,
                    tokens: 5,
                    cost: 0.5,
                    evidence: Self.dayEvidence(
                        revision: 1,
                        scopeID: scopeID,
                        lineageID: lineageID,
                        verifiedAt: candidateAt))],
                fixture: .init(
                    since: today,
                    until: today,
                    historyDays: 1,
                    updatedAt: candidateAt,
                    established: false,
                    credentialScopeFingerprint: credentialScopeFingerprint))
        }

        #expect(UsageStore.codexCostSnapshotOverlayingVerifiedDays(
            candidate(scopeID: "root-b"), onto: established, calendar: calendar) == nil)
        #expect(UsageStore.codexCostSnapshotOverlayingVerifiedDays(
            candidate(lineageID: "epoch-b"), onto: established, calendar: calendar) == nil)
        #expect(UsageStore.codexCostSnapshotOverlayingVerifiedDays(
            candidate(credentialScopeFingerprint: "account-b"),
            onto: established,
            calendar: calendar) == nil)
    }

    @Test
    func `same revision with newer proof time refreshes metadata without changing content`() throws {
        let store = try Self.makeStore(suite: "same-revision-proof-refresh")
        let calendar = Self.utcCalendar
        let today = "2026-10-03"
        let establishedAt = try Self.date(today, hour: 9, calendar: calendar)
        let proofRefreshAt = try Self.date(today, hour: 10, calendar: calendar)
        let establishedModel = CostUsageDailyReport.ModelBreakdown(
            modelName: "gpt-4.1",
            costUSD: 8,
            totalTokens: 80,
            requestCount: 3,
            inputTokens: 70,
            outputTokens: 10)
        let establishedEntry = CostUsageDailyReport.Entry(
            date: today,
            inputTokens: 70,
            outputTokens: 10,
            totalTokens: 80,
            requestCount: 3,
            costUSD: 8,
            modelsUsed: ["gpt-4.1"],
            modelBreakdowns: [establishedModel],
            pricedRequestCount: 3,
            dayEvidence: Self.dayEvidence(revision: 8, verifiedAt: establishedAt))
        let establishedProject = CostUsageProjectBreakdown(
            name: "original project",
            path: "/tmp/original",
            totalTokens: 80,
            totalCostUSD: 8,
            daily: [establishedEntry],
            modelBreakdowns: [establishedModel])
        let establishedSession = CostUsageSessionBreakdown(
            sessionID: "original-session",
            lastActivity: establishedAt,
            inputTokens: 70,
            cachedInputTokens: nil,
            outputTokens: 10,
            totalTokens: 80,
            requestCount: 3,
            costUSD: 8,
            modelBreakdowns: [establishedModel],
            projectPath: "/tmp/original",
            projectName: "original project")
        let establishedHourly = CostUsageHourlyEntry(hour: establishedAt, totalTokens: 80, costUSD: 8)
        let establishedSlice = CostUsageTimedEntry(timestamp: establishedAt, totalTokens: 80, costUSD: 8)
        let established = Self.codexSnapshot(
            entries: [establishedEntry],
            fixture: .init(
                since: today,
                until: today,
                historyDays: 1,
                updatedAt: establishedAt,
                established: true,
                projects: [establishedProject],
                sessions: [establishedSession],
                hourly: [establishedHourly],
                quotaSlices: [establishedSlice]))
        let candidateModel = CostUsageDailyReport.ModelBreakdown(
            modelName: "different-model",
            costUSD: 0.5,
            totalTokens: 5,
            requestCount: 1,
            inputTokens: 2,
            outputTokens: 3)
        let candidateEntry = CostUsageDailyReport.Entry(
            date: today,
            inputTokens: 2,
            outputTokens: 3,
            totalTokens: 5,
            requestCount: 1,
            costUSD: 0.5,
            modelsUsed: ["different-model"],
            modelBreakdowns: [candidateModel],
            dayEvidence: Self.dayEvidence(revision: 8, verifiedAt: proofRefreshAt))
        let candidateProject = CostUsageProjectBreakdown(
            name: "candidate project",
            path: "/tmp/candidate",
            totalTokens: 5,
            totalCostUSD: 0.5,
            daily: [candidateEntry],
            modelBreakdowns: [candidateModel])
        let candidateSession = CostUsageSessionBreakdown(
            sessionID: "candidate-session",
            lastActivity: proofRefreshAt,
            inputTokens: 2,
            cachedInputTokens: nil,
            outputTokens: 3,
            totalTokens: 5,
            requestCount: 1,
            costUSD: 0.5,
            modelBreakdowns: [candidateModel])
        let candidate = try Self.codexSnapshot(
            entries: [candidateEntry],
            fixture: .init(
                since: today,
                until: today,
                historyDays: 1,
                updatedAt: Self.date(today, hour: 11, calendar: calendar),
                established: true,
                projects: [candidateProject],
                sessions: [candidateSession],
                hourly: [CostUsageHourlyEntry(hour: proofRefreshAt, totalTokens: 5, costUSD: 0.5)],
                quotaSlices: [CostUsageTimedEntry(timestamp: proofRefreshAt, totalTokens: 5, costUSD: 0.5)]))
        let sameContentWithRefreshedProof = Self.codexSnapshot(
            entries: [CostUsageDailyReport.Entry(
                date: today,
                inputTokens: 70,
                outputTokens: 10,
                totalTokens: 80,
                requestCount: 3,
                costUSD: 8,
                modelsUsed: ["gpt-4.1"],
                modelBreakdowns: [establishedModel],
                pricedRequestCount: 3,
                dayEvidence: Self.dayEvidence(revision: 8, verifiedAt: proofRefreshAt))],
            fixture: .init(
                since: today,
                until: today,
                historyDays: 1,
                updatedAt: establishedAt,
                established: true,
                projects: [establishedProject],
                sessions: [establishedSession],
                hourly: [establishedHourly],
                quotaSlices: [establishedSlice]))

        store.publishTokenSnapshot(established, for: .codex)
        store.publishTokenSnapshot(candidate, for: .codex)
        let overlaid = try #require(store.tokenSnapshot(for: .codex))

        #expect(overlaid.daily.first?.inputTokens == 70)
        #expect(overlaid.daily.first?.outputTokens == 10)
        #expect(overlaid.daily.first?.costUSD == 8)
        #expect(overlaid.daily.first?.modelBreakdowns == [establishedModel])
        #expect(overlaid.daily.first?.dayEvidence?.revision == 8)
        #expect(overlaid.daily.first?.dayEvidence?.verifiedAt == proofRefreshAt)
        #expect(overlaid.projects == [establishedProject])
        #expect(overlaid.sessions == [establishedSession])
        #expect(overlaid.hourly == [establishedHourly])
        #expect(overlaid.quotaSlices == [establishedSlice])
        #expect(overlaid.last30DaysCostUSD == 8)
        #expect(overlaid.updatedAt == proofRefreshAt)
        #expect(store.spendDashboardSnapshotSemanticFingerprint(sameContentWithRefreshedProof)
            != store.spendDashboardSnapshotSemanticFingerprint(established))
    }

    @Test
    func `legacy bootstrap compares proof time against established cost time`() throws {
        let calendar = Self.utcCalendar
        let today = "2026-10-03"
        let establishedAt = try Self.date(today, hour: 9, calendar: calendar)
        let established = Self.codexSnapshot(
            entries: [Self.entry(today, tokens: 90, cost: 9)],
            fixture: .init(
                since: today,
                until: today,
                historyDays: 1,
                updatedAt: establishedAt,
                established: true))
        let laterReportAt = try Self.date(today, hour: 10, calendar: calendar)
        let staleProofCandidate = try Self.codexSnapshot(
            entries: [Self.entry(
                today,
                tokens: 50,
                cost: 5,
                evidence: Self.dayEvidence(
                    revision: 1,
                    verifiedAt: Self.date(today, hour: 5, calendar: calendar)))],
            fixture: .init(
                since: today,
                until: today,
                historyDays: 1,
                updatedAt: laterReportAt,
                established: false))
        let freshProofAt = try Self.date(today, hour: 9, calendar: calendar).addingTimeInterval(60)
        let freshProofCandidate = Self.codexSnapshot(
            entries: [Self.entry(
                today,
                tokens: 50,
                cost: 5,
                evidence: Self.dayEvidence(revision: 1, verifiedAt: freshProofAt))],
            fixture: .init(
                since: today,
                until: today,
                historyDays: 1,
                updatedAt: laterReportAt,
                established: false))

        #expect(UsageStore.codexCostSnapshotOverlayingVerifiedDays(
            staleProofCandidate,
            onto: established,
            calendar: calendar) == nil)
        #expect(UsageStore.codexCostSnapshotOverlayingVerifiedDays(
            freshProofCandidate,
            onto: established,
            calendar: calendar)?.last30DaysCostUSD == 5)
    }

    @Test
    func `complete baseline can explicitly adopt a new ledger lineage`() throws {
        let store = try Self.makeStore(suite: "complete-lineage-adoption")
        let calendar = Self.utcCalendar
        let today = "2026-10-03"
        let establishedAt = try Self.date(today, hour: 10, calendar: calendar)
        store.publishTokenSnapshot(
            Self.codexSnapshot(
                entries: [Self.entry(
                    today,
                    tokens: 80,
                    cost: 8,
                    evidence: Self.dayEvidence(revision: 40, verifiedAt: establishedAt))],
                fixture: .init(
                    since: today,
                    until: today,
                    historyDays: 1,
                    updatedAt: establishedAt,
                    established: true)),
            for: .codex)
        let nextAt = try Self.date(today, hour: 11, calendar: calendar)
        let completeReplacement = Self.codexSnapshot(
            entries: [Self.entry(
                today,
                tokens: 1,
                cost: 0.1,
                evidence: Self.dayEvidence(
                    revision: 1,
                    lineageID: "epoch-b",
                    verifiedAt: nextAt))],
            fixture: .init(
                since: today,
                until: today,
                historyDays: 1,
                updatedAt: nextAt,
                established: true))

        store.publishTokenSnapshot(completeReplacement, for: .codex)

        #expect(store.tokenSnapshot(for: .codex)?.last30DaysCostUSD == 0.1)
        #expect(store.tokenSnapshot(for: .codex)?.daily.first?.dayEvidence?.lineageID == "epoch-b")
    }

    @Test
    func `ordinary publication overlays proof and fingerprints proof revisions`() throws {
        let store = try Self.makeStore(suite: "ordinary-proof-publication")
        let calendar = Self.utcCalendar
        let yesterday = "2026-10-02"
        let today = "2026-10-03"
        let establishedAt = try Self.date(today, hour: 10, calendar: calendar)
        let established = Self.codexSnapshot(
            entries: [
                Self.entry(yesterday, tokens: 40, cost: 4),
                Self.entry(
                    today,
                    tokens: 60,
                    cost: 6,
                    evidence: Self.dayEvidence(revision: 20, verifiedAt: establishedAt)),
            ],
            fixture: .init(
                since: yesterday,
                until: today,
                historyDays: 2,
                updatedAt: establishedAt,
                established: true))
        store.publishTokenSnapshot(established, for: .codex)
        let oldRevision = store.tokenSnapshotPublicationRevision(for: .codex)
        let candidateAt = try Self.date(today, hour: 11, calendar: calendar)
        let partial = Self.codexSnapshot(
            entries: [Self.entry(
                today,
                tokens: 10,
                cost: 1,
                evidence: Self.dayEvidence(revision: 21, verifiedAt: candidateAt))],
            fixture: .init(
                since: yesterday,
                until: today,
                historyDays: 2,
                updatedAt: candidateAt,
                established: false))

        let oldFingerprint = store.spendDashboardSnapshotSemanticFingerprint(partial)
        store.publishTokenSnapshot(partial, for: .codex)
        let published = try #require(store.tokenSnapshot(for: .codex))
        let newerProof = Self.codexSnapshot(
            entries: [Self.entry(
                today,
                tokens: 10,
                cost: 1,
                evidence: Self.dayEvidence(revision: 22, verifiedAt: candidateAt))],
            fixture: .init(
                since: yesterday,
                until: today,
                historyDays: 2,
                updatedAt: candidateAt,
                established: false))

        #expect(published.historyCoverageIsEstablished)
        #expect(published.last30DaysCostUSD == 5)
        #expect(store.tokenSnapshotPublicationRevision(for: .codex) == oldRevision + 1)
        #expect(oldFingerprint != store.spendDashboardSnapshotSemanticFingerprint(newerProof))
    }
}

extension UsageStoreCodexVerifiedDayPublicationTests {
    private static func makeStore(suite: String) throws -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "UsageStoreCodexVerifiedDayPublicationTests-\(suite)",
            userDefaults: InMemoryUserDefaults())
        settings.costUsageEnabled = true
        settings.costUsageHistoryDays = 30
        let metadata = try #require(ProviderRegistry.shared.metadata[.codex])
        settings.setProviderEnabled(provider: .codex, metadata: metadata, enabled: true)
        return UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
    }

    private static func tokenSnapshot(
        cost: Double,
        now: Date,
        historyCoverageIsEstablished: Bool,
        dayEvidence: CostUsageDayEvidence) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: 10,
            sessionCostUSD: cost,
            last30DaysTokens: 10,
            last30DaysCostUSD: cost,
            historyCoverageIsEstablished: historyCoverageIsEstablished,
            daily: [CostUsageDailyReport.Entry(
                date: "2026-07-30",
                inputTokens: 4,
                outputTokens: 6,
                totalTokens: 10,
                costUSD: cost,
                modelsUsed: nil,
                modelBreakdowns: nil,
                dayEvidence: dayEvidence)],
            updatedAt: now)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private static func date(_ dayKey: String, hour: Int, calendar: Calendar) throws -> Date {
        let components = dayKey.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else {
            Issue.record("Expected yyyy-MM-dd test day key, received \(dayKey)")
            throw CancellationError()
        }
        return try #require(calendar.date(from: DateComponents(
            year: components[0],
            month: components[1],
            day: components[2],
            hour: hour)))
    }

    private static func dayEvidence(
        revision: Int64,
        scopeID: String = "root-a",
        lineageID: String = "epoch-a",
        verifiedAt: Date) -> CostUsageDayEvidence
    {
        CostUsageDayEvidence(
            sourceKind: "codexLocalLedger",
            scopeID: scopeID,
            lineageID: lineageID,
            revision: revision,
            verifiedAt: verifiedAt)
    }

    private static func entry(
        _ dayKey: String,
        tokens: Int,
        cost: Double?,
        requests: Int? = 1,
        unpricedRequests: Int? = nil,
        evidence: CostUsageDayEvidence? = nil) -> CostUsageDailyReport.Entry
    {
        CostUsageDailyReport.Entry(
            date: dayKey,
            inputTokens: tokens,
            outputTokens: 0,
            totalTokens: tokens,
            requestCount: requests,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil,
            unpricedRequestCount: unpricedRequests,
            dayEvidence: evidence)
    }

    private static func codexSnapshot(
        entries: [CostUsageDailyReport.Entry],
        fixture: CodexVerifiedDaySnapshotFixture) -> CostUsageTokenSnapshot
    {
        let allTokensKnown = !entries.isEmpty && entries.allSatisfy { $0.totalTokens != nil }
        let allCostsKnown = !entries.isEmpty && entries.allSatisfy {
            $0.costUSD != nil && ($0.unpricedRequestCount ?? 0) == 0
        }
        let allRequestsKnown = !entries.isEmpty && entries.allSatisfy { $0.requestCount != nil }
        let current = entries.last { $0.date == fixture.until }
        return CostUsageTokenSnapshot(
            sessionTokens: current?.totalTokens,
            sessionCostUSD: current?.costUSD,
            sessionRequests: current?.requestCount,
            last30DaysTokens: allTokensKnown ? entries.compactMap(\.totalTokens).reduce(0, +) : nil,
            last30DaysCostUSD: allCostsKnown ? entries.compactMap(\.costUSD).reduce(0, +) : nil,
            last30DaysRequests: allRequestsKnown ? entries.compactMap(\.requestCount).reduce(0, +) : nil,
            historyDays: fixture.historyDays,
            historyCoverageIsEstablished: fixture.established,
            historySinceDayKey: fixture.since,
            historyUntilDayKey: fixture.until,
            credentialScopeFingerprint: fixture.credentialScopeFingerprint,
            daily: entries,
            projects: fixture.projects,
            sessions: fixture.sessions,
            hourly: fixture.hourly,
            quotaSlices: fixture.quotaSlices,
            updatedAt: fixture.updatedAt)
    }
}

private struct CodexVerifiedDaySnapshotFixture {
    var since: String
    var until: String
    var historyDays: Int
    var updatedAt: Date
    var established: Bool
    var credentialScopeFingerprint: String?
    var projects: [CostUsageProjectBreakdown] = []
    var sessions: [CostUsageSessionBreakdown] = []
    var hourly: [CostUsageHourlyEntry] = []
    var quotaSlices: [CostUsageTimedEntry] = []
}
