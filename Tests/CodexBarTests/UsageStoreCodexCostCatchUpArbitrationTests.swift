import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct UsageStoreCodexCostCatchUpArbitrationTests {
    @Test
    func `independent visible All demand does not widen the primary worker`() async throws {
        let settings = testSettingsStore(
            suiteName: "UsageStoreCodexCostCatchUpArbitrationTests-independent-all")
        settings.costUsageEnabled = true
        settings.costUsageHistoryDays = 30
        settings.codexActiveSource = .liveSystem
        let metadata = try #require(ProviderRegistry.shared.metadata[.codex])
        settings.setProviderEnabled(provider: .codex, metadata: metadata, enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])

        let defaults = try #require(UserDefaults(
            suiteName: "UsageStoreCodexCostCatchUpArbitrationTests-controller-\(UUID().uuidString)"))
        let controller = SpendDashboardController(
            userDefaults: defaults,
            requestBuilder: { _ in
                SpendDashboardLoadRequest(
                    configuration: SpendDashboardConfiguration(
                        costUsageEnabled: false,
                        providerIDs: [],
                        codexAccountIdentities: []),
                    capturedInputs: [],
                    unavailableSourceIDs: [],
                    codexRequests: [],
                    now: Date(timeIntervalSince1970: 1_784_179_200),
                    force: false)
            })
        store.sharedSpendDashboardControllerStorage = controller
        controller.selectDays(SpendDashboardSource.scanDays)
        controller.activateHistoryDemandForVisibleDashboard()

        var primaryHistory: [Int] = []
        var independentHistory: [Int] = []
        var primaryCompleted = false
        var independentCompleted = false
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, now, _, _ in
            Self.snapshot(now: now)
        }
        store._test_codexCostCatchUpStatusOverride = { _ in
            Self.status(
                pending: !primaryCompleted,
                key: primaryCompleted ? "primary-complete" : "primary-pending")
        }
        store._test_codexCostCatchUpAdvanceOverride = { _, _, historyDays in
            primaryHistory.append(historyDays)
            primaryCompleted = true
            return Self.status(pending: false, key: "primary-complete")
        }
        store._test_codexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_codexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }
        store._test_spendDashboardCodexCostCatchUpStatusOverride = { _ in
            Self.status(
                pending: !independentCompleted,
                key: independentCompleted ? "independent-complete" : "independent-pending")
        }
        store._test_spendDashboardCodexCostCatchUpAdvanceOverride = { _, _, historyDays in
            independentHistory.append(historyDays)
            independentCompleted = true
            return Self.status(pending: false, key: "independent-complete")
        }
        store._test_spendDashboardCodexCostCatchUpSleepOverride = { _ in await Task.yield() }
        store._test_spendDashboardCodexCostCatchUpResourceStateOverride = { (.ac, false, .nominal) }

        let sharedAccount = Self.account(id: "live", source: .liveSystem, cacheIdentity: "live-cache")
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: [sharedAccount])
        await Self.waitUntil { store.codexCostCatchUpTask == nil }
        #expect(primaryHistory == [SpendDashboardSource.scanDays])
        #expect(store.spendDashboardCodexCostCatchUpUsesPrimaryWorker)

        let independentAccount = Self.account(
            id: "managed",
            source: .profileHome(path: "/synthetic/managed"),
            cacheIdentity: "managed-cache")
        store.synchronizeSpendDashboardCodexCostCatchUp(accounts: [independentAccount])
        await Self.waitUntil { store.spendDashboardCodexCostCatchUpTask == nil }

        #expect(independentHistory == [SpendDashboardSource.scanDays])
        #expect(!store.spendDashboardCodexCostCatchUpUsesPrimaryWorker)

        // The dashboard remains on visible All, but its independent cache no longer owns the
        // ambient worker. A generic primary start must re-arbitrate back to the routine horizon.
        primaryCompleted = false
        store.startCodexCostCatchUpIfNeeded()
        await Self.waitUntil { store.codexCostCatchUpTask == nil }

        #expect(primaryHistory == [SpendDashboardSource.scanDays, 30])
        #expect(store.codexCostCatchUpHistoryDays == 30)
        controller.deactivateHistoryDemand()
        store.cancelCodexCostCatchUp()
        store.cancelSpendDashboardCodexCostCatchUp()
    }

    private static func account(
        id: String,
        source: CodexActiveSource,
        cacheIdentity: String) -> CodexSpendScanRequest
    {
        CodexSpendScanRequest(
            id: id,
            displayName: "Codex · \(id)",
            source: source,
            homePath: "/synthetic/\(id)",
            authFingerprint: nil,
            authFileWasReadable: false,
            cacheIdentity: cacheIdentity)
    }

    private static func snapshot(now: Date) -> CostUsageTokenSnapshot {
        CostUsageTokenSnapshot(
            sessionTokens: 10,
            sessionCostUSD: 1,
            last30DaysTokens: 10,
            last30DaysCostUSD: 1,
            historyCoverageIsEstablished: true,
            daily: [CostUsageDailyReport.Entry(
                date: "2026-07-30",
                inputTokens: 4,
                outputTokens: 6,
                totalTokens: 10,
                costUSD: 1,
                modelsUsed: nil,
                modelBreakdowns: nil)],
            updatedAt: now)
    }

    private static func status(
        pending: Bool,
        key: String) -> CostUsageFetcher.CodexScanCatchUpStatus
    {
        CostUsageFetcher.CodexScanCatchUpStatus(
            pending: pending,
            progressKey: key,
            processedBytes: pending ? 25 : 100,
            totalBytes: 100,
            completedFiles: pending ? 0 : 1,
            totalFiles: 1)
    }

    private static func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1000 {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("Timed out waiting for Codex catch-up arbitration")
    }
}
