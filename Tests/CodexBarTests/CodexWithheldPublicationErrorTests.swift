import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
extension CodexAccountScopedRefreshTests {
    @Test
    func `withheld weekly reset clears the failure recorded before it`() async throws {
        let suite = "CodexWithheldPublicationErrorTests-clears-stale-failure"
        let email = "withheld-stale-failure@example.com"
        let settings = self.makeSettingsStore(suite: suite)
        settings.refreshFrequency = .manual
        settings.codexCookieSource = .off
        settings._test_liveSystemCodexAccount = self.liveAccount(
            email: email,
            identity: .providerAccount(id: "acct-withheld-stale-failure"))
        defer { settings._test_liveSystemCodexAccount = nil }

        let now = Date()
        let priorBoundary = now.addingTimeInterval(2 * 24 * 60 * 60)
        let nextBoundary = priorBoundary.addingTimeInterval(7 * 24 * 60 * 60)
        let creditExpiry = nextBoundary.addingTimeInterval(24 * 60 * 60)
        let prior = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 81,
            weeklyReset: priorBoundary,
            updatedAt: now.addingTimeInterval(-600),
            resetCredits: withheldPublicationResetCredits(
                capturedAt: now.addingTimeInterval(-600),
                expiresAt: creditExpiry),
            dataConfidence: .exact)
        let postReset = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 0,
            weeklyReset: nextBoundary,
            updatedAt: now.addingTimeInterval(-60),
            resetCredits: withheldPublicationResetCredits(
                capturedAt: now.addingTimeInterval(-60),
                expiresAt: creditExpiry),
            dataConfidence: .exact)

        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-withheld-error-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }
        let snapshotStore = FileCodexAccountUsageSnapshotStore(fileURL: snapshotURL)

        let seedStore = self.makeCodexWeeklyPublicationStore(
            settings: settings,
            suite: suite,
            snapshotStore: snapshotStore)
        self.installContextualCodexProvider(on: seedStore, sourceLabel: "oauth", kind: .oauth) { _ in prior }
        await seedStore.refreshProvider(.codex, allowDisabled: true)
        #expect(seedStore.errors[.codex] == nil)

        let visibleAccounts = settings.codexVisibleAccountProjection.visibleAccounts
        let seeded = try #require(snapshotStore.load(for: visibleAccounts).first)
        snapshotStore.store([CodexAccountUsageSnapshot(
            account: seeded.account,
            snapshot: seeded.snapshot,
            error: "Network error: The Internet connection appears to be offline.",
            sourceLabel: seeded.sourceLabel,
            credits: seeded.credits)])
        let persistedFailure = try #require(snapshotStore.load(for: visibleAccounts).first)
        #expect(persistedFailure.error != nil)
        #expect(persistedFailure.snapshot?.updatedAt == prior.updatedAt)

        let relaunchedStore = self.makeCodexWeeklyPublicationStore(
            settings: settings,
            suite: suite,
            snapshotStore: snapshotStore)
        self.installContextualCodexProvider(on: relaunchedStore, sourceLabel: "oauth", kind: .oauth) { _ in
            postReset
        }
        await CodexWeeklyResetConfirmation.$observationDateOverride.withValue(postReset.updatedAt) {
            await relaunchedStore.refreshProvider(.codex, allowDisabled: true)
        }

        #expect(relaunchedStore.snapshots[.codex]?.updatedAt == prior.updatedAt)
        #expect(relaunchedStore.errors[.codex] == nil)
        let persistedAfterWithhold = try #require(snapshotStore.load(
            for: settings.codexVisibleAccountProjection.visibleAccounts).first)
        #expect(persistedAfterWithhold.error == nil)
        #expect(persistedAfterWithhold.snapshot?.updatedAt == prior.updatedAt)
    }

    @Test
    func `withheld publication keeps a failure recorded by the same refresh`() async {
        let suite = "CodexWithheldPublicationErrorTests-keeps-current-failure"
        let email = "withheld-current-failure@example.com"
        let settings = self.makeSettingsStore(suite: suite)
        settings.refreshFrequency = .manual
        settings.codexCookieSource = .off
        settings._test_liveSystemCodexAccount = self.liveAccount(
            email: email,
            identity: .providerAccount(id: "acct-withheld-current-failure"))
        defer { settings._test_liveSystemCodexAccount = nil }

        let now = Date()
        let prior = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 81,
            weeklyReset: now.addingTimeInterval(2 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-600),
            dataConfidence: .exact)

        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-withheld-error-current-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }
        let snapshotStore = FileCodexAccountUsageSnapshotStore(fileURL: snapshotURL)

        let seedStore = self.makeCodexWeeklyPublicationStore(
            settings: settings,
            suite: suite,
            snapshotStore: snapshotStore)
        self.installContextualCodexProvider(on: seedStore, sourceLabel: "oauth", kind: .oauth) { _ in prior }
        await seedStore.refreshProvider(.codex, allowDisabled: true)

        let failingStore = self.makeCodexWeeklyPublicationStore(
            settings: settings,
            suite: suite,
            snapshotStore: snapshotStore)
        self.installContextualCodexProvider(on: failingStore, sourceLabel: "oauth", kind: .oauth) { _ in
            throw withheldPublicationNetworkError()
        }
        await failingStore.refreshProvider(.codex, allowDisabled: true)
        await failingStore.refreshProvider(.codex, allowDisabled: true)

        #expect(failingStore.errors[.codex] != nil)
        #expect(failingStore.snapshots[.codex]?.updatedAt == prior.updatedAt)
    }

    @Test
    func `a withheld success restores first-failure suppression`() async {
        let suite = "CodexWithheldPublicationErrorTests-gate-recovery"
        let email = "withheld-gate-recovery@example.com"
        let settings = self.makeSettingsStore(suite: suite)
        settings.refreshFrequency = .manual
        settings.codexCookieSource = .off
        settings._test_liveSystemCodexAccount = self.liveAccount(
            email: email,
            identity: .providerAccount(id: "acct-withheld-gate-recovery"))
        defer { settings._test_liveSystemCodexAccount = nil }

        let now = Date()
        let priorBoundary = now.addingTimeInterval(2 * 24 * 60 * 60)
        let nextBoundary = priorBoundary.addingTimeInterval(7 * 24 * 60 * 60)
        let creditExpiry = nextBoundary.addingTimeInterval(24 * 60 * 60)
        let prior = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 81,
            weeklyReset: priorBoundary,
            updatedAt: now.addingTimeInterval(-600),
            resetCredits: withheldPublicationResetCredits(
                capturedAt: now.addingTimeInterval(-600),
                expiresAt: creditExpiry),
            dataConfidence: .exact)
        let postReset = self.codexWeeklySnapshot(
            email: email,
            weeklyUsedPercent: 0,
            weeklyReset: nextBoundary,
            updatedAt: now.addingTimeInterval(-60),
            resetCredits: withheldPublicationResetCredits(
                capturedAt: now.addingTimeInterval(-60),
                expiresAt: creditExpiry),
            dataConfidence: .exact)

        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-withheld-gate-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }
        let snapshotStore = FileCodexAccountUsageSnapshotStore(fileURL: snapshotURL)

        let seedStore = self.makeCodexWeeklyPublicationStore(
            settings: settings,
            suite: suite,
            snapshotStore: snapshotStore)
        self.installContextualCodexProvider(on: seedStore, sourceLabel: "oauth", kind: .oauth) { _ in prior }
        await seedStore.refreshProvider(.codex, allowDisabled: true)

        let script = WithheldPublicationFetchScript(success: postReset)
        let store = self.makeCodexWeeklyPublicationStore(
            settings: settings,
            suite: suite,
            snapshotStore: snapshotStore)
        self.installContextualCodexProvider(on: store, sourceLabel: "oauth", kind: .oauth) { _ in
            try await script.load()
        }

        await store.refreshProvider(.codex, allowDisabled: true)
        await store.refreshProvider(.codex, allowDisabled: true)
        #expect(store.errors[.codex] != nil)

        await script.setFailing(false)
        await CodexWeeklyResetConfirmation.$observationDateOverride.withValue(postReset.updatedAt) {
            await store.refreshProvider(.codex, allowDisabled: true)
        }
        #expect(store.errors[.codex] == nil)
        #expect(store.snapshots[.codex]?.updatedAt == prior.updatedAt)

        await script.setFailing(true)
        await store.refreshProvider(.codex, allowDisabled: true)
        #expect(store.errors[.codex] == nil)
        #expect(store.snapshots[.codex]?.updatedAt == prior.updatedAt)
    }

    @Test
    func `a withheld publication clears only a connectivity claim`() {
        #expect(UsageStore.shouldPreserveCodexAccountSnapshotOnFailure(
            "Network error: The Internet connection appears to be offline."))
        #expect(UsageStore.shouldPreserveCodexAccountSnapshotOnFailure("Request timed out"))
        #expect(!UsageStore.shouldPreserveCodexAccountSnapshotOnFailure("prior error"))
        #expect(!UsageStore.shouldPreserveCodexAccountSnapshotOnFailure("401 unauthorized"))
        #expect(!UsageStore.shouldPreserveCodexAccountSnapshotOnFailure("Workspace deactivated"))
    }
}

