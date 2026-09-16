import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// Deterministic regression coverage for
/// `ColumbusLabs/QuotaKit#159`: same-owner source-revision churn must not
/// discard completed ordinary loads without publication.
///
/// Every test drives load completion through a controllable loader gate, so
/// no test depends on timing sleeps.
@MainActor
struct SpendDashboardLoadLivenessTests {
    @Test
    func `same-owner burst publishes in-flight result and coalesces one follow-up`() async {
        let revisionA = Self.configuration(revision: "rev-A")
        let revisionB = Self.configuration(revision: "rev-B")
        let revisionC = Self.configuration(revision: "rev-C")
        let revisionD = Self.configuration(revision: "rev-D")
        let builder = SpendDashboardLivenessBuildScript([
            .init(mode: .refreshMissing, request: Self.request(revisionA, mode: .refreshMissing)),
            .init(mode: .refreshMissing, request: Self.request(revisionD, mode: .refreshMissing)),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: revisionA)
        await Self.waitForPendingCount(1, gate: loader)

        controller.update(configuration: revisionB)
        controller.update(configuration: revisionC)
        controller.update(configuration: revisionD)
        await Task.yield()
        #expect(await loader.pendingCount == 1)
        #expect(builder.modes == [.refreshMissing])
        #expect(controller.generation == 1)

        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 5)], failedSourceIDs: []))
        await Self.waitForPendingCount(1, gate: loader)

        // The identity-safe completed result must become visible even though
        // newer same-owner revisions arrived while it ran.
        #expect(controller.model.groups.first?.totalCost == 5)
        // The newest desired configuration must survive; applying A must not
        // roll the controller back to the stale revision.
        #expect(controller.configuration == revisionD)
        #expect(controller.generation == 2)

        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 9)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing }

        #expect(controller.model.groups.first?.totalCost == 9)
        #expect(controller.configuration == revisionD)
        #expect(builder.modes == [.refreshMissing, .refreshMissing])
        let loadedRevisions = await loader.configurations.map(\.sourceRevisions)
        #expect(loadedRevisions == [revisionA.sourceRevisions, revisionD.sourceRevisions])
        #expect(controller.loadLivenessCounters.completedResultsApplied == 2)
        #expect(controller.loadLivenessCounters.completedResultsDiscardedForOwnership == 0)
        #expect(controller.loadLivenessCounters.sameOwnerDriftCoalesced == 1)
        #expect(controller.loadLivenessCounters.followUpLoadsScheduled == 1)
    }

    @Test
    func `churn during follow-up still publishes each safe completion`() async {
        let revisionA = Self.configuration(revision: "rev-A")
        let revisionB = Self.configuration(revision: "rev-B")
        let revisionC = Self.configuration(revision: "rev-C")
        let revisionD = Self.configuration(revision: "rev-D")
        let revisionE = Self.configuration(revision: "rev-E")
        let builder = SpendDashboardLivenessBuildScript([
            .init(mode: .refreshMissing, request: Self.request(revisionA, mode: .refreshMissing)),
            .init(mode: .refreshMissing, request: Self.request(revisionC, mode: .refreshMissing)),
            .init(mode: .refreshMissing, request: Self.request(revisionE, mode: .refreshMissing)),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: revisionA)
        await Self.waitForPendingCount(1, gate: loader)
        controller.update(configuration: revisionB)
        controller.update(configuration: revisionC)

        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 5)], failedSourceIDs: []))
        await Self.waitForPendingCount(1, gate: loader)
        #expect(controller.model.groups.first?.totalCost == 5)
        #expect(controller.configuration == revisionC)

        controller.update(configuration: revisionD)
        controller.update(configuration: revisionE)
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 7)], failedSourceIDs: []))
        await Self.waitForPendingCount(1, gate: loader)

        // The follow-up result must not be discarded solely because E arrived.
        #expect(controller.model.groups.first?.totalCost == 7)
        #expect(controller.configuration == revisionE)

        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 11)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing }

        #expect(controller.model.groups.first?.totalCost == 11)
        #expect(builder.modes == [.refreshMissing, .refreshMissing, .refreshMissing])
        let loadedRevisions = await loader.configurations.map(\.sourceRevisions)
        #expect(loadedRevisions == [
            revisionA.sourceRevisions,
            revisionC.sourceRevisions,
            revisionE.sourceRevisions,
        ])
        #expect(controller.loadLivenessCounters.completedResultsApplied == 3)
        #expect(controller.loadLivenessCounters.completedResultsDiscardedForOwnership == 0)
    }

    @Test
    func `true owner change still invalidates the in-flight completion`() async {
        let firstOwner = Self.configuration(owner: "owner-one", revision: "rev-R")
        let secondOwner = Self.configuration(owner: "owner-two", revision: "rev-R")
        let builder = SpendDashboardLivenessBuildScript([
            .init(mode: .refreshMissing, request: Self.request(firstOwner, mode: .refreshMissing)),
            .init(mode: .refreshMissing, request: Self.request(secondOwner, mode: .refreshMissing)),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: firstOwner)
        await Self.waitForPendingCount(1, gate: loader)
        controller.update(configuration: secondOwner)
        await Self.waitForPendingCount(2, gate: loader)

        await loader.resume(at: 1, result: .init(inputs: [Self.input(cost: 2)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing }
        #expect(controller.model.groups.first?.totalCost == 2)
        #expect(controller.configuration == secondOwner)
        #expect(controller.generation == 2)

        // The stale first-owner completion must never publish.
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 99)], failedSourceIDs: []))
        await Task.yield()
        #expect(controller.model.groups.first?.totalCost == 2)
        #expect(controller.configuration == secondOwner)
    }

    @Test
    func `forced refresh under same-owner churn forces providers exactly once`() async {
        let initial = Self.configuration(revision: "rev-R")
        let latest = Self.configuration(revision: "rev-L")
        let builder = SpendDashboardLivenessBuildScript([
            .init(
                mode: .forceRefresh,
                request: Self.request(initial, mode: .forceRefresh, codexAccount: true)),
            .init(
                mode: .captureOnly,
                request: Self.request(
                    latest,
                    mode: .captureOnly,
                    inputs: [Self.input(id: "claude", provider: .claude, cost: 7)])),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: initial, force: true)
        await Self.waitForPendingCount(1, gate: loader)
        controller.update(configuration: latest)
        await Task.yield()
        // Same-owner churn during a forced refresh must not start another
        // provider force.
        #expect(builder.modes == [.forceRefresh])

        await loader.resume(at: 0, result: .init(
            inputs: [Self.input(id: "codex:a", provider: .codex, cost: 5)],
            failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing }

        #expect(builder.modes == [.forceRefresh, .captureOnly])
        #expect(await loader.forces == [true])
        #expect(controller.configuration == latest)
        #expect(controller.model.groups.first?.totalCost == 12)
    }

    @Test
    func `five revision burst performs exactly two loads and keeps progress visible`() async {
        let revisions = (1...5).map { Self.configuration(revision: "rev-\($0)") }
        let builder = SpendDashboardLivenessBuildScript([
            .init(mode: .refreshMissing, request: Self.request(revisions[0], mode: .refreshMissing)),
            .init(mode: .refreshMissing, request: Self.request(revisions[4], mode: .refreshMissing)),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: revisions[0])
        await Self.waitForPendingCount(1, gate: loader)
        for revision in revisions[1...] {
            controller.update(configuration: revision)
        }
        await Task.yield()
        #expect(await loader.pendingCount == 1)

        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 5)], failedSourceIDs: []))
        await Self.waitForPendingCount(1, gate: loader)
        // The coalesced follow-up targets the newest revision while the
        // already-published result stays visible.
        #expect(controller.model.groups.first?.totalCost == 5)
        let followUpRevisions = await loader.configurations.map(\.sourceRevisions)
        #expect(followUpRevisions == [revisions[0].sourceRevisions, revisions[4].sourceRevisions])

        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 11)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing }

        #expect(controller.model.groups.first?.totalCost == 11)
        #expect(await loader.configurations.count == 2)
        #expect(builder.modes == [.refreshMissing, .refreshMissing])
        #expect(controller.generation == 2)
    }

    private static func configuration(owner: String = "owner", revision: String) -> SpendDashboardConfiguration {
        SpendDashboardConfiguration(
            costUsageEnabled: true,
            providerIDs: [UsageProvider.codex.rawValue, UsageProvider.claude.rawValue],
            codexAccountIdentities: ["a|\(owner)"],
            sourceOwnershipFingerprints: ["claude:\(owner)"],
            sourceRevisions: [revision])
    }

    private static func request(
        _ configuration: SpendDashboardConfiguration,
        mode: SpendDashboardRequestBuildMode,
        inputs: [SpendDashboardModel.ProviderInput] = [],
        codexAccount: Bool = false) -> SpendDashboardLoadRequest
    {
        SpendDashboardLoadRequest(
            configuration: configuration,
            capturedInputs: inputs,
            unavailableSourceIDs: [],
            codexRequests: codexAccount ? [self.codexRequest()] : [],
            now: Date(timeIntervalSince1970: 1_784_179_200),
            force: mode.forcesLoader)
    }

    private static func codexRequest() -> CodexSpendScanRequest {
        CodexSpendScanRequest(
            id: "a",
            displayName: "Codex",
            source: .profileHome(path: "/synthetic/codex-a"),
            homePath: "/synthetic/codex-a",
            authFingerprint: nil,
            authFileWasReadable: false,
            cacheIdentity: "synthetic-a")
    }

    private static func input(
        id: String? = nil,
        provider: UsageProvider = .codex,
        cost: Double) -> SpendDashboardModel.ProviderInput
    {
        let entry = CostUsageDailyReport.Entry(
            date: "2026-07-15",
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: 10,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil)
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 10,
            last30DaysCostUSD: cost,
            daily: [entry],
            updatedAt: Date(timeIntervalSince1970: 1_784_179_200))
        return SpendDashboardModel.ProviderInput(
            id: id,
            provider: provider,
            displayName: provider.rawValue,
            modelProviderName: provider == .codex ? "Codex" : nil,
            snapshot: snapshot)
    }

    private static func waitForPendingCount(_ count: Int, gate: SpendDashboardLivenessLoaderGate) async {
        for _ in 0..<1000 {
            if await gate.pendingCount == count {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for \(count) pending loads")
    }

    private static func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<1000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for controller state")
    }
}

