import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct ClaudeCredentialQuotaWarningTests {
    private final class NotifierSpy: SessionQuotaNotifying {
        var thresholds: [Int] = []

        func post(transition _: SessionQuotaTransition, provider _: UsageProvider, badge _: NSNumber?) {}

        func postQuotaWarning(
            event: QuotaWarningEvent,
            provider _: UsageProvider,
            soundEnabled _: Bool,
            onScreenAlertEnabled _: Bool)
        {
            self.thresholds.append(event.threshold)
        }
    }

    @Test(arguments: [true, false])
    func `credential rewrites preserve known account threshold episodes`(hasActiveAccount: Bool) async throws {
        try await self.checkRefreshes(
            activeAccount: hasActiveAccount ? "fixture-account-a" : nil,
            historyOwner: "fixture-oauth-owner",
            expectedThresholds: [50, 50, 20])
    }

    @Test
    func `credential rewrites preserve unresolved account threshold episodes`() async throws {
        try await self.checkRefreshes(
            activeAccount: nil,
            historyOwner: nil,
            expectedThresholds: [50, 50, 20])
    }

    @Test(arguments: [true, false], ["session", "weekly", "scoped"])
    func `repeated CLI identity gaps keep independent warning histories`(hasReset: Bool, lane: String) throws {
        try self.checkIdentitySamples(
            [49.0, 48, 47, 46, 45, 44].enumerated().map { index, remaining in
                (index.isMultiple(of: 2) ? "account-a" : nil, remaining, hasReset ? 3600 : nil)
            },
            expectedThresholds: hasReset ? [50] : [50, 50],
            lane: lane)
    }

    @Test
    func `promoted weekly usage does not fire session quota warning`() throws {
        try self.checkIdentitySamples(
            [("account-a", 49, 3600)],
            expectedThresholds: [],
            lane: "promoted")
    }

    @Test(arguments: [true, false], [true, false])
    func `later thresholds do not repeat across either identity key`(hasReset: Bool, crossingIsKnown: Bool) throws {
        let remaining = crossingIsKnown ? [49.0, 48, 19, 18, 17, 16] : [49.0, 48, 47, 19, 18, 17]
        try self.checkIdentitySamples(
            remaining.enumerated().map { index, value in
                (index.isMultiple(of: 2) ? "account-a" : nil, value, hasReset ? 3600 : nil)
            },
            expectedThresholds: hasReset ? [50, 20] : [50, 50, 20])
    }

    @Test(arguments: ["reset", "increase", "missing"])
    func `discontinuous identity gaps start one independent fallback episode`(discontinuity: String) throws {
        let reset: TimeInterval? = discontinuity == "missing" ? nil : (discontinuity == "reset" ? 7200 : 3600)
        var samples: [(identity: String?, remaining: Double, reset: TimeInterval?)] = [
            ("account-a", 40, 3600),
            (nil, discontinuity == "increase" ? 49 : 39, reset),
            ("account-a", 38, 3600),
            (nil, discontinuity == "increase" ? 49 : 37, reset),
            ("account-a", 36, 3600),
            (nil, discontinuity == "increase" ? 49 : 35, reset),
        ]
        if discontinuity == "increase" {
            // Exercise the 20% threshold after the independent fallback episode begins.
            samples.append((nil, 19, reset))
        }
        try self.checkIdentitySamples(
            samples,
            expectedThresholds: discontinuity == "increase" ? [50, 50, 20] : [50, 50])
    }

    @Test
    func `identity gaps follow the most recently verified account without merging known accounts`() throws {
        try self.checkIdentitySamples(
            [
                ("account-a", 49, 3600),
                ("account-b", 48, 3600),
                (nil, 47, 3600),
                ("account-a", 46, 3600),
                (nil, 45, 3600),
                ("account-b", 44, 3600),
                (nil, 43, 3600),
            ],
            expectedThresholds: [50, 50])
    }

    @Test
    func `unresolved warning migrates when a later stable account is observed`() throws {
        try self.checkIdentitySamples(
            [(nil, 49, 3600), ("account-b", 48, 7200), (nil, 47, 3600)],
            expectedThresholds: [50])
    }

    @Test
    func `known warning history continues through a same-cycle identity gap`() throws {
        try self.checkIdentitySamples(
            [("account-a", 49, 3600), (nil, 48, 3600), ("account-a", 47, 3600)],
            expectedThresholds: [50])
    }

    @Test(arguments: [true, false])
    func `unresolved and known histories survive repeated quota recovery`(hasReset: Bool) throws {
        let reset: TimeInterval? = hasReset ? 3600 : nil
        try self.checkIdentitySamples(
            [
                (nil, 49, reset),
                ("account-a", 48, reset),
                (nil, 47, reset),
                ("account-a", 19, reset),
                (nil, 18, reset),
                ("account-a", 60, reset),
                (nil, 49, reset),
                ("account-a", 48, reset),
                (nil, 47, reset),
            ],
            expectedThresholds: [50, 20, 50])
    }

    private func checkIdentitySamples(
        _ samples: [(identity: String?, remaining: Double, reset: TimeInterval?)],
        expectedThresholds: [Int],
        lane: String = "session") throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeRepeatedIdentityGapTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = ["HOME": root.path, "CLAUDE_CONFIG_DIR": root.path]
        let settings = try self.makeSettings(root: root)
        defer { settings.configFileWatcher?.stop() }
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)
        let notifier = NotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier,
            startupBehavior: .testing,
            environmentBase: environment)
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        for (index, sample) in samples.enumerated() {
            let scopes = store.warningClaudeAccountDiscriminators(
                strategyKind: .cli,
                observation: .stable(identity: sample.identity))
            let window = RateWindow(
                usedPercent: 100 - sample.remaining,
                windowMinutes: lane == "session" ? 300 : 10080,
                resetsAt: sample.reset.map { now.addingTimeInterval($0) },
                resetDescription: nil)
            store.handleQuotaWarningTransitions(
                provider: .claude,
                snapshot: UsageSnapshot(
                    primary: lane == "session" || lane == "promoted" ? window : nil,
                    secondary: lane == "weekly" ? window : nil,
                    extraRateWindows: lane == "scoped"
                        ? [NamedRateWindow(id: "claude-weekly-scoped-fable", title: "Fable", window: window)] : nil,
                    updatedAt: now.addingTimeInterval(Double(index))),
                accountDiscriminator: scopes.quota,
                hookAccountDiscriminator: scopes.source,
                requiresKnownAccount: true)
        }
        #expect(notifier.thresholds == expectedThresholds)
    }

    private func checkRefreshes(
        activeAccount: String?,
        historyOwner: String?,
        expectedThresholds: [Int]) async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCredentialQuotaWarningTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = ["HOME": root.path, "CLAUDE_CONFIG_DIR": root.path]
        let settings = try self.makeSettings(root: root)
        defer { settings.configFileWatcher?.stop() }
        let notifier = NotifierSpy()
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier,
            startupBehavior: .testing,
            environmentBase: environment)
        let otherAccount = UsageStore.QuotaWarningStateKey(
            provider: .claude, window: .session, accountDiscriminator: "other-account")
        let otherProvider = UsageStore.QuotaWarningStateKey(
            provider: .deepseek, window: .session, accountDiscriminator: nil)
        for key in [otherAccount, otherProvider] {
            store.quotaWarningState[key] = UsageStore.QuotaWarningState(lastRemaining: 40, firedThresholds: [50])
        }
        let file = root.appendingPathComponent("credentials.json")
        let pending = ClaudeOAuthCredentialsStore.PendingCacheClearMemoryStore()
        try await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.never) {
            try await ClaudeOAuthCredentialsStore.withPendingCacheClearStoreOverrideForTesting(pending) { @Sendable in
                try await ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting { @Sendable in
                    try await ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting { @Sendable in
                        try await ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(file) { @Sendable in
                            try await UsageStore.withActiveClaudeAccountUuidForTesting(activeAccount) { @MainActor in
                                for (index, remaining) in [60.0, 49, 48, 47, 60, 49, 19].enumerated() {
                                    // A size change proves a fresh fingerprint without filesystem timing assumptions.
                                    let credentials: [String: Any] = ["claudeAiOauth": [
                                        "accessToken": "fixture-" + String(repeating: "x", count: index + 1),
                                        "expiresAt": 1_900_020_000_000,
                                        "scopes": ["user:profile", "user:inference"],
                                    ]]
                                    try JSONSerialization.data(withJSONObject: credentials).write(to: file)
                                    let snapshot = UsageSnapshot(
                                        primary: RateWindow(
                                            usedPercent: 100 - remaining,
                                            windowMinutes: 300,
                                            resetsAt: Date(timeIntervalSince1970: 1_900_020_000),
                                            resetDescription: nil),
                                        secondary: nil,
                                        updatedAt: Date(timeIntervalSince1970: 1_900_000_000 + Double(index)))
                                    let outcome = ProviderFetchOutcome(
                                        result: .success(ProviderFetchResult(
                                            usage: snapshot,
                                            credits: nil,
                                            dashboard: nil,
                                            sourceLabel: "oauth",
                                            strategyID: "fixture.oauth",
                                            strategyKind: .oauth,
                                            claudeOAuthHistoryOwnerIdentifier: historyOwner,
                                            claudeOAuthCredentialOwner: .claudeCLI)),
                                        attempts: [])
                                    store._test_providerFetchOutcomeOverride = { _ in outcome }
                                    await store.refreshProvider(.claude, allowDisabled: true)
                                    #expect(store.snapshot(for: .claude)?.primary?.remainingPercent == remaining)
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(notifier.thresholds == expectedThresholds)
        #expect(store.quotaWarningState[otherAccount]?.firedThresholds == [50])
        #expect(store.quotaWarningState[otherProvider]?.firedThresholds == [50])
    }

    private func makeSettings(root: URL) throws -> SettingsStore {
        let defaults = try #require(UserDefaults(suiteName: "ClaudeCredentialQuotaWarningTests-\(UUID())"))
        defaults.set(false, forKey: "openAIWebAccessEnabled")
        let config = CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json"))
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: config,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore(fileURL: root.appendingPathComponent("accounts.json")),
            antigravityOAuthCredentialsStore: AntigravityOAuthCredentialsStore(
                fileURL: root.appendingPathComponent("antigravity.json")),
            performInitialProviderDetection: false)
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.claudeUsageDataSource = .oauth
        settings.claudeOAuthKeychainPromptMode = .never
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50, 20]
        settings.setQuotaWarningWindowEnabled(.session, enabled: true)
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: false)
        settings.sessionQuotaNotificationsEnabled = false
        settings.predictivePaceWarningNotificationsEnabled = false
        return settings
    }
}
