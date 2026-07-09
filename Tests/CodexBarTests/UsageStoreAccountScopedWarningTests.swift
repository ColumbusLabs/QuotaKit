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
    func `session quota transitions are scoped by account discriminator`() {
        let settings = self.makeSettings(suiteName: "UsageStoreAccountScopedWarningTests-session")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.sessionQuotaNotificationsEnabled = true

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

        store.handleSessionQuotaTransition(
            provider: .codex,
            snapshot: baseline,
            accountDiscriminatorOverride: "account-a")
        store.handleSessionQuotaTransition(
            provider: .codex,
            snapshot: baseline,
            accountDiscriminatorOverride: "account-b")
        store.handleSessionQuotaTransition(
            provider: .codex,
            snapshot: depleted,
            accountDiscriminatorOverride: "account-a")
        store.handleSessionQuotaTransition(
            provider: .codex,
            snapshot: depleted,
            accountDiscriminatorOverride: "account-b")

        #expect(notifier.posts.count == 2)
    }
}
