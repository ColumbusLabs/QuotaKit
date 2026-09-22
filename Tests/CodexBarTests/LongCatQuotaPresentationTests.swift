import AppKit
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

@MainActor
struct LongCatQuotaPresentationTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func snapshot(hasExpiry: Bool) -> UsageSnapshot {
        LongCatUsageSnapshot(
            totalQuota: 1000,
            usedQuota: 250,
            fuelPackTotal: 500,
            fuelPackRemaining: 200,
            nearestFuelExpiry: hasExpiry ? Self.now.addingTimeInterval(7200) : nil,
            updatedAt: Self.now).toUsageSnapshot()
    }

    private func model(_ snapshot: UsageSnapshot) throws -> UsageMenuCardView.Model {
        let metadata = ProviderDescriptorRegistry.descriptor(for: .longcat).metadata
        return UsageMenuCardView.Model.make(.init(
            provider: .longcat,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: Self.now))
    }

    @Test(arguments: [false, true])
    func `quota balances remain details alongside fuel expiry`(hasExpiry: Bool) throws {
        let snapshot = self.snapshot(hasExpiry: hasExpiry)
        let model = try self.model(snapshot)
        let primary = try #require(model.metrics.first { $0.id == "primary" })
        let fuel = try #require(model.metrics.first { $0.id == "secondary" })
        #expect(primary.percent == 75)
        #expect(primary.detailText == "250/1000")
        #expect(primary.resetText == nil)
        #expect(fuel.percent == 40)
        #expect(fuel.detailText == "Fuel pack: 200/500")
        #expect(fuel.resetText == (hasExpiry ? "Resets in 2h" : nil))

        let settings = testSettingsStore(suiteName: "LongCatQuotaPresentationTests-\(hasExpiry)")
        settings.statusChecksEnabled = false
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(snapshot, provider: .longcat)
        let descriptor = MenuDescriptor.build(
            provider: .longcat,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false,
            includeContextualActions: false,
            now: Self.now)
        let text = descriptor.sections.flatMap(\.entries).compactMap { entry -> String? in
            guard case let .text(value, _) = entry else { return nil }
            return value
        }
        #expect(text.contains("250/1000"))
        #expect(text.contains("Fuel pack: 200/500"))
        #expect(!text.contains { $0.hasPrefix("Resets 250/") || $0.hasPrefix("Resets Fuel pack:") })
        #expect(text.contains { $0.hasPrefix("Resets ") } == hasExpiry)
    }

    @Test(arguments: [false, true])
    func `CLI text and cards separate quota details from reset dates`(hasExpiry: Bool) throws {
        let snapshot = self.snapshot(hasExpiry: hasExpiry)
        let metadata = ProviderDescriptorRegistry.descriptor(for: .longcat).metadata
        let card = CLICardsRenderer.makeCard(CLICardBuildInput(
            provider: .longcat,
            snapshot: snapshot,
            credits: nil,
            source: "web",
            status: nil,
            notes: [],
            useColor: false,
            resetStyle: .countdown,
            weeklyWorkDays: nil,
            now: Self.now))
        let primary = try #require(card.metrics.first { $0.label == metadata.sessionLabel })
        let fuel = try #require(card.metrics.first { $0.label == metadata.weeklyLabel })
        #expect(primary.detailText == "250/1000")
        #expect(primary.resetText == nil)
        #expect(fuel.detailText == "Fuel pack: 200/500")
        #expect(fuel.resetText == (hasExpiry ? "⏳ Resets in 2h" : nil))

        let output = CLIRenderer.renderText(
            provider: .longcat,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(header: "LongCat", status: nil, useColor: false, resetStyle: .countdown),
            now: Self.now)
        #expect(output.contains("250/1000"))
        #expect(output.contains("Fuel pack: 200/500"))
        #expect(!output.contains("Resets 250/") && !output.contains("Resets Fuel pack:"))
        #expect(output.contains("Resets in 2h") == hasExpiry)
    }

    @Test
    func `unrepresentable parsed expiry shows fuel detail without a fake reset`() throws {
        let parsed = LongCatUsageFetcher.buildSnapshot(
            account: nil,
            tokenPackSummary: nil,
            tokenUsage: nil,
            pendingFuel: ["totalQuota": 1000, "list": [["availableToken": 500, "expireTime": 1e24]]],
            now: Self.now)
        #expect((parsed.nearestFuelExpiry?.timeIntervalSince1970 ?? 0) > 1e20)

        let snapshot = parsed.toUsageSnapshot()
        let window = try #require(snapshot.secondary)
        #expect(window.usedPercent == 50)
        #expect((window.resetsAt?.timeIntervalSince1970 ?? 0) > 1e20)
        #expect(window.resetDescription == "Fuel pack: 500/1000")

        let model = try self.model(snapshot)
        let fuelMetric = try #require(model.metrics.first { $0.id == "secondary" })
        #expect(fuelMetric.detailText == "Fuel pack: 500/1000")
        #expect(fuelMetric.resetText == nil)

        let settings = testSettingsStore(suiteName: "LongCatQuotaPresentationTests-unrepresentable-expiry")
        settings.statusChecksEnabled = false
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(snapshot, provider: .longcat)
        let descriptor = MenuDescriptor.build(
            provider: .longcat,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false,
            includeContextualActions: false,
            now: Self.now)
        let menuText = descriptor.sections.flatMap(\.entries).compactMap { entry -> String? in
            guard case let .text(value, _) = entry else { return nil }
            return value
        }
        #expect(menuText.contains("Fuel pack: 500/1000"))
        #expect(!menuText.contains { $0.hasPrefix("Resets ") })

        let output = CLIRenderer.renderText(
            provider: .longcat,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(header: "LongCat", status: nil, useColor: false, resetStyle: .countdown),
            now: Self.now)
        #expect(output.contains("Fuel pack: 500/1000"))
        #expect(!output.contains("Resets "))
    }
}
