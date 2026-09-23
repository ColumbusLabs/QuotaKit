import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct SpendDashboardOpenCodexPricingRefreshTests {
    @Test
    func `fresh dashboard load refreshes prices after loading nonempty entries`() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let configuration = SpendDashboardConfiguration(
            costUsageEnabled: true,
            providerIDs: [],
            codexAccountIdentities: [],
            openCodexUsageLogsEnabled: true)
        let request = SpendDashboardLoadRequest(
            configuration: configuration,
            capturedInputs: [],
            unavailableSourceIDs: [],
            codexRequests: [],
            now: now,
            force: false)
        let entry = OpenCodexUsageEntry(
            requestID: "refresh-request",
            timestamp: now,
            provider: "opencode-go",
            model: "gpt-5.4",
            usageStatus: .reported,
            usage: OpenCodexTokenUsage(inputTokens: 100, outputTokens: 10, totalTokens: 110))
        let recorder = PricingRefreshRecorder()

        let result = await SpendDashboardSource.mergingOpenCodexInputsAfterRefreshingPricing(
            [],
            request: request,
            environment: ["OPENCODEX_HOME": "/tmp/opencodex-pricing-refresh-test"],
            entryLoader: { _ in [entry] },
            pricingRefresher: { entries, refreshDate in
                await recorder.record(entries: entries, now: refreshDate)
            })

        #expect(result.observation == .available)
        #expect(result.inputs.contains { $0.provider == .opencodego })
        #expect(await recorder.callCount == 1)
        #expect(await recorder.entryCount == 1)
        #expect(await recorder.timestamp == now)
    }

    @Test
    func `fresh dashboard load skips pricing refresh for empty or disabled sources`() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let recorder = PricingRefreshRecorder()
        let disabled = SpendDashboardLoadRequest(
            configuration: SpendDashboardConfiguration(
                costUsageEnabled: true,
                providerIDs: [],
                codexAccountIdentities: [],
                openCodexUsageLogsEnabled: false),
            capturedInputs: [],
            unavailableSourceIDs: [],
            codexRequests: [],
            now: now,
            force: false)
        let disabledResult = await SpendDashboardSource.mergingOpenCodexInputsAfterRefreshingPricing(
            [],
            request: disabled,
            environment: ["OPENCODEX_HOME": "/tmp/opencodex-pricing-refresh-test"],
            entryLoader: { _ in [] },
            pricingRefresher: { entries, date in await recorder.record(entries: entries, now: date) })
        #expect(disabledResult.observation == .disabled)

        let enabled = SpendDashboardLoadRequest(
            configuration: SpendDashboardConfiguration(
                costUsageEnabled: true,
                providerIDs: [],
                codexAccountIdentities: [],
                openCodexUsageLogsEnabled: true),
            capturedInputs: [],
            unavailableSourceIDs: [],
            codexRequests: [],
            now: now,
            force: false)
        let emptyResult = await SpendDashboardSource.mergingOpenCodexInputsAfterRefreshingPricing(
            [],
            request: enabled,
            environment: ["OPENCODEX_HOME": "/tmp/opencodex-pricing-refresh-test"],
            entryLoader: { _ in [] },
            pricingRefresher: { entries, date in await recorder.record(entries: entries, now: date) })
        #expect(emptyResult.observation == .confirmedEmpty)
        #expect(await recorder.callCount == 0)
    }
}

private actor PricingRefreshRecorder {
    private(set) var callCount = 0
    private(set) var entryCount = 0
    private(set) var timestamp: Date?

    func record(entries: [OpenCodexUsageEntry], now: Date) {
        self.callCount += 1
        self.entryCount = entries.count
        self.timestamp = now
    }
}
