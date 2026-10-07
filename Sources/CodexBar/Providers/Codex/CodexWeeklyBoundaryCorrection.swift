import CodexBarCore
import Foundation

struct CodexWeeklyBoundaryCorrectionCandidate: Codable, Sendable {
    static let currentEvidenceVersion = 1

    let evidenceVersion: Int
    let originalBoundary: Date
    let firstObservedAt: Date
    let createdAt: Date
    let snapshot: UsageSnapshot

    init(
        originalBoundary: Date,
        firstObservedAt: Date,
        createdAt: Date,
        snapshot: UsageSnapshot)
    {
        self.evidenceVersion = Self.currentEvidenceVersion
        self.originalBoundary = originalBoundary
        self.firstObservedAt = firstObservedAt
        self.createdAt = createdAt
        self.snapshot = snapshot
    }

    private enum CodingKeys: String, CodingKey {
        case evidenceVersion
        case originalBoundary
        case firstObservedAt
        case createdAt
        case snapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.evidenceVersion = try container.decodeIfPresent(Int.self, forKey: .evidenceVersion) ?? 0
        self.originalBoundary = try container.decode(Date.self, forKey: .originalBoundary)
        self.firstObservedAt = try container.decode(Date.self, forKey: .firstObservedAt)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.snapshot = try container.decode(UsageSnapshot.self, forKey: .snapshot)
    }
}

struct CodexWeeklyBoundaryEvidence: Codable, Sendable {
    var correctionCandidate: CodexWeeklyBoundaryCorrectionCandidate?
    var retiredBoundaries: [Date]
    var holdReason: CodexWeeklyBoundaryCorrection.Reason?
    var pendingDetectorCorrection: UsageSnapshot?

    init(
        correctionCandidate: CodexWeeklyBoundaryCorrectionCandidate? = nil,
        retiredBoundaries: [Date] = [],
        holdReason: CodexWeeklyBoundaryCorrection.Reason? = nil,
        pendingDetectorCorrection: UsageSnapshot? = nil)
    {
        self.correctionCandidate = correctionCandidate
        self.retiredBoundaries = retiredBoundaries
        self.holdReason = holdReason
        self.pendingDetectorCorrection = pendingDetectorCorrection
    }

    private enum CodingKeys: String, CodingKey {
        case correctionCandidate
        case retiredBoundaries
        case holdReason
        case pendingDetectorCorrection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.correctionCandidate = try container.decodeIfPresent(
            CodexWeeklyBoundaryCorrectionCandidate.self,
            forKey: .correctionCandidate)
        self.retiredBoundaries = try container.decodeIfPresent([Date].self, forKey: .retiredBoundaries) ?? []
        self.holdReason = try container.decodeIfPresent(
            CodexWeeklyBoundaryCorrection.Reason.self,
            forKey: .holdReason)
        self.pendingDetectorCorrection = try container.decodeIfPresent(
            UsageSnapshot.self,
            forKey: .pendingDetectorCorrection)
    }
}

enum CodexWeeklyBoundaryCorrection {
    static let boundaryEquivalenceTolerance: TimeInterval = 2 * 60
    static let minimumConfirmationAge: TimeInterval = 60
    static let maximumCandidateAge: TimeInterval = 30 * 60

    enum Decision: Equatable, Sendable {
        case retainPrevious
        case publishCorrection
    }

    enum Reason: String, Codable, Equatable, Sendable {
        case missingPreviousSnapshot
        case sourceNotExactOAuth
        case confidenceNotExact
        case invalidObservationTime
        case futureObservation
        case nonMonotonicObservationTime
        case unknownAccount
        case accountMismatch
        case unknownPlan
        case planMismatch
        case missingWeeklyWindow
        case invalidWeeklyUsage
        case usageOutOfRange
        case usageDecreased
        case invalidResetBoundary
        case boundaryNotRegressed
        case retiredBoundary
        case candidateEvidenceVersionMismatch
        case candidateExpired
        case futureCandidate
        case candidateBaselineChanged
        case candidateBoundaryConflict
        case staleObservation
        case minimumDelay
        case candidateCreated
        case confirmedObservation
    }

    struct SourceEvidence: Equatable, Sendable {
        static let allExactOAuth = Self(previousIsExactOAuth: true, currentIsExactOAuth: true)

