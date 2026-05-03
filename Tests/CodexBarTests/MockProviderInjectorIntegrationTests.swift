// swiftlint:disable multiline_arguments
import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// MR2-MR5: extensibility, SyncCoordinator integration, mock+real
/// coexistence, and edge cases for `MockProviderInjector`.
///
/// MR1 (basic unit tests) lives in `MockProviderInjectorTests.swift`.
/// This file adds depth: 5+ rounds of testing with different conditions
/// to ensure the mock injection system is robust against real-world use.
///
/// See `Research/020-multi-account-comprehensive.md` (mock section).
@MainActor
@Suite(.serialized)
struct MockProviderInjectorIntegrationTests {
    private func resetActivationState() {
        UserDefaults.standard.removeObject(
            forKey: MockProviderInjector.userDefaultsKey)
    }

    private func enableMock() {
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
    }

    private func disableMock() {
        UserDefaults.standard.set(
            false, forKey: MockProviderInjector.userDefaultsKey)
    }

    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
    }

    // MARK: - MR2 Extensibility / determinism

    @Test("MR2.1: enabled count is exactly 8 (5 IDs, 3+2+1+1+1 entries)")
    func enabledCountIsStable() {
        self.enableMock()
        defer { self.resetActivationState() }
        #expect(MockProviderInjector.injectedSnapshots().count == 8)
    }

    @Test("MR2.2: all mock providerIDs are distinct or shared-by-multi-account")
    func providerIDsHaveSensibleDistribution() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let providerIDs = snapshots.map(\.providerID)
        let uniqueIDs = Set(providerIDs)
        // 5 distinct providerIDs total: codex_multi (3 entries),
        // claude_multi (2 entries), perplexity_credit, cursor_error,
        // synthetic_3lane.
        #expect(uniqueIDs.count == 5, "should be 5 distinct mock provider IDs")
        // Verify expected IDs present.
        let expected: Set<String> = [
            "_mock_codex_multi",
            "_mock_claude_multi",
            "_mock_perplexity_credit",
            "_mock_cursor_error",
            "_mock_synthetic_3lane",
        ]
        #expect(uniqueIDs == expected)
    }

    @Test("MR2.3: re-toggle returns the same providerIDs (deterministic)")
    func reToggleIsDeterministic() {
        self.enableMock()
        let firstIDs = Set(
            MockProviderInjector.injectedSnapshots().map(\.providerID))
        self.disableMock()
        #expect(MockProviderInjector.injectedSnapshots().isEmpty)
        self.enableMock()
        let secondIDs = Set(
            MockProviderInjector.injectedSnapshots().map(\.providerID))
        self.resetActivationState()
        #expect(firstIDs == secondIDs)
    }

    @Test("MR2.4: same call produces consistent providerName/email per ID")
    func sameCallStableNameEmail() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots1 = MockProviderInjector.injectedSnapshots()
        let snapshots2 = MockProviderInjector.injectedSnapshots()
        // Compare provider name + email pairs (not whole snapshot — timestamps differ)
        let pairs1 = Set(
            snapshots1.map { "\($0.providerName)|\($0.accountEmail ?? "")" })
        let pairs2 = Set(
            snapshots2.map { "\($0.providerName)|\($0.accountEmail ?? "")" })
        #expect(pairs1 == pairs2)
    }

    @Test("MR2.5: providerID prefix is exactly `_mock_` (no variations)")
    func prefixIsExact() {
        self.enableMock()
        defer { self.resetActivationState() }
        for snap in MockProviderInjector.injectedSnapshots() {
            #expect(snap.providerID.hasPrefix("_mock_"))
            #expect(!snap.providerID.hasPrefix("_mock_mock_"))
            #expect(snap.providerID != "_mock_")
        }
    }

    // MARK: - MR3 SyncCoordinator integration

    @Test("MR3.1: enabled mock causes 8 mock providers in lastSnapshot")
    func enabledMockEmitsViaSyncCoordinator() async throws {
        self.enableMock()
        defer { self.resetActivationState() }
        let settings = self.makeSettingsStore(suite: "MR3-1-Enable")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock,
            mockInjector: { MockProviderInjector.allMocks() })
        await coordinator.pushCurrentSnapshot()

        let mockProviders = mock.lastSnapshot?.providers
            .filter { $0.providerID.hasPrefix("_mock_") } ?? []
        #expect(mockProviders.count == 8)
    }

    @Test("MR3.2: empty mock injector closure causes 0 mock providers in lastSnapshot")
    func disabledMockEmitsNothing() async throws {
        let settings = self.makeSettingsStore(suite: "MR3-2-Disable")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        // Pass empty closure — simulates production "mock disabled" state.
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock,
            mockInjector: { [] })
        await coordinator.pushCurrentSnapshot()

        let mockProviders = mock.lastSnapshot?.providers
            .filter { $0.providerID.hasPrefix("_mock_") } ?? []
        #expect(mockProviders.isEmpty)
    }

    @Test("MR3.3: mock providers also flow through per-provider write path")
    func mockProvidersFlowToPerProviderZone() async throws {
        self.enableMock()
        defer { self.resetActivationState() }
        let settings = self.makeSettingsStore(suite: "MR3-3-PerProvider")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock,
            mockInjector: { MockProviderInjector.allMocks() })
        await coordinator.pushCurrentSnapshot()

        let mockEnvelopes = mock.lastPerProviderEnvelopes
            .filter { $0.provider.providerID.hasPrefix("_mock_") }
        #expect(mockEnvelopes.count == 8)
    }

    /// Reference wrapper so tests can flip the mock activation state
    /// while reusing the same `SyncCoordinator` instance across cycles.
    private final class MockSwitch {
        var enabled: Bool
        init(enabled: Bool) {
            self.enabled = enabled
        }
    }

    @Test("MR3.4: enable → disable → next push has no mock + delete fires immediately (whole-provider-gone)")
    func enableDisableTriggersGhostCleanup() async throws {
        // Each mock providerID is distinct from any real provider, so
        // when mock is disabled, every mock provider becomes
        // "whole-provider gone" (currentProviders no longer contains
        // them). Per R3 P1.2 logic, whole-provider-gone fires immediate
        // 1-cycle delete (matching the existing L1 contract for
        // "user disabled provider").
        let settings = self.makeSettingsStore(suite: "MR3-4-Cleanup")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        // Use class wrapper so closure can read mid-test toggle without
        // depending on process-global UserDefaults (which doesn't
        // isolate across parallel suites).
        let mockSwitch = MockSwitch(enabled: true)
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock,
            mockInjector: {
                mockSwitch.enabled ? MockProviderInjector.allMocks() : []
            })

        // Cycle 1: mock enabled → emit 8 mocks. No deletes (first push).
        await coordinator.pushCurrentSnapshot()
        #expect(mock.lastSnapshot?.providers.contains { $0.providerID.hasPrefix("_mock_") } == true)
        #expect(mock.deleteCallCount == 0)

        // Flip the in-memory switch.
        mockSwitch.enabled = false

        // Cycle 2: no mocks emitted. Whole-provider gone → immediate
        // 1-cycle delete for all mock recordNames.
        await coordinator.pushCurrentSnapshot()
        let cycle2Mocks = mock.lastSnapshot?.providers
            .filter { $0.providerID.hasPrefix("_mock_") } ?? []
        #expect(cycle2Mocks.isEmpty)
        #expect(mock.deleteCallCount == 1, "whole-provider-gone fires immediate delete in cycle 2")
        let lastDeletes = mock.deletedRecordNamesAcrossCalls.last ?? []
        let mockDeletes = lastDeletes.filter { $0.contains("_mock_") }
        #expect(
            mockDeletes.count >= 5,
            "all 5 mock providerIDs (with their per-account records, total 8) get delete-targeted")
    }

    @Test("MR3.5: mock providers don't disturb real provider sync")
    func mockDoesNotDisturbRealProvider() async throws {
        self.enableMock()
        defer { self.resetActivationState() }
        let settings = self.makeSettingsStore(suite: "MR3-5-Coexist")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)

        // Real Codex active snapshot.
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 30, windowMinutes: 300,
                    resetsAt: Date(), resetDescription: "test"),
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "real@example.com",
                    accountOrganization: nil,
                    loginMethod: "oauth")),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock,
            mockInjector: { MockProviderInjector.allMocks() })
        await coordinator.pushCurrentSnapshot()

        let allProviders = mock.lastSnapshot?.providers ?? []
        let realCodex = allProviders.filter { $0.providerID == "codex" }
        let mockProviders = allProviders.filter { $0.providerID.hasPrefix("_mock_") }
        #expect(realCodex.count == 1, "real Codex still emits its 1 record")
        #expect(realCodex.first?.accountEmail == "real@example.com")
        #expect(mockProviders.count == 8, "8 mock providers also emit")
        // Real and mock must not collide on providerID.
        let realIDs = Set(realCodex.map(\.providerID))
        let mockIDs = Set(mockProviders.map(\.providerID))
        #expect(realIDs.isDisjoint(with: mockIDs))
    }

    // MARK: - MR4 Mock + real coexistence

    @Test("MR4.1: mock providerIDs are completely disjoint from real UsageProvider.allCases")
    func mockProvidersAreDisjointFromAllReal() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let mockIDs = Set(snapshots.map(\.providerID))
        let realIDs = Set(UsageProvider.allCases.map(\.rawValue))
        #expect(
            mockIDs.isDisjoint(with: realIDs),
            "no mock providerID may collide with any real UsageProvider rawValue (per-Codex-MCP-review P2)")
    }

    @Test("MR4.2: mock per-account records have distinct CK record names")
    func mockMultiAccountRecordNamesDistinct() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        // Build composite record names like CloudSyncManager would.
        let deviceID = "test-device"
        let recordNames = snapshots.map { snap in
            CloudSyncManager.perProviderRecordName(
                deviceID: deviceID,
                providerID: snap.providerID,
                accountEmail: snap.accountEmail)
        }
        #expect(Set(recordNames).count == recordNames.count, "all 8 mock record names must be distinct")
    }

    @Test("MR4.3: mock multi-account uses accountIdentities for cross-Mac merge")
    func mockMultiAccountIdentitiesAlignWithRealSchema() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let codexMulti = snapshots.filter { $0.providerID == "_mock_codex_multi" }
        for snap in codexMulti {
            let ids = snap.accountIdentities ?? []
            #expect(ids.count >= 1)
            #expect(
                ids.contains { $0.hasPrefix("_mock_codex_multi:email:") },
                "schema must follow `{providerID}:{scheme}:{value}`")
        }
    }

    // MARK: - MR5 Edge cases / robustness

    /// Helper: build a transient UserDefaults so we can test isEnabled
    /// with controlled state (avoids polluting the shared standard
    /// defaults across test cases).
    private func transientDefaults(setEnabled: Bool?) -> UserDefaults {
        let suiteName = "MR5-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        if let value = setEnabled {
            defaults.set(value, forKey: MockProviderInjector.userDefaultsKey)
        }
        return defaults
    }

    @Test("MR5.1: env var `1` activates (parser-level)")
    func envVarValueOneActivates() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "1"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2: env var `true` (lowercase) activates")
    func envVarValueTrueActivates() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "true"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2b: env var `TRUE` (uppercase) activates")
    func envVarValueTrueUppercaseActivates() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "TRUE"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2c: env var `yes` activates")
    func envVarValueYesActivates() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "yes"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2d: env var `0` does NOT activate")
    func envVarValueZeroDoesNotActivate() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "0"]
        #expect(!MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2e: env var arbitrary value (`maybe`) does NOT activate")
    func envVarValueArbitraryDoesNotActivate() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "maybe"]
        #expect(!MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2f: env var truthy overrides UserDefaults disabled")
    func envVarTruthyOverridesUserDefaultsDisabled() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "1"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2g: UserDefaults true activates when env var absent")
    func userDefaultsActivatesWhenEnvVarAbsent() {
        let defaults = self.transientDefaults(setEnabled: true)
        let env: [String: String] = [:]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2h: env var falsy + UserDefaults true → activates (env var only acts when truthy)")
    func envVarFalsyDoesNotOverrideUserDefaultsTrue() {
        // Design choice: env var only activates when truthy. A falsy
        // env var doesn't deactivate UserDefaults. This means env var
        // is "force on" not "force on/off".
        let defaults = self.transientDefaults(setEnabled: true)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "0"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2i: env var name constant is exactly `CODEXBAR_MOCK_PROVIDERS`")
    func envVarNameIsConstant() {
        #expect(MockProviderInjector.environmentVariableName == "CODEXBAR_MOCK_PROVIDERS")
    }

    @Test("MR5.3: disabled state always returns empty array (not partial)")
    func disabledReturnsCompletelyEmpty() {
        self.disableMock()
        defer { self.resetActivationState() }
        for _ in 1...5 {
            #expect(MockProviderInjector.injectedSnapshots().isEmpty)
        }
    }

    @Test("MR5.4: every mock snapshot has lastUpdated within reasonable window")
    func mockTimestampsAreReasonable() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let now = Date()
        for snap in snapshots {
            let delta = abs(snap.lastUpdated.timeIntervalSince(now))
            #expect(delta < 60, "lastUpdated should be within 60 seconds of now (got \(delta)s)")
        }
    }

    @Test("MR5.5: synthetic 3-lane utilization history all entries within 30 days")
    func syntheticHistoryWithin30Days() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let synth = snapshots.first { $0.providerID == "_mock_synthetic_3lane" }
        let now = Date()
        let thirtyOneDaysAgo = now.addingTimeInterval(-31 * 86400)
        for series in synth?.utilizationHistory ?? [] {
            for entry in series.entries {
                #expect(entry.capturedAt > thirtyOneDaysAgo)
                #expect(entry.capturedAt <= now.addingTimeInterval(60))
            }
        }
    }

    @Test("MR5.6: error mock has no rate windows or cost (gracefully degraded)")
    func errorMockHasNoRateWindows() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let errMock = snapshots.first { $0.providerID == "_mock_cursor_error" }
        #expect(errMock?.primary == nil)
        #expect(errMock?.secondary == nil)
        #expect(errMock?.rateWindows.isEmpty == true)
        #expect(errMock?.costSummary == nil)
        #expect(errMock?.budget == nil)
    }

    @Test("MR5.7: Perplexity mock credit values are non-negative")
    func perplexityMockCreditsNonNegative() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let perp = snapshots.first { $0.providerID == "_mock_perplexity_credit" }
        let credits = perp?.perplexityCredits
        #expect((credits?.recurringTotalCents ?? -1) >= 0)
        #expect((credits?.recurringUsedCents ?? -1) >= 0)
        #expect((credits?.promoTotalCents ?? -1) >= 0)
        #expect((credits?.promoUsedCents ?? -1) >= 0)
        #expect((credits?.purchasedTotalCents ?? -1) >= 0)
        #expect((credits?.purchasedUsedCents ?? -1) >= 0)
    }

    @Test("MR5.8: usedPercent values stay in [0, 100] range across all mocks")
    func usedPercentInRange() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        for snap in snapshots {
            for window in snap.rateWindows {
                #expect(window.usedPercent >= 0)
                #expect(window.usedPercent <= 100)
            }
            if let primary = snap.primary {
                #expect(primary.usedPercent >= 0)
                #expect(primary.usedPercent <= 100)
            }
            if let secondary = snap.secondary {
                #expect(secondary.usedPercent >= 0)
                #expect(secondary.usedPercent <= 100)
            }
        }
    }

    @Test("MR5.9: mock snapshots are valid Codable (no encoding errors)")
    func mockSnapshotsAreValidCodable() throws {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for snap in snapshots {
            let data = try encoder.encode(snap)
            #expect(!data.isEmpty)
        }
    }

    @Test("MR5.9b: at least one mock has usedPercent at 0 boundary")
    func boundaryZeroPercentExists() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let zeroBoundary = snapshots.contains { snap in
            snap.rateWindows.contains { $0.usedPercent == 0 }
                || snap.primary?.usedPercent == 0
        }
        #expect(zeroBoundary, "at least one mock should exercise the 0% boundary (per-Codex-MCP-review P2)")
    }

    @Test("MR5.9c: at least one mock has usedPercent at 100 boundary")
    func boundaryHundredPercentExists() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let hundredBoundary = snapshots.contains { snap in
            snap.rateWindows.contains { $0.usedPercent == 100 }
                || snap.primary?.usedPercent == 100
                || snap.secondary?.usedPercent == 100
        }
        #expect(hundredBoundary, "at least one mock should exercise the 100% boundary (per-Codex-MCP-review P2)")
    }

    @Test("MR5.9d: at least one mock has non-ASCII accountEmail")
    func nonASCIIEmailExists() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let nonASCII = snapshots.contains { snap in
            guard let email = snap.accountEmail else { return false }
            return !email.allSatisfy(\.isASCII)
        }
        #expect(
            nonASCII,
            "at least one mock should have a non-ASCII email to exercise UTF-8 path (per-Codex-MCP-review P2)")
    }

    @Test("MR5.9e: non-ASCII email's accountIdentities is percent-encoded NFC form")
    func nonASCIIEmailIdentityEncoded() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let cafeMock = snapshots.first { snap in
            (snap.accountEmail ?? "").contains("café")
        }
        #expect(cafeMock != nil, "café mock should exist")
        let identities = cafeMock?.accountIdentities ?? []
        let cafeIdentity = identities.first { $0.contains("caf%C3%A9") }
        #expect(
            cafeIdentity != nil,
            "non-ASCII email's accountIdentities entry must contain percent-encoded NFC bytes `caf%C3%A9`")
    }

    @Test("MR5.10: Codable round-trip preserves all critical multi-account fields")
    func codableRoundTripPreservesIdentities() throws {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for snap in snapshots {
            let data = try encoder.encode(snap)
            let decoded = try decoder.decode(
                ProviderUsageSnapshot.self, from: data)
            #expect(decoded.providerID == snap.providerID)
            #expect(decoded.accountEmail == snap.accountEmail)
            #expect(decoded.accountIdentities == snap.accountIdentities)
            #expect(decoded.isError == snap.isError)
            #expect(decoded.providerName == snap.providerName)
        }
    }
}

// swiftlint:enable multiline_arguments
