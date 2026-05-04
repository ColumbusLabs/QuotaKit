import CodexBarSync
import Foundation
import Testing

@testable import CodexBarMobile

/// Pins the iOS-side mock detection contract introduced in iOS 1.5.2.
///
/// Mac 0.23.5+ injects synthetic providers via `MockProviderInjector`.
/// iOS detects them via `MockProviderDetector`, which gates the visual
/// treatment (MOCK badge, purple accent ring, top banner, Settings →
/// Diagnostics row).
///
/// **Detection contract** (must mirror Mac-side
/// `MockProviderInjector.realProviderIDsBorrowedByMocks` ∪
/// `syntheticProviderIDs` ∪ `mockEmailTLD`):
///
/// - REAL providerID + `*-mock@*.test` email → mock
/// - synthetic `_mock_*` providerID prefix → mock
/// - everything else → real data (no false positives on real users)
@Suite("Mock provider detection (iOS 1.5.2)")
struct MockProviderDetectorTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSnapshot(
        providerID: String,
        accountEmail: String?
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerID,
            primary: nil,
            secondary: nil,
            accountEmail: accountEmail,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.baseDate)
    }

    // MARK: - Real-borrowed providerID + .test TLD email = mock

    @Test("Real codex providerID + mock email TLD → mock")
    func realCodexProviderIDWithMockEmailIsMock() {
        let snap = self.makeSnapshot(
            providerID: "codex",
            accountEmail: "alice-mock@codex.test")
        #expect(MockProviderDetector.isMock(snap))
    }

    @Test("Real claude providerID + mock email TLD → mock")
    func realClaudeProviderIDWithMockEmailIsMock() {
        let snap = self.makeSnapshot(
            providerID: "claude",
            accountEmail: "personal-mock@claude.test")
        #expect(MockProviderDetector.isMock(snap))
    }

    @Test("Real perplexity providerID + mock email TLD → mock")
    func realPerplexityProviderIDWithMockEmailIsMock() {
        let snap = self.makeSnapshot(
            providerID: "perplexity",
            accountEmail: "pro-mock@perplexity.test")
        #expect(MockProviderDetector.isMock(snap))
    }

    @Test("Non-ASCII email with .test TLD → mock (caf\u{00E9}-mock@codex.test)")
    func nonASCIIEmailMockTLDIsMock() {
        let snap = self.makeSnapshot(
            providerID: "codex",
            accountEmail: "café-mock@codex.test")
        #expect(MockProviderDetector.isMock(snap))
    }

    // MARK: - Synthetic _mock_* providerID = mock

    @Test("_mock_cursor_unknown providerID → mock (regardless of email)")
    func syntheticCursorUnknownIsMock() {
        let snap = self.makeSnapshot(
            providerID: "_mock_cursor_unknown",
            accountEmail: "expired-mock@cursor.test")
        #expect(MockProviderDetector.isMock(snap))
    }

    @Test("_mock_synthetic_unknown providerID → mock")
    func syntheticUnknownIsMock() {
        let snap = self.makeSnapshot(
            providerID: "_mock_synthetic_unknown",
            accountEmail: "lanes-mock@synthetic.test")
        #expect(MockProviderDetector.isMock(snap))
    }

    @Test("Future _mock_*.providerID hypotheticals are mock")
    func futureSyntheticPrefixIsMock() {
        // Forward-compat: future fallback mocks named _mock_anything
        // should still be recognized.
        let snap = self.makeSnapshot(
            providerID: "_mock_future_provider",
            accountEmail: nil)
        #expect(MockProviderDetector.isMock(snap))
    }

    // MARK: - Real users without mock activation = NOT mock

    @Test("Real codex provider + real email → NOT mock")
    func realCodexProviderRealEmailIsNotMock() {
        let snap = self.makeSnapshot(
            providerID: "codex",
            accountEmail: "alice@example.com")
        #expect(!MockProviderDetector.isMock(snap))
    }

    @Test("Real claude provider + work email → NOT mock")
    func realClaudeProviderWorkEmailIsNotMock() {
        let snap = self.makeSnapshot(
            providerID: "claude",
            accountEmail: "user@anthropic.com")
        #expect(!MockProviderDetector.isMock(snap))
    }

    @Test("Real perplexity + nil email → NOT mock (no signal)")
    func realPerplexityNilEmailIsNotMock() {
        let snap = self.makeSnapshot(
            providerID: "perplexity",
            accountEmail: nil)
        #expect(!MockProviderDetector.isMock(snap))
    }

    @Test("Real cursor + .test in middle of email → NOT mock (must be TLD)")
    func realCursorTestInMiddleIsNotMock() {
        // Email like "test-user@example.com" doesn't END in `.test`
        // and shouldn't be misclassified.
        let snap = self.makeSnapshot(
            providerID: "cursor",
            accountEmail: "test-user@example.com")
        #expect(!MockProviderDetector.isMock(snap))
    }

    @Test("Empty email → NOT mock")
    func emptyEmailIsNotMock() {
        let snap = self.makeSnapshot(
            providerID: "codex",
            accountEmail: "")
        #expect(!MockProviderDetector.isMock(snap))
    }

    // MARK: - Snapshot-level helpers

    @Test("hasAnyMock detects single mock among real providers")
    func hasAnyMockMixed() {
        let real = self.makeSnapshot(
            providerID: "codex", accountEmail: "real@example.com")
        let mock = self.makeSnapshot(
            providerID: "codex", accountEmail: "alice-mock@codex.test")
        let snapshot = SyncedUsageSnapshot(
            providers: [real, mock],
            syncTimestamp: self.baseDate,
            deviceName: "Mac",
            appVersion: "0.23.5",
            mobileVersion: "1.5.2")
        #expect(MockProviderDetector.hasAnyMock(in: snapshot))
        #expect(MockProviderDetector.mockCount(in: snapshot) == 1)
    }

    @Test("hasAnyMock false when all providers are real")
    func hasAnyMockAllReal() {
        let real = self.makeSnapshot(
            providerID: "codex", accountEmail: "real@example.com")
        let snapshot = SyncedUsageSnapshot(
            providers: [real],
            syncTimestamp: self.baseDate,
            deviceName: "Mac",
            appVersion: "0.23.5",
            mobileVersion: "1.5.2")
        #expect(!MockProviderDetector.hasAnyMock(in: snapshot))
        #expect(MockProviderDetector.mockCount(in: snapshot) == 0)
    }

    @Test("hasAnyMock false when snapshot is nil")
    func hasAnyMockNilSnapshot() {
        #expect(!MockProviderDetector.hasAnyMock(in: nil))
        #expect(MockProviderDetector.mockCount(in: nil) == 0)
        #expect(MockProviderDetector.mockSnapshots(in: nil).isEmpty)
    }

    @Test("mockCount counts all 8 mocks when full mock set is present")
    func mockCountFull8() {
        let mocks = [
            ("codex", "alice-mock@codex.test"),
            ("codex", "bob-mock@codex.test"),
            ("codex", "carol-mock@codex.test"),
            ("claude", "personal-mock@claude.test"),
            ("claude", "work-mock@claude.test"),
            ("perplexity", "pro-mock@perplexity.test"),
            ("_mock_cursor_unknown", "expired-mock@cursor.test"),
            ("_mock_synthetic_unknown", "lanes-mock@synthetic.test"),
        ].map { self.makeSnapshot(providerID: $0.0, accountEmail: $0.1) }
        let snapshot = SyncedUsageSnapshot(
            providers: mocks,
            syncTimestamp: self.baseDate,
            deviceName: "Mac",
            appVersion: "0.23.5",
            mobileVersion: "1.5.2")
        #expect(MockProviderDetector.mockCount(in: snapshot) == 8)
    }

    // MARK: - Constants

    @Test("Detector constants match Mac-side wire contract")
    func constantsAlignWithMac() {
        #expect(MockProviderDetector.mockEmailTLD == ".test")
        #expect(MockProviderDetector.mockProviderIDPrefix == "_mock_")
    }
}
