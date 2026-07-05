import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// Pins the subtitle selection rule for multi-account provider cards
/// introduced in iOS 1.3.0 (72).
///
/// Before T5, `ProviderUsageView`'s header always showed `accountEmail`
/// when non-nil (good) and was silent when nil — so two Codex cards that
/// both lacked email rendered indistinguishably. Worse, the `ContentView`
/// ForEach used `\.providerID` as SwiftUI identity, which collapsed
/// multiple-card entries down to one view instance in the list regardless
/// of what the data layer emitted.
///
/// These tests lock in:
///   - Single card (ordinal=nil) with email → subtitle is the email
///   - Single card (ordinal=nil) without email → subtitle is nil (clean layout)
///   - Multi-card (ordinal set) with email → email wins
///   - Multi-card (ordinal set) without email → "providerName N" ordinal fallback
///   - `cardIdentityKey` matches `CloudSyncReader.mergeSnapshots`'s bucket
@Suite("Provider card subtitle selection (T5)")
struct ProviderUsageViewSubtitleTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    private func makeSnapshot(
        providerID: String = "codex",
        providerName: String = "Codex",
        accountEmail: String?) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerName,
            primary: nil,
            secondary: nil,
            accountEmail: accountEmail,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.baseDate)
    }

    // MARK: - cardIdentityKey

    @Test
    func `cardIdentityKey includes accountEmail when present`() {
        let snap = self.makeSnapshot(accountEmail: "alice@example.com")
        #expect(snap.cardIdentityKey == "codex|alice@example.com")
    }

    @Test
    func `cardIdentityKey collapses nil accountEmail to empty tail (matches mergeSnapshots bucket)`() {
        let snap = self.makeSnapshot(accountEmail: nil)
        #expect(snap.cardIdentityKey == "codex|")
    }

    @Test
    func `Two distinct accounts → distinct cardIdentityKeys (so ForEach doesn't collapse)`() {
        let alice = self.makeSnapshot(accountEmail: "alice@example.com")
        let bob = self.makeSnapshot(accountEmail: "bob@example.com")
        #expect(alice.cardIdentityKey != bob.cardIdentityKey)
    }

    // MARK: - Subtitle selection

    @Test
    func `Single-card + email → subtitle is the email`() {
        let view = ProviderUsageView(
            provider: self.makeSnapshot(accountEmail: "alice@example.com"),
            duplicateOrdinal: nil)
        #expect(view.subtitleLine() == "alice@example.com")
    }

    @Test
    func `Single-card + nil email → subtitle is nil (clean layout)`() {
        let view = ProviderUsageView(
            provider: self.makeSnapshot(accountEmail: nil),
            duplicateOrdinal: nil)
        #expect(view.subtitleLine() == nil)
    }

    @Test
    func `Multi-card + email → email still wins (never show bare ordinal when email is attributable)`() {
        let view = ProviderUsageView(
            provider: self.makeSnapshot(accountEmail: "alice@example.com"),
            duplicateOrdinal: 1)
        #expect(view.subtitleLine() == "alice@example.com")
    }

    @Test
    func `Multi-card + nil email → ordinal fallback (localized template)`() {
        let view = ProviderUsageView(
            provider: self.makeSnapshot(accountEmail: nil),
            duplicateOrdinal: 2)
        let result = view.subtitleLine()
        // Template is `%@ %lld`-shaped in source locale; must contain the
        // provider name and the ordinal digits somewhere. Asserting on
        // substring rather than exact match keeps the test tolerant of
        // locale-specific reorderings (e.g. zh-Hans appends ` 号账户`).
        #expect(result != nil)
        #expect(result?.contains("Codex") == true)
        #expect(result?.contains("2") == true)
    }

    @Test
    func `Multi-card + empty string email treated as nil`() {
        // Defense against the bucket-merge fallback where `accountEmail: ""`
        // would otherwise render as a blank row. The subtitle helper
        // explicitly checks `!email.isEmpty`.
        let view = ProviderUsageView(
            provider: self.makeSnapshot(accountEmail: ""),
            duplicateOrdinal: 3)
        #expect(view.subtitleLine() != nil)
        #expect(view.subtitleLine()?.isEmpty == false)
    }
}
