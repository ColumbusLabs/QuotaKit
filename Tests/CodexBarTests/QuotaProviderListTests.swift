import CodexBarSync
import Foundation
import Testing

/// Regression guard for the provider list that seeds iOS CKRecordZoneSubscriptions.
///
/// iOS 1.3.0 adds Perplexity and OpenCode Go to align with upstream v0.20.
/// The provider set is the single source of truth for both:
///   - Mac side picks the CloudKit zone to write a QuotaTransition record to
///   - iOS side creates one CKRecordZoneSubscription per (provider, state)
/// If the two sides drift, iOS stops receiving pushes for the orphaned provider.
/// Tests below pin the expected set so upstream provider churn is a compile-time
/// conversation, not a silent production miss.
@Suite("QuotaProviderList contract")
struct QuotaProviderListTests {
    @Test("Provider list has expected count (25 after Perplexity + OpenCode Go)")
    func providerCount() {
        #expect(QuotaProviderList.providers.count == 25)
    }

    @Test("Perplexity is registered with the Mac-side displayName")
    func perplexityRegistered() throws {
        let entry = try #require(QuotaProviderList.providers.first { $0.id == "perplexity" })
        #expect(entry.displayName == "Perplexity")
    }

    @Test("OpenCode Go is registered and distinct from OpenCode Zen")
    func opencodeGoRegistered() throws {
        let zen = try #require(QuotaProviderList.providers.first { $0.id == "opencode" })
        let go = try #require(QuotaProviderList.providers.first { $0.id == "opencodego" })
        #expect(zen.displayName == "OpenCode")
        #expect(go.displayName == "OpenCode Go")
        #expect(zen.id != go.id)
    }

    @Test("No duplicate provider IDs")
    func noDuplicateIDs() {
        let ids = QuotaProviderList.providers.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test("No blank IDs or displayNames")
    func noBlankEntries() {
        for provider in QuotaProviderList.providers {
            #expect(!provider.id.isEmpty)
            #expect(!provider.displayName.isEmpty)
        }
    }

    @Test("quotaZoneName composes (providerID, state) consistently for Mac + iOS")
    func zoneNameContract() {
        // Mac writes QuotaTransition records to this exact zone name; iOS
        // subscribes to this exact zone name. If the formula drifts the two
        // sides lose each other.
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "perplexity", state: "depleted")
                == "Quota-perplexity-depletedZone")
        #expect(
            QuotaProviderList.quotaZoneName(providerID: "opencodego", state: "restored")
                == "Quota-opencodego-restoredZone")
    }

    @Test("iOS subscription count is 25 × 2 = 50 (depleted + restored per provider)")
    func subscriptionCountDerivation() {
        // The 46 → 50 jump is the headline effect of this change. If this ever
        // fails, someone either dropped a provider or forgot to update the
        // factor-of-2 state assumption.
        let states = ["depleted", "restored"]
        let subscriptionCount = QuotaProviderList.providers.count * states.count
        #expect(subscriptionCount == 50)
    }
}
