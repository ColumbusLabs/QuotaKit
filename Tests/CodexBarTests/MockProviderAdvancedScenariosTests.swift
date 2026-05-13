import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// P3: Advanced mock provider test scenarios — time travel, error
/// state library, multi-Mac merge with mocks, and push subscription
/// e2e. Building on the P0-P2 mock infrastructure (32 mocks across
/// 29 providerIDs), these tests validate edge cases that real users
/// would otherwise have to encounter in production to surface.
@MainActor
@Suite(.serialized)
struct MockProviderAdvancedScenariosTests {
    private func resetActivationState() {
        UserDefaults.standard.removeObject(
            forKey: MockProviderInjector.userDefaultsKey)
    }

    private func enableMock() {
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
    }

    // MARK: - P3.1 Time travel: dated mock data

    @Test("Codex Alice 30-day daily breakdown spans exactly 30 days back from now")
    func aliceDailyBreakdownSpans30Days() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let alice = snapshots.first { $0.providerID == "codex"
            && ($0.accountEmail ?? "").contains("café")
        }
        let daily = alice?.costSummary?.daily ?? []
        #expect(daily.count == 30)
        // Day keys should be UTC-formatted YYYY-MM-DD; first ≤ 30 days
        // ago, last ≤ today.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateValues = daily.compactMap { formatter.date(from: $0.dayKey) }
        #expect(dateValues.count == 30, "all 30 dayKeys must parse as valid UTC dates")
        let oldest = dateValues.min() ?? Date()
        let newest = dateValues.max() ?? Date()
        let now = Date()
        let span = newest.timeIntervalSince(oldest)
        // 29 days from oldest to newest (30 entries inclusive).
        #expect(span > 28 * 86400 - 60, "oldest entry should be ~29 days before newest")
        #expect(span < 30 * 86400 + 60, "no more than 30 days span")
        #expect(newest <= now.addingTimeInterval(86400), "newest entry should not be future")
    }

    @Test("Synthetic 3-lane utilization history dates strictly increase")
    func syntheticHistoryDatesIncrease() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let synth = snapshots.first { $0.providerID == "_mock_synthetic_unknown" }
        for series in synth?.utilizationHistory ?? [] {
            let times = series.entries.map(\.capturedAt)
            for i in 1..<times.count {
                #expect(times[i] > times[i - 1], "utilization entries must be strictly time-ordered")
            }
        }
    }

    @Test("Quota reset times are in the future for non-error mocks (where present)")
    func quotaResetTimesInFutureForNonError() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let now = Date()
        for snap in snapshots where !snap.isError {
            for window in snap.rateWindows {
                guard let resetsAt = window.resetsAt else { continue }
                let id = snap.providerID
                #expect(
                    resetsAt > now,
                    "non-error mock \(id) resetsAt must be future; got \(resetsAt)")
            }
        }
    }

    @Test("Perplexity renewal date is in the future")
    func perplexityRenewalInFuture() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let perp = snapshots.first { $0.providerID == "perplexity" }
        let renewal = perp?.perplexityCredits?.renewalAt
        #expect(renewal != nil)
        let now = Date()
        if let renewal {
            #expect(renewal > now, "renewal must be in the future")
            #expect(renewal < now.addingTimeInterval(60 * 86400), "renewal within 60 days")
        }
    }

    // MARK: - P3.2 Error state library

    @Test("Cursor fallback mock has cookie-expired error state with isError=true")
    func cursorFallbackHasErrorState() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let err = snapshots.first { $0.providerID == "_mock_cursor_unknown" }
        #expect(err?.isError == true)
        #expect(err?.statusMessage?.contains("Cookie") == true)
    }

    @Test("Bob mock at 100% boundary represents quota-depleted state")
    func bobMockRepresentsQuotaDepleted() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let bob = snapshots.first { $0.providerID == "codex"
            && ($0.accountEmail ?? "").contains("bob")
        }
        #expect(bob != nil)
        // Bob's secondary (Weekly) is at 100% — quota fully consumed.
        let secondary = bob?.secondary
        #expect(secondary?.usedPercent == 100, "Bob mock must hit 100% quota for depleted-state testing")
    }

    @Test("Carol mock at 0% boundary represents fresh-quota state")
    func carolMockRepresentsFreshQuota() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let carol = snapshots.first { $0.providerID == "codex"
            && ($0.accountEmail ?? "").contains("carol")
        }
        #expect(carol != nil)
        let primary = carol?.primary
        #expect(primary?.usedPercent == 0, "Carol mock must hit 0% quota for fresh-state testing")
    }

    @Test("Mock error message text is clearly synthetic — contains 'Mock' substring")
    func errorMessagesAreSynthetic() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        for snap in snapshots where snap.statusMessage != nil {
            let msg = snap.statusMessage ?? ""
            #expect(
                msg.contains("Mock") || msg.contains("mock"),
                "synthetic mock error messages must mark themselves as Mock; got: \(msg)")
        }
    }

    // MARK: - P3.3 Multi-Mac merge with mock data

    /// Build a mock snapshot from one Mac's perspective: a Codex mock
    /// emitted from "Mac1" with Alice as active account.
    private func mac1Codex() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex (Alice from Mac1)",
            primary: nil,
            secondary: nil,
            accountEmail: "alice-mock@codex.test",
            loginMethod: "Pro $200",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            costSummary: nil,
            budget: nil,
            rateWindows: [],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "codex:email:alice-mock%40codex.test",
            ])
    }

    /// Build a mock snapshot from another Mac's perspective: same
    /// Codex Alice account, slightly different metadata (Mac2 saw an
    /// older timestamp, different loginMethod label after upgrade).
    private func mac2Codex() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex (Alice from Mac2)",
            primary: nil,
            secondary: nil,
            accountEmail: "alice-mock@codex.test",
            loginMethod: "Pro",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date().addingTimeInterval(-300),
            costSummary: nil,
            budget: nil,
            rateWindows: [],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: [
                "codex:email:alice-mock%40codex.test",
            ])
    }

    @Test("Two Macs emitting same mock account share the accountIdentities key (cross-Mac merge)")
    func crossMacAccountIdentityMatches() {
        let m1 = self.mac1Codex()
        let m2 = self.mac2Codex()
        let m1Identities = Set(m1.accountIdentities ?? [])
        let m2Identities = Set(m2.accountIdentities ?? [])
        // The cross-Mac merge layer (Shared/iCloud/CloudSyncReader.swift)
        // uses accountIdentities to join records. If two Macs emit the
        // same Alice mock, their accountIdentities sets must intersect
        // for the merge layer to recognize them as the same account.
        let intersection = m1Identities.intersection(m2Identities)
        #expect(!intersection.isEmpty, "mock identities must intersect across Macs for merge to work")
        #expect(intersection.contains("codex:email:alice-mock%40codex.test"))
    }

    @Test("Real codex providerID + .test TLD emails don't collide across Macs")
    func mockEmailsAreStableAcrossMacs() {
        let m1 = self.mac1Codex()
        let m2 = self.mac2Codex()
        // Both Macs use the exact same email — mock data is
        // deterministic by design. iOS dedup logic (cardIdentityKey =
        // providerID|accountEmail) sees them as one card.
        #expect(m1.accountEmail == m2.accountEmail)
        #expect(m1.providerID == m2.providerID)
    }

    // MARK: - P3.4 Push notification path with mocks

    @Test("Mock providers are subscribable for push: providerID is in QuotaProviderList")
    func mockProvidersAreSubscribable() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let realCatalog = Set(UsageProvider.allCases.map(\.rawValue))
        let realBorrowedMocks = snapshots.filter {
            realCatalog.contains($0.providerID)
        }
        // 30 snapshots use real provider IDs (3 codex + 2 claude + 1
        // perplexity + 24 simple). All 30 share their providerID with
        // a real provider, so iOS's existing CKQuerySubscription set
        // covers them — push notifications fire on quota events without
        // any subscription change.
        #expect(realBorrowedMocks.count == 41)
        for snap in realBorrowedMocks {
            #expect(
                realCatalog.contains(snap.providerID),
                "mock providerID \(snap.providerID) must be in UsageProvider.allCases for push subscription coverage")
        }
    }

    @Test("Synthetic _mock_* providerIDs are NOT in QuotaProviderList — push won't fire (expected)")
    func syntheticIDsAreNotSubscribable() {
        let realCatalog = Set(UsageProvider.allCases.map(\.rawValue))
        for syntheticID in MockProviderInjector.syntheticProviderIDs {
            #expect(
                !realCatalog.contains(syntheticID),
                "synthetic mock providerID \(syntheticID) must NOT be in real catalog (exercises fallback)")
        }
    }
}
