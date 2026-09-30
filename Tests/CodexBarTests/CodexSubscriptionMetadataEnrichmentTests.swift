import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
@MainActor
struct CodexSubscriptionMetadataEnrichmentTests {
    @Test
    func `subscription enrichment is limited to uniquely authorized email only dashboards`() {
        let eligible = Self.input(
            identity: .emailOnly(normalizedEmail: "owner@example.com"),
            expectedEmail: "owner@example.com",
            signedInEmail: "OWNER@example.com")
        let eligibleDecision = CodexDashboardAuthority.evaluate(eligible)

        #expect(eligibleDecision.disposition == .attach)
        #expect(CodexSubscriptionMetadataEnrichmentPolicy.expectedEmail(
            input: eligible,
            decision: eligibleDecision) == "owner@example.com")
    }

    @Test
    func `subscription enrichment rejects scoped workspace and competing owner evidence`() {
        let workspaceAccount = Self.input(
            identity: .emailOnly(normalizedEmail: "owner@example.com"),
            expectedEmail: "owner@example.com",
            signedInEmail: "owner@example.com",
            dashboardAccountID: "workspace-1")
        let workspaceDecision = CodexDashboardAuthority.evaluate(workspaceAccount)
        #expect(CodexSubscriptionMetadataEnrichmentPolicy.expectedEmail(
            input: workspaceAccount,
            decision: workspaceDecision) == nil)

        let workspaceBalance = Self.input(
            identity: .emailOnly(normalizedEmail: "owner@example.com"),
            expectedEmail: "owner@example.com",
            signedInEmail: "owner@example.com",
            requiresWorkspaceBalanceScope: true)
        let workspaceBalanceDecision = CodexDashboardAuthority.evaluate(workspaceBalance)
        #expect(CodexSubscriptionMetadataEnrichmentPolicy.expectedEmail(
            input: workspaceBalance,
            decision: workspaceBalanceDecision) == nil)

        let ambiguous = Self.input(
            identity: .emailOnly(normalizedEmail: "owner@example.com"),
            expectedEmail: "owner@example.com",
            signedInEmail: "owner@example.com",
            sourceIsolationIdentifiers: ["managed-a", "managed-b"])
        let ambiguousDecision = CodexDashboardAuthority.evaluate(ambiguous)
        #expect(ambiguousDecision.disposition == .displayOnly)
        #expect(CodexSubscriptionMetadataEnrichmentPolicy.expectedEmail(
            input: ambiguous,
            decision: ambiguousDecision) == nil)
    }

    @Test
    func `subscription enrichment rejects provider account identity and cached dashboards`() {
        let providerAccount = Self.input(
            identity: .providerAccount(id: "workspace-1"),
            expectedEmail: "owner@example.com",
            signedInEmail: "owner@example.com",
            ownerIdentity: .providerAccount(id: "workspace-1"))
        let providerDecision = CodexDashboardAuthority.evaluate(providerAccount)
        #expect(providerDecision.disposition == .attach)
        #expect(CodexSubscriptionMetadataEnrichmentPolicy.expectedEmail(
            input: providerAccount,
            decision: providerDecision) == nil)

        let cachedDashboard = Self.input(
            sourceKind: .cachedDashboard,
            identity: .emailOnly(normalizedEmail: "owner@example.com"),
            expectedEmail: "owner@example.com",
            signedInEmail: "owner@example.com")
        let cachedDecision = CodexDashboardAuthority.evaluate(cachedDashboard)
        #expect(CodexSubscriptionMetadataEnrichmentPolicy.expectedEmail(
            input: cachedDashboard,
            decision: cachedDecision) == nil)
    }

    @Test
    func `authorized subscription enrichment updates dashboard cache and matching raw usage`() async throws {
        let fixture = self.makeFixture(suite: "CodexSubscriptionMetadataEnrichment-success")
        let metadata = OpenAISubscriptionMetadata(
            expiresAt: nil,
            renewsAt: Date(timeIntervalSince1970: 2_000_000_000))
        let fetch = SuspendedCodexSubscriptionMetadataFetch()

        try await self.withDashboardCache { _ in
            try await self.resolveEnrichment(
                fixture: fixture,
                fetch: fetch,
                result: .success(metadata),
                beforeResume: {})

            #expect(fetch.requestedEmails == [fixture.email])
            let enriched = fixture.dashboard.withSubscriptionMetadata(metadata)
            #expect(fixture.store.openAIDashboard == enriched)
            #expect(fixture.store.lastOpenAIDashboardSnapshot == enriched)

            let cache = try #require(OpenAIDashboardCacheStore.load())
            #expect(cache.accountEmail == fixture.email)
            #expect(cache.snapshot == enriched)

            let usage = try #require(fixture.store.snapshots[.codex])
            #expect(usage.primary == fixture.usage.primary)
            #expect(usage.secondary == fixture.usage.secondary)
            #expect(usage.updatedAt == fixture.usage.updatedAt)
            #expect(usage.subscriptionRenewsAt == metadata.renewsAt)
            #expect(usage.subscriptionExpiresAt == nil)
            await fixture.store.widgetSnapshotPersistTask?.value
        }
    }

    @Test
    func `superseded subscription enrichment cannot publish dashboard cache or raw usage`() async throws {
        let fixture = self.makeFixture(suite: "CodexSubscriptionMetadataEnrichment-stale-task")
        let oldTaskToken = UUID()
        let newTaskToken = UUID()
        fixture.store.openAIDashboardRefreshTaskToken = oldTaskToken
        let fetch = SuspendedCodexSubscriptionMetadataFetch()

        try await self.withDashboardCache { _ in
            try await self.resolveEnrichment(
                fixture: fixture,
                fetch: fetch,
                result: .success(OpenAISubscriptionMetadata(
                    expiresAt: nil,
                    renewsAt: Date(timeIntervalSince1970: 2_000_000_000))),
                refreshTaskToken: oldTaskToken,
                beforeResume: {
                    fixture.store.openAIDashboardRefreshTaskToken = newTaskToken
                })

            #expect(fixture.store.openAIDashboard == fixture.dashboard)
            #expect(fixture.store.lastOpenAIDashboardSnapshot == fixture.dashboard)
            #expect(try #require(OpenAIDashboardCacheStore.load()).snapshot == fixture.dashboard)
            #expect(try self.snapshotData(#require(fixture.store.snapshots[.codex])) == self
                .snapshotData(fixture.usage))
        }
    }

    @Test
    func `account transition discards suspended subscription enrichment`() async throws {
        let fixture = self.makeFixture(suite: "CodexSubscriptionMetadataEnrichment-account-transition")
        let fetch = SuspendedCodexSubscriptionMetadataFetch()

        try await self.withDashboardCache { _ in
            try await self.resolveEnrichment(
                fixture: fixture,
                fetch: fetch,
                result: .success(OpenAISubscriptionMetadata(
                    expiresAt: nil,
                    renewsAt: Date(timeIntervalSince1970: 2_000_000_000))),
                beforeResume: {
                    fixture.settings._test_liveSystemCodexAccount = Self.liveAccount(email: "next@example.com")
                })

            #expect(fixture.store.openAIDashboard == fixture.dashboard)
            #expect(fixture.store.lastOpenAIDashboardSnapshot == fixture.dashboard)
            #expect(try #require(OpenAIDashboardCacheStore.load()).snapshot == fixture.dashboard)
            #expect(try self.snapshotData(#require(fixture.store.snapshots[.codex])) == self
                .snapshotData(fixture.usage))
        }
    }

    private func snapshotData(_ snapshot: UsageSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(snapshot)
    }

    private func resolveEnrichment(
        fixture: Fixture,
        fetch: SuspendedCodexSubscriptionMetadataFetch,
        result: OpenAISubscriptionFetchResult,
        refreshTaskToken: UUID? = nil,
        beforeResume: @MainActor () -> Void) async throws
    {
        let loader: CodexSubscriptionMetadataEnrichmentTestOverrides.Loader = { email in
            await fetch.load(email: email)
        }
        let completion: CodexSubscriptionMetadataEnrichmentTestOverrides.Completion = { fetch.finish() }
        try await CodexSubscriptionMetadataEnrichmentTestOverrides.$loader.withValue(loader, operation: {
            try await CodexSubscriptionMetadataEnrichmentTestOverrides.$completion.withValue(completion, operation: {
                await fixture.store.applyOpenAIDashboard(
                    fixture.dashboard,
                    targetEmail: fixture.email,
                    expectedGuard: fixture.refreshGuard,
                    refreshTaskToken: refreshTaskToken,
                    allowCodexUsageBackfill: false)
                guard await fetch.waitUntilStarted(timeout: .seconds(2)) else {
                    fetch.abort()
                    _ = await fetch.waitUntilFinished(timeout: .seconds(2))
                    throw EnrichmentTestError.timeout("dashboard metadata fetch did not start")
                }
                beforeResume()
                fetch.resume(with: result)
                guard await fetch.waitUntilFinished(timeout: .seconds(2)) else {
                    throw EnrichmentTestError.timeout("dashboard metadata enrichment did not finish")
                }
            })
        })
        #expect(fetch.requestedEmails == [fixture.email])
    }

    private func withDashboardCache<T>(
        _ operation: @MainActor (URL) async throws -> T) async rethrows -> T
    {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-dashboard-enrichment-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        return try await OpenAIDashboardCacheStore.$cacheURLOverride.withValue(cacheURL) {
            try await operation(cacheURL)
        }
    }

    private func makeFixture(suite: String, email: String = "owner@example.com") -> Fixture {
        let suiteName = "\(suite)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "providerDetectionCompleted")
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suiteName),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-enrichment-\(UUID().uuidString)", isDirectory: true)
        let environment = [
            "HOME": home.path,
            "CODEX_HOME": home.appendingPathComponent(".codex", isDirectory: true).path,
            "XDG_CONFIG_HOME": home.appendingPathComponent(".config", isDirectory: true).path,
        ]
        settings._test_codexReconciliationEnvironment = environment
        settings._test_liveSystemCodexAccount = Self.liveAccount(email: email, home: home)
        settings.codexActiveSource = .liveSystem
        settings.codexCookieSource = .auto
        settings.openAIWebAccessEnabled = true
        settings.providerDetectionCompleted = true
        if let metadata = ProviderDescriptorRegistry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: metadata, enabled: true)
        }

        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(homeDirectory: home.path, cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: environment)
        store._test_widgetSnapshotSaveOverride = { _ in }
        let refreshGuard = store.freshCodexOpenAIWebRefreshGuard()
        let usage = UsageSnapshot(
            primary: RateWindow(usedPercent: 17, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 41, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            updatedAt: Date(timeIntervalSince1970: 1_900_000_000),
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: email,
                accountOrganization: nil,
                loginMethod: "Plus"))
        store.snapshots[.codex] = usage
        store.lastSourceLabels[.codex] = "codex-cli"
        store.lastCodexUsagePublicationGuard = refreshGuard
        store.lastCodexAccountScopedRefreshGuard = refreshGuard
        let dashboard = OpenAIDashboardSnapshot(
            signedInEmail: email,
            codeReviewRemainingPercent: 91,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            accountPlan: "Plus",
            updatedAt: Date(timeIntervalSince1970: 1_900_000_000))
        return Fixture(
            settings: settings,
            store: store,
            email: email,
            refreshGuard: refreshGuard,
            dashboard: dashboard,
            usage: usage)
    }

    private static func liveAccount(email: String, home: URL? = nil) -> ObservedSystemCodexAccount {
        ObservedSystemCodexAccount(
            email: email,
            authFingerprint: "synthetic-auth-\(email)",
            codexHomePath: home?.appendingPathComponent(".codex").path ?? "/synthetic/.codex",
            observedAt: Date(),
            identity: .emailOnly(normalizedEmail: email))
    }

    private static func input(
        sourceKind: CodexDashboardSourceKind = .liveWeb,
        identity: CodexIdentity,
        expectedEmail: String?,
        signedInEmail: String?,
        dashboardAccountID: String? = nil,
        requiresWorkspaceBalanceScope: Bool = false,
        ownerIdentity: CodexIdentity? = nil,
        sourceIsolationIdentifiers: [String] = ["owner"])
        -> CodexDashboardAuthorityInput
    {
        CodexDashboardAuthorityInput(
            sourceKind: sourceKind,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: identity,
                expectedScopedEmail: expectedEmail,
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: signedInEmail,
                dashboardAccountID: dashboardAccountID,
                requiresWorkspaceBalanceScope: requiresWorkspaceBalanceScope,
                knownOwners: sourceIsolationIdentifiers.map { isolation in
                    CodexDashboardKnownOwnerCandidate(
                        identity: ownerIdentity ?? .emailOnly(normalizedEmail: "owner@example.com"),
                        normalizedEmail: "owner@example.com",
                        sourceIsolationIdentifier: isolation)
                }),
            routing: CodexDashboardRoutingHints(
                targetEmail: expectedEmail,
                lastKnownDashboardRoutingEmail: nil))
    }
}

