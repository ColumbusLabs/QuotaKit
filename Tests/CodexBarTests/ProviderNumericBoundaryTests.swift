import Foundation
import Testing
@testable import CodexBarCore

struct ProviderNumericBoundaryTests {
    @Test
    func `amp window conversion rejects nonfinite and out of range minutes`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        for hours in [Double.greatestFiniteMagnitude, Double.infinity, Double.nan] {
            let snapshot = AmpUsageSnapshot(
                freeQuota: 10,
                freeUsed: 5,
                hourlyReplenishment: nil,
                windowHours: hours,
                updatedAt: now)
            let window = snapshot.toUsageSnapshot(now: now).primary

            #expect(window?.usedPercent == 50)
            #expect(window?.windowMinutes == nil)
        }
    }

    @Test
    func `amp window conversion preserves fractional and zero duration behavior`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fractional = AmpUsageSnapshot(
            freeQuota: 10,
            freeUsed: 5,
            hourlyReplenishment: nil,
            windowHours: 0.5,
            updatedAt: now)
        let zero = AmpUsageSnapshot(
            freeQuota: 10,
            freeUsed: 5,
            hourlyReplenishment: nil,
            windowHours: 0,
            updatedAt: now)

        #expect(fractional.toUsageSnapshot(now: now).primary?.windowMinutes == 30)
        #expect(zero.toUsageSnapshot(now: now).primary?.windowMinutes == nil)
    }

    @Test
    func `amp tier uses explicit period when renewal count is unrepresentable`() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-16T12:00:00Z"))
        let renewalCount = String(repeating: "9", count: 24)
        let output = """
        Amp Example Tier: agent usage $18 of $20 remaining - period 2026-09-13 to 2026-10-13, \
        resets upon renewal in \(renewalCount) days
        Individual credits: $12 remaining
        """

        let snapshot = try AmpUsageParser.parse(displayText: output, now: now)
        let usage = snapshot.toUsageSnapshot(now: now)

        #expect(snapshot.subscription?.resetsAt == ISO8601DateFormatter().date(from: "2026-10-13T00:00:00Z"))
        #expect(snapshot.subscription?.resetDescription == "renews in period")
        #expect(snapshot.individualCredits == 12)
        #expect(usage.primary?.windowMinutes == 30 * 24 * 60)
    }

    @Test
    func `amp tier omits impossible renewal dates but retains independent credits`() throws {
        for unit in ["days", "months"] {
            let output = """
            Amp Example Tier: agent usage $18 of $20 remaining - resets upon renewal in \(Int.max) \(unit)
            Individual credits: $12 remaining
            """
            let snapshot = try AmpUsageParser.parse(displayText: output)

            #expect(snapshot.subscription == nil)
            #expect(snapshot.individualCredits == 12)
        }

        let unrepresentableCount = """
        Amp Example Tier: agent usage $18 of $20 remaining - resets upon renewal in 999999999999999999999999 days
        Individual credits: $12 remaining
        """
        let snapshot = try AmpUsageParser.parse(displayText: unrepresentableCount)
        #expect(snapshot.subscription == nil)
        #expect(snapshot.individualCredits == 12)
    }

    @Test
    func `kilo formats large whole credit values and preserves ordinary formatting`() {
        let large = self.kiloSnapshot(used: 1e20, total: 1e20, remaining: 0).toUsageSnapshot()
        let fractional = self.kiloSnapshot(used: 2.5, total: 10, remaining: 7.5).toUsageSnapshot()
        let zero = self.kiloSnapshot(used: 0, total: 0, remaining: 0).toUsageSnapshot()
        let fractionalPass = self.kiloSnapshot(
            used: 0,
            total: 1,
            remaining: 1,
            passUsed: 2.5,
            passTotal: 12,
            passRemaining: 9.5,
            passBonus: 2).toUsageSnapshot()
        let zeroPass = self.kiloSnapshot(
            used: 0,
            total: 0,
            remaining: 0,
            passUsed: 0,
            passTotal: 0,
            passRemaining: 0).toUsageSnapshot()

        #expect(large.primary?.resetDescription == "100000000000000000000/100000000000000000000 credits")
        #expect(fractional.primary?.usedPercent == 25)
        #expect(fractional.primary?.resetDescription == "2.50/10 credits")
        #expect(zero.primary?.usedPercent == 100)
        #expect(zero.primary?.resetDescription == "0/0 credits")
        #expect(self.kiloSnapshot(used: -0.0, total: -0.0, remaining: -0.0)
            .toUsageSnapshot().primary?.resetDescription == "0/0 credits")
        #expect(fractionalPass.secondary?.usedPercent == (2.5 / 12) * 100)
        #expect(fractionalPass.secondary?.resetDescription == "$2.50 / $10.00 (+ $2.00 bonus)")
        #expect(zeroPass.secondary?.usedPercent == 100)
        #expect(zeroPass.secondary?.resetDescription == "$0.00 / $0.00")
    }

    @Test
    func `kilo omits primary window when derived total overflows`() throws {
        let json = """
        [
          {"result":{"data":{"json":{"blocks":[{"usedCredits":1e308,"remainingCredits":1e308}]}}}},
          {"result":{"data":{"json":{}}}},
          {"result":{"data":{"json":{}}}}
        ]
        """
        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let usage = parsed.toUsageSnapshot()
        let encoded = try JSONEncoder().encode(usage)
        let encodedText = try #require(String(bytes: encoded, encoding: .utf8))
        let invalidDirect = [
            self.kiloSnapshot(used: .infinity, total: 100, remaining: 50),
            self.kiloSnapshot(used: 5, total: .infinity, remaining: 5),
            self.kiloSnapshot(used: nil, total: 100, remaining: .nan),
        ].map { $0.toUsageSnapshot() }

        #expect(parsed.creditsTotal == nil)
        #expect(usage.primary == nil)
        #expect(!encodedText.contains("Infinity"))
        for result in invalidDirect {
            #expect(result.primary == nil)
        }
    }

    @Test
    func `kilo omits invalid pass projection while preserving primary credits`() throws {
        let json = """
        [
          {"result":{"data":{"json":{"blocks":[{"usedCredits":5,"totalCredits":10,"remainingCredits":5}]}}}},
          {"result":{"data":{"json":{"subscription":{
            "currentPeriodUsageUsd":1,
            "currentPeriodBaseCreditsUsd":1e308,
            "currentPeriodBonusCreditsUsd":1e308
          }}}}},
          {"result":{"data":{"json":{}}}}
        ]
        """
        let parsed = try KiloUsageFetcher._parseSnapshotForTesting(Data(json.utf8))
        let overflowedPass = parsed.toUsageSnapshot()
        let invalidDirectPasses = [
            self.kiloSnapshot(used: 5, total: 10, remaining: 5, passUsed: 1e308, passTotal: nil, passRemaining: 1e308),
            self.kiloSnapshot(used: 5, total: 10, remaining: 5, passUsed: .infinity, passTotal: 100, passRemaining: 50),
            self.kiloSnapshot(
                used: 5,
                total: 10,
                remaining: 5,
                passUsed: 5,
                passTotal: 10,
                passRemaining: 5,
                passBonus: .infinity),
            self.kiloSnapshot(
                used: 5,
                total: 10,
                remaining: 5,
                passUsed: 5,
                passTotal: 10,
                passRemaining: 5,
                passBonus: .nan),
            self.kiloSnapshot(used: 5, total: 10, remaining: 5, passUsed: 5, passTotal: .infinity),
            self.kiloSnapshot(used: 5, total: 10, remaining: 5, passTotal: 100, passRemaining: .nan),
        ].map { $0.toUsageSnapshot() }

        #expect(parsed.passTotal == nil)
        #expect(overflowedPass.primary?.usedPercent == 50)
        #expect(overflowedPass.secondary == nil)
        for usage in invalidDirectPasses {
            #expect(usage.primary?.usedPercent == 50)
            #expect(usage.secondary == nil)
        }
    }

    @Test
    func `monthly pace retains sentinel when reset date is outside calendar range`() {
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: ProviderPaceCapability.monthlyWindowSentinelMinutes,
            resetsAt: Date(timeIntervalSinceReferenceDate: Double.greatestFiniteMagnitude),
            resetDescription: nil)

        let resolved = ProviderPaceCapability.calendarMonthResetWindow.resolvedResetWindowForPace(window)

        #expect(resolved.windowMinutes == ProviderPaceCapability.monthlyWindowSentinelMinutes)
    }

    @Test
    func `updated timestamp returns the same unknown fallback for invalid deltas`() {
        let now = Date(timeIntervalSince1970: 1_710_048_000)
        let unknown = UsageFormatter.updatedString(
            from: Date(timeIntervalSinceReferenceDate: .infinity),
            now: now)

        for interval in [
            Double.greatestFiniteMagnitude,
            -Double.greatestFiniteMagnitude,
            Double.infinity,
            -Double.infinity,
            Double.nan,
        ] {
            let date = Date(timeIntervalSinceReferenceDate: interval)
            #expect(UsageFormatter.updatedString(from: date, now: now) == unknown)
        }
    }

    private func kiloSnapshot(
        used: Double?,
        total: Double?,
        remaining: Double?,
        passUsed: Double? = nil,
        passTotal: Double? = nil,
        passRemaining: Double? = nil,
        passBonus: Double? = nil) -> KiloUsageSnapshot
    {
        KiloUsageSnapshot(
            creditsUsed: used,
            creditsTotal: total,
            creditsRemaining: remaining,
            passUsed: passUsed,
            passTotal: passTotal,
            passRemaining: passRemaining,
            passBonus: passBonus,
            planName: nil,
            autoTopUpEnabled: nil,
            autoTopUpMethod: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
}