@MainActor
private final class SpendDashboardLivenessBuildScript {
    struct Step {
        let mode: SpendDashboardRequestBuildMode
        let request: SpendDashboardLoadRequest
    }

    private var steps: [Step]
    private(set) var modes: [SpendDashboardRequestBuildMode] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func next(_ mode: SpendDashboardRequestBuildMode) async -> SpendDashboardLoadRequest {
        guard !self.steps.isEmpty else {
            Issue.record("Unexpected dashboard build mode: \(mode)")
            return SpendDashboardLoadRequest(
                configuration: SpendDashboardConfiguration(
                    costUsageEnabled: false,
                    providerIDs: [],
                    codexAccountIdentities: []),
                capturedInputs: [],
                unavailableSourceIDs: [],
                codexRequests: [],
                now: Date(timeIntervalSince1970: 1_784_179_200),
                force: mode.forcesLoader)
        }
        let step = self.steps.removeFirst()
        self.modes.append(mode)
        #expect(mode == step.mode)
        return step.request
    }
}

private actor SpendDashboardLivenessLoaderGate {
    private var continuations: [CheckedContinuation<SpendDashboardLoadResult, Never>] = []
    private(set) var configurations: [SpendDashboardConfiguration] = []
    private(set) var forces: [Bool] = []

    var pendingCount: Int {
        self.continuations.count
    }

    func load(_ request: SpendDashboardLoadRequest) async -> SpendDashboardLoadResult {
        self.configurations.append(request.configuration)
        self.forces.append(request.force)
        return await withCheckedContinuation { continuation in
            self.continuations.append(continuation)
        }
    }

    func resume(at index: Int, result: SpendDashboardLoadResult) {
        self.continuations.remove(at: index).resume(returning: result)
    }
}
