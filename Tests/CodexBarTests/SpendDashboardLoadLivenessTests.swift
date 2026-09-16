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
        await Self.waitForModelDerivation(controller)

        // The identity-safe completed result must become visible even though
        // newer same-owner revisions arrived while it ran.
        #expect(controller.model.groups.first?.totalCost == 5)
        // The newest desired configuration must survive; applying A must not
        // roll the controller back to the stale revision.
        #expect(controller.configuration == revisionD)
        #expect(controller.generation == 2)

        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 9)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

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
        await Self.waitForModelDerivation(controller)
        #expect(controller.model.groups.first?.totalCost == 5)
        #expect(controller.configuration == revisionC)

        controller.update(configuration: revisionD)
        controller.update(configuration: revisionE)
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 7)], failedSourceIDs: []))
        await Self.waitForPendingCount(1, gate: loader)
        await Self.waitForModelDerivation(controller)

        // The follow-up result must not be discarded solely because E arrived.
        #expect(controller.model.groups.first?.totalCost == 7)
        #expect(controller.configuration == revisionE)

        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 11)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

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
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }
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
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

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
        await Self.waitForModelDerivation(controller)
        // The coalesced follow-up targets the newest revision while the
        // already-published result stays visible.
        #expect(controller.model.groups.first?.totalCost == 5)
        let followUpRevisions = await loader.configurations.map(\.sourceRevisions)
        #expect(followUpRevisions == [revisions[0].sourceRevisions, revisions[4].sourceRevisions])

        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 11)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

        #expect(controller.model.groups.first?.totalCost == 11)
        #expect(await loader.configurations.count == 2)
        #expect(builder.modes == [.refreshMissing, .refreshMissing])
        #expect(controller.generation == 2)
    }

    @Test
    func `display-only change during ordinary load publishes without a replacement load`() async {
        let revisionA = Self.configuration(revision: "rev-A")
        let displayDrift = Self.configuration(
            revision: "rev-A",
            currency: "auto",
            hiddenSourceIDs: ["claude"],
            hideNativeCodex: true)
        let builder = SpendDashboardLivenessBuildScript([
            .init(mode: .refreshMissing, request: Self.request(revisionA, mode: .refreshMissing)),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: revisionA)
        await Self.waitForPendingCount(1, gate: loader)

        // Currency, hidden-source, and native-Codex visibility state are
        // presentation-only: they rebuild locally and start no source work.
        controller.update(configuration: displayDrift)
        await Task.yield()
        #expect(await loader.pendingCount == 1)
        #expect(builder.modes == [.refreshMissing])

        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 5)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

        // The identity-safe result publishes; no replacement source load runs
        // solely because of display drift, and newest presentation survives.
        #expect(controller.model.groups.first?.totalCost == 5)
        #expect(controller.configuration == displayDrift)
        #expect(controller.configuration?.preferredCurrencyCode == "auto")
        #expect(controller.configuration?.hiddenSourceIDs == ["claude"])
        #expect(controller.configuration?.hideNativeCodexCostWhenOpenCodexPresent == true)
        #expect(controller.generation == 1)
        #expect(builder.modes == [.refreshMissing])
        #expect(await loader.configurations.count == 1)
    }

    @Test
    func `display-only change during forced reconciliation does not force again`() async {
        let initial = Self.configuration(revision: "rev-R")
        let displayDrift = Self.configuration(revision: "rev-R", currency: "auto")
        let captureGate = SpendDashboardLivenessBuildGate()
        let builder = SpendDashboardLivenessBuildScript([
            .init(
                mode: .forceRefresh,
                request: Self.request(initial, mode: .forceRefresh, codexAccount: true)),
            .init(
                mode: .captureOnly,
                request: Self.request(
                    initial,
                    mode: .captureOnly,
                    inputs: [Self.input(id: "claude", provider: .claude, cost: 7)]),
                gate: captureGate),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: initial, force: true)
        await Self.waitForPendingCount(1, gate: loader)
        await loader.resume(at: 0, result: .init(
            inputs: [Self.input(id: "codex:a", provider: .codex, cost: 5)],
            failedSourceIDs: []))
        await Self.waitForBuildGate(captureGate)

        controller.update(configuration: displayDrift)
        await Task.yield()
        // A presentation-only change must not start another provider force;
        // the capture build already in flight is the only expected addition.
        #expect(builder.modes == [.forceRefresh, .captureOnly])

        await captureGate.resume()
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

        #expect(builder.modes == [.forceRefresh, .captureOnly])
        #expect(await loader.forces == [true])
        #expect(controller.configuration == displayDrift)
        #expect(controller.model.groups.first?.totalCost == 12)
    }

    @Test
    func `codex display-name drift keeps newest label without a source reload`() async {
        let oldName = Self.configuration(revision: "rev-A", displayNames: ["codex:a": "Old"])
        let newName = Self.configuration(revision: "rev-A", displayNames: ["codex:a": "New"])
        let builder = SpendDashboardLivenessBuildScript([
            .init(mode: .refreshMissing, request: Self.request(oldName, mode: .refreshMissing)),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: oldName)
        await Self.waitForPendingCount(1, gate: loader)

        controller.update(configuration: newName)
        await Task.yield()
        #expect(await loader.pendingCount == 1)
        #expect(builder.modes == [.refreshMissing])

        await loader.resume(at: 0, result: .init(
            inputs: [Self.input(id: "codex:a", provider: .codex, cost: 5)],
            failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

        #expect(controller.model.groups.first?.totalCost == 5)
        // No source follow-up is required solely for the label.
        #expect(builder.modes == [.refreshMissing])
        #expect(await loader.configurations.count == 1)
        #expect(controller.configuration == newName)
        // Visible presentation uses the newest label ...
        let visibleNames = Dictionary(
            uniqueKeysWithValues: controller.publication.inputs.map { ($0.id, $0.displayName) })
        #expect(visibleNames["codex:a"] == "New")
        // ... while provenance still describes the request that produced data.
        #expect(controller.lastSuccessfulConfiguration == oldName)
    }

    @Test
    func `same-owner churn while request builder is gated still reaches the loader`() async throws {
        let revisionA = Self.configuration(revision: "rev-A")
        let revisionB = Self.configuration(revision: "rev-B")
        let revisionC = Self.configuration(revision: "rev-C")
        let buildGate = SpendDashboardLivenessBuildGate()
        let builder = SpendDashboardLivenessBuildScript([
            .init(
                mode: .refreshMissing,
                request: Self.request(revisionA, mode: .refreshMissing),
                gate: buildGate),
            .init(mode: .refreshMissing, request: Self.request(revisionC, mode: .refreshMissing)),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: revisionA)
        await Self.waitForBuildGate(buildGate)
        controller.update(configuration: revisionB)
        controller.update(configuration: revisionC)
        await buildGate.resume()

        // Revision churn during request construction must not starve the
        // builder: the identity-safe A request proceeds to the loader.
        await Self.waitForPendingCount(1, gate: loader)
        let firstLoaded = await loader.configurations.map(\.sourceRevisions)
        #expect(firstLoaded == [revisionA.sourceRevisions])

        try #require(await loader.pendingCount == 1)
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 5)], failedSourceIDs: []))
        await Self.waitForPendingCount(1, gate: loader)
        await Self.waitForModelDerivation(controller)
        #expect(controller.model.groups.first?.totalCost == 5)

        try #require(await loader.pendingCount == 1)
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 9)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

        #expect(controller.model.groups.first?.totalCost == 9)
        #expect(builder.modes == [.refreshMissing, .refreshMissing])
        let loadedRevisions = await loader.configurations.map(\.sourceRevisions)
        #expect(loadedRevisions == [revisionA.sourceRevisions, revisionC.sourceRevisions])
    }

    @Test
    func `hard ownership change while request builder is gated never loads stale owner`() async throws {
        let firstOwner = Self.configuration(owner: "owner-one", revision: "rev-R")
        let secondOwner = Self.configuration(owner: "owner-two", revision: "rev-R")
        let buildGate = SpendDashboardLivenessBuildGate()
        let builder = SpendDashboardLivenessBuildScript([
            .init(
                mode: .refreshMissing,
                request: Self.request(firstOwner, mode: .refreshMissing),
                gate: buildGate),
            .init(mode: .refreshMissing, request: Self.request(secondOwner, mode: .refreshMissing)),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: firstOwner)
        await Self.waitForBuildGate(buildGate)
        controller.update(configuration: secondOwner)
        await Self.waitForPendingCount(1, gate: loader)
        await buildGate.resume()
        await Task.yield()

        // The released owner-1 request belongs to a stale generation and must
        // never reach the loader as current-owner data.
        let loadedOwners = await loader.configurations.map(\.codexAccountIdentities)
        #expect(loadedOwners == [secondOwner.codexAccountIdentities])

        try #require(await loader.pendingCount == 1)
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 2)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

        #expect(controller.model.groups.first?.totalCost == 2)
        #expect(controller.configuration == secondOwner)
        #expect(builder.modes == [.refreshMissing, .refreshMissing])
    }

    @Test
    func `churn through gated follow-up build still publishes each safe result`() async throws {
        let revisionA = Self.configuration(revision: "rev-A")
        let revisionB = Self.configuration(revision: "rev-B")
        let revisionC = Self.configuration(revision: "rev-C")
        let revisionD = Self.configuration(revision: "rev-D")
        let revisionE = Self.configuration(revision: "rev-E")
        let firstBuildGate = SpendDashboardLivenessBuildGate()
        let followUpBuildGate = SpendDashboardLivenessBuildGate()
        let builder = SpendDashboardLivenessBuildScript([
            .init(
                mode: .refreshMissing,
                request: Self.request(revisionA, mode: .refreshMissing),
                gate: firstBuildGate),
            .init(
                mode: .refreshMissing,
                request: Self.request(revisionC, mode: .refreshMissing),
                gate: followUpBuildGate),
            .init(mode: .refreshMissing, request: Self.request(revisionE, mode: .refreshMissing)),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: revisionA)
        await Self.waitForBuildGate(firstBuildGate)
        controller.update(configuration: revisionB)
        controller.update(configuration: revisionC)
        await firstBuildGate.resume()
        await Self.waitForPendingCount(1, gate: loader)

        try #require(await loader.pendingCount == 1)
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 5)], failedSourceIDs: []))
        await Self.waitForBuildGate(followUpBuildGate)
        await Self.waitForModelDerivation(controller)
        #expect(controller.model.groups.first?.totalCost == 5)

        controller.update(configuration: revisionD)
        controller.update(configuration: revisionE)
        await followUpBuildGate.resume()
        await Self.waitForPendingCount(1, gate: loader)

        // The C follow-up still runs and publishes although E arrived.
        try #require(await loader.pendingCount == 1)
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 7)], failedSourceIDs: []))
        await Self.waitForPendingCount(1, gate: loader)
        await Self.waitForModelDerivation(controller)
        #expect(controller.model.groups.first?.totalCost == 7)

        try #require(await loader.pendingCount == 1)
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 11)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

        #expect(controller.model.groups.first?.totalCost == 11)
        #expect(builder.modes == [.refreshMissing, .refreshMissing, .refreshMissing])
        let loadedRevisions = await loader.configurations.map(\.sourceRevisions)
        #expect(loadedRevisions == [
            revisionA.sourceRevisions,
            revisionC.sourceRevisions,
            revisionE.sourceRevisions,
        ])
    }

    private static func configuration(
        owner: String = "owner",
        revision: String,
        currency: String = "USD",
        hiddenSourceIDs: [String] = [],
        hideNativeCodex: Bool = false,
        displayNames: [String: String] = [:],
        historyDays: Int = SpendDashboardSource.scanDays) -> SpendDashboardConfiguration
    {
        SpendDashboardConfiguration(
            costUsageEnabled: true,
            preferredCurrencyCode: currency,
            providerIDs: [UsageProvider.codex.rawValue, UsageProvider.claude.rawValue],
            codexAccountIdentities: ["a|\(owner)"],
            codexAccountDisplayNames: displayNames,
            sourceOwnershipFingerprints: ["claude:\(owner)"],
            sourceRevisions: [revision],
            hideNativeCodexCostWhenOpenCodexPresent: hideNativeCodex,
            hiddenSourceIDs: hiddenSourceIDs,
            codexHistoryDays: historyDays)
    }

    @Test
    func `history scope change during ordinary load invalidates the old scope`() async throws {
        let scope30 = Self.configuration(revision: "rev-A", historyDays: 30)
        let scope365 = Self.configuration(revision: "rev-A", historyDays: 365)
        let builder = SpendDashboardLivenessBuildScript([
            .init(
                mode: .refreshMissing,
                request: Self.request(scope30, mode: .refreshMissing, historyDays: 30)),
            .init(
                mode: .refreshMissing,
                request: Self.request(scope365, mode: .refreshMissing, historyDays: 365)),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: scope30)
        await Self.waitForPendingCount(1, gate: loader)
        controller.update(configuration: scope365)
        await Self.waitForPendingCount(2, gate: loader)

        // The stale 30-day completion must not publish as satisfying the
        // 365-day scope.
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 5)], failedSourceIDs: []))
        await Self.waitForPendingCount(1, gate: loader)
        #expect(controller.model.groups.isEmpty)
        #expect(controller.isRefreshing)

        try #require(await loader.pendingCount == 1)
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 9)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

        #expect(controller.model.groups.first?.totalCost == 9)
        #expect(controller.configuration == scope365)
        #expect(builder.modes == [.refreshMissing, .refreshMissing])
        #expect(await loader.historyDays == [30, 365])
    }

    @Test
    func `history scope change while request builder is gated never loads stale scope`() async throws {
        let scope30 = Self.configuration(revision: "rev-A", historyDays: 30)
        let scope365 = Self.configuration(revision: "rev-A", historyDays: 365)
        let buildGate = SpendDashboardLivenessBuildGate()
        let builder = SpendDashboardLivenessBuildScript([
            .init(
                mode: .refreshMissing,
                request: Self.request(scope30, mode: .refreshMissing, historyDays: 30),
                gate: buildGate),
            .init(
                mode: .refreshMissing,
                request: Self.request(scope365, mode: .refreshMissing, historyDays: 365)),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: scope30)
        await Self.waitForBuildGate(buildGate)
        controller.update(configuration: scope365)
        await Self.waitForPendingCount(1, gate: loader)
        await buildGate.resume()
        await Self.waitForPendingCount(1, gate: loader)

        // The released 30-day request belongs to a stale generation and must
        // never reach the loader as current-scope work.
        #expect(await loader.historyDays == [365])

        try #require(await loader.pendingCount == 1)
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 9)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

        #expect(controller.model.groups.first?.totalCost == 9)
        #expect(controller.configuration == scope365)
        #expect(builder.modes == [.refreshMissing, .refreshMissing])
    }

    @Test
    func `same history scope revision churn still publishes and coalesces`() async throws {
        let revisionA = Self.configuration(revision: "rev-A", historyDays: 30)
        let revisionB = Self.configuration(revision: "rev-B", historyDays: 30)
        let builder = SpendDashboardLivenessBuildScript([
            .init(
                mode: .refreshMissing,
                request: Self.request(revisionA, mode: .refreshMissing, historyDays: 30)),
            .init(
                mode: .refreshMissing,
                request: Self.request(revisionB, mode: .refreshMissing, historyDays: 30)),
        ])
        let loader = SpendDashboardLivenessLoaderGate()
        let controller = SpendDashboardController(
            requestBuilder: { mode in await builder.next(mode) },
            loader: { request in await loader.load(request) })

        controller.update(configuration: revisionA)
        await Self.waitForPendingCount(1, gate: loader)
        controller.update(configuration: revisionB)

        try #require(await loader.pendingCount == 1)
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 5)], failedSourceIDs: []))
        await Self.waitForPendingCount(1, gate: loader)
        await Self.waitForModelDerivation(controller)
        #expect(controller.model.groups.first?.totalCost == 5)

        try #require(await loader.pendingCount == 1)
        await loader.resume(at: 0, result: .init(inputs: [Self.input(cost: 9)], failedSourceIDs: []))
        await Self.waitUntil { !controller.isRefreshing && !controller.isModelDerivationInFlight }

        #expect(controller.model.groups.first?.totalCost == 9)
        #expect(builder.modes == [.refreshMissing, .refreshMissing])
        #expect(await loader.historyDays == [30, 30])
    }

    @Test
    func `built request history depth matches its configuration scope`() async {
        let (settings, store) = Self.historyScopeStore(suiteName: "SpendDashboardLoadLivenessTests-scope")
        let request = await SpendDashboardSource.makeRequest(
            settings: settings,
            store: store,
            mode: .refreshMissing,
            now: Date(timeIntervalSince1970: 1_784_179_200))

        #expect(request.codexHistoryDays == request.configuration.codexHistoryDays)
    }

    private static func historyScopeStore(suiteName: String) -> (SettingsStore, UsageStore) {
        let settings = testSettingsStore(suiteName: suiteName)
        settings.costUsageEnabled = true
        for provider in UsageProvider.allCases {
            guard let metadata = ProviderRegistry.shared.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: provider == .codex)
        }
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        return (settings, store)
    }

    private static func request(
        _ configuration: SpendDashboardConfiguration,
        mode: SpendDashboardRequestBuildMode,
        inputs: [SpendDashboardModel.ProviderInput] = [],
        codexAccount: Bool = false,
        historyDays: Int? = nil) -> SpendDashboardLoadRequest
    {
        SpendDashboardLoadRequest(
            configuration: configuration,
            capturedInputs: inputs,
            unavailableSourceIDs: [],
            codexRequests: codexAccount ? [self.codexRequest()] : [],
            codexHistoryDays: historyDays ?? configuration.codexHistoryDays,
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

    private static func waitForBuildGate(_ gate: SpendDashboardLivenessBuildGate) async {
        for _ in 0..<1000 {
            if await gate.isSuspended {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for dashboard build gate")
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

    private static func waitForModelDerivation(_ controller: SpendDashboardController) async {
        await self.waitUntil { !controller.isModelDerivationInFlight }
    }
}

@MainActor
private final class SpendDashboardLivenessBuildScript {
    struct Step {
        let mode: SpendDashboardRequestBuildMode
        let request: SpendDashboardLoadRequest
        let gate: SpendDashboardLivenessBuildGate?

        init(
            mode: SpendDashboardRequestBuildMode,
            request: SpendDashboardLoadRequest,
            gate: SpendDashboardLivenessBuildGate? = nil)
        {
            self.mode = mode
            self.request = request
            self.gate = gate
        }
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
        if let gate = step.gate {
            await gate.suspend()
        }
        return step.request
    }
}

private actor SpendDashboardLivenessBuildGate {
    private var continuation: CheckedContinuation<Void, Never>?

    var isSuspended: Bool {
        self.continuation != nil
    }

    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        self.continuation?.resume()
        self.continuation = nil
    }
}

private actor SpendDashboardLivenessLoaderGate {
    private var continuations: [CheckedContinuation<SpendDashboardLoadResult, Never>] = []
    private(set) var configurations: [SpendDashboardConfiguration] = []
    private(set) var forces: [Bool] = []
    private(set) var historyDays: [Int] = []

    var pendingCount: Int {
        self.continuations.count
    }

    func load(_ request: SpendDashboardLoadRequest) async -> SpendDashboardLoadResult {
        self.configurations.append(request.configuration)
        self.forces.append(request.force)
        self.historyDays.append(request.codexHistoryDays)
        return await withCheckedContinuation { continuation in
            self.continuations.append(continuation)
        }
    }

    func resume(at index: Int, result: SpendDashboardLoadResult) {
        self.continuations.remove(at: index).resume(returning: result)
    }
}
