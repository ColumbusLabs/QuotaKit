import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
extension CodexAccountScopedRefreshTests {
    @Test
    func `exact oauth boundary correction holds then publishes across relaunch`() async throws {
        let suite = "CodexWeeklyBoundaryPublicationTests-incident-correction"
        let email = "weekly-boundary-correction@example.com"
        let settings = self.makeSettingsStore(suite: suite)
        settings.refreshFrequency = .manual
        settings.codexCookieSource = .off
        settings._test_liveSystemCodexAccount = self.liveAccount(
            email: email,
            identity: .providerAccount(id: "acct-weekly-boundary-correction"))
        defer { settings._test_liveSystemCodexAccount = nil }

        let baselineAt = weeklyBoundaryTestDate("2026-10-07T11:58:26Z")
        let baselineBoundary = weeklyBoundaryTestDate("2026-10-14T11:06:24Z")
        let correctedBoundary = weeklyBoundaryTestDate("2026-10-14T03:38:58Z")
        let baseline = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 1,
            weeklyReset: baselineBoundary,
            updatedAt: baselineAt,
            dataConfidence: .exact)
        let initialCorrection = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 11,
            weeklyReset: correctedBoundary,
            updatedAt: baselineAt.addingTimeInterval(60),
            dataConfidence: .exact)
        let confirmedCorrection = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 11.2,
            weeklyReset: correctedBoundary,
            updatedAt: initialCorrection.updatedAt.addingTimeInterval(61),
            dataConfidence: .exact)
        let ordinaryReading = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 12,
            weeklyReset: correctedBoundary,
            updatedAt: confirmedCorrection.updatedAt.addingTimeInterval(61),
            dataConfidence: .exact)
        let replayOne = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 13,
            weeklyReset: baselineBoundary,
            updatedAt: ordinaryReading.updatedAt.addingTimeInterval(61),
            dataConfidence: .exact)
        let replayTwo = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 14,
            weeklyReset: baselineBoundary,
            updatedAt: replayOne.updatedAt.addingTimeInterval(61),
            dataConfidence: .exact)
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-weekly-boundary-correction-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }
        let snapshotStore = BoundaryConsistencyCodexAccountUsageSnapshotStore(
            base: FileCodexAccountUsageSnapshotStore(fileURL: snapshotURL))
        let account = try #require(settings.codexVisibleAccountProjection.visibleAccounts.first)
        let baselineRow = CodexAccountUsageSnapshot(
            account: account,
            snapshot: baseline,
            error: nil,
            sourceLabel: "oauth",
            credits: self.credits(remaining: 17))
        snapshotStore.store([baselineRow])

        let firstStore = self.makeCodexWeeklyPublicationStore(
            settings: settings,
            suite: suite,
            snapshotStore: snapshotStore)
        firstStore.codexAccountSnapshots = [baselineRow]
        let baselineHistoryRevision = await self.seedCodexWeeklyPublicationState(
            store: firstStore,
            settings: settings,
            snapshot: baseline,
            error: nil)
        firstStore.lastSourceLabels[.codex] = "oauth"
        self.installContextualCodexProvider(on: firstStore, sourceLabel: "oauth", kind: .oauth) { _ in
            initialCorrection
        }
        let recorder = WeeklyBoundaryPublicationEventRecorder(email: email)
        defer { recorder.invalidate() }

        await CodexWeeklyResetConfirmation.$observationDateOverride.withValue(initialCorrection.updatedAt) {
            await firstStore.refreshProvider(.codex, allowDisabled: true)
        }

        #expect(firstStore.snapshots[.codex]?.updatedAt == baseline.updatedAt)
        #expect(firstStore.snapshots[.codex]?.secondary?.usedPercent == 1)
        #expect(firstStore.planUtilizationHistoryRevision == baselineHistoryRevision)
        #expect(recorder.isEmpty)
        #expect(firstStore.codexQuotaPublicationHoldMessage?.contains("last accepted reading") == true)
        #expect(firstStore.menuCardInput(for: .codex, context: .menu).lastError
            == firstStore.codexQuotaPublicationHoldMessage)
        let persistedCandidate = try #require(snapshotStore.load(
            for: settings.codexVisibleAccountProjection.visibleAccounts).first)
        #expect(persistedCandidate.snapshot?.updatedAt == baseline.updatedAt)
        #expect(persistedCandidate.credits?.remaining == 17)
        #expect(persistedCandidate.weeklyBoundaryEvidence?.correctionCandidate?.snapshot.updatedAt
            == initialCorrection.updatedAt)
        #expect(persistedCandidate.weeklyBoundaryEvidence?.holdReason == .candidateCreated)

        let relaunchedStore = self.makeCodexWeeklyPublicationStore(
            settings: settings,
            suite: suite,
            snapshotStore: snapshotStore)
        #expect(relaunchedStore.snapshots[.codex] == nil)
        #expect(relaunchedStore.codexAccountSnapshots.first?.weeklyBoundaryEvidence?.correctionCandidate != nil)
        self.installContextualCodexProvider(on: relaunchedStore, sourceLabel: "oauth", kind: .oauth) { _ in
            confirmedCorrection
        }

        await CodexWeeklyResetConfirmation.$observationDateOverride.withValue(confirmedCorrection.updatedAt) {
            await relaunchedStore.refreshProvider(.codex, allowDisabled: true)
        }

        #expect(relaunchedStore.snapshots[.codex]?.updatedAt == confirmedCorrection.updatedAt)
        #expect(relaunchedStore.snapshots[.codex]?.secondary?.usedPercent == 11.2)
        let persistedCorrection = try #require(snapshotStore.load(
            for: settings.codexVisibleAccountProjection.visibleAccounts).first)
        let correctionEvidence = try #require(persistedCorrection.weeklyBoundaryEvidence)
        #expect(persistedCorrection.snapshot?.secondary?.resetsAt == correctedBoundary)
        #expect(persistedCorrection.credits?.remaining == 17)
        #expect(correctionEvidence.correctionCandidate == nil)
        #expect(correctionEvidence.retiredBoundaries.contains { abs($0.timeIntervalSince(baselineBoundary)) < 120 })
        #expect(!correctionEvidence.retiredBoundaries.contains {
            abs($0.timeIntervalSince(correctedBoundary)) < 120
        })

        self.installContextualCodexProvider(on: relaunchedStore, sourceLabel: "oauth", kind: .oauth) { _ in
            ordinaryReading
        }
        await CodexWeeklyResetConfirmation.$observationDateOverride.withValue(ordinaryReading.updatedAt) {
            await relaunchedStore.refreshProvider(.codex, allowDisabled: true)
        }
        #expect(relaunchedStore.snapshots[.codex]?.updatedAt == ordinaryReading.updatedAt)
        #expect(relaunchedStore.snapshots[.codex]?.secondary?.usedPercent == 12)
        let historyRevisionAfterOrdinaryReading = relaunchedStore.planUtilizationHistoryRevision

        for replay in [replayOne, replayTwo] {
            self.installContextualCodexProvider(on: relaunchedStore, sourceLabel: "oauth", kind: .oauth) { _ in
                replay
            }
            await CodexWeeklyResetConfirmation.$observationDateOverride.withValue(replay.updatedAt) {
                await relaunchedStore.refreshProvider(.codex, allowDisabled: true)
            }
            #expect(relaunchedStore.snapshots[.codex]?.updatedAt == ordinaryReading.updatedAt)
            #expect(relaunchedStore.snapshots[.codex]?.secondary?.usedPercent == 12)
            #expect(relaunchedStore.codexQuotaPublicationHoldMessage?.contains("older quota cycle") == true)
            #expect(relaunchedStore.menuCardInput(for: .codex, context: .menu).lastError
                == relaunchedStore.codexQuotaPublicationHoldMessage)
            #expect(relaunchedStore.planUtilizationHistoryRevision == historyRevisionAfterOrdinaryReading)
        }

        let persistedReplayState = try #require(snapshotStore.load(
            for: settings.codexVisibleAccountProjection.visibleAccounts).first)
        #expect(persistedReplayState.snapshot?.updatedAt == ordinaryReading.updatedAt)
        #expect(persistedReplayState.weeklyBoundaryEvidence?.holdReason == .retiredBoundary)
        #expect(recorder.isEmpty)
        #expect(snapshotStore.invalidCommitCount == 0)
    }

    @Test
    func `confirmed ordinary reset retires old earlier boundary and blocks replay`() async throws {
        let suite = "CodexWeeklyBoundaryPublicationTests-ordinary-reset-retirement"
        let email = "ordinary-reset-retirement@example.com"
        let settings = self.makeSettingsStore(suite: suite)
        settings.refreshFrequency = .manual
        settings.codexCookieSource = .off
        settings._test_liveSystemCodexAccount = self.liveAccount(
            email: email,
            identity: .providerAccount(id: "acct-ordinary-reset-retirement"))
        defer { settings._test_liveSystemCodexAccount = nil }

        let baselineAt = weeklyBoundaryTestDate("2026-10-07T10:00:00Z")
        let oldBoundary = weeklyBoundaryTestDate("2026-10-09T10:00:00Z")
        let newBoundary = oldBoundary.addingTimeInterval(7 * 24 * 60 * 60)
        let baseline = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 80,
            weeklyReset: oldBoundary,
            updatedAt: baselineAt,
            dataConfidence: .exact)
        let initialLow = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 0.2,
            weeklyReset: newBoundary,
            updatedAt: baselineAt.addingTimeInterval(60),
            dataConfidence: .exact)
        let confirmedLow = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 0.3,
            weeklyReset: newBoundary,
            updatedAt: baselineAt.addingTimeInterval(61),
            dataConfidence: .exact)
        let replayOne = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 81,
            weeklyReset: oldBoundary,
            updatedAt: baselineAt.addingTimeInterval(122),
            dataConfidence: .exact)
        let replayTwo = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 82,
            weeklyReset: oldBoundary,
            updatedAt: baselineAt.addingTimeInterval(183),
            dataConfidence: .exact)
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-weekly-reset-retirement-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }
        let snapshotStore = FileCodexAccountUsageSnapshotStore(fileURL: snapshotURL)
        let account = try #require(settings.codexVisibleAccountProjection.visibleAccounts.first)
        let baselineRow = CodexAccountUsageSnapshot(
            account: account,
            snapshot: baseline,
            error: nil,
            sourceLabel: "oauth")
        snapshotStore.store([baselineRow])

        let store = self.makeCodexWeeklyPublicationStore(
            settings: settings,
            suite: suite,
            snapshotStore: snapshotStore)
        store.codexAccountSnapshots = [baselineRow]
        _ = await self.seedCodexWeeklyPublicationState(
            store: store,
            settings: settings,
            snapshot: baseline,
            error: nil)
        store.lastSourceLabels[.codex] = "oauth"
        let loader = SequencedCodexSnapshotLoader(steps: [.success(initialLow), .success(confirmedLow)])
        self.installContextualCodexProvider(on: store, sourceLabel: "oauth", kind: .oauth) { _ in
            try await loader.load()
        }

        await CodexWeeklyResetConfirmation.$observationDateOverride.withValue(baselineAt.addingTimeInterval(120)) {
            await store.refreshProvider(.codex, allowDisabled: true)
        }

        #expect(await loader.callCount == 2)
        #expect(store.snapshots[.codex]?.updatedAt == confirmedLow.updatedAt)
        let persistedReset = try #require(snapshotStore.load(
            for: settings.codexVisibleAccountProjection.visibleAccounts).first)
        let resetEvidence = try #require(persistedReset.weeklyBoundaryEvidence)
        #expect(persistedReset.snapshot?.secondary?.resetsAt == newBoundary)
        #expect(resetEvidence.retiredBoundaries.contains { abs($0.timeIntervalSince(oldBoundary)) < 120 })
        #expect(!resetEvidence.retiredBoundaries.contains { abs($0.timeIntervalSince(newBoundary)) < 120 })
        let acceptedHistoryRevision = store.planUtilizationHistoryRevision

        for replay in [replayOne, replayTwo] {
            self.installContextualCodexProvider(on: store, sourceLabel: "oauth", kind: .oauth) { _ in replay }
            await CodexWeeklyResetConfirmation.$observationDateOverride.withValue(replay.updatedAt) {
                await store.refreshProvider(.codex, allowDisabled: true)
            }
            #expect(store.snapshots[.codex]?.updatedAt == confirmedLow.updatedAt)
            #expect(store.snapshots[.codex]?.secondary?.usedPercent == 0.3)
            #expect(store.codexQuotaPublicationHoldMessage?.contains("older quota cycle") == true)
            #expect(store.planUtilizationHistoryRevision == acceptedHistoryRevision)
        }

        let persistedReplayState = try #require(snapshotStore.load(
            for: settings.codexVisibleAccountProjection.visibleAccounts).first)
        #expect(persistedReplayState.snapshot?.updatedAt == confirmedLow.updatedAt)
        #expect(persistedReplayState.weeklyBoundaryEvidence?.holdReason == .retiredBoundary)
    }

    @Test
    func `exactly two minute boundary drift stays on ordinary publication path`() async {
        let observedAt = weeklyBoundaryTestDate("2026-10-07T12:10:00Z")
        let previousBoundary = weeklyBoundaryTestDate("2026-10-14T12:00:00Z")
        let currentBoundary = previousBoundary.addingTimeInterval(
            -CodexWeeklyBoundaryCorrection.boundaryEquivalenceTolerance)
        let previous = self.codexWeeklySnapshot(
            email: "two-minute-drift@example.com",
            weeklyUsedPercent: 1,
            weeklyReset: previousBoundary,
            updatedAt: observedAt,
            dataConfidence: .exact)
        let current = self.codexWeeklySnapshot(
            email: "two-minute-drift@example.com",
            weeklyUsedPercent: 11,
            weeklyReset: currentBoundary,
            updatedAt: observedAt.addingTimeInterval(1),
            dataConfidence: .exact)
        let outcome = weeklyBoundaryFetchOutcome(current)

        let admission = await UsageStore.codexOutcomeAdmittedForPublication(
            initialOutcome: outcome,
            previousSnapshot: previous,
            previousSourceLabel: "oauth",
            missingWindowBackfillSnapshot: nil,
            weeklyBoundaryEvidence: CodexWeeklyBoundaryEvidence(),
            observedAt: current.updatedAt,
            fetchConfirmation: { outcome })

        #expect(admission.outcome != nil)
        #expect(!admission.correctsWeeklyBoundary)
        #expect(admission.weeklyBoundaryEvidence?.correctionCandidate == nil)
        #expect(admission.weeklyBoundaryEvidence?.holdReason == nil)
    }

    @Test
    func `inactive corrected boundary detector marker survives relaunch and is consumed`() throws {
        let suite = "CodexWeeklyBoundaryPublicationTests-inactive-detector-marker"
        let activeEmail = "active-boundary-owner@example.com"
        let inactiveEmail = "inactive-boundary-owner@example.com"
        let settings = self.makeSettingsStore(suite: suite)
        settings.refreshFrequency = .manual
        settings.codexCookieSource = .off
        settings.multiAccountMenuLayout = .stacked
        settings._test_liveSystemCodexAccount = self.liveAccount(
            email: activeEmail,
            identity: .providerAccount(id: "acct-active-boundary-owner"))
        settings.codexActiveSource = .liveSystem
        defer {
            settings._test_liveSystemCodexAccount = nil
            settings._test_managedCodexAccountStoreURL = nil
        }

        let temporaryRoot = CodexCredentialFixtures.root
            .appendingPathComponent("codex-inactive-boundary-marker-\(UUID().uuidString)", isDirectory: true)
        let managedHome = temporaryRoot.appendingPathComponent("managed", isDirectory: true)
        let managedID = UUID()
        let managedAccount = try self.makeManagedCodexWeeklyPublicationAccount(
            id: managedID,
            email: inactiveEmail,
            workspaceID: "acct-inactive-boundary-owner",
            workspaceLabel: "Inactive workspace",
            homeURL: managedHome)
        let managedStoreURL = try self.makeManagedAccountStoreURL(accounts: [managedAccount])
        settings._test_managedCodexAccountStoreURL = managedStoreURL
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
            try? FileManager.default.removeItem(at: managedStoreURL)
        }

        let projection = settings.codexVisibleAccountProjection
        let activeAccount = try #require(projection.visibleAccounts.first {
            $0.selectionSource == .liveSystem
        })
        let inactiveAccount = try #require(projection.visibleAccounts.first {
            $0.storedAccountID == managedID
        })
        let observedAt = weeklyBoundaryTestDate("2026-10-07T12:30:00Z")
        let retiredBoundary = weeklyBoundaryTestDate("2026-10-14T11:06:24Z")
        let correctedBoundary = weeklyBoundaryTestDate("2026-10-14T03:38:58Z")
        let activeSnapshot = self.codexWeeklySnapshot(
            email: activeEmail,
            weeklyUsedPercent: 60,
            weeklyReset: retiredBoundary,
            updatedAt: observedAt,
            dataConfidence: .exact)
        let inactiveCorrection = self.codexWeeklySnapshot(
            email: inactiveEmail,
            weeklyUsedPercent: 11.2,
            weeklyReset: correctedBoundary,
            updatedAt: observedAt,
            dataConfidence: .exact)
        let activeRow = CodexAccountUsageSnapshot(
            account: activeAccount,
            snapshot: activeSnapshot,
            error: nil,
            sourceLabel: "oauth")
        let inactiveRow = CodexAccountUsageSnapshot(
            account: inactiveAccount,
            snapshot: inactiveCorrection,
            error: nil,
            sourceLabel: "oauth",
            weeklyBoundaryEvidence: CodexWeeklyBoundaryEvidence(
                retiredBoundaries: [retiredBoundary],
                pendingDetectorCorrection: inactiveCorrection))
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-inactive-boundary-marker-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }
        let snapshotStore = FileCodexAccountUsageSnapshotStore(fileURL: snapshotURL)
        snapshotStore.store([activeRow, inactiveRow])

        let persistedBeforeRelaunch = try #require(snapshotStore.load(
            for: projection.visibleAccounts).first { $0.id == inactiveAccount.id })
        #expect(persistedBeforeRelaunch.weeklyBoundaryEvidence?.pendingDetectorCorrection?.updatedAt
            == inactiveCorrection.updatedAt)
        let store = self.makeCodexWeeklyPublicationStore(
            settings: settings,
            suite: suite,
            snapshotStore: snapshotStore)
        let historyRevisionBeforeConsumption = store.planUtilizationHistoryRevision
        let recorder = WeeklyBoundaryPublicationEventRecorder(email: inactiveEmail)
        defer { recorder.invalidate() }

        store.consumePendingCodexBoundaryDetectorCorrections()

        let ownerKey = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "acct-inactive-boundary-owner"),
            accountEmail: inactiveEmail))
        let detectorKey = UsageStore.limitResetDetectorStateKey(
            provider: .codex,
            accountIdentifier: ownerKey.rawValue)
        let detectorState = try #require(store.weeklyLimitResetDetectorStates[detectorKey])
        #expect(detectorState.resetBoundary == correctedBoundary)
        #expect(detectorState.wasAboveThreshold)
        #expect(detectorState.codexEarlyWeeklyResetPending == false)
        #expect(detectorState.pendingLowConfirmation == false)
        #expect(store.planUtilizationHistoryRevision == historyRevisionBeforeConsumption)
        #expect(recorder.isEmpty)

        let persistedAfterConsumption = try #require(snapshotStore.load(
            for: projection.visibleAccounts).first { $0.id == inactiveAccount.id })
        #expect(persistedAfterConsumption.snapshot?.updatedAt == inactiveCorrection.updatedAt)
        #expect(persistedAfterConsumption.weeklyBoundaryEvidence?.pendingDetectorCorrection == nil)
        #expect(persistedAfterConsumption.weeklyBoundaryEvidence?.retiredBoundaries.contains {
            abs($0.timeIntervalSince(retiredBoundary)) < 120
        } == true)
        let persistedActiveAccount = try #require(snapshotStore.load(
            for: projection.visibleAccounts).first { $0.id == activeAccount.id })
        #expect(persistedActiveAccount.snapshot?.updatedAt == activeSnapshot.updatedAt)
        #expect(persistedActiveAccount.weeklyBoundaryEvidence == nil)
    }

    @Test
    func `plan change starts a fresh boundary scope`() async throws {
        let suite = "CodexWeeklyBoundaryPublicationTests-plan-change"
        let email = "plan-change-boundary@example.com"
        let settings = self.makeSettingsStore(suite: suite)
        settings.refreshFrequency = .manual
        settings.codexCookieSource = .off
        settings._test_liveSystemCodexAccount = self.liveAccount(
            email: email,
            identity: .providerAccount(id: "acct-plan-change-boundary"))
        defer { settings._test_liveSystemCodexAccount = nil }

        let baselineAt = weeklyBoundaryTestDate("2026-10-07T09:00:00Z")
        let priorPlanBoundary = weeklyBoundaryTestDate("2026-10-14T11:06:24Z")
        let plusBoundary = priorPlanBoundary.addingTimeInterval(7 * 24 * 60 * 60)
        let proBaseline = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 40,
            weeklyReset: priorPlanBoundary,
            updatedAt: baselineAt,
            dataConfidence: .exact)
        let plusBaseline = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 45,
            weeklyReset: plusBoundary,
            updatedAt: baselineAt.addingTimeInterval(60),
            dataConfidence: .exact)
            .withIdentity(self.codexIdentitySnapshot(email: email, loginMethod: "Plus"))
        let plusCorrectionCandidate = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 46,
            weeklyReset: priorPlanBoundary,
            updatedAt: baselineAt.addingTimeInterval(121),
            dataConfidence: .exact)
            .withIdentity(self.codexIdentitySnapshot(email: email, loginMethod: "Plus"))
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-weekly-plan-scope-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }
        let snapshotStore = FileCodexAccountUsageSnapshotStore(fileURL: snapshotURL)
        let account = try #require(settings.codexVisibleAccountProjection.visibleAccounts.first)
        let baselineRow = CodexAccountUsageSnapshot(
            account: account,
            snapshot: proBaseline,
            error: nil,
            sourceLabel: "oauth")
        snapshotStore.store([baselineRow])

        let store = self.makeCodexWeeklyPublicationStore(
            settings: settings,
            suite: suite,
            snapshotStore: snapshotStore)
        store.codexAccountSnapshots = [baselineRow]
        _ = await self.seedCodexWeeklyPublicationState(
            store: store,
            settings: settings,
            snapshot: proBaseline,
            error: nil)
        store.lastSourceLabels[.codex] = "oauth"
        self.installContextualCodexProvider(on: store, sourceLabel: "oauth", kind: .oauth) { _ in plusBaseline }

        await CodexWeeklyResetConfirmation.$observationDateOverride.withValue(plusBaseline.updatedAt) {
            await store.refreshProvider(.codex, allowDisabled: true)
        }

        #expect(store.snapshots[.codex]?.updatedAt == plusBaseline.updatedAt)
        let persistedPlusBaseline = try #require(snapshotStore.load(
            for: settings.codexVisibleAccountProjection.visibleAccounts).first)
        #expect(persistedPlusBaseline.snapshot?.secondary?.resetsAt == plusBoundary)
        #expect(persistedPlusBaseline.weeklyBoundaryEvidence?.retiredBoundaries.isEmpty == true)
        #expect(persistedPlusBaseline.weeklyBoundaryEvidence?.correctionCandidate == nil)

        self.installContextualCodexProvider(on: store, sourceLabel: "oauth", kind: .oauth) { _ in
            plusCorrectionCandidate
        }
        await CodexWeeklyResetConfirmation.$observationDateOverride.withValue(plusCorrectionCandidate.updatedAt) {
            await store.refreshProvider(.codex, allowDisabled: true)
        }

        #expect(store.snapshots[.codex]?.updatedAt == plusBaseline.updatedAt)
        let persistedCandidate = try #require(snapshotStore.load(
            for: settings.codexVisibleAccountProjection.visibleAccounts).first)
        let evidence = try #require(persistedCandidate.weeklyBoundaryEvidence)
        #expect(evidence.holdReason == .candidateCreated)
        #expect(evidence.correctionCandidate?.originalBoundary == plusBoundary)
        #expect(evidence.retiredBoundaries.isEmpty)
        #expect(persistedCandidate.snapshot?.secondary?.resetsAt == plusBoundary)
    }
}

