import Foundation
import Testing
@testable import CodexBarCore

struct CursorStatusSnapshotProjectionTests {
    @Test
    func `converts snapshot to usage snapshot`() {
        let snapshot = CursorStatusSnapshot(
            planPercentUsed: 45.0,
            autoPercentUsed: 5.0,
            apiPercentUsed: nil,
            planUsedUSD: 22.50,
            planLimitUSD: 50.0,
            onDemandUsedUSD: 5.0,
            onDemandLimitUSD: 100.0,
            teamOnDemandUsedUSD: 25.0,
            teamOnDemandLimitUSD: 500.0,
            billingCycleStart: Date(timeIntervalSince1970: 1_735_689_600), // Jan 1, 2025
            billingCycleEnd: Date(timeIntervalSince1970: 1_738_368_000), // Feb 1, 2025
            membershipType: "pro",
            accountEmail: "user@example.com",
            accountName: "Test User",
            rawJSON: nil)

        let usageSnapshot = snapshot.toUsageSnapshot()

        #expect(usageSnapshot.primary?.usedPercent == 5.0)
        #expect(usageSnapshot.cursorRateWindowLayout == .autoOnly)
        #expect(usageSnapshot.accountEmail(for: .cursor) == "user@example.com")
        #expect(usageSnapshot.loginMethod(for: .cursor) == "Cursor Pro")
        #expect(usageSnapshot.secondary == nil)
        #expect(usageSnapshot.tertiary == nil)
        #expect(usageSnapshot.primary?.windowMinutes == 44640)
        #expect(usageSnapshot.providerCost?.used == 5.0)
        #expect(usageSnapshot.providerCost?.limit == 100.0)
        #expect(usageSnapshot.providerCost?.currencyCode == "USD")
    }

    @Test
    func `usage snapshot maps both cursor split lanes`() {
        let snapshot = CursorStatusSnapshot(
            planPercentUsed: 45.0,
            autoPercentUsed: 12.0,
            apiPercentUsed: 34.0,
            planUsedUSD: 22.50,
            planLimitUSD: 50.0,
            onDemandUsedUSD: 0,
            onDemandLimitUSD: nil,
            teamOnDemandUsedUSD: nil,
            teamOnDemandLimitUSD: nil,
            billingCycleEnd: nil,
            membershipType: "pro",
            accountEmail: nil,
            accountName: nil,
            rawJSON: nil)

        let usageSnapshot = snapshot.toUsageSnapshot()

        #expect(usageSnapshot.primary?.usedPercent == 12.0)
        #expect(usageSnapshot.secondary?.usedPercent == 34.0)
        #expect(usageSnapshot.tertiary == nil)
        #expect(usageSnapshot.cursorRateWindowLayout == .autoAPI)
    }

    @Test
    func `usage snapshot promotes cursor api only lane to primary`() {
        let snapshot = CursorStatusSnapshot(
            planPercentUsed: 45.0,
            autoPercentUsed: nil,
            apiPercentUsed: 34.0,
            planUsedUSD: 22.50,
            planLimitUSD: 50.0,
            onDemandUsedUSD: 0,
            onDemandLimitUSD: nil,
            teamOnDemandUsedUSD: nil,
            teamOnDemandLimitUSD: nil,
            billingCycleEnd: nil,
            membershipType: "pro",
            accountEmail: nil,
            accountName: nil,
            rawJSON: nil)

        let usageSnapshot = snapshot.toUsageSnapshot()

        #expect(usageSnapshot.primary?.usedPercent == 34.0)
        #expect(usageSnapshot.secondary == nil)
        #expect(usageSnapshot.cursorRateWindowLayout == .apiOnly)
    }

    @Test
    func `usage snapshot preserves cursor plan fallback when split lanes are absent`() {
        let snapshot = CursorStatusSnapshot(
            planPercentUsed: 45.0,
            autoPercentUsed: nil,
            apiPercentUsed: nil,
            planUsedUSD: 22.50,
            planLimitUSD: 50.0,
            onDemandUsedUSD: 0,
            onDemandLimitUSD: nil,
            teamOnDemandUsedUSD: nil,
            teamOnDemandLimitUSD: nil,
            billingCycleEnd: nil,
            membershipType: "enterprise",
            accountEmail: nil,
            accountName: nil,
            rawJSON: nil)

        let usageSnapshot = snapshot.toUsageSnapshot()

        #expect(usageSnapshot.primary?.usedPercent == 45.0)
        #expect(usageSnapshot.secondary == nil)
        #expect(usageSnapshot.cursorRateWindowLayout == .plan)
    }
}
