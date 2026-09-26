import Foundation
import Testing
@testable import CodexBarCore

struct GrokProductUsageTests {
    @Test
    func `composing proxy shares reach the shared detail section`() throws {
        let billing = try GrokCreditsProxyFetcher.parseSnapshot(Data("""
        {"config":{"creditUsagePercent":6,"productUsage":[
          {"product":"GrokBuild","usagePercent":2},
          {"product":"GrokChat","usagePercent":4}
        ]}}
        """.utf8))
        let usage = GrokUsageSnapshot(
            billing: nil,
            webBilling: billing,
            credentials: nil,
            localSummary: nil,
            cliVersion: nil,
            updatedAt: Date()).toUsageSnapshot()

        #expect(usage.primary?.usedPercent == 6)
        let section = try #require(usage.details.first)
        #expect(section.title == "Usage breakdown")
        #expect(section.rows.map(\.label) == ["Grok Chat", "Grok Build"])
        #expect(section.rows.map(\.value) == ["4%", "2%"])
    }

    @Test
    func `malformed or noncomposing products never replace the billing percent`() throws {
        let malformed = try GrokCreditsProxyFetcher.parseSnapshot(Data("""
        {"config":{"creditUsagePercent":6,"productUsage":[
          {"product":"GrokBuild","usagePercent":2},
          {"product":"GrokChat","usagePercent":"4"}
        ]}}
        """.utf8))
        let differentTotal = try GrokCreditsProxyFetcher.parseSnapshot(Data("""
        {"config":{"creditUsagePercent":6,"productUsage":[
          {"product":"GrokBuild","usagePercent":2}
        ]}}
        """.utf8))
        #expect(malformed.usedPercent == 6)
        #expect(malformed.productUsage.isEmpty)
        #expect(differentTotal.usedPercent == 6)
        #expect(differentTotal.productUsage.isEmpty)
    }

    @Test
    func `a CLI usage percent never borrows proxy product shares`() throws {
        let proxy = GrokWebBillingSnapshot(
            usedPercent: 6,
            resetsAt: nil,
            productUsage: [GrokProductUsage(product: "GrokBuild", usedPercent: 6)])
        let billing = GrokUsageSnapshot(
            billing: nil,
            webBilling: proxy,
            credentials: nil,
            localSummary: nil,
            cliVersion: nil,
            updatedAt: Date()).toUsageSnapshot()
        #expect(billing.details.count == 1)
        let other = GrokWebBillingSnapshot(usedPercent: 8, resetsAt: nil).completing(with: proxy)
        #expect(other.usedPercent == 8)
        #expect(other.productUsage.isEmpty)
    }
}
