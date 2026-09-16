import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct SpendDashboardRecalculationPerformanceTests {
    private nonisolated static let now = Date(timeIntervalSince1970: 1_784_179_200)

    @Test
    func `repeated configuration reads reuse the published snapshot fingerprint`() {
        let (settings, store) = Self.tokenStore(suiteName: "fingerprint-reuse")
        let snapshot = Self.snapshot(cost: 2.5)
        let beforePublicationCount = SpendDashboardSnapshotRevisionEncoder.fingerprintComputationCount
        store._setTokenSnapshotForTesting(snapshot, provider: .mistral)

        let firstCount = SpendDashboardSnapshotRevisionEncoder.fingerprintComputationCount
        let firstConfiguration = SpendDashboardSource.configuration(settings: settings, store: store)
        #expect(firstCount == beforePublicationCount + 1)
        #expect(firstConfiguration.sourceRevisions.contains { $0.hasSuffix(
            SpendDashboardSnapshotRevisionEncoder.fingerprint(snapshot)) })

        for mode in [MenuBarDisplayMode.pace, .both, .resetTime, .percent] {
            settings.menuBarDisplayMode = mode
            let repeatedConfiguration = SpendDashboardSource.configuration(settings: settings, store: store)
            #expect(repeatedConfiguration.sourceRevisions == firstConfiguration.sourceRevisions)
        }

        #expect(SpendDashboardSnapshotRevisionEncoder.fingerprintComputationCount == firstCount)
        #expect(
            SpendDashboardSource.configuration(settings: settings, store: store).sourceRevisions ==
                firstConfiguration.sourceRevisions)
    }

    @Test
    func `a new publication computes and exposes one new semantic fingerprint`() {
        let (settings, store) = Self.tokenStore(suiteName: "fingerprint-publication")
        let firstSnapshot = Self.snapshot(cost: 1)
        store._setTokenSnapshotForTesting(firstSnapshot, provider: .mistral)
        let firstConfiguration = SpendDashboardSource.configuration(settings: settings, store: store)
        let firstCount = SpendDashboardSnapshotRevisionEncoder.fingerprintComputationCount

        let secondSnapshot = Self.snapshot(cost: 7)
        store._setTokenSnapshotForTesting(secondSnapshot, provider: .mistral)
        let secondConfiguration = SpendDashboardSource.configuration(settings: settings, store: store)

        #expect(SpendDashboardSnapshotRevisionEncoder.fingerprintComputationCount == firstCount + 1)
        #expect(secondConfiguration.sourceRevisions != firstConfiguration.sourceRevisions)
        #expect(secondConfiguration.sourceRevisions.contains { $0.hasSuffix(
            SpendDashboardSnapshotRevisionEncoder.fingerprint(secondSnapshot)) })

        settings.updateProviderConfig(provider: .mistral) { config in
            config.enterpriseHost = "owner-b.invalid"
        }
        #expect(store.tokenSnapshotPublicationForCurrentProviderConfig(for: .mistral) == nil)
        #expect(SpendDashboardSource.configuration(settings: settings, store: store).sourceRevisions
            .contains("mistral:unavailable"))
    }

    @Test
    func `equivalent snapshots have a deterministic semantic fingerprint`() {
        let first = Self.snapshot(cost: 3)
        let equivalent = Self.snapshot(cost: 3)
        let changed = Self.snapshot(cost: 4)

        #expect(SpendDashboardSnapshotRevisionEncoder.fingerprint(first) ==
            SpendDashboardSnapshotRevisionEncoder.fingerprint(equivalent))
        #expect(SpendDashboardSnapshotRevisionEncoder.fingerprint(first) !=
            SpendDashboardSnapshotRevisionEncoder.fingerprint(changed))
    }

    @Test
    func `an identical model key avoids another full derivation`() async {
        let configuration = Self.configuration()
        let input = Self.input()
        let probe = SpendDashboardRecalculationBuildProbe()
        let controller = Self.controller(
            configuration: configuration,
            input: input,
            probe: probe,
            modelBuilder: { request in
                request.build()
            })

        controller.update(configuration: configuration)
        await Self.waitForBuilds(1, controller: controller)
        let firstModel = controller.model

        let menuOnlyConfiguration = Self.configuration(menuOwnershipFingerprint: "menu-only-change")
        controller.update(configuration: menuOnlyConfiguration)
        await Task.yield()

        #expect(probe.count == 1)
        #expect(controller.model == firstModel)
        #expect(controller.modelDerivationCounters.snapshot.buildsExecuted == 1)
        #expect(controller.modelDerivationCounters.snapshot.cacheHits > 0)
    }

    @Test
    func `the production model builder executes outside the main thread`() async {
        let probe = SpendDashboardRecalculationBuildProbe()
        let controller = Self.controller(
            configuration: Self.configuration(),
            input: Self.input(),
            probe: probe,
            modelBuilder: { request in
                request.build()
            })

        controller.update(configuration: Self.configuration())
        await Self.waitForBuilds(1, controller: controller)

        #expect(probe.mainThreadFlags == [false])
    }

    @Test
    func `a stale background model cannot replace a newer selection`() async {
        let gate = SpendDashboardRecalculationBuildGate()
        let controller = Self.controller(
            configuration: Self.configuration(),
            input: Self.input(),
            probe: nil,
            modelBuilder: { request in
                gate.build(request)
            })
        defer { gate.releaseFirstBuild() }

        controller.update(configuration: Self.configuration())
        await Self.waitUntil { gate.firstBuildStarted.value }

        controller.selectDays(90)
        await Self.waitUntil {
            controller.model.requestedDays == 90 &&
                controller.modelDerivationCounters.snapshot.buildCompletions >= 1
        }
        gate.releaseFirstBuild()
        await Self.waitUntil {
            controller.model.requestedDays == 90 &&
                controller.modelDerivationCounters.snapshot.staleCompletionsDiscarded >= 1
        }

        #expect(controller.model.requestedDays == 90)
        #expect(controller.modelDerivationCounters.snapshot.staleCompletionsDiscarded == 1)
    }

    @Test
    func `semantic model changes rebuild while menu-only changes do not`() async {
        let configuration = Self.configuration()
        let input = Self.input()
        let probe = SpendDashboardRecalculationBuildProbe()
        let controller = Self.controller(
            configuration: configuration,
            input: input,
            probe: probe,
            modelBuilder: { request in
                request.build()
            })

        controller.update(configuration: configuration)
        await Self.waitForBuilds(1, controller: controller)

        controller.selectDays(90)
        await Self.waitForBuilds(2, controller: controller)

        let currencyConfiguration = Self.configuration(preferredCurrencyCode: "EUR")
        controller.update(configuration: currencyConfiguration)
        await Self.waitForBuilds(3, controller: controller)

        let hiddenConfiguration = Self.configuration(
            preferredCurrencyCode: "EUR",
            hiddenSourceIDs: [input.id])
        controller.update(configuration: hiddenConfiguration)
        await Self.waitForBuilds(4, controller: controller)

        controller.selectDay(Self.now)
        await Self.waitForBuilds(5, controller: controller)

        let sourceRevisionConfiguration = Self.configuration(
            preferredCurrencyCode: "EUR",
            hiddenSourceIDs: [input.id],
            sourceRevision: "source-2")
        controller.update(configuration: sourceRevisionConfiguration)
        await Self.waitForBuilds(6, controller: controller)

        let buildsBeforeMenuChange = probe.count
        let menuOnlyConfiguration = Self.configuration(
            preferredCurrencyCode: "EUR",
            hiddenSourceIDs: [input.id],
            sourceRevision: "source-2",
            menuOwnershipFingerprint: "menu-only-change")
        controller.update(configuration: menuOnlyConfiguration)
        await Task.yield()

        #expect(probe.count == buildsBeforeMenuChange)

        let request = SpendDashboardModelBuildRequest(
            configuration: sourceRevisionConfiguration,
            inputs: [input],
            requestedDays: 90,
            now: Self.now,
            calendar: sourceRevisionConfiguration.bucketCalendar,
            preferredCurrencyCode: sourceRevisionConfiguration.preferredCurrencyCode,
            hiddenSourceIDs: Set(sourceRevisionConfiguration.hiddenSourceIDs),
            hideNativeCodexWhenOpenCodexPresent:
            sourceRevisionConfiguration.hideNativeCodexCostWhenOpenCodexPresent,
            selectedDay: Self.now)
        let nextDayRequest = SpendDashboardModelBuildRequest(
            configuration: sourceRevisionConfiguration,
            inputs: [input],
            requestedDays: 90,
            now: Self.now.addingTimeInterval(86400),
            calendar: sourceRevisionConfiguration.bucketCalendar,
            preferredCurrencyCode: sourceRevisionConfiguration.preferredCurrencyCode,
            hiddenSourceIDs: Set(sourceRevisionConfiguration.hiddenSourceIDs),
            hideNativeCodexWhenOpenCodexPresent:
            sourceRevisionConfiguration.hideNativeCodexCostWhenOpenCodexPresent,
            selectedDay: Self.now)
        let pacificConfiguration = Self.configuration(
            preferredCurrencyCode: "EUR",
            hiddenSourceIDs: [input.id],
            sourceRevision: "source-2",
            bucketTimeZoneIdentifier: "America/Los_Angeles")
        let timeZoneRequest = SpendDashboardModelBuildRequest(
            configuration: pacificConfiguration,
            inputs: [input],
            requestedDays: 90,
            now: Self.now,
            calendar: pacificConfiguration.bucketCalendar,
            preferredCurrencyCode: pacificConfiguration.preferredCurrencyCode,
            hiddenSourceIDs: Set(pacificConfiguration.hiddenSourceIDs),
            hideNativeCodexWhenOpenCodexPresent:
            pacificConfiguration.hideNativeCodexCostWhenOpenCodexPresent,
            selectedDay: Self.now)

        #expect(request.key != nextDayRequest.key)
        #expect(request.key != timeZoneRequest.key)
    }

    @Test
    func `publication model reuses the controller derivation and isolates scopes`() async {
        let configuration = Self.configuration()
        let input = Self.input()
        let probe = SpendDashboardRecalculationBuildProbe()
        let controller = Self.controller(
            configuration: configuration,
            input: input,
            probe: probe,
            modelBuilder: { request in
                request.build()
            })

        controller.update(configuration: configuration)
        await Self.waitForBuilds(1, controller: controller)
        let publication = controller.publication
        let before = controller.modelDerivationCounters.snapshot
        let reused = publication.model(
            requestedDays: controller.selectedDays,
            now: Self.now,
            calendar: configuration.bucketCalendar,
            preferredCurrencyCode: configuration.preferredCurrencyCode,
            selectedDay: controller.selectedDay)

        #expect(reused == controller.model)
        #expect(controller.modelDerivationCounters.snapshot.buildsExecuted == before.buildsExecuted)
        #expect(controller.modelDerivationCounters.snapshot.cacheHits > before.cacheHits)

        let scoped = publication.model(
            requestedDays: controller.selectedDays,
            now: Self.now,
            calendar: configuration.bucketCalendar,
            preferredCurrencyCode: configuration.preferredCurrencyCode,
            providerScope: [])
        let afterScopedBuild = controller.modelDerivationCounters.snapshot
        let scopedAgain = publication.model(
            requestedDays: controller.selectedDays,
            now: Self.now,
            calendar: configuration.bucketCalendar,
            preferredCurrencyCode: configuration.preferredCurrencyCode,
            providerScope: [])

        #expect(scoped.groups.isEmpty)
        #expect(scopedAgain == scoped)
        #expect(afterScopedBuild.buildsExecuted == before.buildsExecuted + 1)
        #expect(controller.modelDerivationCounters.snapshot.buildsExecuted == afterScopedBuild.buildsExecuted)
    }

    @Test
    func `source ownership changes cannot reuse an old cached model`() async {
        let originalConfiguration = Self.configuration(sourceOwnership: "owner-a")
        let input = Self.input()
        let probe = SpendDashboardRecalculationBuildProbe()
        let controller = Self.controller(
            configuration: originalConfiguration,
            input: input,
            probe: probe,
            modelBuilder: { request in
                request.build()
            })

        controller.update(configuration: originalConfiguration)
        await Self.waitForBuilds(1, controller: controller)
        let original = controller.publication
        let replacementConfiguration = Self.configuration(sourceOwnership: "owner-b")
        let replacement = SpendDashboardPublication(
            revision: original.revision + 1,
            generation: original.generation + 1,
            configuration: replacementConfiguration,
            loadedAt: original.loadedAt,
            isRefreshing: false,
            inputs: original.inputs,
            sources: original.sources,
            modelCache: original.modelCache)
        let before = controller.modelDerivationCounters.snapshot.buildsExecuted

        _ = replacement.model(
            requestedDays: 30,
            now: Self.now,
            calendar: replacementConfiguration.bucketCalendar,
            preferredCurrencyCode: replacementConfiguration.preferredCurrencyCode)

        #expect(controller.modelDerivationCounters.snapshot.buildsExecuted == before + 1)
    }

    private static func tokenStore(suiteName: String) -> (SettingsStore, UsageStore) {
        let settings = testSettingsStore(suiteName: "SpendDashboardRecalculationPerformanceTests-\(suiteName)")
        settings.costUsageEnabled = true
        if let metadata = ProviderRegistry.shared.metadata[.mistral] {
            settings.setProviderEnabled(provider: .mistral, metadata: metadata, enabled: true)
        }
        settings.costUsageBucketTimeZoneIdentifier = "UTC"
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        return (settings, store)
    }

    private static func configuration(
        sourceOwnership: String = "owner-a",
        preferredCurrencyCode: String = "USD",
        hiddenSourceIDs: [String] = [],
        sourceRevision: String = "source-1",
        bucketTimeZoneIdentifier: String = "UTC",
        menuOwnershipFingerprint: String = "") -> SpendDashboardConfiguration
    {
        SpendDashboardConfiguration(
            costUsageEnabled: true,
            preferredCurrencyCode: preferredCurrencyCode,
            providerIDs: [UsageProvider.claude.rawValue],
            codexAccountIdentities: [],
            sourceOwnershipFingerprints: ["claude:\(sourceOwnership)"],
            sourceRevisions: ["claude:\(sourceRevision)"],
            bucketTimeZoneIdentifier: bucketTimeZoneIdentifier,
            hiddenSourceIDs: hiddenSourceIDs,
            menuOwnershipFingerprint: menuOwnershipFingerprint)
    }

    private static func controller(
        configuration: SpendDashboardConfiguration,
        input: SpendDashboardModel.ProviderInput,
        probe: SpendDashboardRecalculationBuildProbe?,
        modelBuilder: @escaping SpendDashboardController.ModelBuilder) -> SpendDashboardController
    {
        let box = SpendDashboardRecalculationControllerBox()
        let controller = SpendDashboardController(
            userDefaults: UserDefaults(suiteName: "SpendDashboardRecalculation-\(UUID().uuidString)")!,
            requestBuilder: { mode in
                let currentConfiguration = box.controller?.configuration ?? configuration
                return SpendDashboardLoadRequest(
                    configuration: currentConfiguration,
                    capturedInputs: [],
                    unavailableSourceIDs: [],
                    codexRequests: [],
                    now: Self.now,
                    force: mode.forcesLoader)
            },
            loader: { _ in
                SpendDashboardLoadResult(inputs: [input], failedSourceIDs: [])
            },
            nowProvider: { Self.now },
            modelBuilder: { request in
                probe?.record(request)
                return modelBuilder(request)
            })
        box.controller = controller
        return controller
    }

    private static func input() -> SpendDashboardModel.ProviderInput {
        SpendDashboardModel.ProviderInput(
            id: "claude",
            provider: .claude,
            displayName: "Claude",
            snapshot: self.snapshot(cost: 5))
    }

    private static func snapshot(cost: Double, day: String = "2026-07-15") -> CostUsageTokenSnapshot {
        let entry = CostUsageDailyReport.Entry(
            date: day,
            inputTokens: 10,
            outputTokens: 5,
            totalTokens: 15,
            costUSD: cost,
            modelsUsed: ["fictional-model"],
            modelBreakdowns: [
                CostUsageDailyReport.ModelBreakdown(
                    modelName: "fictional-model",
                    costUSD: cost,
                    totalTokens: 15),
            ])
        return CostUsageTokenSnapshot(
            sessionTokens: 15,
            sessionCostUSD: cost,
            last30DaysTokens: 15,
            last30DaysCostUSD: cost,
            currencyCode: "USD",
            historyDays: 30,
            daily: [entry],
            updatedAt: Self.now)
    }

    private static func waitForBuilds(_ count: Int, controller: SpendDashboardController) async {
        await self.waitUntil {
            controller.modelDerivationCounters.snapshot.buildCompletions >= count
        }
    }

    private static func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<2000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for spend dashboard state")
    }
}

private final class SpendDashboardRecalculationBuildProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [SpendDashboardModelBuildRequest] = []
    private var recordedMainThreadFlags: [Bool] = []

    var count: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recordedRequests.count
    }

    var mainThreadFlags: [Bool] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recordedMainThreadFlags
    }

    func record(_ request: SpendDashboardModelBuildRequest) {
        self.lock.lock()
        self.recordedRequests.append(request)
        self.recordedMainThreadFlags.append(Thread.isMainThread)
        self.lock.unlock()
    }
}

@MainActor
private final class SpendDashboardRecalculationControllerBox {
    weak var controller: SpendDashboardController?
}

private final class SpendDashboardRecalculationBuildGate: @unchecked Sendable {
    let firstBuildStarted = LockIsolated(false)
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    func build(_ request: SpendDashboardModelBuildRequest) -> SpendDashboardModel {
        if request.requestedDays == 30, !self.firstBuildStarted.value {
            self.firstBuildStarted.setValue(true)
            self.releaseSemaphore.wait()
        }
        return SpendDashboardModel(requestedDays: request.requestedDays, groups: [])
    }

    func releaseFirstBuild() {
        self.releaseSemaphore.signal()
    }
}
