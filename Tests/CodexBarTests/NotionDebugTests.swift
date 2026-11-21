import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct NotionDebugTests {
    @Test
    func `debug reports allowances without requesting premium credits`() async {
        let result = await UsageStore.debugNotionLog(
            browserDetection: BrowserDetection(),
            notionCookieSource: .manual,
            notionCookieHeader: "token_v2=synthetic",
            notionWorkspaceID: "space",
            transport: ProviderHTTPTransportHandler { request in
                let endpoint = request.url?.lastPathComponent
                #expect(endpoint != "getAIUsageEligibilityV2")
                let body = endpoint == "getSpaces"
                    ? #"{"user":{"space":{"space":{"value":{"id":"space","name":"Fixture"}}}}}"#
                    : #"{"window":{"window":"6h","used":42,"limit":100},"billingPeriodWindow":{"used":18,"limit":100}}"#
                let url = try #require(request.url)
                return try (Data(body.utf8), #require(HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
            })
        #expect(result.contains("Fetch Success"))
        #expect(result.contains("rollingUsed=42.0"))
        #expect(result.contains("billingUsed=18.0"))
        #expect(!result.contains("synthetic"))
    }

    @Test
    func `debug names migrated monthly pools without an optional credit lookup`() async {
        let result = await UsageStore.debugNotionLog(
            browserDetection: BrowserDetection(),
            notionCookieSource: .manual,
            notionCookieHeader: "token_v2=synthetic",
            notionWorkspaceID: "space",
            transport: ProviderHTTPTransportHandler { request in
                let endpoint = request.url?.lastPathComponent
                #expect(endpoint != "getAIUsageEligibilityV2")
                let body = endpoint == "getSpaces"
                    ? #"{"user":{"space":{"space":{"value":{"id":"space","name":"Fixture"}}}}}"#
                    : #"""
                    {"status":"not_applicable","allowances":[
                      {"bucketId":"auto","cadence":"billing_period","state":"resolved","used":20,"limit":100},
                      {"bucketId":"flex","cadence":"billing_period","state":"resolved","used":0,"limit":100}
                    ]}
                    """#
                let url = try #require(request.url)
                return try (Data(body.utf8), #require(HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
            })
        #expect(result.contains("Fetch Success"))
        #expect(result.contains("Standard used: 20.0"))
        #expect(result.contains("Select used: 0.0"))
        #expect(!result.contains("synthetic"))
    }
}
