import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct PredictivePaceWarningTests {
    @MainActor
    final class NotifierSpy: SessionQuotaNotifying {
        struct PredictivePost {
            let event: PredictivePaceWarningEvent
            let provider: UsageProvider
            let soundEnabled: Bool
            let onScreenAlertEnabled: Bool
            let now: Date
        }

        private(set) var quotaWarningPosts: [(
            event: QuotaWarningEvent,
            provider: UsageProvider,
            soundEnabled: Bool,
            onScreenAlertEnabled: Bool)] = []
        private(set) var predictivePosts: [PredictivePost] = []

        func post(transition _: SessionQuotaTransition, provider _: UsageProvider, badge _: NSNumber?) {}

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

        func postPredictivePaceWarning(
            event: PredictivePaceWarningEvent,
            provider: UsageProvider,
            soundEnabled: Bool,
            onScreenAlertEnabled: Bool,
            now: Date)
        {
            self.predictivePosts.append(PredictivePost(
                event: event,
                provider: provider,
                soundEnabled: soundEnabled,
                onScreenAlertEnabled: onScreenAlertEnabled,
                now: now))
        }
    }

    @Test
    func `predictive pace warnings default off and persist when enabled`() throws {
        let suite = "PredictivePaceWarningTests-default-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = self.makeSettings(suiteName: suite, clear: false)

        #expect(settings.predictivePaceWarningNotificationsEnabled == false)
        #expect(defaults.object(forKey: "predictivePaceWarningNotificationsEnabled") == nil)

        settings.predictivePaceWarningNotificationsEnabled = true

        #expect(defaults.bool(forKey: "predictivePaceWarningNotificationsEnabled") == true)
        #expect(self.makeSettings(suiteName: suite, clear: false).predictivePaceWarningNotificationsEnabled == true)
    }

    @Test
    func `trigger only accepts at risk pace with positive eta and confident probability`() {
        #expect(PredictivePaceWarningNotificationLogic.shouldNotify(pace: self.pace(
            willLastToReset: false,
            etaSeconds: 60,
            runOutProbability: nil)))
        #expect(PredictivePaceWarningNotificationLogic.shouldNotify(pace: self.pace(
            willLastToReset: false,
            etaSeconds: 60,
            runOutProbability: 0.5)))
        #expect(!PredictivePaceWarningNotificationLogic.shouldNotify(pace: self.pace(
            willLastToReset: true,
            etaSeconds: 60,
            runOutProbability: nil)))
        #expect(!PredictivePaceWarningNotificationLogic.shouldNotify(pace: self.pace(
            willLastToReset: false,
            etaSeconds: nil,
            runOutProbability: nil)))
        #expect(!PredictivePaceWarningNotificationLogic.shouldNotify(pace: self.pace(
            willLastToReset: false,
            etaSeconds: 0,
            runOutProbability: nil)))
        #expect(!PredictivePaceWarningNotificationLogic.shouldNotify(pace: self.pace(
            willLastToReset: false,
            etaSeconds: 60,
            runOutProbability: 0.49)))
    }

    @Test
    func `state machine suppresses repeats until authoritative recovery`() {
        let key = PredictivePaceWarningStateKey(
            provider: .claude,
            accountDiscriminator: "email:person@example.com",
            window: .session,
            resetWindowID: "300:1780000000")
        var notifiedKeys: Set<PredictivePaceWarningStateKey> = []

        #expect(PredictivePaceWarningNotificationLogic.recordObservation(
            key: key,
            pace: self.pace(willLastToReset: false, etaSeconds: 60),
            notifiedKeys: &notifiedKeys))
        #expect(!PredictivePaceWarningNotificationLogic.recordObservation(
            key: key,
            pace: self.pace(willLastToReset: false, etaSeconds: 60),
            notifiedKeys: &notifiedKeys))
        #expect(!PredictivePaceWarningNotificationLogic.recordObservation(
            key: key,
            pace: self.pace(willLastToReset: false, etaSeconds: 60, runOutProbability: 0.2),
            notifiedKeys: &notifiedKeys))
        #expect(notifiedKeys.contains(key))

        #expect(!PredictivePaceWarningNotificationLogic.recordObservation(
            key: key,
            pace: self.pace(willLastToReset: true, etaSeconds: nil),
            notifiedKeys: &notifiedKeys))
        #expect(!notifiedKeys.contains(key))
        #expect(PredictivePaceWarningNotificationLogic.recordObservation(
            key: key,
            pace: self.pace(willLastToReset: false, etaSeconds: 60),
            notifiedKeys: &notifiedKeys))
    }

    @Test
    func `new reset window identity is independent and prunes expired sibling key`() {
        var notifiedKeys: Set<PredictivePaceWarningStateKey> = []
        let oldKey = PredictivePaceWarningStateKey(
            provider: .claude,
            accountDiscriminator: "email:person@example.com",
            window: .weekly,
            resetWindowID: "10080:1780000000")
        let newKey = PredictivePaceWarningStateKey(
            provider: .claude,
            accountDiscriminator: "email:person@example.com",
            window: .weekly,
            resetWindowID: "10080:1780604800")

        #expect(PredictivePaceWarningNotificationLogic.recordObservation(
            key: oldKey,
            pace: self.pace(willLastToReset: false, etaSeconds: 60),
            notifiedKeys: &notifiedKeys))
        PredictivePaceWarningNotificationLogic.pruneSiblingWindowKeys(
            activeKey: newKey,
            notifiedKeys: &notifiedKeys)
        #expect(!notifiedKeys.contains(oldKey))
        #expect(PredictivePaceWarningNotificationLogic.recordObservation(
            key: newKey,
            pace: self.pace(willLastToReset: false, etaSeconds: 60),
            notifiedKeys: &notifiedKeys))
    }

    @Test
    func `store posts once for Claude session and weekly risk then re-arms after recovery`() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let settings = self.makeSettings(suiteName: "PredictivePaceWarningTests-claude-store")
        settings.predictivePaceWarningNotificationsEnabled = true
        settings.quotaWarningSoundEnabled = false
        settings.quotaWarningOnScreenAlertEnabled = true
        let notifier = NotifierSpy()
        let store = self.makeStore(settings: settings, notifier: notifier)

        let atRisk = self.snapshot(
            now: now,
            sessionUsed: 80,
            weeklyUsed: 90,
            accountEmail: "person@example.com")
        store.handlePredictivePaceWarningTransitions(provider: .claude, snapshot: atRisk)
        store.handlePredictivePaceWarningTransitions(provider: .claude, snapshot: atRisk)

        #expect(notifier.predictivePosts.map(\.event.window) == [.session, .weekly])
        #expect(notifier.predictivePosts.allSatisfy { $0.provider == .claude })
        #expect(notifier.predictivePosts.allSatisfy { $0.soundEnabled == false })
        #expect(notifier.predictivePosts.allSatisfy { $0.onScreenAlertEnabled == true })
        #expect(notifier.predictivePosts.allSatisfy { $0.event.accountDisplayName == "person@example.com" })

        let recovered = self.snapshot(
            now: now,
            sessionUsed: 20,
            weeklyUsed: 20,
            accountEmail: "person@example.com")
        store.handlePredictivePaceWarningTransitions(provider: .claude, snapshot: recovered)
        store.handlePredictivePaceWarningTransitions(provider: .claude, snapshot: atRisk)

        #expect(notifier.predictivePosts.map(\.event.window) == [.session, .weekly, .session, .weekly])
    }

    @Test
    func `store posts for Codex session and weekly risk`() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let settings = self.makeSettings(suiteName: "PredictivePaceWarningTests-codex-store")
        settings.predictivePaceWarningNotificationsEnabled = true
        let notifier = NotifierSpy()
        let store = self.makeStore(settings: settings, notifier: notifier)

        let atRisk = self.snapshot(
            now: now,
            sessionUsed: 80,
            weeklyUsed: 90,
            accountEmail: "codex@example.com",
            provider: .codex)
        store.handlePredictivePaceWarningTransitions(provider: .codex, snapshot: atRisk)
        store.handlePredictivePaceWarningTransitions(provider: .codex, snapshot: atRisk)

        #expect(notifier.predictivePosts.map(\.event.window) == [.session, .weekly])
        #expect(notifier.predictivePosts.allSatisfy { $0.provider == .codex })
        #expect(notifier.predictivePosts.allSatisfy { $0.event.accountDisplayName == "codex@example.com" })
    }

    @Test
    func `store isolates risk episodes by account`() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let settings = self.makeSettings(suiteName: "PredictivePaceWarningTests-account-isolation")
        settings.predictivePaceWarningNotificationsEnabled = true
        let notifier = NotifierSpy()
        let store = self.makeStore(settings: settings, notifier: notifier)

        let firstAccount = self.snapshot(
            now: now,
            sessionUsed: 80,
            weeklyUsed: 20,
            accountEmail: "first@example.com")
        let secondAccount = self.snapshot(
            now: now,
            sessionUsed: 80,
            weeklyUsed: 20,
            accountEmail: "second@example.com")

        store.handlePredictivePaceWarningTransitions(provider: .claude, snapshot: firstAccount)
        store.handlePredictivePaceWarningTransitions(provider: .claude, snapshot: firstAccount)
        store.handlePredictivePaceWarningTransitions(provider: .claude, snapshot: secondAccount)
        store.handlePredictivePaceWarningTransitions(provider: .claude, snapshot: firstAccount)

        #expect(notifier.predictivePosts.map(\.event.window) == [.session, .session])
        #expect(notifier.predictivePosts.map(\.event.accountDisplayName) == [
            "first@example.com",
            "second@example.com",
        ])
    }

    @Test
    func `store isolates no-email Claude OAuth risk episodes by owner discriminator`() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let settings = self.makeSettings(suiteName: "PredictivePaceWarningTests-claude-oauth-owner")
        settings.predictivePaceWarningNotificationsEnabled = true
        let notifier = NotifierSpy()
        let store = self.makeStore(settings: settings, notifier: notifier)
        let firstOwner = UsageStore.predictivePaceWarningClaudeOAuthAccountDiscriminator(
            ownerIdentifier: "owner-a")
        let secondOwner = UsageStore.predictivePaceWarningClaudeOAuthAccountDiscriminator(
            ownerIdentifier: "owner-b")
        let snapshot = self.snapshot(
            now: now,
            sessionUsed: 80,
            weeklyUsed: 20,
            accountEmail: nil)

        store.handlePredictivePaceWarningTransitions(
            provider: .claude,
            snapshot: snapshot,
            accountDiscriminatorOverride: firstOwner)
        store.handlePredictivePaceWarningTransitions(
            provider: .claude,
            snapshot: snapshot,
            accountDiscriminatorOverride: firstOwner)
        store.handlePredictivePaceWarningTransitions(
            provider: .claude,
            snapshot: snapshot,
            accountDiscriminatorOverride: secondOwner)

        #expect(notifier.predictivePosts.map(\.event.window) == [.session, .session])
        #expect(notifier.predictivePosts.allSatisfy { $0.provider == .claude })
        #expect(notifier.predictivePosts.allSatisfy { $0.event.accountDisplayName == nil })
    }

    @Test
    func `selected Claude OAuth token account uses owner discriminator when email is missing`() async throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let settings = self.makeSettings(suiteName: "PredictivePaceWarningTests-selected-claude-oauth-owner")
        settings.predictivePaceWarningNotificationsEnabled = true
        settings.addTokenAccount(provider: .claude, label: "Selected", token: "Bearer sk-ant-oat-selected")
        let account = try #require(settings.selectedTokenAccount(for: .claude))
        let notifier = NotifierSpy()
        let store = self.makeStore(settings: settings, notifier: notifier)
        let snapshot = self.snapshot(
            now: now,
            sessionUsed: 80,
            weeklyUsed: 20,
            accountEmail: nil)

        await store.applySelectedOutcome(
            self.claudeOAuthOutcome(snapshot: snapshot, ownerIdentifier: "owner-a"),
            provider: .claude,
            account: account,
            fallbackSnapshot: nil)
        await store.applySelectedOutcome(
            self.claudeOAuthOutcome(snapshot: snapshot, ownerIdentifier: "owner-a"),
            provider: .claude,
            account: account,
            fallbackSnapshot: nil)
        await store.applySelectedOutcome(
            self.claudeOAuthOutcome(snapshot: snapshot, ownerIdentifier: "owner-b"),
            provider: .claude,
            account: account,
            fallbackSnapshot: nil)

        #expect(notifier.predictivePosts.map(\.event.window) == [.session, .session])
        #expect(notifier.predictivePosts.allSatisfy { $0.provider == .claude })
        #expect(notifier.predictivePosts.allSatisfy { $0.event.accountDisplayName == "Selected" })
    }

    @Test
    func `store keeps identity out of copy when personal info is hidden`() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let settings = self.makeSettings(suiteName: "PredictivePaceWarningTests-hidden-info")
        settings.predictivePaceWarningNotificationsEnabled = true
        settings.hidePersonalInfo = true
        let notifier = NotifierSpy()
        let store = self.makeStore(settings: settings, notifier: notifier)

        store.handlePredictivePaceWarningTransitions(
            provider: .claude,
            snapshot: self.snapshot(
                now: now,
                sessionUsed: 80,
                weeklyUsed: 20,
                accountEmail: "person@example.com"))

        #expect(notifier.predictivePosts.first?.event.accountDisplayName == nil)
        let copy = try PredictivePaceWarningNotificationLogic.notificationCopy(
            providerName: "Claude",
            event: #require(notifier.predictivePosts.first?.event),
            now: now)
        #expect(!copy.body.contains("person@example.com"))
    }

    @Test
    func `store ignores providers outside accepted scope`() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let settings = self.makeSettings(suiteName: "PredictivePaceWarningTests-scope")
        settings.predictivePaceWarningNotificationsEnabled = true
        let notifier = NotifierSpy()
        let store = self.makeStore(settings: settings, notifier: notifier)

        store.handlePredictivePaceWarningTransitions(
            provider: .zai,
            snapshot: self.snapshot(now: now, sessionUsed: 80, weeklyUsed: 90, accountEmail: "person@example.com"))

        #expect(notifier.predictivePosts.isEmpty)
    }

    private func makeSettings(suiteName: String, clear: Bool = true) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suiteName)!
        if clear {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suiteName),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
    }

    private func makeStore(settings: SettingsStore, notifier: NotifierSpy) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier)
    }

    private func claudeOAuthOutcome(snapshot: UsageSnapshot, ownerIdentifier: String) -> ProviderFetchOutcome {
        ProviderFetchOutcome(
            result: .success(ProviderFetchResult(
                usage: snapshot,
                credits: nil,
                dashboard: nil,
                sourceLabel: "oauth",
                strategyID: "claude-oauth",
                strategyKind: .oauth,
                claudeOAuthHistoryOwnerIdentifier: ownerIdentifier)),
            attempts: [])
    }

    private func snapshot(
        now: Date,
        sessionUsed: Double,
        weeklyUsed: Double,
        accountEmail: String?,
        provider: UsageProvider = .claude) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: sessionUsed,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(2 * 3600),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: weeklyUsed,
                windowMinutes: 7 * 24 * 60,
                resetsAt: now.addingTimeInterval(2 * 24 * 3600),
                resetDescription: nil),
            updatedAt: now,
            identity: ProviderIdentitySnapshot(
                providerID: provider,
                accountEmail: accountEmail,
                accountOrganization: nil,
                loginMethod: nil))
    }

    private func pace(
        willLastToReset: Bool,
        etaSeconds: TimeInterval?,
        runOutProbability: Double? = nil) -> UsagePace
    {
        UsagePace(
            stage: willLastToReset ? .onTrack : .ahead,
            deltaPercent: willLastToReset ? 0 : 20,
            expectedUsedPercent: 50,
            actualUsedPercent: willLastToReset ? 40 : 70,
            etaSeconds: etaSeconds,
            willLastToReset: willLastToReset,
            runOutProbability: runOutProbability)
    }
}