        let previousIsExactOAuth: Bool
        let currentIsExactOAuth: Bool
    }

    struct Evaluation: Sendable {
        let decision: Decision
        let evidence: CodexWeeklyBoundaryEvidence
        let reason: Reason
    }

    private struct EvaluationInput {
        let previous: UsageSnapshot?
        let current: UsageSnapshot
        let sourceEvidence: SourceEvidence
        let evidence: CodexWeeklyBoundaryEvidence
        let observedAt: Date
    }

    private struct ValidatedObservation {
        let previous: UsageSnapshot
        let current: UsageSnapshot
        let previousWeekly: RateWindow
        let currentWeekly: RateWindow
        let previousBoundary: Date
        let currentBoundary: Date
        let observedAt: Date
    }

    private struct ValidatedWeeklyWindows {
        let previous: RateWindow
        let current: RateWindow
        let previousBoundary: Date
        let currentBoundary: Date
    }

    private enum Validation {
        case valid(ValidatedObservation)
        case rejected(Reason)
    }

    private enum WeeklyValidation {
        case valid(ValidatedWeeklyWindows)
        case rejected(Reason)
    }

    private enum CandidateWeeklyValidation {
        case valid(RateWindow)
        case rejected(Reason)
    }

    private enum CandidateTiming {
        case valid(age: TimeInterval)
        case rejected(Reason)
    }

    static func evaluate(
        previous: UsageSnapshot?,
        current: UsageSnapshot,
        sourceEvidence: SourceEvidence,
        evidence: CodexWeeklyBoundaryEvidence,
        observedAt: Date) -> Evaluation
    {
        var normalizedEvidence = evidence
        if Self.isFinite(observedAt) {
            normalizedEvidence.retiredBoundaries = self.futureRetiredBoundaries(
                evidence.retiredBoundaries,
                observedAt: observedAt)
        }
        let input = EvaluationInput(
            previous: previous,
            current: current,
            sourceEvidence: sourceEvidence,
            evidence: normalizedEvidence,
            observedAt: observedAt)
        switch Self.validateBaseline(input) {
        case let .rejected(reason):
            return Self.retain(reason, evidence: normalizedEvidence)
        case let .valid(observation):
            return Self.evaluateValidated(input, observation: observation)
        }
    }

    private static func validateBaseline(_ input: EvaluationInput) -> Validation {
        guard let previous = input.previous else { return .rejected(.missingPreviousSnapshot) }
        if let reason = Self.provenanceFailure(input, previous: previous) {
            return .rejected(reason)
        }
        switch Self.validateWeeklyWindows(input, previous: previous) {
        case let .rejected(reason):
            return .rejected(reason)
        case let .valid(windows):
            return .valid(ValidatedObservation(
                previous: previous,
                current: input.current,
                previousWeekly: windows.previous,
                currentWeekly: windows.current,
                previousBoundary: windows.previousBoundary,
                currentBoundary: windows.currentBoundary,
                observedAt: input.observedAt))
        }
    }

    private static func provenanceFailure(_ input: EvaluationInput, previous: UsageSnapshot) -> Reason? {
        guard input.sourceEvidence.previousIsExactOAuth, input.sourceEvidence.currentIsExactOAuth else {
            return .sourceNotExactOAuth
        }
        guard previous.dataConfidence == .exact, input.current.dataConfidence == .exact else {
            return .confidenceNotExact
        }
        guard self.isFinite(previous.updatedAt),
              self.isFinite(input.current.updatedAt),
              self.isFinite(input.observedAt)
        else {
            return .invalidObservationTime
        }
        guard input.current.updatedAt > previous.updatedAt,
              input.observedAt > previous.updatedAt
        else {
            return .nonMonotonicObservationTime
        }
        // The caller samples this local clock after the provider fetch returns. A source snapshot
        // carrying a future local timestamp is malformed and cannot anchor persisted evidence.
        guard input.current.updatedAt <= input.observedAt else { return .futureObservation }

        let snapshots = [previous, input.current]
        guard Self.haveMatchingKnownAccounts(snapshots) else {
            return snapshots.allSatisfy(Self.hasKnownAccount) ? .accountMismatch : .unknownAccount
        }
        guard Self.haveMatchingKnownPlans(snapshots) else {
            return snapshots.allSatisfy(Self.hasKnownPlan) ? .planMismatch : .unknownPlan
        }
        return nil
    }

