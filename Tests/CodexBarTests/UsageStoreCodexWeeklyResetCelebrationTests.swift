import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

extension UsageStorePlanUtilizationTests {
    @MainActor
    @Test
    func `codex weekly steady low usage does not create a reset candidate`() async throws {
        let store = Self.makeStore()
        let accountLabel = "codex-weekly-steady-low@example.com"
        let ownerKey = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "fixture-codex-weekly-steady-low"),
            accountEmail: accountLabel))
        let recorder = WeeklyLimitResetEventRecorder(provider: .codex, accountLabel: accountLabel)
        defer { recorder.invalidate() }

        let firstDate = Date(timeIntervalSince1970: 1_701_400_000)
        let weeklyReset = firstDate.addingTimeInterval(3 * 24 * 3600)
        for offset in [TimeInterval(0), 60, 120] {
            let snapshot = codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 3,
                resetsAt: weeklyReset,
                updatedAt: firstDate.addingTimeInterval(offset))
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: snapshot,
                codexLimitResetOwnerKey: ownerKey,
                now: snapshot.updatedAt)
        }

        #expect(recorder.events.isEmpty)
        #expect(store.weeklyLimitResetDetectorStates.values.first?.pendingLowConfirmation == false)
    }

    @MainActor
    @Test
    func `codex weekly six to five percent drift does not celebrate`() async throws {
        let store = Self.makeStore()
        let accountLabel = "codex-weekly-small-drift@example.com"
        let ownerKey = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "fixture-codex-weekly-small-drift"),
            accountEmail: accountLabel))
        let recorder = WeeklyLimitResetEventRecorder(provider: .codex, accountLabel: accountLabel)
        defer { recorder.invalidate() }

        let firstDate = Date(timeIntervalSince1970: 1_701_450_000)
        let weeklyReset = firstDate.addingTimeInterval(3 * 24 * 3600)
        for (offset, usedPercent) in [(TimeInterval(0), 6.0), (60, 5.0), (120, 5.0)] {
            let snapshot = codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: usedPercent,
                resetsAt: weeklyReset,
                updatedAt: firstDate.addingTimeInterval(offset))
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: snapshot,
                codexLimitResetOwnerKey: ownerKey,
                now: snapshot.updatedAt)
        }

        #expect(recorder.events.isEmpty)
        #expect(store.weeklyLimitResetDetectorStates.values.first?.pendingLowConfirmation == false)
    }

    @MainActor
    @Test
    func `codex weekly unchanged boundary candidate can start at two percent and confirms later`() async throws {
        let store = Self.makeStore()
        let accountLabel = "codex-weekly-delayed-confirmation@example.com"
        let ownerKey = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "fixture-codex-weekly-delayed-confirmation"),
            accountEmail: accountLabel))
        let recorder = WeeklyLimitResetEventRecorder(provider: .codex, accountLabel: accountLabel)
        defer { recorder.invalidate() }

        let firstDate = Date(timeIntervalSince1970: 1_701_500_000)
        let weeklyReset = firstDate.addingTimeInterval(3 * 24 * 3600)
        let before = codexWeeklyResetSnapshot(
            accountLabel: accountLabel,
            usedPercent: 86,
            resetsAt: weeklyReset,
            updatedAt: firstDate)
        let candidate = codexWeeklyResetSnapshot(
            accountLabel: accountLabel,
            usedPercent: 2,
            resetsAt: weeklyReset,
            updatedAt: firstDate.addingTimeInterval(60))
        let tooSoon = codexWeeklyResetSnapshot(
            accountLabel: accountLabel,
            usedPercent: 2,
            resetsAt: weeklyReset,
            updatedAt: firstDate.addingTimeInterval(119))
        let confirmed = codexWeeklyResetSnapshot(
            accountLabel: accountLabel,
            usedPercent: 2,
            resetsAt: weeklyReset,
            updatedAt: firstDate.addingTimeInterval(120))

        for snapshot in [before, candidate, tooSoon] {
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: snapshot,
                codexLimitResetOwnerKey: ownerKey,
                now: snapshot.updatedAt)
        }
        #expect(recorder.events.isEmpty)
        #expect(store.weeklyLimitResetDetectorStates.values.first?.pendingLowConfirmation == true)

        store.weeklyLimitResetDetectorStates = UsageStore.loadWeeklyLimitResetDetectorStates(
            from: store.settings.userDefaults)
        await store.recordPlanUtilizationHistorySample(
            provider: .codex,
            snapshot: confirmed,
            codexLimitResetOwnerKey: ownerKey,
            now: confirmed.updatedAt)

        #expect(recorder.events.count == 1)
        #expect(recorder.events.first?.usedPercent == 2)

        for snapshot in [
            codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 3,
                resetsAt: weeklyReset,
                updatedAt: firstDate.addingTimeInterval(180)),
            codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 0,
                resetsAt: weeklyReset,
                updatedAt: firstDate.addingTimeInterval(240)),
        ] {
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: snapshot,
                codexLimitResetOwnerKey: ownerKey,
                now: snapshot.updatedAt)
        }
        #expect(recorder.events.count == 1)
    }

    @MainActor
    @Test
    func `codex weekly candidate expires and is cancelled by a plan change`() async throws {
        let accountLabel = "codex-weekly-candidate-lifetime@example.com"
        let ownerKey = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "fixture-codex-weekly-candidate-lifetime"),
            accountEmail: accountLabel))
        let firstDate = Date(timeIntervalSince1970: 1_701_700_000)
        let weeklyReset = firstDate.addingTimeInterval(3 * 24 * 3600)

        for (laterPlan, laterOffset) in [
            ("pro", TimeInterval(60 + 30 * 60 + 1)),
            ("plus", TimeInterval(120)),
        ] {
            let store = Self.makeStore()
            let recorder = WeeklyLimitResetEventRecorder(provider: .codex, accountLabel: accountLabel)
            defer { recorder.invalidate() }
            let before = codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 86,
                resetsAt: weeklyReset,
                updatedAt: firstDate,
                loginMethod: "pro")
            let candidate = codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 0.5,
                resetsAt: weeklyReset,
                updatedAt: firstDate.addingTimeInterval(60),
                loginMethod: "pro")
            let later = codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 2,
                resetsAt: weeklyReset,
                updatedAt: firstDate.addingTimeInterval(laterOffset),
                loginMethod: laterPlan)

            for snapshot in [before, candidate, later] {
                await store.recordPlanUtilizationHistorySample(
                    provider: .codex,
                    snapshot: snapshot,
                    codexLimitResetOwnerKey: ownerKey,
                    now: snapshot.updatedAt)
            }

            #expect(recorder.events.isEmpty)
            #expect(store.weeklyLimitResetDetectorStates.values.first?.pendingLowConfirmation == false)
        }
    }

    @MainActor
    @Test
    func `codex weekly rebound cancels the old candidate before a later crossing starts a new one`() async throws {
        let store = Self.makeStore()
        let accountLabel = "codex-weekly-candidate-rebound@example.com"
        let ownerKey = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "fixture-codex-weekly-candidate-rebound"),
            accountEmail: accountLabel))
        let recorder = WeeklyLimitResetEventRecorder(provider: .codex, accountLabel: accountLabel)
        defer { recorder.invalidate() }
        let firstDate = Date(timeIntervalSince1970: 1_701_800_000)
        let weeklyReset = firstDate.addingTimeInterval(3 * 24 * 3600)

        for snapshot in [
            codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 86,
                resetsAt: weeklyReset,
                updatedAt: firstDate),
            codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 0.5,
                resetsAt: weeklyReset,
                updatedAt: firstDate.addingTimeInterval(60)),
        ] {
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: snapshot,
                codexLimitResetOwnerKey: ownerKey,
                now: snapshot.updatedAt)
        }
        #expect(store.weeklyLimitResetDetectorStates.values.first?.pendingLowConfirmation == true)

        let rebound = codexWeeklyResetSnapshot(
            accountLabel: accountLabel,
            usedPercent: 30,
            resetsAt: weeklyReset,
            updatedAt: firstDate.addingTimeInterval(120))
        await store.recordPlanUtilizationHistorySample(
            provider: .codex,
            snapshot: rebound,
            codexLimitResetOwnerKey: ownerKey,
            now: rebound.updatedAt)
        #expect(store.weeklyLimitResetDetectorStates.values.first?.pendingLowConfirmation == false)

        let laterCrossing = codexWeeklyResetSnapshot(
            accountLabel: accountLabel,
            usedPercent: 2,
            resetsAt: weeklyReset,
            updatedAt: firstDate.addingTimeInterval(180))
        await store.recordPlanUtilizationHistorySample(
            provider: .codex,
            snapshot: laterCrossing,
            codexLimitResetOwnerKey: ownerKey,
            now: laterCrossing.updatedAt)

        #expect(recorder.events.isEmpty)
        #expect(store.weeklyLimitResetDetectorStates.values.first?.pendingLowConfirmation == true)
        #expect(store.weeklyLimitResetDetectorStates.values.first?.pendingLowObservedAt == laterCrossing.updatedAt)
    }

    @MainActor
    @Test
    func `codex weekly candidate requires a known stable plan and boundary`() async throws {
        let accountLabel = "codex-weekly-candidate-evidence@example.com"
        let ownerKey = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "fixture-codex-weekly-candidate-evidence"),
            accountEmail: accountLabel))
        let firstDate = Date(timeIntervalSince1970: 1_701_850_000)
        let weeklyReset = firstDate.addingTimeInterval(3 * 24 * 3600)

        for (loginMethod, laterBoundary) in [
            (nil, weeklyReset),
            ("pro", weeklyReset.addingTimeInterval(90)),
        ] as [(String?, Date)] {
            let store = Self.makeStore()
            let recorder = WeeklyLimitResetEventRecorder(provider: .codex, accountLabel: accountLabel)
            defer { recorder.invalidate() }
            for snapshot in [
                codexWeeklyResetSnapshot(
                    accountLabel: accountLabel,
                    usedPercent: 86,
                    resetsAt: weeklyReset,
                    updatedAt: firstDate,
                    loginMethod: loginMethod),
                codexWeeklyResetSnapshot(
                    accountLabel: accountLabel,
                    usedPercent: 0.5,
                    resetsAt: weeklyReset,
                    updatedAt: firstDate.addingTimeInterval(60),
                    loginMethod: loginMethod),
                codexWeeklyResetSnapshot(
                    accountLabel: accountLabel,
                    usedPercent: 2,
                    resetsAt: laterBoundary,
                    updatedAt: firstDate.addingTimeInterval(120),
                    loginMethod: loginMethod),
            ] {
                await store.recordPlanUtilizationHistorySample(
                    provider: .codex,
                    snapshot: snapshot,
                    codexLimitResetOwnerKey: ownerKey,
                    now: snapshot.updatedAt)
            }

            #expect(recorder.events.isEmpty)
            #expect(store.weeklyLimitResetDetectorStates.values.first?.pendingLowConfirmation == false)
        }
    }

    @MainActor
    @Test
    func `codex weekly candidate cannot be confirmed by another owner`() async throws {
        let store = Self.makeStore()
        let accountLabel = "codex-weekly-candidate-owner@example.com"
        let ownerA = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "fixture-codex-weekly-candidate-owner-a"),
            accountEmail: accountLabel))
        let ownerB = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "fixture-codex-weekly-candidate-owner-b"),
            accountEmail: accountLabel))
        let recorder = WeeklyLimitResetEventRecorder(provider: .codex, accountLabel: accountLabel)
        defer { recorder.invalidate() }
        let firstDate = Date(timeIntervalSince1970: 1_701_875_000)
        let weeklyReset = firstDate.addingTimeInterval(3 * 24 * 3600)

        for snapshot in [
            codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 86,
                resetsAt: weeklyReset,
                updatedAt: firstDate),
            codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 0.5,
                resetsAt: weeklyReset,
                updatedAt: firstDate.addingTimeInterval(60)),
        ] {
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: snapshot,
                codexLimitResetOwnerKey: ownerA,
                now: snapshot.updatedAt)
        }

        let otherOwnerLow = codexWeeklyResetSnapshot(
            accountLabel: accountLabel,
            usedPercent: 2,
            resetsAt: weeklyReset,
            updatedAt: firstDate.addingTimeInterval(120))
        await store.recordPlanUtilizationHistorySample(
            provider: .codex,
            snapshot: otherOwnerLow,
            codexLimitResetOwnerKey: ownerB,
            now: otherOwnerLow.updatedAt)
        #expect(recorder.events.isEmpty)

        let returningOwnerLow = codexWeeklyResetSnapshot(
            accountLabel: accountLabel,
            usedPercent: 2,
            resetsAt: weeklyReset,
            updatedAt: firstDate.addingTimeInterval(180))
        await store.recordPlanUtilizationHistorySample(
            provider: .codex,
            snapshot: returningOwnerLow,
            codexLimitResetOwnerKey: ownerA,
            now: returningOwnerLow.updatedAt)

        #expect(recorder.events.count == 1)
        #expect(recorder.events.first?.usedPercent == 2)
    }

    @MainActor
    @Test
    func `codex weekly advanced boundary celebrates a reset already used to two percent`() async throws {
        let store = Self.makeStore()
        let accountLabel = "codex-weekly-two-percent@example.com"
        let ownerKey = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "fixture-codex-weekly-two-percent"),
            accountEmail: accountLabel))
        let recorder = WeeklyLimitResetEventRecorder(provider: .codex, accountLabel: accountLabel)
        defer { recorder.invalidate() }

        let firstDate = Date(timeIntervalSince1970: 1_701_900_000)
        let weeklyReset = firstDate.addingTimeInterval(3 * 24 * 3600)
        let nextWeeklyReset = weeklyReset.addingTimeInterval(7 * 24 * 3600)
        let before = codexWeeklyResetSnapshot(
            accountLabel: accountLabel,
            usedPercent: 86,
            resetsAt: weeklyReset,
            updatedAt: firstDate)
        let reset = codexWeeklyResetSnapshot(
            accountLabel: accountLabel,
            usedPercent: 2,
            resetsAt: nextWeeklyReset,
            updatedAt: firstDate.addingTimeInterval(60))

        for snapshot in [before, reset] {
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: snapshot,
                codexLimitResetOwnerKey: ownerKey,
                now: snapshot.updatedAt)
        }

        #expect(recorder.events.count == 1)
        #expect(recorder.events.first?.usedPercent == 2)
    }

    @MainActor
    @Test
    func `codex weekly advanced boundary reset range is capped at five percent`() async throws {
        let firstDate = Date(timeIntervalSince1970: 1_701_950_000)
        let weeklyReset = firstDate.addingTimeInterval(3 * 24 * 3600)
        let nextWeeklyReset = weeklyReset.addingTimeInterval(7 * 24 * 3600)

        for (usedPercent, expectedEventCount) in [(5.0, 1), (5.01, 0)] {
            let store = Self.makeStore()
            let accountLabel = "codex-weekly-threshold-\(usedPercent)@example.com"
            let ownerKey = try #require(CodexLimitResetOwnerKey(
                identity: .providerAccount(id: "fixture-codex-weekly-threshold-\(usedPercent)"),
                accountEmail: accountLabel))
            let recorder = WeeklyLimitResetEventRecorder(provider: .codex, accountLabel: accountLabel)
            defer { recorder.invalidate() }

            for snapshot in [
                codexWeeklyResetSnapshot(
                    accountLabel: accountLabel,
                    usedPercent: 86,
                    resetsAt: weeklyReset,
                    updatedAt: firstDate),
                codexWeeklyResetSnapshot(
                    accountLabel: accountLabel,
                    usedPercent: usedPercent,
                    resetsAt: nextWeeklyReset,
                    updatedAt: firstDate.addingTimeInterval(60)),
            ] {
                await store.recordPlanUtilizationHistorySample(
                    provider: .codex,
                    snapshot: snapshot,
                    codexLimitResetOwnerKey: ownerKey,
                    now: snapshot.updatedAt)
            }

            #expect(recorder.events.count == expectedEventCount)
        }
    }

    @MainActor
    @Test
    func `accepted codex weekly boundary correction clears candidates and preserves the next reset`() async throws {
        let notifier = CodexWeeklyResetNotificationSpy()
        let store = makeCodexWeeklyResetCorrectionStore(notifier: notifier)
        store.settings.limitResetNotificationsEnabled = true
        let accountLabel = "codex-weekly-boundary-correction@example.com"
        let ownerKey = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "fixture-codex-weekly-boundary-correction"),
            accountEmail: accountLabel))
        let sessionRecorder = SessionLimitResetEventRecorder(provider: .codex, accountLabel: accountLabel)
        defer { sessionRecorder.invalidate() }
        let recorder = WeeklyLimitResetEventRecorder(provider: .codex, accountLabel: accountLabel)
        defer { recorder.invalidate() }

        let firstDate = Date(timeIntervalSince1970: 1_702_000_000)
        let publishedBoundary = firstDate.addingTimeInterval(3 * 24 * 3600)
        let correctedBoundary = firstDate.addingTimeInterval(2 * 24 * 3600)
        let earlierReceiptBoundary = firstDate.addingTimeInterval(-7 * 24 * 3600)
        let initial = codexWeeklyResetSnapshot(
            accountLabel: accountLabel,
            usedPercent: 86,
            resetsAt: publishedBoundary,
            updatedAt: firstDate,
            sessionUsedPercent: 86,
            sessionResetsAt: firstDate.addingTimeInterval(5 * 60 * 60))
        await store.recordPlanUtilizationHistorySample(
            provider: .codex,
            snapshot: initial,
            codexLimitResetOwnerKey: ownerKey,
            now: initial.updatedAt)

        let detectorKey = try #require(store.weeklyLimitResetDetectorStates.keys.first)
        let baseline = try #require(store.weeklyLimitResetDetectorStates[detectorKey])
        store.weeklyLimitResetDetectorStates[detectorKey] = UsageStore.LimitResetDetectorState(
            wasAboveThreshold: baseline.wasAboveThreshold,
            wasAboveCodexWeeklyCandidateThreshold: baseline.wasAboveCodexWeeklyCandidateThreshold,
            lastObservedAt: baseline.lastObservedAt,
            sourceRawValue: baseline.sourceRawValue,
            resetBoundary: baseline.resetBoundary,
            recoveryAboveThresholdCount: baseline.recoveryAboveThresholdCount,
            codexEarlyWeeklyResetPending: true,
            pendingLowConfirmation: true,
            pendingLowObservedAt: firstDate.addingTimeInterval(30),
            lastPostedResetBoundary: earlierReceiptBoundary,
            notificationReceipt: UsageStore.LimitResetNotificationReceipt(
                resetBoundary: earlierReceiptBoundary),
            lastNotifiedResetBoundary: earlierReceiptBoundary,
            planRawValue: baseline.planRawValue)

        let correction = codexWeeklyResetSnapshot(
            accountLabel: accountLabel,
            usedPercent: 2,
            resetsAt: correctedBoundary,
            updatedAt: firstDate.addingTimeInterval(60),
            sessionUsedPercent: 0,
            sessionResetsAt: firstDate.addingTimeInterval(9 * 60 * 60))
        await store.recordPlanUtilizationHistorySample(
            provider: .codex,
            snapshot: correction,
            codexLimitResetOwnerKey: ownerKey,
            codexCorrectsWeeklyBoundary: true,
            now: correction.updatedAt)

        #expect(recorder.events.isEmpty)
        #expect(sessionRecorder.events.isEmpty)
        #expect(notifier.limitResetPosts.isEmpty)
        let correctedState = try #require(store.weeklyLimitResetDetectorStates[detectorKey])
        #expect(correctedState.resetBoundary == correctedBoundary)
        #expect(correctedState.codexEarlyWeeklyResetPending == false)
        #expect(correctedState.pendingLowConfirmation == false)
        #expect(correctedState.pendingLowObservedAt == nil)
        #expect(correctedState.wasAboveThreshold)
        #expect(correctedState.lastPostedResetBoundary == earlierReceiptBoundary)
        #expect(correctedState.notificationReceipt == UsageStore.LimitResetNotificationReceipt(
            resetBoundary: earlierReceiptBoundary))
        #expect(correctedState.lastNotifiedResetBoundary == earlierReceiptBoundary)

        let nextBoundary = correctedBoundary.addingTimeInterval(7 * 24 * 3600)
        for offset in [TimeInterval(120), 180] {
            let reset = codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 2,
                resetsAt: nextBoundary,
                updatedAt: firstDate.addingTimeInterval(offset))
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: reset,
                codexLimitResetOwnerKey: ownerKey,
                now: reset.updatedAt)
        }

        #expect(recorder.events.count == 1)
        #expect(recorder.events.first?.usedPercent == 2)
        #expect(sessionRecorder.events.isEmpty)
        #expect(notifier.limitResetPosts == [.weekly])
    }

    @MainActor
    @Test
    func `codex weekly one to eleven correction keeps a direct advanced reset eligible`() async throws {
        let firstDate = Date(timeIntervalSince1970: 1_702_050_000)
        let publishedBoundary = firstDate.addingTimeInterval(3 * 24 * 3600)
        let correctedBoundary = firstDate.addingTimeInterval(2 * 24 * 3600)
        let nextBoundary = correctedBoundary.addingTimeInterval(7 * 24 * 3600)

        for genuineResetUsage in [0.0, 2.0] {
            let notifier = CodexWeeklyResetNotificationSpy()
            let store = makeCodexWeeklyResetCorrectionStore(notifier: notifier)
            store.settings.limitResetNotificationsEnabled = true
            let accountLabel = "codex-weekly-1-to-11-\(genuineResetUsage)@example.com"
            let ownerKey = try #require(CodexLimitResetOwnerKey(
                identity: .providerAccount(id: "fixture-codex-weekly-1-to-11-\(genuineResetUsage)"),
                accountEmail: accountLabel))
            let recorder = WeeklyLimitResetEventRecorder(provider: .codex, accountLabel: accountLabel)
            defer { recorder.invalidate() }

            let initial = codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 1,
                resetsAt: publishedBoundary,
                updatedAt: firstDate)
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: initial,
                codexLimitResetOwnerKey: ownerKey,
                now: initial.updatedAt)

            let correction = codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: 11,
                resetsAt: correctedBoundary,
                updatedAt: firstDate.addingTimeInterval(60))
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: correction,
                codexLimitResetOwnerKey: ownerKey,
                codexCorrectsWeeklyBoundary: true,
                now: correction.updatedAt)

            #expect(recorder.events.isEmpty)
            #expect(notifier.limitResetPosts.isEmpty)
            #expect(store.weeklyLimitResetDetectorStates.values.first?.wasAboveThreshold == true)

            let reset = codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: genuineResetUsage,
                resetsAt: nextBoundary,
                updatedAt: firstDate.addingTimeInterval(120))
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: reset,
                codexLimitResetOwnerKey: ownerKey,
                now: reset.updatedAt)
            #expect(recorder.events.count == 1)
            #expect(recorder.events.first?.usedPercent == genuineResetUsage)
            #expect(notifier.limitResetPosts == [.weekly])

            let duplicate = codexWeeklyResetSnapshot(
                accountLabel: accountLabel,
                usedPercent: genuineResetUsage,
                resetsAt: nextBoundary,
                updatedAt: firstDate.addingTimeInterval(180))
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: duplicate,
                codexLimitResetOwnerKey: ownerKey,
                now: duplicate.updatedAt)
            #expect(recorder.events.count == 1)
            #expect(notifier.limitResetPosts == [.weekly])
        }
    }

    @MainActor
    @Test
    func `normalizing a nonactive codex owner preserves its next weekly reset`() async throws {
        let notifier = CodexWeeklyResetNotificationSpy()
        let store = makeCodexWeeklyResetCorrectionStore(notifier: notifier)
        store.settings.limitResetNotificationsEnabled = true
        let emailA = "codex-correction-active@example.com"
        let emailB = "codex-correction-inactive@example.com"
        let ownerA = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "fixture-codex-correction-active"),
            accountEmail: emailA))
        let ownerB = try #require(CodexLimitResetOwnerKey(
            identity: .providerAccount(id: "fixture-codex-correction-inactive"),
            accountEmail: emailB))
        let recorder = WeeklyLimitResetEventRecorder(provider: .codex, accountLabel: emailB)
        defer { recorder.invalidate() }

        let firstDate = Date(timeIntervalSince1970: 1_702_100_000)
        let publishedBoundary = firstDate.addingTimeInterval(3 * 24 * 3600)
        let correctedBoundary = firstDate.addingTimeInterval(2 * 24 * 3600)
        let oldReceiptBoundary = firstDate.addingTimeInterval(-7 * 24 * 3600)
        let activeSnapshot = codexWeeklyResetSnapshot(
            accountLabel: emailA,
            usedPercent: 70,
            resetsAt: publishedBoundary,
            updatedAt: firstDate)
        await store.recordPlanUtilizationHistorySample(
            provider: .codex,
            snapshot: activeSnapshot,
            codexLimitResetOwnerKey: ownerA,
            now: activeSnapshot.updatedAt)
        store.snapshots[.codex] = activeSnapshot

        let inactiveBaseline = codexWeeklyResetSnapshot(
            accountLabel: emailB,
            usedPercent: 1,
            resetsAt: publishedBoundary,
            updatedAt: firstDate)
        await store.recordPlanUtilizationHistorySample(
            provider: .codex,
            snapshot: inactiveBaseline,
            codexLimitResetOwnerKey: ownerB,
            now: inactiveBaseline.updatedAt)

        let activeDetectorKey = UsageStore.limitResetDetectorStateKey(
            provider: .codex,
            accountIdentifier: ownerA.rawValue)
        let inactiveDetectorKey = UsageStore.limitResetDetectorStateKey(
            provider: .codex,
            accountIdentifier: ownerB.rawValue)
        let activeState = try #require(store.weeklyLimitResetDetectorStates[activeDetectorKey])
        let inactiveState = try #require(store.weeklyLimitResetDetectorStates[inactiveDetectorKey])
        store.weeklyLimitResetDetectorStates[inactiveDetectorKey] = UsageStore.LimitResetDetectorState(
            wasAboveThreshold: inactiveState.wasAboveThreshold,
            wasAboveCodexWeeklyCandidateThreshold: inactiveState.wasAboveCodexWeeklyCandidateThreshold,
            lastObservedAt: inactiveState.lastObservedAt,
            sourceRawValue: inactiveState.sourceRawValue,
            resetBoundary: publishedBoundary,
            codexEarlyWeeklyResetPending: true,
            pendingLowConfirmation: true,
            pendingLowObservedAt: firstDate.addingTimeInterval(30),
            lastPostedResetBoundary: oldReceiptBoundary,
            notificationReceipt: UsageStore.LimitResetNotificationReceipt(resetBoundary: oldReceiptBoundary),
            lastNotifiedResetBoundary: oldReceiptBoundary,
            planRawValue: inactiveState.planRawValue)

        let activeHistory = PlanUtilizationSeriesHistory(
            name: .weekly,
            windowMinutes: 10080,
            entries: [PlanUtilizationHistoryEntry(
                capturedAt: firstDate,
                usedPercent: 70,
                resetsAt: publishedBoundary)])
        store.planUtilizationHistory[.codex] = PlanUtilizationHistoryBuckets(
            preferredAccountKey: "active-owner-a",
            accounts: ["active-owner-a": [activeHistory]])
        let historyBeforeNormalization = store.planUtilizationHistory

        let correction = codexWeeklyResetSnapshot(
            accountLabel: emailB,
            usedPercent: 11,
            resetsAt: correctedBoundary,
            updatedAt: firstDate.addingTimeInterval(60))
        store.normalizeCodexWeeklyBoundaryCorrection(snapshot: correction, ownerKey: ownerB)

        #expect(recorder.events.isEmpty)
        #expect(notifier.limitResetPosts.isEmpty)
        #expect(store.weeklyLimitResetDetectorStates[activeDetectorKey] == activeState)
        let normalizedState = try #require(store.weeklyLimitResetDetectorStates[inactiveDetectorKey])
        #expect(normalizedState.resetBoundary == correctedBoundary)
        #expect(normalizedState.wasAboveThreshold)
        #expect(normalizedState.codexEarlyWeeklyResetPending == false)
        #expect(normalizedState.pendingLowConfirmation == false)
        #expect(normalizedState.pendingLowObservedAt == nil)
        #expect(normalizedState.lastPostedResetBoundary == oldReceiptBoundary)
        #expect(normalizedState.notificationReceipt == UsageStore.LimitResetNotificationReceipt(
            resetBoundary: oldReceiptBoundary))
        #expect(normalizedState.lastNotifiedResetBoundary == oldReceiptBoundary)
        #expect(store.snapshots[.codex]?.accountEmail(for: .codex) == emailA)
        #expect(store.planUtilizationHistory == historyBeforeNormalization)
        #expect(store.planUtilizationHistory[.codex]?.preferredAccountKey == "active-owner-a")

        let ordinaryB = codexWeeklyResetSnapshot(
            accountLabel: emailB,
            usedPercent: 11,
            resetsAt: correctedBoundary,
            updatedAt: firstDate.addingTimeInterval(120))
        await store.recordPlanUtilizationHistorySample(
            provider: .codex,
            snapshot: ordinaryB,
            codexLimitResetOwnerKey: ownerB,
            now: ordinaryB.updatedAt)
        #expect(recorder.events.isEmpty)

        let nextBoundary = correctedBoundary.addingTimeInterval(7 * 24 * 3600)
        for offset in [TimeInterval(180), 240] {
            let reset = codexWeeklyResetSnapshot(
                accountLabel: emailB,
                usedPercent: 2,
                resetsAt: nextBoundary,
                updatedAt: firstDate.addingTimeInterval(offset))
            await store.recordPlanUtilizationHistorySample(
                provider: .codex,
                snapshot: reset,
                codexLimitResetOwnerKey: ownerB,
                now: reset.updatedAt)
        }

        #expect(recorder.events.count == 1)
        #expect(recorder.events.first?.usedPercent == 2)
        #expect(notifier.limitResetPosts == [.weekly])
        #expect(store.snapshots[.codex]?.accountEmail(for: .codex) == emailA)
    }
}