private func withheldPublicationNetworkError() -> Error {
    NSError(
        domain: NSURLErrorDomain,
        code: NSURLErrorNotConnectedToInternet,
        userInfo: [
            NSLocalizedDescriptionKey: "Network error: The Internet connection appears to be offline.",
        ])
}

private actor WithheldPublicationFetchScript {
    private var failing = true
    private let success: UsageSnapshot

    init(success: UsageSnapshot) {
        self.success = success
    }

    func setFailing(_ value: Bool) {
        self.failing = value
    }

    func load() throws -> UsageSnapshot {
        if self.failing {
            throw withheldPublicationNetworkError()
        }
        return self.success
    }
}

private func withheldPublicationResetCredits(
    capturedAt: Date,
    expiresAt: Date) -> CodexRateLimitResetCreditsSnapshot
{
    CodexRateLimitResetCreditsSnapshot(
        credits: [CodexRateLimitResetCredit(
            id: "withheld-publication-reset-credit",
            resetType: "codex_rate_limits",
            status: .available,
            grantedAt: capturedAt.addingTimeInterval(-24 * 60 * 60),
            expiresAt: expiresAt,
            redeemStartedAt: nil,
            redeemedAt: nil,
            title: nil,
            description: nil)],
        availableCount: 1,
        updatedAt: capturedAt)
}
