import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct ProviderQuotaSignalTests {
    private final class NotifierSpy: SessionQuotaNotifying {
        private(set) var warnings: [(UsageProvider, QuotaWarningEvent)] = []

        func post(transition _: SessionQuotaTransition, provider _: UsageProvider, badge _: NSNumber?) {}

        func postQuotaWarning(
            event: QuotaWarningEvent,
            provider: UsageProvider,
            soundEnabled _: Bool,
            onScreenAlertEnabled _: Bool)
        {
            self.warnings.append((provider, event))
        }
    }

    @Test
    func `Chatbox plan remains a session quota while prepaid secondary meter stays out of warnings and hooks`() {
        let settings = self.settings("ProviderQuotaSignalTests-chatbox")
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50]
        settings.setQuotaWarningWindowEnabled(.session, enabled: true)
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)
        settings.setHooksEnabled(true)
        settings.addHookRule(HookRule(
            event: .quotaLow,
            provider: UsageProvider.chatbox.rawValue,
            threshold: 1,
            executable: "/usr/bin/true"))
        let notifier = NotifierSpy()
        let store = self.store(settings: settings, notifier: notifier)
        let quotaLowSession = UsageStore.QuotaLowHookStateKey(provider: .chatbox, window: .session)
        let quotaLowWeekly = UsageStore.QuotaLowHookStateKey(provider: .chatbox, window: .weekly)

        store.handleQuotaWarningTransitions(
            provider: .chatbox,
            snapshot: Self.snapshot(primaryUsed: 40, secondaryUsed: 40, time: 1))
        store.handleQuotaWarningTransitions(
            provider: .chatbox,
            snapshot: Self.snapshot(primaryUsed: 55, secondaryUsed: 90, time: 2))

        #expect(notifier.warnings.map { $0.1.window } == [.session])
        #expect(store.quotaWarningState[.init(provider: .chatbox, window: .weekly, accountDiscriminator: nil)] == nil)
        #expect(store.quotaLowHookUsage[quotaLowSession] == 0.55)
        #expect(store.quotaLowHookUsage[quotaLowWeekly] == nil)
    }

    @Test
    func `Abliteration prepaid usage does not enter quota warnings hooks or session transitions`() {
        let settings = self.settings("ProviderQuotaSignalTests-abliteration")
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50]
        settings.setQuotaWarningWindowEnabled(.session, enabled: true)
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)
        settings.sessionQuotaNotificationsEnabled = true
        settings.setHooksEnabled(true)
        settings.addHookRule(HookRule(
            event: .quotaLow,
            provider: UsageProvider.abliteration.rawValue,
            threshold: 0.5,
            executable: "/usr/bin/true"))
        settings.addHookRule(HookRule(
            event: .quotaReached,
            provider: UsageProvider.abliteration.rawValue,
            executable: "/usr/bin/true"))
        let notifier = NotifierSpy()
        let store = self.store(settings: settings, notifier: notifier)
        let quotaLowSession = UsageStore.QuotaLowHookStateKey(provider: .abliteration, window: .session)
        let quotaLowWeekly = UsageStore.QuotaLowHookStateKey(provider: .abliteration, window: .weekly)

        store.handleQuotaWarningTransitions(
            provider: .abliteration,
            snapshot: Self.snapshot(primaryUsed: 40, secondaryUsed: 10, time: 1))
        store.handleQuotaWarningTransitions(
            provider: .abliteration,
            snapshot: Self.snapshot(primaryUsed: 95, secondaryUsed: 90, time: 2))
        let transitionPosted = store.handleSessionQuotaTransition(
            provider: .abliteration,
            snapshot: Self.snapshot(primaryUsed: 100, secondaryUsed: 90, time: 3))

        #expect(notifier.warnings.isEmpty)
        #expect(!transitionPosted)
        #expect(store.sessionQuotaTransitionStates[.init(provider: .abliteration)] == nil)
        #expect(store.quotaLowHookUsage[quotaLowSession] == nil)
        #expect(store.quotaLowHookUsage[quotaLowWeekly] == nil)
    }

    @Test
    func `Abliteration retains billing detail outside its quota signal projection`() throws {
        let store = self.store(
            settings: self.settings("ProviderQuotaSignalTests-abliteration-window"),
            notifier: NotifierSpy())
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 40, windowMinutes: nil, resetsAt: nil, resetDescription: "$4.00 / $10.00"),
            secondary: nil,
            details: [try ProviderDetailSection(title: "Credits", rows: [
                try ProviderDetailSection.Row(label: "Balance", value: "$6.00"),
            ])],
            updatedAt: Date(timeIntervalSince1970: 1))
        #expect(store.sessionQuotaWindow(provider: .abliteration, snapshot: snapshot) == nil)
        #expect(snapshot.primary?.usedPercent == 40)
        #expect(snapshot.details.first?.rows.first?.value == "$6.00")
    }

    private func settings(_ suiteName: String) -> SettingsStore {
        let settings = testSettingsStore(suiteName: suiteName)
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        return settings
    }

    private func store(settings: SettingsStore, notifier: NotifierSpy) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier,
            environmentBase: [:],
            startupBehavior: .testing)
    }

    private static func snapshot(primaryUsed: Double, secondaryUsed: Double, time: Double) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: primaryUsed,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: secondaryUsed,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: nil),
            updatedAt: Date(timeIntervalSince1970: time))
    }
}
