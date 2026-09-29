import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized, CodexCredentialFixtures())
struct CodexKeyringSpendDashboardTests {
    @Test
    func `ambient sessions publish local spend without auth json or account identity`() async throws {
        let root = CodexCredentialFixtures.root
        let home = root.appendingPathComponent(".codex", isDirectory: true)
        let sessions = home.appendingPathComponent("sessions", isDirectory: true)
        let archive = home.appendingPathComponent("archived_sessions", isDirectory: true)
        let now = Date()
        let day = CostUsageScanner.CostUsageDayRange.dayKey(from: now)
        let partition = sessions.appendingPathComponent(day.replacingOccurrences(of: "-", with: "/"))
        try FileManager.default.createDirectory(at: partition, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        for (directory, tokens) in [(partition, 1_000_000), (archive, 2_000_000)] {
            let contents = try Self.jsonl([
                [
                    "type": "turn_context",
                    "timestamp": Self.isoString(now),
                    "payload": ["model": "gpt-5.4"],
                ],
                [
                    "type": "event_msg",
                    "timestamp": Self.isoString(now),
                    "payload": ["type": "token_count", "info": [
                        "last_token_usage": [
                            "input_tokens": tokens,
                            "cached_input_tokens": 0,
                            "output_tokens": 0,
                        ],
                        "model": "gpt-5.4",
                    ]],
                ],
            ])
            try contents.write(
                to: directory.appendingPathComponent("rollout-\(day)-\(tokens).jsonl"),
                atomically: true,
                encoding: .utf8)
        }

        let environment = ["HOME": root.path, "CODEX_HOME": home.path]
        let settings = Self.settings(environment: environment, root: root)
        let store = Self.store(settings: settings, environment: environment)
        let request = await SpendDashboardSource.makeRequest(
            settings: settings,
            store: store,
            mode: .forceRefresh,
            now: now)

        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path))
        #expect(request.configuration.codexAccountIdentities.count == 1)
        #expect(request.codexRequests.map(\.id) == ["local"])
        #expect(request.capturedInputs.isEmpty)
        let codexRequest = try #require(request.codexRequests.first)
        #expect(codexRequest.source == .liveSystem)
        #expect(codexRequest.homePath == home.path)
        #expect(codexRequest.authFingerprint == nil)
        #expect(!codexRequest.authFileWasReadable)
        #expect(SpendDashboardSource.codexAuthFingerprintMatches(codexRequest))

        let scannerOptions = CostUsageScanner.Options(
            codexSessionsRoot: sessions,
            cacheRoot: root.appendingPathComponent("cache", isDirectory: true),
            codexTraceDatabaseURL: root.appendingPathComponent("missing-traces.sqlite"))
        let fetcher = CostUsageFetcher(scannerOptions: scannerOptions)
        let result = await SpendDashboardSource.load(request) { context in
            try await fetcher.loadTokenSnapshot(
                provider: .codex,
                environment: environment,
                now: now,
                forceRefresh: context.force,
                codexHomePath: context.account.homePath,
                historyDays: context.historyDays,
                allowPricingRefresh: false,
                refreshPricingInBackground: false,
                includePiSessions: false)
        }

        #expect(result.failedSourceIDs.isEmpty)
        #expect(result.inputs.map(\.id) == ["codex:local"])
        #expect(result.inputs.first?.snapshot.sessionTokens == 3_000_000)
        #expect(try #require(result.inputs.first?.snapshot.sessionCostUSD) > 0)
        #expect(try #require(result.inputs.first?.snapshot.last30DaysCostUSD) > 0)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path))
    }

    @Test
    func `ambient source deduplicates live and aliased managed homes`() throws {
        let root = CodexCredentialFixtures.root
        let home = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let environment = ["HOME": root.path, "CODEX_HOME": home.path]
        let settings = Self.settings(environment: environment, root: root)
        let store = Self.store(settings: settings, environment: environment)
        let now = Date()

        settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "live@example.test",
            codexHomePath: home.path,
            observedAt: now)
        let liveRequests = SpendDashboardSource.codexRequests(settings: settings, store: store)
        #expect(liveRequests.count == 1)
        #expect(liveRequests.first?.source == .liveSystem)
        #expect(liveRequests.first?.id != "local")

        settings._test_liveSystemCodexAccount = nil
        let managedID = UUID()
        let managedHome = root.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: managedHome, withIntermediateDirectories: true)
        let managed = ManagedCodexAccount(
            id: managedID,
            email: "managed@example.test",
            managedHomePath: managedHome.path,
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        settings._test_activeManagedCodexAccount = managed
        settings._test_activeManagedCodexRemoteHomePath = managedHome.path
        settings.codexActiveSource = .managedAccount(id: managedID)

        let separateRequests = SpendDashboardSource.codexRequests(settings: settings, store: store)
        #expect(separateRequests.count == 2)
        #expect(separateRequests.first(where: { $0.id == "local" })?.homePath == home.path)
        #expect(separateRequests.first(where: { $0.source == .managedAccount(id: managedID) })?.homePath ==
            managedHome.path)
        #expect(Set(separateRequests.map(\.cacheIdentity)).count == 2)

        let aliasedHome = home.deletingLastPathComponent()
            .appendingPathComponent("unused", isDirectory: true)
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent(home.lastPathComponent, isDirectory: true)
        settings._test_activeManagedCodexRemoteHomePath = aliasedHome.path
        let aliasedRequests = SpendDashboardSource.codexRequests(settings: settings, store: store)
        #expect(aliasedRequests.count == 1)
        #expect(aliasedRequests.first?.homePath == home.path)
        #expect(aliasedRequests.first?.source == .managedAccount(id: managedID))
        #expect(aliasedRequests.first?.id != "local")
    }

    private static func settings(environment: [String: String], root: URL) -> SettingsStore {
        let settings = testSettingsStore(suiteName: "CodexKeyringSpendDashboardTests")
        settings._test_managedCodexAccountStoreURL = root.appendingPathComponent("accounts.json")
        settings._test_liveSystemCodexAccount = nil
        settings._test_codexReconciliationEnvironment = environment
        settings.codexActiveSource = .liveSystem
        settings.costUsageEnabled = true
        enableTestProviders([.codex], settings: settings)
        return settings
    }

    private static func store(settings: SettingsStore, environment: [String: String]) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(
                homeDirectory: environment["HOME"] ?? FileManager.default.temporaryDirectory.path,
                cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: environment)
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func jsonl(_ objects: [Any]) throws -> String {
        try objects.map { object in
            let data = try JSONSerialization.data(withJSONObject: object)
            guard let line = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "CodexKeyringSpendDashboardTests", code: 1)
            }
            return line
        }.joined(separator: "\n") + "\n"
    }
}
