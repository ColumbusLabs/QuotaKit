import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct QwenCloudTeamMenuTests {
    @Test(arguments: [false, true])
    @MainActor
    func `Team menu labels the credit pool and renders synthetic proof`(before: Bool) async throws {
        let now = Date(timeIntervalSince1970: 1_789_500_000)
        let runtime = try ProviderPluginRuntime(
            bundledPlugin: "qwencloud-team", transport: ProviderHTTPTransportHandler { request in
                let url = try #require(request.url)
                let body = if url.path == "/tool/user/info.json" {
                    #"{"data":{"secToken":"synthetic-token"}}"#
                } else if url.query?.contains("LoadHumanInfo") == true {
                    #"{"successResponse":true,"data":{"Data":{"SellerInfoDto":{"Nbid":"synthetic"}}}}"#
                } else {
                    #"""
                    {"successResponse":true,"data":{"Success":true,"Data":{
                      "StartTime":1784894400000,"EndTime":1790251200000,"ProductCode":"sfm_tokenplanteams_dp_intl",
                      "SubscriptionGroupList":[{"SpecType":"standard","SubscriptionAssignedNumber":1,
                        "SubscriptionTotalNumber":1,"NextCycleFlushTime":1790251200000,"EquityList":[
                          {"EquityCode":"credit_value","TotalValue":"25000","SurplusValue":"6373.93922996"}
                        ]}]
                    }}}
                    """#
                }
                return try (
                    Data(body.utf8),
                    #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
            })
        let usage = try await runtime.fetchUsage(now: now, cookieResolver: { _, _ in "session=synthetic" })
        let model = UsageMenuCardView.Model.make(.init(
            provider: .qwencloud,
            metadata: QwenCloudProviderDescriptor.descriptor.metadata,
            snapshot: before ? nil : usage,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: before ? nil : "Standard Team"),
            isRefreshing: false,
            lastError: before ? "Failed to parse Qwen Cloud usage: Missing token plan data" : nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: true,
            now: now))
        if !before {
            #expect(model.metrics.map(\.title) == ["Team"])
            #expect(model.metrics.first?.percentLabel == "75% used")
        }
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_QWEN_TEAM_PROOF_DIR"] else { return }
        let hosting = NSHostingView(rootView: UsageMenuCardView(model: model, width: 340)
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light))
        hosting.appearance = NSAppearance(named: .aqua)
        let data = try #require(MenuLayoutScreenshotRenderTests.pngDataWithWindow(hosting: hosting))
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try data.write(to: output.appendingPathComponent(before ? "before.png" : "after.png"))
    }
}
