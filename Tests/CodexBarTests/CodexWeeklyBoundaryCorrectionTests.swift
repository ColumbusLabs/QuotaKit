import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CodexWeeklyBoundaryCorrectionTests {
    private let observation = Self.date("2026-10-07T11:58:26Z")
    private let oldBoundary = Self.date("2026-10-14T11:06:24Z")
    private let correctedBoundary = Self.date("2026-10-14T03:38:58Z")

    @Test
    func `incident correction publishes after a stable exact OAuth observation`() {
        let previous = self.snapshot(
            usage: 1,
            boundary: self.oldBoundary,
            updatedAt: self.observation)
        let firstObservation = self.observation.addingTimeInterval(1)
        let current = self.snapshot(
            usage: 11,
            boundary: self.correctedBoundary,
            updatedAt: firstObservation)
        let first = Self.evaluate(
            previous: previous,
            current: current,
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: firstObservation)

        #expect(first.decision == .retainPrevious)
        #expect(first.reason == .candidateCreated)
        #expect(first.evidence.correctionCandidate?.originalBoundary == self.oldBoundary)
        #expect(first.evidence.correctionCandidate?.snapshot.updatedAt == firstObservation)

        let confirmationTime = self.observation.addingTimeInterval(61)
        let confirmation = self.snapshot(
            usage: 11.2,
            boundary: self.correctedBoundary,
            updatedAt: confirmationTime)
        let confirmed = Self.evaluate(
            previous: previous,
            current: confirmation,
            evidence: first.evidence,
            observedAt: confirmationTime)

        #expect(confirmed.decision == .publishCorrection)
        #expect(confirmed.reason == .confirmedObservation)
        #expect(confirmed.evidence.correctionCandidate == nil)
        #expect(confirmed.evidence.holdReason == nil)
    }

    @Test
    func `candidate age stays anchored while newer observations replace its snapshot`() throws {
        let previous = self.snapshot(
            usage: 1,
            boundary: self.oldBoundary,
            updatedAt: self.observation)
        let firstTime = self.observation.addingTimeInterval(1)
        let first = Self.evaluate(
            previous: previous,
            current: self.snapshot(usage: 11, boundary: self.correctedBoundary, updatedAt: firstTime),
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: firstTime)
        let candidateCreatedAt = try #require(first.evidence.correctionCandidate?.createdAt)

        let stale = Self.evaluate(
            previous: previous,
            current: self.snapshot(usage: 11, boundary: self.correctedBoundary, updatedAt: firstTime),
            evidence: first.evidence,
            observedAt: self.observation.addingTimeInterval(10))
        #expect(stale.reason == .staleObservation)
        #expect(stale.evidence.correctionCandidate?.snapshot.updatedAt == firstTime)

        let beforeMinimum = self.observation.addingTimeInterval(30)
        let waiting = Self.evaluate(
            previous: previous,
            current: self.snapshot(usage: 11.1, boundary: self.correctedBoundary, updatedAt: beforeMinimum),
            evidence: first.evidence,
            observedAt: beforeMinimum)
        let refreshedCandidate = try #require(waiting.evidence.correctionCandidate)

        #expect(waiting.decision == .retainPrevious)
        #expect(waiting.reason == .minimumDelay)
        #expect(refreshedCandidate.snapshot.updatedAt == beforeMinimum)
        #expect(refreshedCandidate.createdAt == candidateCreatedAt)
        #expect(refreshedCandidate.firstObservedAt == firstTime)

        let atMinimum = self.observation.addingTimeInterval(61)
        let confirmed = Self.evaluate(
            previous: previous,
            current: self.snapshot(usage: 11.2, boundary: self.correctedBoundary, updatedAt: atMinimum),
            evidence: waiting.evidence,
            observedAt: atMinimum)

        #expect(confirmed.decision == .publishCorrection)
    }

    @Test
    func `candidate expires after thirty minutes`() {
        let previous = self.snapshot(
            usage: 1,
            boundary: self.oldBoundary,
            updatedAt: self.observation)
        let firstTime = self.observation.addingTimeInterval(1)
        let first = Self.evaluate(
            previous: previous,
            current: self.snapshot(usage: 11, boundary: self.correctedBoundary, updatedAt: firstTime),
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: firstTime)
        let expiredAt = firstTime.addingTimeInterval(30 * 60 + 1)
        let expired = Self.evaluate(
            previous: previous,
            current: self.snapshot(usage: 12, boundary: self.correctedBoundary, updatedAt: expiredAt),
            evidence: first.evidence,
            observedAt: expiredAt)

        #expect(expired.decision == .retainPrevious)
        #expect(expired.reason == .candidateExpired)
        #expect(expired.evidence.correctionCandidate == nil)
    }

    @Test
    func `source confidence account and plan evidence must be exact and known`() {
        let previous = self.snapshot(
            usage: 1,
            boundary: self.oldBoundary,
            updatedAt: self.observation)
        let currentTime = self.observation.addingTimeInterval(1)
        let matchingCurrent = self.snapshot(
            usage: 11,
            boundary: self.correctedBoundary,
            updatedAt: currentTime)

        #expect(Self.evaluate(
            previous: previous,
            current: matchingCurrent,
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: currentTime,
            sourceEvidence: .init(previousIsExactOAuth: true, currentIsExactOAuth: false)).reason
            == .sourceNotExactOAuth)
        #expect(Self.evaluate(
            previous: previous.withDataConfidence(.estimated),
            current: matchingCurrent,
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: currentTime).reason == .confidenceNotExact)
        #expect(Self.evaluate(
            previous: previous,
            current: self.snapshot(
                usage: 11,
                boundary: self.correctedBoundary,
                updatedAt: currentTime,
                email: nil),
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: currentTime).reason == .unknownAccount)
        #expect(Self.evaluate(
            previous: previous,
            current: self.snapshot(
                usage: 11,
                boundary: self.correctedBoundary,
                updatedAt: currentTime,
                email: "other@example.com"),
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: currentTime).reason == .accountMismatch)
        #expect(Self.evaluate(
            previous: previous,
            current: self.snapshot(
                usage: 11,
                boundary: self.correctedBoundary,
                updatedAt: currentTime,
                plan: nil),
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: currentTime).reason == .unknownPlan)
        #expect(Self.evaluate(
            previous: previous,
            current: self.snapshot(
                usage: 11,
                boundary: self.correctedBoundary,
                updatedAt: currentTime,
                plan: "Plus"),
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: currentTime).reason == .planMismatch)

        let equivalentPlan = self.snapshot(
            usage: 11,
            boundary: self.correctedBoundary,
            updatedAt: currentTime,
            plan: "pro-lite")
        let proLitePrevious = self.snapshot(
            usage: 1,
            boundary: self.oldBoundary,
            updatedAt: self.observation,
            plan: "Pro Lite")
        #expect(Self.evaluate(
            previous: proLitePrevious,
            current: equivalentPlan,
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: currentTime).reason == .candidateCreated)
    }

    @Test
    func `invalid timestamps boundaries and weekly usage fail closed`() {
        let previous = self.snapshot(
            usage: 1,
            boundary: self.oldBoundary,
            updatedAt: self.observation)
        let currentTime = self.observation.addingTimeInterval(1)
        let emptyEvidence = CodexWeeklyBoundaryEvidence()

        #expect(Self.evaluate(
            previous: previous,
            current: self.snapshot(
                usage: 11,
                boundary: self.correctedBoundary,
                updatedAt: Date(timeIntervalSinceReferenceDate: .infinity)),
            evidence: emptyEvidence,
            observedAt: currentTime).reason == .invalidObservationTime)
        #expect(Self.evaluate(
            previous: previous,
            current: self.snapshot(
                usage: 11,
                boundary: self.correctedBoundary,
                updatedAt: currentTime),
            evidence: emptyEvidence,
            observedAt: Date(timeIntervalSinceReferenceDate: .infinity)).reason == .invalidObservationTime)
        #expect(Self.evaluate(
            previous: previous,
            current: self.snapshot(usage: 11, boundary: currentTime, updatedAt: currentTime),
            evidence: emptyEvidence,
            observedAt: currentTime).reason == .invalidResetBoundary)
        #expect(Self.evaluate(
            previous: previous,
            current: self.snapshot(
                usage: 11,
                boundary: Date(timeIntervalSinceReferenceDate: .infinity),
                updatedAt: currentTime),
            evidence: emptyEvidence,
            observedAt: currentTime).reason == .invalidResetBoundary)
        #expect(Self.evaluate(
            previous: previous,
            current: self.snapshot(usage: .nan, boundary: self.correctedBoundary, updatedAt: currentTime),
            evidence: emptyEvidence,
            observedAt: currentTime).reason == .invalidWeeklyUsage)
        #expect(Self.evaluate(
            previous: previous,
            current: self.snapshot(usage: 101, boundary: self.correctedBoundary, updatedAt: currentTime),
            evidence: emptyEvidence,
            observedAt: currentTime).reason == .usageOutOfRange)
        #expect(Self.evaluate(
            previous: previous,
            current: self.snapshot(
                usage: 11,
                boundary: self.correctedBoundary,
                updatedAt: self.observation),
            evidence: emptyEvidence,
            observedAt: currentTime).reason == .nonMonotonicObservationTime)
        #expect(Self.evaluate(
            previous: previous,
            current: self.snapshot(
                usage: 11,
                boundary: self.correctedBoundary,
                updatedAt: currentTime.addingTimeInterval(1)),
            evidence: emptyEvidence,
            observedAt: currentTime).reason == .futureObservation)

        let firstCandidate = Self.evaluate(
            previous: previous,
            current: self.snapshot(usage: 11, boundary: self.correctedBoundary, updatedAt: currentTime),
            evidence: emptyEvidence,
            observedAt: currentTime)
        let malformedCandidate = CodexWeeklyBoundaryCorrectionCandidate(
            originalBoundary: self.oldBoundary,
            firstObservedAt: currentTime.addingTimeInterval(2),
            createdAt: currentTime.addingTimeInterval(1),
            snapshot: self.snapshot(usage: 11, boundary: self.correctedBoundary, updatedAt: currentTime))
        let malformed = Self.evaluate(
            previous: previous,
            current: self.snapshot(
                usage: 12,
                boundary: self.correctedBoundary,
                updatedAt: currentTime.addingTimeInterval(10)),
            evidence: CodexWeeklyBoundaryEvidence(correctionCandidate: malformedCandidate),
            observedAt: currentTime.addingTimeInterval(10))

        #expect(firstCandidate.reason == .candidateCreated)
        #expect(malformed.reason == .futureCandidate)
        #expect(malformed.evidence.correctionCandidate == nil)
    }

    @Test
    func `usage cannot fall when creating or confirming a correction`() {
        let previous = self.snapshot(
            usage: 11,
            boundary: self.oldBoundary,
            updatedAt: self.observation)
        let firstTime = self.observation.addingTimeInterval(1)
        let lowerInitial = Self.evaluate(
            previous: previous,
            current: self.snapshot(usage: 10, boundary: self.correctedBoundary, updatedAt: firstTime),
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: firstTime)

        #expect(lowerInitial.reason == .usageDecreased)
        #expect(lowerInitial.evidence.correctionCandidate == nil)

        let baseline = self.snapshot(
            usage: 1,
            boundary: self.oldBoundary,
            updatedAt: self.observation)
        let first = Self.evaluate(
            previous: baseline,
            current: self.snapshot(usage: 11, boundary: self.correctedBoundary, updatedAt: firstTime),
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: firstTime)
        let lowerConfirmationTime = self.observation.addingTimeInterval(61)
        let lowerConfirmation = Self.evaluate(
            previous: baseline,
            current: self.snapshot(usage: 10, boundary: self.correctedBoundary, updatedAt: lowerConfirmationTime),
            evidence: first.evidence,
            observedAt: lowerConfirmationTime)

        #expect(lowerConfirmation.reason == .usageDecreased)
        #expect(lowerConfirmation.evidence.correctionCandidate == nil)
    }

    @Test
    func `small boundary movement does not create a correction candidate`() {
        let previous = self.snapshot(
            usage: 1,
            boundary: self.oldBoundary,
            updatedAt: self.observation)
        let currentTime = self.observation.addingTimeInterval(1)
        let result = Self.evaluate(
            previous: previous,
            current: self.snapshot(
                usage: 11,
                boundary: self.oldBoundary.addingTimeInterval(-119),
                updatedAt: currentTime),
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: currentTime)

        #expect(result.decision == .retainPrevious)
        #expect(result.reason == .boundaryNotRegressed)
        #expect(result.evidence.correctionCandidate == nil)
    }

    @Test
    func `candidate is cleared when its baseline or correction boundary changes`() {
        let previous = self.snapshot(
            usage: 1,
            boundary: self.oldBoundary,
            updatedAt: self.observation)
        let firstTime = self.observation.addingTimeInterval(1)
        let first = Self.evaluate(
            previous: previous,
            current: self.snapshot(usage: 11, boundary: self.correctedBoundary, updatedAt: firstTime),
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: firstTime)

        let changedBaseline = self.snapshot(
            usage: 1,
            boundary: self.oldBoundary.addingTimeInterval(180),
            updatedAt: firstTime.addingTimeInterval(1))
        let laterTime = firstTime.addingTimeInterval(2)
        let baselineChangedResult = Self.evaluate(
            previous: changedBaseline,
            current: self.snapshot(usage: 12, boundary: self.correctedBoundary, updatedAt: laterTime),
            evidence: first.evidence,
            observedAt: laterTime)

        #expect(baselineChangedResult.reason == .candidateBaselineChanged)
        #expect(baselineChangedResult.evidence.correctionCandidate == nil)

        let changedCorrection = Self.evaluate(
            previous: previous,
            current: self.snapshot(
                usage: 12,
                boundary: self.correctedBoundary.addingTimeInterval(-4 * 60),
                updatedAt: laterTime),
            evidence: first.evidence,
            observedAt: laterTime)

        #expect(changedCorrection.reason == .candidateBoundaryConflict)
        #expect(changedCorrection.evidence.correctionCandidate == nil)
    }

    @Test
    func `retiring boundaries preserves entries before and after the accepted boundary`() {
        let middleBoundary = self.correctedBoundary
        let forwardBoundary = Self.date("2026-10-14T09:00:00Z")
        let afterFirstCorrection = CodexWeeklyBoundaryCorrection.retiring(
            previousBoundary: self.oldBoundary,
            acceptedBoundary: middleBoundary,
            evidence: CodexWeeklyBoundaryEvidence(),
            observedAt: self.observation)
        let afterAnotherCorrection = CodexWeeklyBoundaryCorrection.retiring(
            previousBoundary: middleBoundary,
            acceptedBoundary: forwardBoundary,
            evidence: afterFirstCorrection,
            observedAt: self.observation)

        #expect(afterAnotherCorrection.retiredBoundaries.count == 2)
        #expect(CodexWeeklyBoundaryCorrection.isRetiredBoundary(
            self.oldBoundary,
            evidence: afterAnotherCorrection,
            observedAt: self.observation))
        #expect(CodexWeeklyBoundaryCorrection.isRetiredBoundary(
            middleBoundary,
            evidence: afterAnotherCorrection,
            observedAt: self.observation))

        let stale = Self.evaluate(
            previous: self.snapshot(
                usage: 11,
                boundary: forwardBoundary,
                updatedAt: self.observation),
            current: self.snapshot(
                usage: 50,
                boundary: self.oldBoundary,
                updatedAt: self.observation.addingTimeInterval(1)),
            evidence: afterAnotherCorrection,
            observedAt: self.observation.addingTimeInterval(1))
        #expect(stale.reason == .retiredBoundary)
    }

    @Test
    func `expired retired boundaries are ignored and removed during retirement`() {
        let expiredBoundary = self.observation.addingTimeInterval(-1)
        let evidence = CodexWeeklyBoundaryEvidence(retiredBoundaries: [expiredBoundary, self.oldBoundary])
        let now = self.observation.addingTimeInterval(1)

        #expect(!CodexWeeklyBoundaryCorrection.isRetiredBoundary(
            expiredBoundary,
            evidence: evidence,
            observedAt: now))
        let pruned = CodexWeeklyBoundaryCorrection.retiring(
            previousBoundary: nil,
            acceptedBoundary: nil,
            evidence: evidence,
            observedAt: now)
        #expect(pruned.retiredBoundaries == [self.oldBoundary])
    }

    @Test
    func `evidence decodes with defaults when optional fields are absent`() throws {
        let encoded = Data("{\"retiredBoundaries\":[]}".utf8)
        let evidence = try JSONDecoder().decode(CodexWeeklyBoundaryEvidence.self, from: encoded)

        #expect(evidence.correctionCandidate == nil)
        #expect(evidence.retiredBoundaries.isEmpty)
        #expect(evidence.holdReason == nil)
    }

    private func snapshot(
        usage: Double,
        boundary: Date,
        updatedAt: Date,
        email: String? = "user@example.com",
        plan: String? = "Pro") -> UsageSnapshot
    {
        let raw = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: updatedAt.addingTimeInterval(5 * 60 * 60),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: usage,
                windowMinutes: 7 * 24 * 60,
                resetsAt: boundary,
                resetDescription: nil),
            updatedAt: updatedAt)
        return raw.withIdentity(ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: email,
            accountOrganization: nil,
            loginMethod: plan)).withDataConfidence(.exact)
    }

    private static func evaluate(
        previous: UsageSnapshot?,
        current: UsageSnapshot,
        evidence: CodexWeeklyBoundaryEvidence,
        observedAt: Date,
        sourceEvidence: CodexWeeklyBoundaryCorrection.SourceEvidence = .allExactOAuth)
        -> CodexWeeklyBoundaryCorrection.Evaluation
    {
        CodexWeeklyBoundaryCorrection.evaluate(
            previous: previous,
            current: current,
            sourceEvidence: sourceEvidence,
            evidence: evidence,
            observedAt: observedAt)
    }

    private static func date(_ string: String) -> Date {
        guard let date = ISO8601DateFormatter().date(from: string) else {
            preconditionFailure("Invalid fixed ISO 8601 test date: \(string)")
        }
        return date
    }
}
