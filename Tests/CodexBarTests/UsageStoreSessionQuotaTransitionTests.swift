import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct UsageStoreSessionQuotaTransitionTests {
    final class SessionQuotaNotifierSpy: SessionQuotaNotifying {
        private(set) var posts: [(transition: SessionQuotaTransition, provider: UsageProvider)] = []
        private(set) var quotaWarningPosts: [(event: QuotaWarningEvent, provider: UsageProvider)] = []

        func post(transition: SessionQuotaTransition, provider: UsageProvider, badge _: NSNumber?) {
            self.posts.append((transition, provider))
        }

        func postQuotaWarning(
            event: QuotaWarningEvent,
            provider: UsageProvider,
            soundEnabled _: Bool,
            onScreenAlertEnabled _: Bool)
        {
            self.quotaWarningPosts.append((event, provider))
        }
    }

    @Test
    func `weekly primary does not masquerade as a session quota`() {
        let (store, notifier) = self.makeStore(suite: "SessionQuotaTransitionTests-weekly")
        store.handleSessionQuotaTransition(
            provider: .claude,
            snapshot: Self.snapshot(used: 20, windowMinutes: 7 * 24 * 60))
        store.handleSessionQuotaTransition(
            provider: .claude,
            snapshot: Self.snapshot(used: 100, windowMinutes: 7 * 24 * 60))

        #expect(notifier.posts.isEmpty)
    }

    @Test(arguments: [UsageProvider.claude, .cursor, .grok])
    func `retained providers use generic short primary session windows`(provider: UsageProvider) {
        let (store, notifier) = self.makeStore(suite: "SessionQuotaTransitionTests-\(provider.rawValue)")
        store.handleSessionQuotaTransition(provider: provider, snapshot: Self.snapshot(used: 20, windowMinutes: 300))
        store.handleSessionQuotaTransition(provider: provider, snapshot: Self.snapshot(used: 100, windowMinutes: 300))

        #expect(notifier.posts.map(\.provider) == [provider])
        #expect(notifier.posts.map(\.transition) == [.depleted])
    }

    @Test
    func `quota warning posts once per downward threshold crossing`() {
        let (store, notifier) = self.makeStore(suite: "SessionQuotaTransitionTests-warning")
        store.settings.quotaWarningNotificationsEnabled = true
        store.settings.quotaWarningThresholds = [50, 20]
        store.settings.setQuotaWarningWindowEnabled(.session, enabled: true)

        for used in [40.0, 55.0, 60.0] {
            store.handleQuotaWarningTransitions(
                provider: .codex,
                snapshot: Self.snapshot(used: used, windowMinutes: 300))
        }

        #expect(notifier.quotaWarningPosts.count == 1)
        #expect(notifier.quotaWarningPosts.first?.event.threshold == 50)
        #expect(notifier.quotaWarningPosts.first?.provider == .codex)
    }

    @Test
    func `disabling a warning window clears its fired state`() {
        let (store, notifier) = self.makeStore(suite: "SessionQuotaTransitionTests-warning-clear")
        store.settings.quotaWarningNotificationsEnabled = true
        store.settings.quotaWarningThresholds = [50]
        store.settings.setQuotaWarningWindowEnabled(.session, enabled: true)

        store.handleQuotaWarningTransitions(provider: .codex, snapshot: Self.snapshot(used: 40, windowMinutes: 300))
        store.handleQuotaWarningTransitions(provider: .codex, snapshot: Self.snapshot(used: 60, windowMinutes: 300))
        store.settings.setQuotaWarningWindowEnabled(.session, enabled: false)
        store.handleQuotaWarningTransitions(provider: .codex, snapshot: Self.snapshot(used: 60, windowMinutes: 300))

        #expect(notifier.quotaWarningPosts.count == 1)
        #expect(store.quotaWarningState[
            UsageStore.QuotaWarningStateKey(provider: .codex, window: .session, accountDiscriminator: nil),
        ] == nil)
    }

    private func makeStore(suite: String) -> (UsageStore, SessionQuotaNotifierSpy) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite))
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.sessionQuotaNotificationsEnabled = true
        let notifier = SessionQuotaNotifierSpy()
        return (
            UsageStore(
                fetcher: UsageFetcher(environment: [:]),
                browserDetection: BrowserDetection(cacheTTL: 0),
                settings: settings,
                sessionQuotaNotifier: notifier),
            notifier)
    }

    private static func snapshot(used: Double, windowMinutes: Int) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: used,
                windowMinutes: windowMinutes,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
    }
}