private func codexWeeklyResetSnapshot(
    accountLabel: String,
    usedPercent: Double,
    resetsAt: Date?,
    updatedAt: Date,
    loginMethod: String? = "test",
    sessionUsedPercent: Double = 14,
    sessionResetsAt: Date? = nil) -> UsageSnapshot
{
    UsageSnapshot(
        primary: RateWindow(
            usedPercent: usedPercent,
            windowMinutes: 10080,
            resetsAt: resetsAt,
            resetDescription: nil),
        secondary: RateWindow(
            usedPercent: sessionUsedPercent,
            windowMinutes: 300,
            resetsAt: sessionResetsAt,
            resetDescription: nil),
        updatedAt: updatedAt,
        identity: ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: accountLabel,
            accountOrganization: nil,
            loginMethod: loginMethod))
}

@MainActor
private func makeCodexWeeklyResetCorrectionStore(
    notifier: any SessionQuotaNotifying) -> UsageStore
{
    let suiteName = "CodexWeeklyBoundaryCorrectionTests-\(UUID().uuidString)"
    let settings = testSettingsStore(suiteName: suiteName)
    settings.refreshFrequency = .manual
    settings.statusChecksEnabled = false
    let store = UsageStore(
        fetcher: UsageFetcher(),
        browserDetection: BrowserDetection(cacheTTL: 0),
        settings: settings,
        planUtilizationHistoryStore: testPlanUtilizationHistoryStore(suiteName: suiteName),
        sessionQuotaNotifier: notifier,
        startupBehavior: .testing)
    store._cancelPlanUtilizationHistoryLoadForTesting()
    store.planUtilizationHistory = [:]
    return store
}

@MainActor
private final class CodexWeeklyResetNotificationSpy: SessionQuotaNotifying {
    private(set) var limitResetPosts: [QuotaWarningWindow] = []

    func post(transition _: SessionQuotaTransition, provider _: UsageProvider, badge _: NSNumber?) {}

    func postQuotaWarning(
        event _: QuotaWarningEvent,
        provider _: UsageProvider,
        soundEnabled _: Bool,
        onScreenAlertEnabled _: Bool)
    {}

    func postLimitReset(
        provider _: UsageProvider,
        window: QuotaWarningWindow,
        accountDisplayName _: String?,
        isCurrent _: @escaping @MainActor () -> Bool)
    {
        self.limitResetPosts.append(window)
    }
}
