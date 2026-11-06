import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct UsageStoreMenuCardModelTests {
    @Test
    func `Claude menu separates stale usage from its error while settings retain the notice`() throws {
        try KeychainAccessGate.withTaskOverrideForTesting(false) {
            try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
                let store = self.makeStore()
                let snapshot = self.snapshot()
                let raw = ClaudeOAuthCredentialsError.missingAccessToken.localizedDescription
                store.snapshots[.claude] = snapshot
                store.errors[.claude] = raw

                let menu = store.menuCardModel(for: .claude, now: snapshot.updatedAt.addingTimeInterval(3600))
                #expect(menu.subtitleText == raw)
                #expect(menu.subtitleStyle == .error)
                #expect(menu.lastKnownUsageText?.hasPrefix("Showing last-known usage captured ") == true)
                #expect(!menu.subtitleText.contains("Showing last-known usage"))

                let settings = store.menuCardModel(for: .claude, context: .settings)
                let message = try #require(store.userFacingError(for: .claude))
                #expect(settings.subtitleText == message)
                #expect(settings.subtitleText.components(separatedBy: "Showing last-known usage").count == 2)
                #expect(settings.lastKnownUsageText == nil)
            }
        }
    }

    @Test
    func `Claude error without a snapshot has no stale line`() {
        let store = self.makeStore()
        store.errors[.claude] = "Claude request failed"
        let model = store.menuCardModel(for: .claude)
        #expect(model.subtitleText == "Claude request failed")
        #expect(model.lastKnownUsageText == nil)
    }

    @Test
    func `non Claude errors and diagnostics keep separate refresh outcomes`() {
        let store = self.makeStore()
        store.snapshots[.mistral] = self.snapshot()
        store.errors[.mistral] = "Mistral request failed"
        let model = store.menuCardModel(for: .mistral)
        #expect(model.subtitleText == store.userFacingError(for: .mistral))
        #expect(model.subtitleText == "Mistral request failed")
        #expect(model.lastKnownUsageText == nil)
        #expect(model.showsRetainedMeasurement)

        store.errors[.mistral] = nil
        store.diagnostics[.mistral] = "Fallback succeeded"
        let recovered = store.menuCardModel(for: .mistral)
        #expect(recovered.subtitleText == "Fallback succeeded")
        #expect(!recovered.showsRetainedMeasurement)
    }

    @Test
    func `Claude account card keeps its own stale timestamp and error`() {
        let store = self.makeStore()
        let snapshot = self.snapshot()
        let model = store.menuCardModel(for: .claude, context: .account(.init(
            snapshot: snapshot,
            error: "Account request failed",
            lastKnownUsageCapturedAt: snapshot.updatedAt)))
        #expect(model.subtitleText == "Account request failed")
        #expect(model.lastKnownUsageText != nil)
    }

    @Test(arguments: [false, true], [false, true])
    func `failed account switch does not dim successfully refreshed Claude quotas`(
        usageFailed: Bool,
        adapterFailed: Bool)
    {
        let store = self.makeStore()
        let snapshot = self.snapshot()
        let account = ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(source: "claude-swap", opaqueID: "2"),
            provider: .claude,
            displayLabel: "account@example.com",
            isActive: true,
            usesLastKnownUsage: usageFailed,
            snapshot: snapshot,
            error: usageFailed ? "Quota refresh failed" : nil,
            sourceLabel: "claude-swap")
        let context = ClaudeSwapAccountMenuDisplay.cardContext(
            for: account,
            planLabel: nil,
            adapterError: adapterFailed ? "Account list refresh failed" : nil,
            switchError: "Activation failed")

        let model = store.menuCardModel(for: .claude, context: context, now: snapshot.updatedAt)

        #expect(model.subtitleText == "Account switch failed: Activation failed")
        #expect(!model.metrics.isEmpty)
        #expect(model.showsRetainedMeasurement == (usageFailed || adapterFailed))
    }

    @Test(arguments: ClaudeSwapAccountSource.allCases)
    func `current exhausted account quotas keep their tint despite a limit notice`(
        source: ClaudeSwapAccountSource) throws
    {
        let store = self.makeStore()
        store.settings.usageBarsShowUsed = true
        let now = self.snapshot().updatedAt
        let list = ClaudeSwapAccountList(
            activeAccountNumber: 2,
            accounts: [ClaudeSwapAccountRow(
                number: 2,
                email: "account@example.com",
                isActive: true,
                usageStatus: .unavailable,
                fiveHour: ClaudeSwapUsageWindow(usedPercent: 100, resetsAt: now.addingTimeInterval(3600)),
                sevenDay: nil)])
        let account = try #require(ClaudeSwapAccountProjection.accountSnapshots(
            from: list, source: source, now: now).first)
        #expect(!account.usesLastKnownUsage)
        #expect(account.error != nil)
        let context = ClaudeSwapAccountMenuDisplay.cardContext(
            for: account, planLabel: nil, adapterError: nil, switchError: nil)

        let model = store.menuCardModel(for: .claude, context: context, now: now)

        #expect(model.subtitleText.contains("Session limit reached."))
        #expect(model.metrics.first?.percent == 100)
        #expect(!model.showsRetainedMeasurement)
    }

    @Test(arguments: [UsageProvider.claude, .grok])
    func `empty account context cannot borrow live usage identity or cost`(provider: UsageProvider) {
        let store = self.makeStore()
        store.settings.costUsageEnabled = true
        store.settings.hidePersonalInfo = false
        store.snapshots[provider.instanceID] = self.snapshot()
        store.errors[provider.instanceID] = "Live account failed"
        store._setTokenSnapshotForTesting(.init(
            sessionTokens: 100,
            sessionCostUSD: 2,
            last30DaysTokens: 100,
            last30DaysCostUSD: 2,
            daily: [],
            updatedAt: Date()), provider: provider)

        let model = store.menuCardModel(for: provider, context: .account(.init()))

        #expect(model.metrics.isEmpty)
        #expect(model.email.isEmpty)
        #expect(model.tokenUsage == nil)
        #expect(model.subtitleStyle != .error)
        #expect(!model.usesLiveSubtitle)
        #expect(store.menuCardModel(for: provider).subtitleStyle == .error)
    }

    @Test
    func `settings catalogue exposes gated Claude extra usage without changing rendered preferences`() {
        let store = self.makeStore()
        let now = Date(timeIntervalSince1970: 1_782_000_000)
        store.settings.showOptionalCreditsAndExtraUsage = false
        store.snapshots[.claude] = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 12,
                limit: 100,
                currencyCode: "USD",
                period: "Monthly cap",
                updatedAt: now),
            updatedAt: now)

        let displayed = store.menuCardModel(for: .claude, context: .settings)
        let catalogue = UsageMenuCardView.Model.make(store.menuCardInput(
            for: .claude,
            context: .settings,
            now: now,
            optionalUsageOverride: true))
        #expect(!displayed.metrics.contains { $0.id == "claude-extra-usage" })
        #expect(catalogue.usageItemDescriptors.contains {
            $0.id == .claudeExtraUsage && $0.requiresOptionalUsage
        })
        #expect(!store.settings.showOptionalCreditsAndExtraUsage)

        store.settings.setUsageItemVisible(false, itemID: .claudeExtraUsage, for: .claude)
        store.settings.showOptionalCreditsAndExtraUsage = true
        #expect(store.menuCardModel(for: .claude).metrics.isEmpty)
        #expect(store.menuCardModel(for: .claude, context: .settings).metrics.isEmpty)
        store.settings.setUsageItemVisible(true, itemID: .claudeExtraUsage, for: .claude)
        #expect(store.menuCardModel(for: .claude).metrics.contains { $0.id == "claude-extra-usage" })
    }

    @Test(arguments: [UsageDataConfidence.estimated, .exact])
    func `account pace uses its own confidence instead of the live account`(confidence: UsageDataConfidence) {
        let store = self.makeStore()
        let now = OpenCodeGoPaceTestSupport.now
        store.snapshots[.opencodego] = OpenCodeGoPaceTestSupport.snapshot(
            confidence: confidence == .estimated ? .exact : .estimated)
        let input = store.menuCardInput(
            for: .opencodego,
            context: .account(.init(snapshot: OpenCodeGoPaceTestSupport.snapshot(confidence: confidence))),
            now: now)

        #expect((input.weeklyPace != nil) == (confidence != .estimated))
    }

    @Test
    func `shared card inputs preserve scoped weekly observations without changing history`() throws {
        let store = self.makeStore()
        let snapshot = self.snapshot()
        store.snapshots[.claude] = snapshot
        let accountKey = try #require(UsageStore.planUtilizationIdentityAccountKey(
            provider: .claude, snapshot: snapshot))
        let reset = try #require(snapshot.secondary?.resetsAt)
        let history = PlanUtilizationSeriesHistory(name: .weekly, windowMinutes: 10080, entries: [
            .init(capturedAt: snapshot.updatedAt, usedPercent: 50, resetsAt: reset),
        ])
        store.planUtilizationHistory[.claude] = PlanUtilizationHistoryBuckets(
            preferredAccountKey: accountKey,
            accounts: [accountKey: [history]])
        let original = store.planUtilizationHistory
        let revision = store.planUtilizationHistoryRevision
        let expected = [CostUsageQuotaResetObservation(capturedAt: snapshot.updatedAt, resetsAt: reset)]

        let menu = store.menuCardInput(for: .claude, context: .menu, now: snapshot.updatedAt)
        let settings = store.menuCardInput(for: .claude, context: .settings, now: snapshot.updatedAt)
        let empty = store.menuCardInput(for: .claude, context: .account(.init()), now: snapshot.updatedAt)
        let identityless = store.menuCardInput(
            for: .claude,
            context: .account(.init(snapshot: UsageSnapshot(
                primary: snapshot.primary,
                secondary: snapshot.secondary,
                updatedAt: snapshot.updatedAt))),
            now: snapshot.updatedAt)
        let selected = store.menuCardInput(
            for: .claude,
            context: .account(.init(historySelection: .init(accountKey: accountKey, histories: [history]))),
            now: snapshot.updatedAt)

        #expect(menu.observedWeeklyResets == expected)
        #expect(settings.observedWeeklyResets == expected)
        #expect(empty.observedWeeklyResets.isEmpty)
        #expect(identityless.observedWeeklyResets.isEmpty)
        #expect(selected.observedWeeklyResets == expected)
        #expect(store.planUtilizationHistory == original)
        #expect(store.planUtilizationHistoryRevision == revision)
    }

    @Test(arguments: [true, false])
    func `ClaudeSwap cards do not infer OAuth history ownership from an email or active slot`(active: Bool) throws {
        let store = self.makeStore()
        let snapshot = self.snapshot()
        let reset = try #require(snapshot.secondary?.resetsAt)
        let history = PlanUtilizationSeriesHistory(name: .weekly, windowMinutes: 10080, entries: [
            .init(capturedAt: snapshot.updatedAt, usedPercent: 50, resetsAt: reset),
        ])
        let oauthKey = "__claude_oauth__:fixture-owner"
        store.planUtilizationHistory[.claude] = PlanUtilizationHistoryBuckets(
            preferredAccountKey: oauthKey,
            accounts: [oauthKey: [history]])
        store.snapshots[.claude] = snapshot
        let account = try #require(ClaudeSwapAccountProjection.accountSnapshots(
            from: .init(activeAccountNumber: active ? 1 : nil, accounts: [
                .init(
                    number: 1,
                    email: "fixture@example.com",
                    isActive: active,
                    usageStatus: .ok,
                    fiveHour: .init(usedPercent: 25, resetsAt: reset),
                    sevenDay: .init(usedPercent: 50, resetsAt: reset)),
            ]),
            now: snapshot.updatedAt).first)
        let original = store.planUtilizationHistory
        let revision = store.planUtilizationHistoryRevision
        let input = store.menuCardInput(
            for: .claude,
            context: ClaudeSwapAccountMenuDisplay.cardContext(
                for: account, planLabel: nil, adapterError: nil, switchError: nil),
            now: snapshot.updatedAt)

        #expect(input.snapshot?.secondary?.resetsAt == reset)
        #expect(input.observedWeeklyResets.isEmpty)
        #expect(store.planUtilizationHistory == original)
        #expect(store.planUtilizationHistoryRevision == revision)
    }

    private func makeStore() -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "UsageStoreMenuCardModelTests",
            userDefaults: InMemoryUserDefaults())
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._cancelPlanUtilizationHistoryLoadForTesting()
        store.planUtilizationHistory = [:]
        return store
    }

    private func snapshot() -> UsageSnapshot {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return UsageSnapshot(
            primary: .init(
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: .init(
                usedPercent: 50,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(86400),
                resetDescription: nil),
            updatedAt: now,
            identity: .init(
                providerID: .claude,
                accountEmail: "fixture@example.com",
                accountOrganization: nil,
                loginMethod: "max"))
    }
}