    private static func validateWeeklyWindows(
        _ input: EvaluationInput,
        previous: UsageSnapshot) -> WeeklyValidation
    {
        guard let previousWeekly = CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: previous),
              let currentWeekly = CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: input.current)
        else {
            return .rejected(.missingWeeklyWindow)
        }
        guard Self.isValidUsage(previousWeekly.usedPercent),
              Self.isValidUsage(currentWeekly.usedPercent)
        else {
            let reason: Reason = previousWeekly.usedPercent.isFinite && currentWeekly.usedPercent.isFinite
                ? .usageOutOfRange
                : .invalidWeeklyUsage
            return .rejected(reason)
        }
        guard let previousBoundary = previousWeekly.resetsAt,
              let currentBoundary = currentWeekly.resetsAt,
              Self.isFinite(previousBoundary),
              Self.isFinite(currentBoundary),
              previousBoundary > input.observedAt,
              currentBoundary > input.observedAt
        else {
            return .rejected(.invalidResetBoundary)
        }
        guard !Self.isRetiredBoundary(
            currentBoundary,
            evidence: input.evidence,
            observedAt: input.observedAt)
        else {
            return .rejected(.retiredBoundary)
        }
        return .valid(ValidatedWeeklyWindows(
            previous: previousWeekly,
            current: currentWeekly,
            previousBoundary: previousBoundary,
            currentBoundary: currentBoundary))
    }

    private static func evaluateValidated(
        _ input: EvaluationInput,
        observation: ValidatedObservation) -> Evaluation
    {
        let candidate = input.evidence.correctionCandidate
        if let candidate,
           let reason = Self.candidateBaselineFailure(candidate, boundary: observation.previousBoundary)
        {
            return Self.retain(reason, evidence: input.evidence)
        }
        guard Self.isMaterialRegression(observation.currentBoundary, from: observation.previousBoundary) else {
            return Self.retain(.boundaryNotRegressed, evidence: input.evidence)
        }
        if let candidate {
            return Self.evaluateCandidate(candidate, input: input, observation: observation)
        }
        guard observation.currentWeekly.usedPercent >= observation.previousWeekly.usedPercent else {
            return Self.retain(.usageDecreased, evidence: input.evidence)
        }
        let newCandidate = CodexWeeklyBoundaryCorrectionCandidate(
            originalBoundary: observation.previousBoundary,
            firstObservedAt: observation.current.updatedAt,
            createdAt: observation.observedAt,
            snapshot: observation.current)
        return Self.retain(.candidateCreated, evidence: input.evidence, candidate: newCandidate)
    }

    private static func candidateBaselineFailure(
        _ candidate: CodexWeeklyBoundaryCorrectionCandidate,
        boundary: Date) -> Reason?
    {
        guard candidate.evidenceVersion == CodexWeeklyBoundaryCorrectionCandidate.currentEvidenceVersion else {
            return .candidateEvidenceVersionMismatch
        }
        guard self.isFinite(candidate.originalBoundary) else { return .invalidObservationTime }
        guard self.equivalent(candidate.originalBoundary, boundary) else { return .candidateBaselineChanged }
        return nil
    }

    private static func evaluateCandidate(
        _ candidate: CodexWeeklyBoundaryCorrectionCandidate,
        input: EvaluationInput,
        observation: ValidatedObservation) -> Evaluation
    {
        let age: TimeInterval
        switch Self.candidateAge(candidate, observation: observation) {
        case let .rejected(reason):
            return Self.retain(reason, evidence: input.evidence)
        case let .valid(validAge):
            age = validAge
        }
        if let reason = Self.candidateIdentityFailure(candidate, observation: observation) {
            return Self.retain(reason, evidence: input.evidence)
        }
        let candidateWeekly: RateWindow
        switch Self.validateCandidateWeeklyWindow(candidate, observation: observation) {
        case let .rejected(reason):
            return Self.retain(reason, evidence: input.evidence)
        case let .valid(weekly):
            candidateWeekly = weekly
        }
        guard candidateWeekly.usedPercent >= observation.previousWeekly.usedPercent,
              observation.currentWeekly.usedPercent >= candidateWeekly.usedPercent
        else {
            return Self.retain(.usageDecreased, evidence: input.evidence)
        }
        guard observation.current.updatedAt > candidate.snapshot.updatedAt else {
            return Self.retain(.staleObservation, evidence: input.evidence, candidate: candidate)
        }
        let refreshedCandidate = CodexWeeklyBoundaryCorrectionCandidate(
            originalBoundary: candidate.originalBoundary,
            firstObservedAt: candidate.firstObservedAt,
            createdAt: candidate.createdAt,
            snapshot: observation.current)
        guard age >= Self.minimumConfirmationAge else {
            return Self.retain(.minimumDelay, evidence: input.evidence, candidate: refreshedCandidate)
        }
        var nextEvidence = input.evidence
        nextEvidence.correctionCandidate = nil
        nextEvidence.holdReason = nil
        return Evaluation(
            decision: .publishCorrection,
            evidence: nextEvidence,
            reason: .confirmedObservation)
    }

    private static func candidateAge(
        _ candidate: CodexWeeklyBoundaryCorrectionCandidate,
        observation: ValidatedObservation) -> CandidateTiming
    {
        guard self.isFinite(candidate.firstObservedAt),
              self.isFinite(candidate.createdAt),
              self.isFinite(candidate.snapshot.updatedAt)
        else {
            return .rejected(.invalidObservationTime)
        }
        guard candidate.snapshot.updatedAt > observation.previous.updatedAt,
              candidate.firstObservedAt > observation.previous.updatedAt,
              candidate.firstObservedAt <= candidate.snapshot.updatedAt,
              candidate.firstObservedAt <= candidate.createdAt,
              candidate.snapshot.updatedAt <= observation.observedAt
        else {
            return .rejected(.futureCandidate)
        }
        let age = observation.observedAt.timeIntervalSince(candidate.createdAt)
        guard age.isFinite else { return .rejected(.invalidObservationTime) }
        guard age >= 0 else { return .rejected(.futureCandidate) }
        guard age <= Self.maximumCandidateAge else { return .rejected(.candidateExpired) }
        return .valid(age: age)
    }

    private static func candidateIdentityFailure(
        _ candidate: CodexWeeklyBoundaryCorrectionCandidate,
        observation: ValidatedObservation) -> Reason?
    {
        guard candidate.snapshot.dataConfidence == .exact else { return .confidenceNotExact }
        let snapshots = [observation.previous, candidate.snapshot, observation.current]
        guard Self.haveMatchingKnownAccounts(snapshots) else {
            return snapshots.allSatisfy(Self.hasKnownAccount) ? .accountMismatch : .unknownAccount
        }
        guard Self.haveMatchingKnownPlans(snapshots) else {
            return snapshots.allSatisfy(Self.hasKnownPlan) ? .planMismatch : .unknownPlan
        }
        return nil
    }

    private static func validateCandidateWeeklyWindow(
        _ candidate: CodexWeeklyBoundaryCorrectionCandidate,
        observation: ValidatedObservation) -> CandidateWeeklyValidation
    {
        guard let weekly = CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: candidate.snapshot) else {
            return .rejected(.missingWeeklyWindow)
        }
        guard Self.isValidUsage(weekly.usedPercent) else {
            return .rejected(weekly.usedPercent.isFinite ? .usageOutOfRange : .invalidWeeklyUsage)
        }
        guard let boundary = weekly.resetsAt,
              Self.isFinite(boundary),
              boundary > observation.observedAt
        else {
            return .rejected(.invalidResetBoundary)
        }
        guard Self.equivalent(boundary, observation.currentBoundary) else {
            return .rejected(.candidateBoundaryConflict)
        }
        return .valid(weekly)
    }

    private static func retain(
        _ reason: Reason,
        evidence: CodexWeeklyBoundaryEvidence,
        candidate: CodexWeeklyBoundaryCorrectionCandidate? = nil) -> Evaluation
    {
        var nextEvidence = evidence
        nextEvidence.correctionCandidate = candidate
        nextEvidence.holdReason = reason
        return Evaluation(decision: .retainPrevious, evidence: nextEvidence, reason: reason)
    }

    static func isRetiredBoundary(
        _ boundary: Date,
        evidence: CodexWeeklyBoundaryEvidence,
        observedAt: Date) -> Bool
    {
        guard self.isFinite(boundary),
              self.isFinite(observedAt),
              boundary > observedAt
        else {
            return false
        }
        return evidence.retiredBoundaries.contains { retired in
            Self.isFinite(retired)
                && retired > observedAt
                && Self.equivalent(boundary, retired)
        }
    }

    static func retiring(
        previousBoundary: Date?,
        acceptedBoundary: Date?,
        evidence: CodexWeeklyBoundaryEvidence,
        observedAt: Date) -> CodexWeeklyBoundaryEvidence
    {
        var result = evidence
        guard Self.isFinite(observedAt) else {
            result.correctionCandidate = nil
            result.holdReason = nil
            return result
        }
        var retainedBoundaries = self.futureRetiredBoundaries(evidence.retiredBoundaries, observedAt: observedAt)
        if let previousBoundary,
           let acceptedBoundary,
           Self.isFinite(previousBoundary),
           Self.isFinite(acceptedBoundary),
           Self.isFinite(observedAt),
           previousBoundary > observedAt,
           Self.isMeaningfullyDifferent(previousBoundary, acceptedBoundary)
        {
            retainedBoundaries.append(previousBoundary)
        }
        result.retiredBoundaries = self.deduplicatedBoundaries(retainedBoundaries)
        result.correctionCandidate = nil
        result.holdReason = nil
        return result
    }

    private static func haveMatchingKnownAccounts(_ snapshots: [UsageSnapshot]) -> Bool {
        let emails = snapshots.compactMap { CodexIdentityResolver.normalizeEmail($0.accountEmail(for: .codex)) }
        guard emails.count == snapshots.count, let first = emails.first else { return false }
        return emails.allSatisfy { $0 == first }
    }

    private static func haveMatchingKnownPlans(_ snapshots: [UsageSnapshot]) -> Bool {
        let plans = snapshots.compactMap(CodexWeeklyResetConfirmation.normalizedPlan)
        guard plans.count == snapshots.count, let first = plans.first, !first.isEmpty else { return false }
        return plans.allSatisfy { $0 == first }
    }

    private static func hasKnownAccount(_ snapshot: UsageSnapshot) -> Bool {
        CodexIdentityResolver.normalizeEmail(snapshot.accountEmail(for: .codex)) != nil
    }

    private static func hasKnownPlan(_ snapshot: UsageSnapshot) -> Bool {
        guard let plan = CodexWeeklyResetConfirmation.normalizedPlan(snapshot) else { return false }
        return !plan.isEmpty
    }

    private static func isValidUsage(_ percent: Double) -> Bool {
        percent.isFinite && (0...100).contains(percent)
    }

    private static func isMaterialRegression(_ boundary: Date, from previous: Date) -> Bool {
        guard let difference = self.finiteDifference(boundary, previous) else { return false }
        return difference < -Self.boundaryEquivalenceTolerance
    }

    private static func isMeaningfullyDifferent(_ lhs: Date, _ rhs: Date) -> Bool {
        guard let difference = self.finiteDifference(lhs, rhs) else { return false }
        return abs(difference) >= Self.boundaryEquivalenceTolerance
    }

    private static func equivalent(_ lhs: Date, _ rhs: Date) -> Bool {
        guard let difference = self.finiteDifference(lhs, rhs) else { return false }
        return abs(difference) < Self.boundaryEquivalenceTolerance
    }

    private static func futureRetiredBoundaries(_ boundaries: [Date], observedAt: Date) -> [Date] {
        guard self.isFinite(observedAt) else { return [] }
        return self.deduplicatedBoundaries(boundaries.filter {
            Self.isFinite($0) && $0 > observedAt
        })
    }

    private static func deduplicatedBoundaries(_ boundaries: [Date]) -> [Date] {
        let sorted = boundaries.filter(Self.isFinite).sorted()
        var result: [Date] = []
        for boundary in sorted where !result.contains(where: { Self.equivalent($0, boundary) }) {
            result.append(boundary)
        }
        return result
    }

    private static func finiteDifference(_ lhs: Date, _ rhs: Date) -> TimeInterval? {
        let difference = lhs.timeIntervalSince(rhs)
        return difference.isFinite ? difference : nil
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }
}
