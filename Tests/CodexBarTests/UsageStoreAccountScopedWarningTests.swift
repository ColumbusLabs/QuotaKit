import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct UsageStoreAccountScopedWarningTests {
    private func makeSettings(suiteName: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suiteName),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    @MainActor
    final class SessionQuotaNotifierSpy: SessionQuotaNotifying {
        private(set) var posts: [(transition: SessionQuotaTransition, provider: UsageProvider)] = []
        private(set) var quotaWarningPosts: [(
            event: QuotaWarningEvent,
            provider: UsageProvider,
            soundEnabled: Bool,
            onScreenAlertEnabled: Bool)] = []

        func post(transition: SessionQuotaTransition, provider: UsageProvider, badge _: NSNumber?) {
            self.posts.append((transition: transition, provider: provider))
        }

        func postQuotaWarning(
            event: QuotaWarningEvent,
            provider: UsageProvider,
            soundEnabled: Bool,
            onScreenAlertEnabled: Bool)
        {
            self.quotaWarningPosts.append((
                event: event,
                provider: provider,
                soundEnabled: soundEnabled,
                onScreenAlertEnabled: onScreenAlertEnabled))
        }
    }

    @Test
    func `quota warnings are scoped by account discriminator`() {
        let settings = self.makeSettings(suiteName: "UsageStoreAccountScopedWarningTests-warning")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.notificationPushToiOSEnabled = false
        settings.quotaWarningThresholds = [50]
        settings.setQuotaWarningWindowEnabled(.session, enabled: true)

        let notifier = SessionQuotaNotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier)
        let baseline = UsageSnapshot(
            primary: RateWindow(usedPercent: 40, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        let crossed = UsageSnapshot(
            primary: RateWindow(usedPercent: 55, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())

        store.handleQuotaWarningTransitions(
            provider: .codex,
            snapshot: baseline,
            accountDiscriminatorOverride: "account-a")
        store.handleQuotaWarningTransitions(
            provider: .codex,
            snapshot: baseline,
            accountDiscriminatorOverride: "account-b")
        store.handleQuotaWarningTransitions(
            provider: .codex,
            snapshot: crossed,
            accountDiscriminatorOverride: "account-a")
        store.handleQuotaWarningTransitions(
            provider: .codex,
            snapshot: crossed,
            accountDiscriminatorOverride: "account-b")

        #expect(notifier.quotaWarningPosts.count == 2)
    }

    @Test
    func `session quota transitions are scoped by account discriminator`() throws {
        let settings = self.makeSettings(suiteName: "UsageStoreAccountScopedWarningTests-session")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.sessionQuotaNotificationsEnabled = true
        settings.notificationPushToiOSEnabled = false

        let notifier = SessionQuotaNotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier)
        let baseline = UsageSnapshot(
            primary: RateWindow(usedPercent: 40, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        let depleted = UsageSnapshot(
            primary: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        let owner = try #require(CodexSessionQuotaOwnerKey(refreshGuard: CodexAccountScopedRefreshGuard(
            source: .liveSystem,
            identity: .providerAccount(id: "workspace-fixture"),
            accountKey: "session-fixture@example.test")))

        store.handleSessionQuotaTransition(
            provider: .codex,
            snapshot: baseline,
            codexOwnerKey: owner,
            accountDiscriminatorOverride: "account-a")
        store.handleSessionQuotaTransition(
            provider: .codex,
            snapshot: baseline,
            codexOwnerKey: owner,
            accountDiscriminatorOverride: "account-b")
        store.handleSessionQuotaTransition(
            provider: .codex,
            snapshot: depleted,
            codexOwnerKey: owner,
            accountDiscriminatorOverride: "account-a")
        store.handleSessionQuotaTransition(
            provider: .codex,
            snapshot: depleted,
            codexOwnerKey: owner,
            accountDiscriminatorOverride: "account-b")

        #expect(notifier.posts.count == 2)
    }

    @Test
    func `selected token outcomes preserve independent session quota transitions`() async throws {
        let settings = self.makeSettings(suiteName: "UsageStoreAccountScopedWarningTests-selected-session")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.sessionQuotaNotificationsEnabled = true
        settings.notificationPushToiOSEnabled = false

        let accounts = try [
            ProviderTokenAccount(
                id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000011")),
                label: "First",
                token: "fixture",
                addedAt: 0,
                lastUsed: nil),
            ProviderTokenAccount(
                id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000012")),
                label: "Second",
                token: "fixture",
                addedAt: 0,
                lastUsed: nil),
        ]
        let notifier = SessionQuotaNotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier,
            startupBehavior: .testing)

        for (step, account) in accounts.enumerated() {
            await store.applySelectedOutcome(
                Self.outcome(usedPercent: 40, updatedAt: Date(timeIntervalSince1970: 1_780_100_000 + Double(step))),
                provider: .deepseek,
                account: account,
                fallbackSnapshot: nil)
        }
        for (step, account) in accounts.enumerated() {
            await store.applySelectedOutcome(
                Self.outcome(usedPercent: 100, updatedAt: Date(timeIntervalSince1970: 1_780_100_100 + Double(step))),
                provider: .deepseek,
                account: account,
                fallbackSnapshot: nil)
        }

        #expect(notifier.posts.map(\.transition) == [.depleted, .depleted])
    }

    private static func outcome(usedPercent: Double, updatedAt: Date) -> ProviderFetchOutcome {
        ProviderFetchOutcome(
            result: .success(ProviderFetchResult(
                usage: UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: usedPercent,
                        windowMinutes: 300,
                        resetsAt: nil,
                        resetDescription: nil),
                    secondary: nil,
                    updatedAt: updatedAt),
                credits: nil,
                dashboard: nil,
                sourceLabel: "fixture",
                strategyID: "fixture.api-token",
                strategyKind: .apiToken)),
            attempts: [])
    }
}