@MainActor
private struct Fixture {
    let settings: SettingsStore
    let store: UsageStore
    let email: String
    let refreshGuard: CodexAccountScopedRefreshGuard
    let dashboard: OpenAIDashboardSnapshot
    let usage: UsageSnapshot
}

@MainActor
private final class SuspendedCodexSubscriptionMetadataFetch {
    private var started = false
    private var finished = false
    private var aborted = false
    private var resultContinuation: CheckedContinuation<OpenAISubscriptionFetchResult, Never>?
    private var startWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var finishWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var startTimeouts: [UUID: Task<Void, Never>] = [:]
    private var finishTimeouts: [UUID: Task<Void, Never>] = [:]
    private(set) var requestedEmails: [String] = []

    func load(email: String) async -> OpenAISubscriptionFetchResult {
        guard !self.aborted else { return .unavailable }
        self.requestedEmails.append(email)
        self.started = true
        self.resolveStartWaiters()
        return await withCheckedContinuation { self.resultContinuation = $0 }
    }

    func waitUntilStarted(timeout: Duration) async -> Bool {
        guard !self.started else { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            self.startWaiters[id] = continuation
            self.startTimeouts[id] = Task { [weak self] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                self?.resolveStartWaiter(id)
            }
        }
    }

    func resume(with result: OpenAISubscriptionFetchResult) {
        guard let continuation = self.resultContinuation else { return }
        self.resultContinuation = nil
        continuation.resume(returning: result)
    }

