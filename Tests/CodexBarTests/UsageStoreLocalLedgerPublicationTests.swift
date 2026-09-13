import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct UsageStoreLocalLedgerPublicationTests {
    @Test(arguments: [false, true], [false, true])
    func `regular refresh publishes local ledger results once`(globalEnabled: Bool, empty: Bool) async throws {
        try await Self.withFixture(globalEnabled: globalEnabled) { fixture in
            let store = fixture.store
            let old = Self.snapshot(cost: 1, updatedAt: Date(timeIntervalSince1970: 1))
            store.installCachedTokenSnapshot(old, for: .codex)
            store.tokenErrors[.codex] = "Previous scan failed"
            _ = store.tokenFailureGates[.codex]?.shouldSurfaceError(onFailureWithPriorData: false)
            let revision = store.tokenSnapshotPublicationRevision(for: .codex)
            let fresh = Self.snapshot(cost: 2, empty: empty)
            fixture.results = [.success(fresh)]

            await store.refreshTokenUsageNow(for: .codex, force: false)

            #expect(store.tokenSnapshotPublicationRevision(for: .codex) == revision + 1)
            let publication = store.tokenSnapshotPublicationForCurrentProviderConfig(for: .codex)
            #expect(publication != nil)
            #expect(publication?.snapshot == (empty ? nil : fresh))
            #expect(store.tokenSnapshot(for: .codex) == (empty ? nil : fresh))
            #expect(store.tokenError(for: .codex) == (empty ? UsageStore.tokenCostNoDataMessage(for: .codex) : nil))
            #expect(store.tokenFailureGates[.codex]?.streak == 0)
            #expect(store.lastTokenFetchScope[.codex] == store.tokenSnapshotScopeSignature(for: .codex))
            #expect(store.lastTokenFetchAt[.codex] != nil)
            fixture.expectIdle(loadCount: 1)
        }
    }

    @Test
    func `switching from managed account to local ledger hides old cost until ambient scan publishes`() async throws {
        try await Self.withFixture(globalEnabled: true, localEnabled: false) { fixture in
            let store = fixture.store
            let managedHome = fixture.root.appendingPathComponent("managed-home").path
            store.settings._test_activeManagedCodexRemoteHomePath = managedHome
            store.settings.codexActiveSource = .managedAccount(id: UUID())
            let managed = Self.snapshot(cost: 12)
            store.installCachedTokenSnapshot(managed, for: .codex)
            #expect(store.tokenSnapshot(for: .codex) == managed)

            store.settings.codexLocalSessionCostLedgerEnabled = true
            #expect(store.tokenSnapshots[.codex] == managed)
            #expect(store.tokenSnapshotPublicationForCurrentProviderConfig(for: .codex) == nil)
            #expect(store.tokenSnapshot(for: .codex) == nil)

            let ambient = Self.snapshot(cost: 2)
            fixture.results = [.success(ambient)]
            await store.refreshTokenUsageNow(for: .codex, force: false)

            #expect(fixture.loads.map(\.home) == [nil])
            #expect(store.tokenSnapshot(for: .codex) == ambient)
            fixture.expectIdle(loadCount: 1)

            store.settings.codexLocalSessionCostLedgerEnabled = false
            #expect(store.tokenSnapshot(for: .codex) == nil)
        }
    }

    @Test
    func `disabling local ledger hides published ambient cost from widget projection`() async throws {
        try await Self.withFixture { fixture in
            let store = fixture.store
            store._setSnapshotForTesting(
                UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: 25,
                        windowMinutes: 300,
                        resetsAt: nil,
                        resetDescription: nil),
                    secondary: nil,
                    updatedAt: Date()),
                provider: .codex)
            var widgetSnapshots: [WidgetSnapshot] = []
            store._test_widgetSnapshotSaveOverride = { widgetSnapshots.append($0) }
            fixture.results = [.success(Self.snapshot(cost: 3))]

            await store.refreshTokenUsageNow(for: .codex, force: false)
            await store.widgetSnapshotPersistTask?.value
            #expect(store.tokenSnapshot(for: .codex)?.sessionCostUSD == 3)
            #expect(widgetSnapshots.last?.entries.first { $0.provider == .codex }?.tokenUsage?.sessionCostUSD == 3)

            let previousRevision = store.settings.costUsageSettingsRevision
            store.settings.codexLocalSessionCostLedgerEnabled = false
            #expect(store.settings.costUsageSettingsRevision == previousRevision + 1)
            #expect(store.tokenSnapshotPublicationForCurrentProviderConfig(for: .codex) == nil)
            #expect(store.tokenSnapshot(for: .codex) == nil)
            store.persistWidgetSnapshot(reason: "local-ledger-disabled-test")
            await store.widgetSnapshotPersistTask?.value
            #expect(widgetSnapshots.last?.entries.first { $0.provider == .codex }?.tokenUsage == nil)
            fixture.expectIdle(loadCount: 1)
        }
    }

    @Test
    func `both off skips Codex and local mode does not enable unrelated scanners`() async throws {
        try await Self.withFixture(localEnabled: false) { fixture in
            await fixture.store.refreshTokenUsageNow(for: .codex, force: false)
            #expect(fixture.store.tokenSnapshotPublicationRevision(for: .codex) == 0)
            fixture.expectIdle(loadCount: 0)

            fixture.store.settings.codexLocalSessionCostLedgerEnabled = true
            for provider in [UsageProvider.claude, .cursor] {
                fixture.store.settings.setProviderEnabled(
                    provider: provider, metadata: fixture.store.metadata(for: provider), enabled: true)
                await fixture.store.refreshTokenUsageNow(for: provider, force: false)
                #expect(!fixture.store.settings.isCostUsageEffectivelyEnabled(for: provider))
                #expect(fixture.store.tokenSnapshotPublicationRevision(for: provider) == 0)
                #expect(fixture.store.tokenError(for: provider) == nil)
            }
            fixture.expectIdle(loadCount: 0)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func `disabling during a regular fetch rejects its result`(disableProvider: Bool, fail: Bool) async throws {
        try await Self.withFixture { fixture in
            let store = fixture.store
            fixture.results = [fail ? .failure(ScanError.failed) : .success(Self.snapshot(cost: 9))]
            let gate = fixture.gate(load: 1)
            store.scheduleTokenRefresh()
            let task = try #require(store.tokenRefreshSequenceTask)
            try await Self.waitUntil { gate.isWaiting }

            if disableProvider {
                store.settings.setProviderEnabled(
                    provider: .codex,
                    metadata: store.metadata(for: .codex),
                    enabled: false)
            } else {
                store.settings.codexLocalSessionCostLedgerEnabled = false
            }
            gate.release()
            await task.value

            #expect(fixture.loads.count == 1)
            #expect(store.tokenSnapshotPublicationRevision(for: .codex) == 0)
            #expect(store.tokenSnapshot(for: .codex) == nil)
            #expect(store.tokenError(for: .codex) == nil)
            #expect(store.lastTokenFetchAt[.codex] == nil)
            #expect(store.lastTokenFetchScope[.codex] == nil)
            #expect(store.tokenRefreshSequenceTask == nil)
        }
    }

    private static func snapshot(
        cost: Double,
        empty: Bool = false,
        updatedAt: Date = Date()) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: empty ? nil : 10,
            sessionCostUSD: empty ? nil : cost,
            last30DaysTokens: empty ? nil : 10,
            last30DaysCostUSD: empty ? nil : cost,
            daily: empty ? [] : [CostUsageDailyReport.Entry(
                date: "2026-08-26",
                inputTokens: 4,
                outputTokens: 6,
                totalTokens: 10,
                costUSD: cost,
                modelsUsed: nil,
                modelBreakdowns: nil)],
            updatedAt: updatedAt)
    }

    private static func waitUntil(_ condition: () -> Bool) async throws {
        // Bound observation turns rather than wall time: architecture checks can occupy the main actor.
        for _ in 0..<1000 where !condition() {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(condition(), "Timed out waiting for the isolated snapshot loader")
    }

    private static func withFixture(
        globalEnabled: Bool = false,
        localEnabled: Bool = true,
        body: (Fixture) async throws -> Void) async throws
    {
        let fixture = try Fixture(globalEnabled: globalEnabled, localEnabled: localEnabled)
        do {
            try await body(fixture)
        } catch {
            await fixture.tearDown()
            throw error
        }
        await fixture.tearDown()
    }

    private enum ScanError: LocalizedError {
        case failed
        var errorDescription: String? {
            "Isolated local scan failed"
        }
    }

    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        var isWaiting: Bool {
            self.continuation != nil
        }

        func wait() async {
            guard !self.released else { return }
            await withCheckedContinuation { self.continuation = $0 }
        }

        func release() {
            self.released = true
            self.continuation?.resume()
            self.continuation = nil
        }
    }

    @MainActor
    private final class Fixture {
        let store: UsageStore
        let root: URL
        var results: [Result<CostUsageTokenSnapshot, Error>] = []
        var loads: [(provider: UsageProvider, home: String?, historyDays: Int)] = []
        private var gates: [Int: Gate] = [:]
        private var stopping = false

        init(globalEnabled: Bool, localEnabled: Bool) throws {
            self.root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let settings = testSettingsStore(suiteName: "UsageStoreLocalLedgerPublicationTests")
            settings._test_managedCodexAccountStoreURL = self.root.appendingPathComponent("accounts.json")
            settings.costUsageEnabled = globalEnabled
            settings.codexLocalSessionCostLedgerEnabled = localEnabled
            settings.costUsageHistoryDays = 30
            settings.refreshFrequency = .manual
            settings.openAIWebAccessEnabled = false
            settings.providerDetectionCompleted = true
            for provider in UsageProvider.allCases {
                let metadata = try #require(ProviderRegistry.shared.metadata[provider])
                settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: provider == .codex)
            }
            let environment = ["HOME": self.root.path, "CODEX_HOME": self.root.appendingPathComponent("codex").path]
            self.store = UsageStore(
                fetcher: UsageFetcher(environment: environment),
                browserDetection: BrowserDetection(homeDirectory: self.root.path, cacheTTL: 0),
                settings: settings,
                startupBehavior: .testing,
                environmentBase: environment)
            self.store._test_codexCostCatchUpStatusOverride = { _ in
                CostUsageFetcher.CodexScanCatchUpStatus(pending: false, progressKey: "isolated-complete")
            }
            self.store._test_widgetSnapshotSaveOverride = { _ in }
            self.store._test_tokenUsageSnapshotLoaderOverride = { [weak self] provider, _, _, home, historyDays in
                guard let self, !self.stopping else { throw CancellationError() }
                self.loads.append((provider, home, historyDays))
                let count = self.loads.count
                // Unexpected retries must park rather than spin, including on the unfixed production code.
                if count > self.results.count || self.gates[count] != nil {
                    await self.gate(load: count).wait()
                }
                guard !self.stopping else { throw CancellationError() }
                return try self.results[count - 1].get()
            }
        }

        func gate(load: Int) -> Gate {
            if let gate = self.gates[load] {
                return gate
            }
            let gate = Gate()
            self.gates[load] = gate
            return gate
        }

        func expectIdle(loadCount: Int) {
            #expect(self.loads.count == loadCount)
            #expect(self.store.tokenRefreshRetryProviders.isEmpty)
            #expect(self.store.tokenRefreshSequenceTask == nil)
            #expect(self.store.tokenRefreshSequenceToken == nil)
            #expect(self.store.tokenRefreshInFlight.isEmpty)
            #expect(!self.store.pendingForcedTokenRefresh)
        }

        func tearDown() async {
            self.stopping = true
            self.store.settings.costUsageEnabled = false
            self.store.settings.codexLocalSessionCostLedgerEnabled = false
            let sequence = self.store.tokenRefreshSequenceTask
            sequence?.cancel()
            for gate in self.gates.values {
                gate.release()
            }
            await sequence?.value
            let catchUp = self.store.codexCostCatchUpTask
            self.store.cancelCodexCostCatchUp()
            await catchUp?.value
            await self.store.widgetSnapshotPersistTask?.value
            let memoryRelief = self.store.memoryPressureReliefTask
            memoryRelief?.cancel()
            await memoryRelief?.value
            self.store.tokenRefreshRetryProviders.removeAll()
            self.store._test_tokenUsageSnapshotLoaderOverride = nil
            try? FileManager.default.removeItem(at: self.root)
        }
    }
}