private func weeklyBoundaryTestDate(_ value: String) -> Date {
    guard let date = ISO8601DateFormatter().date(from: value) else {
        preconditionFailure("Invalid ISO 8601 test date: \(value)")
    }
    return date
}

private func weeklyBoundaryFetchOutcome(_ snapshot: UsageSnapshot) -> ProviderFetchOutcome {
    ProviderFetchOutcome(
        result: .success(ProviderFetchResult(
            usage: snapshot,
            credits: nil,
            dashboard: nil,
            sourceLabel: "oauth",
            strategyID: "weekly-boundary-publication-test",
            strategyKind: .oauth)),
        attempts: [])
}

private final class WeeklyBoundaryPublicationEventRecorder: @unchecked Sendable {
    private let email: String
    private let lock = NSLock()
    private var events = 0
    private var token: NSObjectProtocol?

    init(email: String) {
        self.email = email
        self.token = NotificationCenter.default.addObserver(
            forName: .codexbarWeeklyLimitReset,
            object: nil,
            queue: nil)
        { [weak self] notification in
            guard let self,
                  let event = notification.object as? WeeklyLimitResetEvent
            else {
                return
            }
            let matches = MainActor.assumeIsolated {
                event.provider == .codex && event.accountLabel == self.email
            }
            guard matches else { return }
            self.lock.lock()
            self.events += 1
            self.lock.unlock()
        }
    }

