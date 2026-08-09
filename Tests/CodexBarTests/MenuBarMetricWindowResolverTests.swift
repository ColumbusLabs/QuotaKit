import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuBarMetricWindowResolverTests {
    @Test
    func `combined primary and secondary metric uses the most constrained lane`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 91, windowMinutes: 7 * 24 * 60, resetsAt: nil, resetDescription: nil),
            updatedAt: Date())

        let window = MenuBarMetricWindowResolver.rateWindow(
            preference: .primaryAndSecondary,
            provider: .codex,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(window?.usedPercent == 91)
        #expect(window?.windowMinutes == 7 * 24 * 60)
    }

    @Test
    func `automatic metric skips exhausted cursor api lane when auto remains usable`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 34,
                windowMinutes: 30 * 24 * 60,
                resetsAt: nil,
                resetDescription: "Auto"),
            secondary: RateWindow(
                usedPercent: 100,
                windowMinutes: 30 * 24 * 60,
                resetsAt: nil,
                resetDescription: "API"),
            tertiary: nil,
            updatedAt: Date())

        let window = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: .cursor,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(window?.remainingPercent == 66)
        #expect(window?.resetDescription == "Auto")
    }

    @Test
    func `automatic metric still reports cursor exhausted when every subquota is exhausted`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 100,
                windowMinutes: 30 * 24 * 60,
                resetsAt: nil,
                resetDescription: "Auto"),
            secondary: RateWindow(
                usedPercent: 100,
                windowMinutes: 30 * 24 * 60,
                resetsAt: nil,
                resetDescription: "API"),
            tertiary: nil,
            updatedAt: Date())

        let window = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: .cursor,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(window?.remainingPercent == 0)
    }

    @Test
    func `automatic metric uses usable cursor api when auto is exhausted`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 100,
                windowMinutes: 30 * 24 * 60,
                resetsAt: nil,
                resetDescription: "Auto"),
            secondary: RateWindow(
                usedPercent: 60,
                windowMinutes: 30 * 24 * 60,
                resetsAt: nil,
                resetDescription: "API"),
            tertiary: nil,
            updatedAt: Date())

        let window = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: .cursor,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(window?.remainingPercent == 40)
        #expect(window?.resetDescription == "API")
    }

    @Test
    func `automatic metric reports cursor exhausted when all modern subquotas are exhausted`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 100,
                windowMinutes: 30 * 24 * 60,
                resetsAt: nil,
                resetDescription: "Auto"),
            secondary: RateWindow(
                usedPercent: 100,
                windowMinutes: 30 * 24 * 60,
                resetsAt: nil,
                resetDescription: "API"),
            tertiary: nil,
            updatedAt: Date())

        let window = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: .cursor,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(window?.remainingPercent == 0)
    }

    @Test
    func `extra usage metric maps provider cost into a menu bar window`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 12, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 37.5,
                limit: 150,
                currencyCode: "USD",
                updatedAt: Date()),
            updatedAt: Date())

        let window = MenuBarMetricWindowResolver.rateWindow(
            preference: .extraUsage,
            provider: .cursor,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(window?.usedPercent == 25)
    }

    @Test
    func `automatic metric uses claude enterprise spend limit`() {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 67.03,
                limit: 1000,
                currencyCode: "USD",
                period: "Spend limit",
                updatedAt: Date()),
            updatedAt: Date())

        let window = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: .claude,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(abs((window?.usedPercent ?? 0) - 6.703) < 0.0001)
    }

    @Test
    func `automatic metric uses marked claude web spend limit placeholder`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 0,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil,
                isSyntheticPlaceholder: true),
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 67.03,
                limit: 1000,
                currencyCode: "USD",
                period: "Monthly",
                updatedAt: Date()),
            updatedAt: Date())

        let window = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: .claude,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(abs((window?.usedPercent ?? 0) - 6.703) < 0.0001)
    }

    @Test
    func `combined metric keeps real zero claude session when spend limit exists`() {
        let primary = RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: primary,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 67.03,
                limit: 1000,
                currencyCode: "USD",
                period: "Monthly",
                updatedAt: Date()),
            updatedAt: Date())

        let window = MenuBarMetricWindowResolver.rateWindow(
            preference: .primaryAndSecondary,
            provider: .claude,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(window == primary)
    }

    @Test
    func `automatic metric keeps real zero claude session when spend limit exists`() {
        let primary = RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil)
        let snapshot = UsageSnapshot(
            primary: primary,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 67.03,
                limit: 1000,
                currencyCode: "USD",
                period: "Monthly",
                updatedAt: Date()),
            updatedAt: Date())

        let window = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: .claude,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(window == primary)
    }

    @Test
    func `automatic metric keeps claude quota window when extra usage is optional`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 42, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 67.03,
                limit: 1000,
                currencyCode: "USD",
                period: "Monthly",
                updatedAt: Date()),
            updatedAt: Date())

        let window = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: .claude,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(window?.usedPercent == 42)
    }

    @Test
    func `automatic metric keeps claude zero quota window when reset exists`() {
        let reset = Date(timeIntervalSince1970: 1000)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 0, windowMinutes: 300, resetsAt: reset, resetDescription: "later"),
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 67.03,
                limit: 1000,
                currencyCode: "USD",
                period: "Monthly",
                updatedAt: Date()),
            updatedAt: Date())

        let window = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: .claude,
            snapshot: snapshot,
            supportsAverage: false)

        #expect(window?.resetsAt == reset)
    }
}
