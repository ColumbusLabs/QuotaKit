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

    @Test("All mock providerIDs are prefixed `_mock_` for safe identification")
    func allMockIDsAreMockPrefixed() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        #expect(!snapshots.isEmpty)
        for snap in snapshots {
            #expect(
                snap.providerID.hasPrefix("_mock_"),
                "all mock providers must use `_mock_` prefix; got: \(snap.providerID)")
        }
    }

    @Test("All mock provider names are clearly labeled `Mock`")
    func allMockNamesAreLabeled() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        for snap in snapshots {
            #expect(
                snap.providerName.contains("Mock"),
                "provider name must contain `Mock`; got: \(snap.providerName)")
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
                email.hasSuffix(".test"),
                "mock email must use `.test` TLD (RFC 6761 reserved); got: \(email)")
        }
    }

    @Test("Codex multi-account mock has 3 distinct accounts")
    func codexMockHas3DistinctAccounts() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let codexEntries = snapshots.filter {
            $0.providerID == "_mock_codex_multi"
        }
        #expect(codexEntries.count == 3, "Codex mock should have 3 accounts")
        let emails = Set(codexEntries.compactMap(\.accountEmail))
        #expect(emails.count == 3, "all 3 Codex accounts must have distinct emails")
    }

    @Test("Claude multi-account mock has 2 distinct accounts")
    func claudeMockHas2DistinctAccounts() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let claudeEntries = snapshots.filter {
            $0.providerID == "_mock_claude_multi"
        }
        #expect(claudeEntries.count == 2)
        let emails = Set(claudeEntries.compactMap(\.accountEmail))
        #expect(emails.count == 2)
    }

    @Test("Perplexity mock has structured credit breakdown")
    func perplexityMockHasCreditBreakdown() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let perplexity = snapshots.first {
            $0.providerID == "_mock_perplexity_credit"
        }
        #expect(perplexity != nil)
        let credits = perplexity?.perplexityCredits
        #expect(credits != nil, "Perplexity mock must populate perplexityCredits")
        #expect(credits?.recurringTotalCents == 50000)
        #expect(credits?.promoTotalCents == 10000)
        #expect(credits?.purchasedTotalCents == 25000)
        #expect(credits?.planName == "Pro")
    }

    @Test("Cursor error mock has isError + statusMessage")
    func cursorErrorMockHasErrorState() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let cursorError = snapshots.first {
            $0.providerID == "_mock_cursor_error"
        }
        #expect(cursorError != nil)
        #expect(cursorError?.isError == true)
        #expect(cursorError?.statusMessage != nil)
        #expect(cursorError?.statusMessage?.contains("Mock") == true)
    }

    @Test("Synthetic 3-lane mock has 3 rate windows + 30-day utilization history")
    func syntheticMockHas3LanesAndHistory() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        let synthetic = snapshots.first {
            $0.providerID == "_mock_synthetic_3lane"
        }
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

    @Test("All mock snapshots have non-empty accountIdentities (where applicable)")
    func mockSnapshotsHaveAccountIdentities() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.injectedSnapshots()
        // All mocks except the error-state cursor (which intentionally
        // sets accountIdentities to nil — exercises the legacy
        // per-device bucket fallback). Cursor mock still has a non-nil
        // accountEmail so iOS shows a "Mock Cursor (Cookie expired)"
        // card; only the cross-Mac merge identifier is intentionally
        // missing.
        let mocksWithIdentities = snapshots.filter {
            $0.providerID != "_mock_cursor_error"
        }
        for snap in mocksWithIdentities {
            #expect(
                (snap.accountIdentities?.count ?? 0) >= 1,
                "\(snap.providerID) should have ≥1 accountIdentities entry for cross-Mac merge")
        }
    }
}