    func abort() {
        self.aborted = true
        self.resume(with: .unavailable)
    }

    func finish() {
        self.finished = true
        let pending = self.finishWaiters
        self.finishWaiters.removeAll()
        let timeouts = self.finishTimeouts
        self.finishTimeouts.removeAll()
        for task in timeouts.values {
            task.cancel()
        }
        for continuation in pending.values {
            continuation.resume(returning: true)
        }
    }

    func waitUntilFinished(timeout: Duration) async -> Bool {
        guard !self.finished else { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            self.finishWaiters[id] = continuation
            self.finishTimeouts[id] = Task { [weak self] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                self?.resolveFinishWaiter(id)
            }
        }
    }

    private func resolveStartWaiters() {
        let pending = self.startWaiters
        self.startWaiters.removeAll()
        let timeouts = self.startTimeouts
        self.startTimeouts.removeAll()
        for task in timeouts.values {
            task.cancel()
        }
        for continuation in pending.values {
            continuation.resume(returning: true)
        }
    }

    private func resolveStartWaiter(_ id: UUID) {
        guard let continuation = self.startWaiters.removeValue(forKey: id) else { return }
        self.startTimeouts.removeValue(forKey: id)?.cancel()
        continuation.resume(returning: false)
    }

    private func resolveFinishWaiter(_ id: UUID) {
        guard let continuation = self.finishWaiters.removeValue(forKey: id) else { return }
        self.finishTimeouts.removeValue(forKey: id)?.cancel()
        continuation.resume(returning: false)
    }
}

private enum EnrichmentTestError: Error {
    case timeout(String)
}