    var isEmpty: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.events == 0
    }

    func invalidate() {
        guard let token else { return }
        NotificationCenter.default.removeObserver(token)
        self.token = nil
    }

    deinit {
        self.invalidate()
    }
}

private final class BoundaryConsistencyCodexAccountUsageSnapshotStore:
    CodexAccountUsageSnapshotStoring,
    @unchecked Sendable
{
    private let base: FileCodexAccountUsageSnapshotStore
    private let lock = NSLock()
    private var invalidCommits = 0

    init(base: FileCodexAccountUsageSnapshotStore) {
        self.base = base
    }

    var invalidCommitCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.invalidCommits
    }

    func load(for accounts: [CodexVisibleAccount]) -> [CodexAccountUsageSnapshot] {
        self.base.load(for: accounts)
    }

    func store(_ snapshots: [CodexAccountUsageSnapshot]) {
        let hasInvalidAcceptedBoundary = snapshots.contains { row in
            guard let snapshot = row.snapshot,
                  let boundary = CodexConsumerProjection.sourceRateWindow(
                      for: .weekly,
                      snapshot: snapshot)?.resetsAt,
                  let evidence = row.weeklyBoundaryEvidence
            else {
                return false
            }
            return evidence.retiredBoundaries.contains {
                abs($0.timeIntervalSince(boundary)) < CodexWeeklyBoundaryCorrection.boundaryEquivalenceTolerance
            }
        }
        if hasInvalidAcceptedBoundary {
            self.lock.lock()
            self.invalidCommits += 1
            self.lock.unlock()
        }
        self.base.store(snapshots)
    }
}
