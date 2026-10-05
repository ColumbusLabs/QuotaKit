import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct ProviderSnapshotExportPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `Langdock is local only while stable providers keep every export surface`() {
        let localOnly = ProviderDescriptorRegistry.descriptor(for: .langdock).snapshotExport
        #expect(!localOnly.allowsWidgets)
        #expect(!localOnly.allowsFleetCloudSync)
        #expect(!localOnly.allowsIPhoneSync)
        #expect(!SyncCoordinator.tokenBasedMultiAccountProvidersForTesting.contains(.langdock))

        let stable = ProviderDescriptorRegistry.descriptor(for: .zai).snapshotExport
        #expect(stable.allowsWidgets)
        #expect(stable.allowsFleetCloudSync)
        #expect(stable.allowsIPhoneSync)
    }

    @Test
    func `final iPhone serializer removes Langdock while retaining stable and CodeRabbit rules`() {
        let result = SyncCoordinator.iphoneExportableSnapshots([
            self.providerSnapshot("langdock"),
            self.providerSnapshot("zai"),
            self.providerSnapshot("coderabbit"),
        ])

        #expect(result.map(\.providerID) == ["zai"])
    }

    @Test
    func `local only provider cannot enter widgets or fleet exports including default accounts`() async throws {
        let settings = self.makeSettingsStore(suite: "local-only-widget-fleet")
        settings.accountWidgetsEnabled = true
        for provider in [UsageProvider.langdock, .zai] {
            settings.setProviderEnabled(
                provider: provider,
                metadata: ProviderDescriptorRegistry.descriptor(for: provider).metadata,
                enabled: true)
        }

        let store = self.makeUsageStore(settings: settings)
        store.snapshots[.langdock] = self.snapshot()
        store.snapshots[.zai] = self.snapshot()
        let account = ProviderTokenAccount(
            id: UUID(), label: "Synthetic profile", token: "synthetic", addedAt: 1, lastUsed: nil)
        store.accountSnapshots[.langdock] = [TokenAccountUsageSnapshot(
            account: account,
            snapshot: self.snapshot(),
            error: nil,
            sourceLabel: "synthetic",
            cacheKey: "synthetic-profile")]
        let session = try await LangdockPluginTests.fetch(
            LangdockPluginTests.body(LangdockPluginTests.plan), now: self.now)
        let sessionAccount = ProviderTokenAccount(
            id: UUID(), label: "Synthetic account", token: "synthetic", addedAt: 1, lastUsed: nil,
            externalIdentifier: "synthetic-session-account")
        store.accountSnapshots[.zai] = [TokenAccountUsageSnapshot(
            account: sessionAccount,
            snapshot: session,
            error: nil,
            sourceLabel: "synthetic",
            cacheKey: "synthetic-session-owner")]

        var saved: WidgetSnapshot?
        store._test_widgetSnapshotSaveOverride = { saved = $0 }
        defer { store._test_widgetSnapshotSaveOverride = nil }
        store.persistWidgetSnapshot(reason: "local-only-provider")
        await store.widgetSnapshotPersistTask?.value

        let widget = try #require(saved)
        #expect(!widget.enabledProviders.contains(.langdock))
        #expect(!widget.entries.contains { $0.provider == .langdock })
        #expect(widget.enabledProviders.contains(.zai))
        #expect(widget.entries.contains { $0.provider == .zai })
        #expect(!store.makeWidgetAccountEntries(now: self.now).contains { $0.provider == .langdock.instanceID })

        let fleet = store.cloudSyncAccountSnapshots()
        #expect(!fleet.contains { $0.provider == .langdock.instanceID })
        #expect(fleet.contains { $0.provider == .zai.instanceID && $0.accountKey == "default" })
        #expect(!fleet.contains { $0.provider == .zai.instanceID && $0.accountKey != "default" })
        #expect(store.cloudSyncLocalAccountKeys(for: .zai) == ["default"])

        store.snapshots[.zai] = session
        saved = nil
        store.persistWidgetSnapshot(reason: "session-owned-provider")
        await store.widgetSnapshotPersistTask?.value
        let sessionWidget = try #require(saved)
        #expect(!sessionWidget.entries.contains { $0.provider == .zai })
        #expect(!store.cloudSyncAccountSnapshots().contains { $0.provider == .zai.instanceID })
        #expect(store.cloudSyncLocalAccountKeys(for: .zai).isEmpty)
    }

    @Test
    func `iPhone sync omits local only providers from both streams and retains stable providers`() async throws {
        let settings = self.makeSettingsStore(suite: "local-only-iphone-sync")
        settings.iCloudSyncEnabled = true
        for provider in [UsageProvider.langdock, .zai] {
            settings.setProviderEnabled(
                provider: provider,
                metadata: ProviderDescriptorRegistry.descriptor(for: provider).metadata,
                enabled: true)
        }

        let store = self.makeUsageStore(settings: settings)
        store._setSnapshotForTesting(self.snapshot(), provider: .langdock)
        store._setSnapshotForTesting(self.snapshot(), provider: .zai)
        let pusher = MockSyncPusher()
        await SyncCoordinator(store: store, settings: settings, syncManager: pusher).pushCurrentSnapshot()

        let legacy = try #require(pusher.lastSnapshot)
        #expect(!legacy.providers.contains { $0.providerID == UsageProvider.langdock.rawValue })
        #expect(legacy.providers.contains { $0.providerID == UsageProvider.zai.rawValue })
        #expect(!pusher.lastPerProviderEnvelopes.contains {
            $0.provider.providerID == UsageProvider.langdock.rawValue
        })
        #expect(pusher.lastPerProviderEnvelopes.contains {
            $0.provider.providerID == UsageProvider.zai.rawValue
        })
    }

    @Test
    func `multi-account iPhone expansion skips session-owned token snapshots`() async throws {
        let settings = self.makeSettingsStore(suite: "session-owned-multiaccount-sync")
        settings.iCloudSyncEnabled = true
        enableTestProviders([.claude], settings: settings)
        settings.addTokenAccount(provider: .claude, label: "Work", token: "synthetic-work")
        settings.addTokenAccount(provider: .claude, label: "Personal", token: "synthetic-personal")

        let store = self.makeUsageStore(settings: settings)
        let session = try await LangdockPluginTests.fetch(
            LangdockPluginTests.body(LangdockPluginTests.plan), now: self.now)
        let accounts = settings.tokenAccounts(for: .claude)
        store.accountSnapshots[.claude] = accounts.enumerated().map { index, account in
            TokenAccountUsageSnapshot(
                account: account,
                snapshot: UsageSnapshot(
                    primary: session.primary,
                    secondary: session.secondary,
                    browserSessionOwner: session.browserSessionOwner,
                    updatedAt: self.now,
                    identity: ProviderIdentitySnapshot(
                        providerID: .claude,
                        accountEmail: account.label,
                        accountOrganization: nil,
                        loginMethod: "selected profile",
                        accountID: "synthetic-account-\(index)")),
                error: nil,
                sourceLabel: "synthetic",
                cacheKey: store.tokenAccountSnapshotCacheKey(provider: .claude, account: account))
        }

        let pusher = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: pusher)
        coordinator.multiAccountCache.record(
            ProviderUsageSnapshot(
                providerID: UsageProvider.claude.rawValue,
                providerName: "Claude",
                primary: nil,
                secondary: nil,
                accountEmail: "prior@example.test",
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: self.now,
                accountIdentities: ["claude:account:prior"]),
            providerID: UsageProvider.claude.rawValue,
            accountID: "prior")
        await coordinator.pushCurrentSnapshot()
        #expect(coordinator.multiAccountCache.count(forProvider: UsageProvider.claude.rawValue) == 0)
        let claudeSnapshots = try #require(pusher.lastSnapshot).providers.filter {
            $0.providerID == UsageProvider.claude.rawValue
        }
        #expect(claudeSnapshots.count == 1)
        #expect(claudeSnapshots[0].accountIdentities?.isEmpty ?? true)
        #expect(!claudeSnapshots.contains { $0.accountEmail == "prior@example.test" })
    }

    @Test
    func `session-owned token snapshots cannot reuse a retained account widget quota`() async throws {
        let settings = self.makeSettingsStore(suite: "session-owned-account-widget")
        enableTestProviders([.claude], settings: settings)
        settings.accountWidgetsEnabled = true
        settings.addTokenAccount(provider: .claude, label: "Work", token: "synthetic-work")

        let store = self.makeUsageStore(settings: settings)
        let account = try #require(settings.tokenAccounts(for: .claude).first)
        let session = try await LangdockPluginTests.fetch(
            LangdockPluginTests.body(LangdockPluginTests.plan), now: self.now)
        let credentialScope = store.tokenAccountSnapshotCacheKey(provider: .claude, account: account)
        store.accountSnapshots[.claude] = [TokenAccountUsageSnapshot(
            account: account,
            snapshot: session,
            error: "Synthetic transient profile failure",
            sourceLabel: "synthetic",
            cacheKey: credentialScope,
            fetchError: ClaudeOAuthFetchError.networkError(URLError(.timedOut)))]
        store.widgetVerifiedTokenSnapshots[.claude] = [account.id: WidgetVerifiedTokenSnapshot(
            credentialScope: credentialScope,
            widgetID: "claude/token:previous",
            usage: WidgetSnapshot.ProviderEntry(
                provider: .claude,
                updatedAt: self.now.addingTimeInterval(-600),
                primary: RateWindow(
                    usedPercent: 20,
                    windowMinutes: 300,
                    resetsAt: self.now.addingTimeInterval(3600),
                    resetDescription: nil),
                secondary: nil,
                tertiary: nil,
                creditsRemaining: nil,
                codeReviewRemainingPercent: nil,
                tokenUsage: nil,
                dailyUsage: []))]

        #expect(store.makeWidgetAccountEntries(now: self.now).isEmpty)
        #expect(store.widgetVerifiedTokenSnapshots[.claude]?.isEmpty == true)
    }

    private func makeSettingsStore(suite: String) -> SettingsStore {
        testSettingsStore(suiteName: suite, userDefaults: InMemoryUserDefaults())
    }

    private func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
    }

    private func snapshot() -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: self.now.addingTimeInterval(300 * 60),
                resetDescription: nil),
            secondary: nil,
            updatedAt: self.now)
    }

    private func providerSnapshot(_ providerID: String) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerID,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.now)
    }
}
