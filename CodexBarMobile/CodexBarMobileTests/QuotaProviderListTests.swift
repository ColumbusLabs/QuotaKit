import CodexBarSync
import Testing
@testable import CodexBarMobile

@Suite("Quota provider list")
struct QuotaProviderListTests {
    @Test
    func `Live provider inventory is exactly the four product providers`() {
        #expect(QuotaKitProviderCatalog.providerIDs == ["codex", "claude", "cursor", "grok"])
        #expect(QuotaProviderList.providers.map(\.id) == QuotaKitProviderCatalog.providerIDs)
        #expect(QuotaProviderList.providers.map(\.displayName) == ["Codex", "Claude", "Cursor", "Grok"])
    }

    @Test
    func `Live subscription inventory is twelve unique provider-state IDs`() {
        let ids = QuotaTransitionSubscriptions.managedSubscriptionIDs(
            providerIDs: QuotaProviderList.providers.map(\.id))

        #expect(ids.count == 12)
        #expect(Set(ids).count == 12)
    }

    @Test
    func `Frozen retirement inventory covers 56 providers and excludes live IDs`() {
        let retired = QuotaProviderList.retiredProviderIDs
        let live = Set(QuotaProviderList.providers.map(\.id))

        #expect(retired.count == 56)
        #expect(Set(retired).count == retired.count)
        #expect(Set(retired).isDisjoint(with: live))
        #expect(Set(retired).union(live).count == 60)
    }

    @Test
    func `Zone name wire format remains unchanged`() {
        #expect(QuotaProviderList.quotaZoneName(
            providerID: "codex", state: "depleted") == "Quota-codex-depletedZone")
        #expect(QuotaProviderList.quotaZoneName(
            providerID: "grok", state: "warning") == "Quota-grok-warningZone")
    }
}
