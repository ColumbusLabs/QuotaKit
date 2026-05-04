import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// Unit tests for `MockProviderInjector` — the debug-only synthetic
/// provider data injector used for end-to-end iCloud sync testing
/// without real provider subscriptions.
///
/// See `Research/020-multi-account-comprehensive.md` (mock injection)
/// and `MockProviderInjector.swift` for activation details.
@MainActor
@Suite(.serialized)
struct MockProviderInjectorTests {
    /// Reset UserDefaults flag and env var before each test to avoid
    /// state leaking across cases.
    private func resetActivationState() {
        UserDefaults.standard.removeObject(
            forKey: MockProviderInjector.userDefaultsKey)
        // Env vars can't be unset from inside a process directly, but
        // since each test process inherits the launch env they should
        // not have CODEXBAR_MOCK_PROVIDERS set unless someone explicitly
        // exported it before running tests. We assume clean env.
    }

    @Test("Disabled by default — no mock snapshots")
    func defaultIsDisabled() {
        self.resetActivationState()
        #expect(!MockProviderInjector.isEnabled)
        #expect(MockProviderInjector.injectedSnapshots().isEmpty)
    }

    @Test("UserDefaults flag activates injection")
    func userDefaultsFlagActivates() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        #expect(MockProviderInjector.isEnabled)
        let snapshots = MockProviderInjector.injectedSnapshots()
        #expect(
            snapshots.count == 8,
            "5 mock provider IDs producing 8 ProviderUsageSnapshot entries (3 codex + 2 claude + 3 single-account)")
    }

    @Test("Disabled flag returns empty even with override")
    func disabledFlagReturnsEmpty() {
        self.resetActivationState()
        UserDefaults.standard.set(
            false, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        #expect(MockProviderInjector.injectedSnapshots().isEmpty)
    }

    @Test("Mock providerIDs are split: real-borrowed (for first-class iOS UI) + `_mock_*` (for fallback test)")
    func mockProviderIDsSplitRealAndSynthetic() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        #expect(!snapshots.isEmpty)
        let realBorrowed = MockProviderInjector.realProviderIDsBorrowedByMocks
        let synthetic = MockProviderInjector.syntheticProviderIDs
        for snap in snapshots {
            let id = snap.providerID
            let isAllowed = realBorrowed.contains(id) || synthetic.contains(id)
            #expect(isAllowed, "mock providerID must be in real-borrowed or synthetic allowlist; got \(id)")
        }
    }

    @Test("Synthetic providerIDs are exactly `_mock_*` prefixed (mock-only namespace)")
    func syntheticIDsArePrefixed() {
        for id in MockProviderInjector.syntheticProviderIDs {
            #expect(id.hasPrefix("_mock_"), "synthetic mock providerID must use `_mock_` prefix; got \(id)")
            #expect(id != "_mock_", "synthetic providerID must have non-empty suffix")
        }
    }

    @Test("All mock account emails use `.test` TLD (RFC 6761 reserved)")
    func allMockEmailsAreReservedTLD() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let accountedEmails = snapshots.compactMap(\.accountEmail)
        #expect(!accountedEmails.isEmpty)
        for email in accountedEmails {
            #expect(
                email.hasSuffix(MockProviderInjector.mockEmailTLD),
                "mock email must use `.test` TLD (RFC 6761 reserved); got: \(email)")
        }
    }

    @Test("Codex (real ID) mock has 3 distinct accounts on `codex` providerID")
    func codexMockHas3DistinctAccounts() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let codexEntries = snapshots.filter { $0.providerID == "codex" }
        #expect(codexEntries.count == 3, "3 Codex mocks on real `codex` providerID")
        let emails = Set(codexEntries.compactMap(\.accountEmail))
        #expect(emails.count == 3, "all 3 Codex mocks must have distinct emails")
        for email in emails {
            #expect(email.hasSuffix(".test"), "all 3 Codex mock emails must use .test TLD; got \(email)")
        }
    }

    @Test("Claude (real ID) mock has 2 distinct accounts on `claude` providerID")
    func claudeMockHas2DistinctAccounts() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let claudeEntries = snapshots.filter { $0.providerID == "claude" }
        #expect(claudeEntries.count == 2)
        let emails = Set(claudeEntries.compactMap(\.accountEmail))
        #expect(emails.count == 2)
    }

    @Test("Perplexity (real ID) mock has structured credit breakdown on `perplexity` providerID")
    func perplexityMockHasCreditBreakdown() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let perplexity = snapshots.first { $0.providerID == "perplexity" }
        #expect(perplexity != nil)
        let credits = perplexity?.perplexityCredits
        #expect(credits != nil, "Perplexity mock must populate perplexityCredits")
        #expect(credits?.recurringTotalCents == 50000)
        #expect(credits?.promoTotalCents == 10000)
        #expect(credits?.purchasedTotalCents == 25000)
        #expect(credits?.planName == "Pro")
    }

    @Test("Cursor fallback mock has isError + statusMessage on `_mock_cursor_unknown` providerID")
    func cursorErrorMockHasErrorState() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let errorMock = snapshots.first { $0.providerID == "_mock_cursor_unknown" }
        #expect(errorMock != nil)
        #expect(errorMock?.isError == true)
        #expect(errorMock?.statusMessage != nil)
        #expect(errorMock?.statusMessage?.contains("Mock") == true)
    }

    @Test("Synthetic fallback mock has 3 rate windows + 30-day utilization history")
    func syntheticMockHas3LanesAndHistory() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let synthetic = snapshots.first { $0.providerID == "_mock_synthetic_unknown" }
        #expect(synthetic != nil)
        #expect(synthetic?.rateWindows.count == 3, "3 lanes: 5h, weekly, search")
        #expect(synthetic?.utilizationHistory?.count == 3, "3 utilization series")
        let history = synthetic?.utilizationHistory ?? []
        for series in history {
            #expect(series.entries.count == 30, "30 days of history entries")
        }
        #expect(synthetic?.budget != nil, "Synthetic mock has a budget snapshot")
    }

    @Test("Mock data round-trips through JSON encoding")
    func mockDataRoundTripsJSON() throws {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
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
            #expect(decoded.providerName == snap.providerName)
            #expect(decoded.accountEmail == snap.accountEmail)
        }
    }

    @Test("All mock snapshots have non-empty accountIdentities (except cursor fallback)")
    func mockSnapshotsHaveAccountIdentities() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        // All mocks except the cursor error mock (which intentionally
        // sets accountIdentities to nil — exercises the legacy
        // per-device bucket fallback). The cursor error mock still has
        // a non-nil accountEmail so iOS shows it via fallback rendering;
        // only the cross-Mac merge identifier is intentionally missing.
        let mocksWithIdentities = snapshots.filter {
            $0.providerID != "_mock_cursor_unknown"
        }
        for snap in mocksWithIdentities {
            #expect(
                (snap.accountIdentities?.count ?? 0) >= 1,
                "\(snap.providerID) should have ≥1 accountIdentities entry for cross-Mac merge")
        }
    }

    @Test("Real-borrowed mocks include cost data so iPhone Cost dashboard is exercisable")
    func realBorrowedMocksHaveCostData() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let realBorrowed = MockProviderInjector.realProviderIDsBorrowedByMocks
        for snap in snapshots where realBorrowed.contains(snap.providerID) {
            let id = "\(snap.providerID)/\(snap.accountEmail ?? "?")"
            #expect(
                snap.costSummary != nil,
                "real-borrowed mock \(id) must carry costSummary for Cost dashboard")
        }
    }

    @Test("Codex Alice mock has 30-day daily breakdown so per-day chart is exercisable")
    func codexAliceHasDailyBreakdown() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let alice = snapshots.first { snap in
            snap.providerID == "codex"
                && (snap.accountEmail ?? "").contains("café")
        }
        #expect(alice != nil, "Alice mock should exist with non-ASCII café email")
        let daily = alice?.costSummary?.daily ?? []
        #expect(daily.count == 30, "Alice carries 30 days of daily cost points")
        let total = daily.reduce(0.0) { $0 + $1.costUSD }
        #expect(total > 0, "daily totals must sum to a positive value")
        for point in daily {
            #expect(!point.modelBreakdowns.isEmpty, "every daily point should have a model breakdown")
        }
    }
}
