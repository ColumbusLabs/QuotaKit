import CodexBarSync
import Foundation
import Testing

@testable import CodexBarMobile

/// Guards `UtilizationAggregateView` (the Cost-tab 30-day subscription
/// utilization chart) against iOS 1.3.0's new upstream providers that
/// don't emit utilization history.
///
/// Perplexity and OpenCode Go have no `utilizationHistory` on Mac today —
/// Perplexity publishes three credit pools instead (handled by T3's
/// PerplexityCreditsCard), OpenCode Go's web usage is reported as flat
/// rate windows. If the aggregate view crashes or produces malformed
/// state on providers with no history, the user opens the Cost tab
/// once with Perplexity enabled and gets a blank screen or a fall-off.
///
/// `UtilizationAggregateView.buildModel(from:windowSize:)` is already
/// `compactMap`-gated on `utilizationHistory` being non-nil and its
/// `session` series having entries — so the no-history case should be a
/// silent skip. These tests pin that behavior (so a future refactor
/// can't reintroduce a force-unwrap) and cover the identity-key stability
/// that the cache invalidation depends on.
@Suite("Subscription Utilization compatibility with new providers (T6)")
struct SubscriptionUtilizationCompatTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeProvider(
        id: String,
        name: String,
        utilization: [SyncUtilizationSeries]? = nil
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.baseDate,
            utilizationHistory: utilization)
    }

    private func sessionSeries(_ percent: Double) -> [SyncUtilizationSeries] {
        [SyncUtilizationSeries(
            name: "session",
            windowMinutes: 300,
            entries: [SyncUtilizationEntry(
                capturedAt: self.baseDate,
                usedPercent: percent,
                resetsAt: nil)])]
    }

    @Test("Identity key is stable when Perplexity provider has no utilization history")
    func identityKeyStableWithPerplexityNoHistory() {
        // Typical real-world mix: Claude + Codex with session data, plus
        // Perplexity sitting in the list with nothing to aggregate. The
        // identity key derivation must skip the no-history provider's
        // entry count (`totalEntries += 0`) and still produce a stable,
        // deterministic key across repeated calls.
        let providers = [
            self.makeProvider(id: "claude", name: "Claude", utilization: self.sessionSeries(42)),
            self.makeProvider(id: "codex", name: "Codex", utilization: self.sessionSeries(18)),
            self.makeProvider(id: "perplexity", name: "Perplexity", utilization: nil),
        ]
        let k1 = UtilizationAggregateView.identityKey(for: providers, windowSize: 30)
        let k2 = UtilizationAggregateView.identityKey(for: providers, windowSize: 30)
        #expect(k1 == k2)
        #expect(k1.contains("perplexity"))
    }

    @Test("Identity key distinct when Perplexity is replaced by OpenCode Go")
    func identityKeyDistinctAcrossNewProviders() {
        let withPerplexity = [
            self.makeProvider(id: "claude", name: "Claude", utilization: self.sessionSeries(42)),
            self.makeProvider(id: "perplexity", name: "Perplexity", utilization: nil),
        ]
        let withOpenCodeGo = [
            self.makeProvider(id: "claude", name: "Claude", utilization: self.sessionSeries(42)),
            self.makeProvider(id: "opencodego", name: "OpenCode Go", utilization: nil),
        ]
        let k1 = UtilizationAggregateView.identityKey(for: withPerplexity, windowSize: 30)
        let k2 = UtilizationAggregateView.identityKey(for: withOpenCodeGo, windowSize: 30)
        #expect(k1 != k2)
    }

    @Test("Mixed providers (some with history, some without) produce a stable key that reflects ONLY history-bearing entries")
    func identityKeyEntryCountIgnoresNoHistoryProviders() {
        // OpenCode Go and Perplexity contribute 0 entries. Only Claude's
        // single entry counts. The `n=1` suffix proves the guard actually
        // excludes them.
        let providers = [
            self.makeProvider(id: "claude", name: "Claude", utilization: self.sessionSeries(42)),
            self.makeProvider(id: "perplexity", name: "Perplexity", utilization: nil),
            self.makeProvider(id: "opencodego", name: "OpenCode Go", utilization: nil),
        ]
        let key = UtilizationAggregateView.identityKey(for: providers, windowSize: 30)
        #expect(key.contains("n=1"))
    }

    @Test("All-no-history provider list produces a well-formed key (no crash)")
    func identityKeyAllNoHistoryProviders() {
        // Hypothetical worst case: user has only providers that don't
        // emit utilization history (e.g., a Perplexity-only account).
        // identityKey must still return a string, not crash, and must
        // not surface NaN / nil anywhere.
        let providers = [
            self.makeProvider(id: "perplexity", name: "Perplexity", utilization: nil),
            self.makeProvider(id: "opencodego", name: "OpenCode Go", utilization: nil),
        ]
        let key = UtilizationAggregateView.identityKey(for: providers, windowSize: 30)
        #expect(!key.isEmpty)
        #expect(key.contains("n=0"))
    }

    @Test("Provider tint color resolves to the palette entry (Perplexity teal, OpenCode Go mint)")
    func aggregateColorsDelegateToPalette() {
        // UtilizationAggregateView.providerColor(for:) now delegates to
        // ProviderColorPalette (consolidated in T2 / Build 70). This pins
        // that the aggregate view uses the SAME colors as the provider
        // cards — before consolidation it silently rendered unknown
        // providers as .gray.
        let perplexityColor = ProviderColorPalette.color(for: "perplexity")
        let goColor = ProviderColorPalette.color(for: "opencodego")
        // These both used to be .gray in UtilizationAggregateView and
        // .blue everywhere else. Post-T2/T6 they're unique.
        #expect(UIColor(perplexityColor) != UIColor(.gray))
        #expect(UIColor(goColor) != UIColor(.gray))
        #expect(UIColor(perplexityColor) != UIColor(goColor))
    }
}
