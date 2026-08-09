import CodexBarSync
import Foundation
import Testing

/// Regression guard for the live four-provider notification inventory and the
/// frozen retirement inventory used by iOS subscription cleanup.
@Suite("QuotaProviderList contract")
struct QuotaProviderListTests {
    @Test
    func `Live provider inventory is exactly the four product providers`() {
        #expect(QuotaProviderList.providers.map(\.id) == ["codex", "claude", "cursor", "grok"])
        #expect(QuotaProviderList.providers.map(\.displayName) == ["Codex", "Claude", "Cursor", "Grok"])
    }

    @Test
    func `No duplicate or blank live provider fields`() {
        let ids = QuotaProviderList.providers.map(\.id)
        #expect(ids.count == Set(ids).count)
        for provider in QuotaProviderList.providers {
            #expect(!provider.id.isEmpty)
            #expect(!provider.displayName.isEmpty)
        }
    }

    @Test
    func `Zone-name wire format remains unchanged for live and retired IDs`() {
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "codex", state: "depleted")
                == "Quota-codex-depletedZone")
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "perplexity", state: "warning")
                == "Quota-perplexity-warningZone")
    }

    @Test
    func `Frozen retirement inventory yields exactly 168 cleanup subscription IDs`() {
        let liveIDs = Set(QuotaProviderList.providers.map(\.id))
        let retiredIDs = QuotaProviderList.retiredProviderIDs
        let states = ["depleted", "restored", "warning"]

        #expect(retiredIDs.count == 56)
        #expect(Set(retiredIDs).count == retiredIDs.count)
        #expect(Set(retiredIDs).isDisjoint(with: liveIDs))
        #expect(Set(retiredIDs).union(liveIDs).count == 60)
        #expect(retiredIDs.count * states.count == 168)
        #expect(retiredIDs.contains("perplexity"))
        #expect(retiredIDs.contains("notion"))
    }
}
