import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct MiniMaxCurrentTokenPlanResponseTests {
    @Test
    func `current china web quota maps percent strings and boosted limits`() async throws {
        let now = Date(timeIntervalSince1970: 1_780_282_340)
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            if url.path == "/console/usage" {
                return Self.httpResponse(url: url, body: "<html></html>", contentType: "text/html")
            }
            #expect(url.absoluteString == "https://www.minimax.cn/backend/account/token_plan/remains_percent")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "session=fixture")
            return Self.httpResponse(
                url: url,
                body: """
                {"base_resp":{"status_code":0},"model_remains":[{
                  "model_name":"general", "current_interval_used_percent":"8%",
                  "current_interval_total_percent":"100%", "remains_time":3600000,
                  "current_weekly_used_percent":"45%", "current_weekly_total_percent":"150%",
                  "weekly_remains_time":7200000
                }]}
                """,
                contentType: "application/json")
        }
        let snapshot = try await MiniMaxUsageFetcher.fetchUsage(
            cookieHeader: "session=fixture",
            region: .chinaMainland,
            environment: [:],
            includeBillingHistory: false,
            session: transport,
            now: now)
        let services = try #require(snapshot.services)
        #expect(services.count == 2)
        #expect(services[0].percent == 8)
        #expect(services[0].limit == 100)
        #expect(services[0].windowType == "5 hours")
        #expect(abs(services[1].percent - 30) < 0.001)
        #expect(services[1].limit == 150)
    }

    @Test
    func `current web percent schema marks unlimited windows`() throws {
        let json = """
        {"base_resp":{"status_code":0},"model_remains":[{"model_name":"general",
          "current_interval_used_percent":"0%", "current_interval_total_percent":"0%",
          "current_interval_status":3, "current_weekly_used_percent":"0%",
          "current_weekly_total_percent":"100%", "current_weekly_status":3}]}
        """
        let snapshot = try MiniMaxUsageParser.parseCodingPlanRemains(data: Data(json.utf8))
        let services = try #require(snapshot.services)
        #expect(services.count == 2)
        #expect(services[0].isUnlimited)
        #expect(services[1].isUnlimited)
    }

    @Test
    func `china web quota falls back after page redirect and unavailable current endpoint`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            if url.path == "/console/usage" || url.path.hasSuffix("remains_percent") {
                let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            }
            #expect(url.host == "platform.minimaxi.com")
            return Self.httpResponse(url: url, body: Self.percentBasedRemainsJSON, contentType: "application/json")
        }
        let snapshot = try await MiniMaxUsageFetcher.fetchUsage(
            cookieHeader: "session=fixture",
            region: .chinaMainland,
            environment: [:],
            includeBillingHistory: false,
            session: transport)
        #expect(snapshot.toUsageSnapshot().primary?.usedPercent == 4)
        #expect(await transport.requests().map { $0.url?.host } == [
            "platform.minimax.cn", "www.minimax.cn", "platform.minimaxi.com",
        ])
    }

    @Test
    func `imported browser credentials are scoped to matching request origins`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            #expect(url.host == "www.minimax.cn")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "session=www-only")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "X-Group-Id") == nil)
            #expect(url.query?.contains("GroupId") != true)
            return Self.httpResponse(url: url, body: Self.percentBasedRemainsJSON, contentType: "application/json")
        }
        let records = [
            ProviderPluginCookieRecord(
                name: "session",
                value: "www-only",
                domain: "www.minimax.cn",
                hostOnly: true,
                path: "/",
                secure: true,
                expires: nil),
            ProviderPluginCookieRecord(
                name: "foreign",
                value: "never-send",
                domain: "platform.minimaxi.com",
                hostOnly: true,
                path: "/other",
                secure: true,
                expires: nil),
        ]
        let snapshot = try await MiniMaxUsageFetcher.fetchUsage(MiniMaxUsageFetcher.WebFetchInput(
            cookieHeader: "session=placeholder",
            authorizationToken: "platform-token",
            groupID: "platform-account",

            region: .chinaMainland,
            environment: [:],
            includeBillingHistory: false,
            transport: transport,
            now: Date(),
            browserCookieRecords: records,
            authorizationOrigin: "https://platform.minimax.cn"))
        #expect(snapshot.toUsageSnapshot().primary?.usedPercent == 4)
        #expect(await transport.requests().allSatisfy { $0.url?.host == "www.minimax.cn" })
    }

    @Test
    func `overlapping imported session cookies with different identities are never sent`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            Issue.record("Ambiguous browser session reached the network: \(request.url?.host ?? "unknown")")
            let url = try #require(request.url)
            return Self.httpResponse(url: url, body: "{}", contentType: "application/json")
        }
        let records = [
            ProviderPluginCookieRecord(
                name: "HERTZ-SESSION",
                value: "first",
                domain: "www.minimax.cn",
                hostOnly: true,
                path: "/",
                secure: true,
                expires: nil),
            ProviderPluginCookieRecord(
                name: "HERTZ-SESSION",
                value: "second",
                domain: "minimax.cn",
                hostOnly: false,
                path: "/backend",
                secure: true,
                expires: nil),
        ]
        // Platform has no matching session cookie; www has two conflicting sessions.
        await #expect(throws: MiniMaxUsageError.self) {
            _ = try await MiniMaxUsageFetcher.fetchUsage(MiniMaxUsageFetcher.WebFetchInput(
                cookieHeader: "session=placeholder",
                authorizationToken: nil,
                groupID: nil,
                region: .chinaMainland,
                environment: [:],
                includeBillingHistory: false,
                transport: transport,
                now: Date(),
                browserCookieRecords: records,
                authorizationOrigin: nil))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test
    func `scoped session bearer stays on matching default HTTPS origin`() throws {
        let records = [ProviderPluginCookieRecord(
            name: "HERTZ-SESSION",
            value: "fixture-session",
            domain: "www.minimax.cn",
            hostOnly: true,
            path: "/",
            secure: true,
            expires: nil)]
        let context = MiniMaxUsageFetcher.WebFetchContext(
            cookie: "scoped=1",
            authorizationToken: nil,
            browserCookieRecords: records,
            authorizationOrigin: nil,
            useSessionBearer: true,
            region: .chinaMainland,
            environment: [:],
            transport: ProviderHTTPClient.shared)
        let normalURL = try #require(URL(string: "https://www.minimax.cn/backend/account/token_plan/remains_percent"))
        var normal = URLRequest(url: normalURL)
        try MiniMaxUsageFetcher.applyWebCredentials(context, to: &normal)
        #expect(normal.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-session")
        let wrongPortURL =
            try #require(URL(string: "https://www.minimax.cn:8443/backend/account/token_plan/remains_percent"))
        var wrongPort = URLRequest(url: wrongPortURL)
        #expect(throws: MiniMaxUsageError.self) { try MiniMaxUsageFetcher.applyWebCredentials(context, to: &wrongPort) }
        #expect(wrongPort.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(wrongPort.value(forHTTPHeaderField: "Authorization") == nil)
        let wrongHostURL = try #require(URL(string: "https://platform.minimax.cn/console/usage"))
        var wrongHost = URLRequest(url: wrongHostURL)
        #expect(throws: MiniMaxUsageError.self) { try MiniMaxUsageFetcher.applyWebCredentials(context, to: &wrongHost) }
    }

    @Test
    func `explicit manual headers retain cross-endpoint behavior`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            #expect(request.value(forHTTPHeaderField: "Cookie") == "session=manual")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer manual-token")
            if url.host == "platform.minimax.cn" {
                return Self.httpResponse(url: url, body: "<html></html>", contentType: "text/html")
            }
            return Self.httpResponse(url: url, body: Self.percentBasedRemainsJSON, contentType: "application/json")
        }
        let snapshot = try await MiniMaxUsageFetcher.fetchUsage(
            cookieHeader: "session=manual",
            authorizationToken: "manual-token",
            region: .chinaMainland,
            environment: [:],
            includeBillingHistory: false,
            session: transport)
        #expect(snapshot.toUsageSnapshot().primary?.usedPercent == 4)
    }

    @Test
    func `coarse html plan name does not replace remains api plan name`() {
        let remainsSnapshot = MiniMaxUsageSnapshot(
            planName: "Token Plan Pro",
            availablePrompts: nil,
            currentPrompts: nil,
            remainingPrompts: nil,
            windowMinutes: nil,
            usedPercent: nil,
            resetsAt: nil,
            updatedAt: Date())

        let enriched = remainsSnapshot.withPlanNameIfMissing("Plus")

        #expect(enriched.planName == "Token Plan Pro")
    }

    @Test
    func `parses token plan boosted weekly lane with permille spelling`() throws {
        let now = Date(timeIntervalSince1970: 1_782_050_596)

        let snapshot = try MiniMaxUsageParser.parseCodingPlanRemains(
            data: Data(Self.currentTokenPlanRemainsJSON.utf8),
            now: now)
        let services = try #require(snapshot.services)

        #expect(services.map(\.windowType) == ["5 hours", "Weekly"])
        #expect(services[0].usage == 0)
        #expect(services[0].limit == 100)
        #expect(services[0].percent == 0)
        #expect(services[1].usage == 45)
        #expect(services[1].limit == 150)
        #expect(abs(services[1].percent - 30) < 0.001)
        #expect(snapshot.toUsageSnapshot().primary?.usedPercent == 0)
        #expect(snapshot.toUsageSnapshot().secondary?.usedPercent == 30)
    }

    @Test
    func `web usage fetch enriches parsed html without service quota data from remains api`() async throws {
        let now = Date(timeIntervalSince1970: 1_780_282_340)
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            if url.path == "/console/usage" {
                return Self.httpResponse(
                    url: url,
                    body: "<html><main>Coding Plan Plus available usage 1000 prompts 5 hours</main></html>",
                    contentType: "text/html")
            }
            #expect(url.host == "www.minimax.cn")
            #expect(url.path == "/backend/account/token_plan/remains_percent")
            return Self.httpResponse(url: url, body: Self.percentBasedRemainsJSON, contentType: "application/json")
        }

        let snapshot = try await MiniMaxUsageFetcher.fetchUsage(
            cookieHeader: "HERTZ-SESSION=abc",
            region: .chinaMainland,
            environment: [:],
            includeBillingHistory: false,
            session: transport,
            now: now)
        let requests = await transport.requests()

        #expect(snapshot.services?.count == 2)
        #expect(snapshot.planName == "Plus")
        #expect(snapshot.toUsageSnapshot().primary?.usedPercent == 4)
        #expect(requests.map { $0.url?.host } == [
            "platform.minimax.cn",
            "www.minimax.cn",
        ])
    }

    @Test
    func `web usage fetch preserves auth failure from parseable html remains fallback`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            if url.path == "/console/usage" {
                return Self.httpResponse(
                    url: url,
                    body: "<html><main>Coding Plan Plus available usage 1000 prompts / 5 hours</main></html>",
                    contentType: "text/html")
            }
            return Self.httpResponse(
                url: url,
                body: #"{"base_resp":{"status_code":1004,"status_msg":"cookie is missing, log in again"}}"#,
                contentType: "application/json")
        }

        await #expect(throws: MiniMaxUsageError.invalidCredentials) {
            try await MiniMaxUsageFetcher.fetchUsage(
                cookieHeader: "HERTZ-SESSION=expired",
                region: .chinaMainland,
                environment: [:],
                includeBillingHistory: false,
                session: transport)
        }
        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == [
            "/console/usage",
            "/backend/account/token_plan/remains_percent",
        ])
    }

    @Test
    func `web usage fetch preserves cancellation from parseable html remains fallback`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            if url.path == "/console/usage" {
                return Self.httpResponse(
                    url: url,
                    body: "<html><main>Coding Plan Plus available usage 1000 prompts / 5 hours</main></html>",
                    contentType: "text/html")
            }
            throw CancellationError()
        }

        await #expect(throws: CancellationError.self) {
            try await MiniMaxUsageFetcher.fetchUsage(
                cookieHeader: "HERTZ-SESSION=abc",
                region: .chinaMainland,
                environment: [:],
                includeBillingHistory: false,
                session: transport)
        }
        let requests = await transport.requests()
        #expect(requests.map { $0.url?.path } == [
            "/console/usage",
            "/backend/account/token_plan/remains_percent",
        ])
    }

    private static let currentTokenPlanRemainsJSON = """
    {
      "model_remains": [
        {
          "start_time": 1782043200000,
          "end_time": 1782057600000,
          "remains_time": 7003536,
          "current_interval_total_count": 0,
          "current_interval_usage_count": 0,
          "model_name": "general",
          "current_weekly_total_count": 0,
          "current_weekly_usage_count": 0,
          "weekly_start_time": 1781452800000,
          "weekly_end_time": 1782057600000,
          "weekly_remains_time": 7003536,
          "current_interval_status": 1,
          "current_interval_remaining_percent": 100,
          "current_weekly_status": 1,
          "current_weekly_remaining_percent": 70,
          "weekly_boost_permille": 1500
        },
        {
          "start_time": 1781971200000,
          "end_time": 1782057600000,
          "remains_time": 7003536,
          "current_interval_total_count": 0,
          "current_interval_usage_count": 0,
          "model_name": "video",
          "current_weekly_total_count": 0,
          "current_weekly_usage_count": 0,
          "weekly_start_time": 1781452800000,
          "weekly_end_time": 1782057600000,
          "weekly_remains_time": 7003536,
          "current_interval_status": 3,
          "current_interval_remaining_percent": 100,
          "current_weekly_status": 3,
          "current_weekly_remaining_percent": 100
        }
      ],
      "base_resp": { "status_code": 0, "status_msg": "success" }
    }
    """

    private static let percentBasedRemainsJSON = """
    {
      "model_remains": [
        {
          "start_time": 1780279200000,
          "end_time": 1780297200000,
          "remains_time": 16659830,
          "current_interval_total_count": 0,
          "current_interval_usage_count": 0,
          "model_name": "general",
          "current_weekly_total_count": 0,
          "current_weekly_usage_count": 0,
          "weekly_start_time": 1780243200000,
          "weekly_end_time": 1780848000000,
          "weekly_remains_time": 567459830,
          "current_interval_status": 1,
          "current_interval_remaining_percent": 96,
          "current_weekly_status": 1,
          "current_weekly_remaining_percent": 99
        }
      ],
      "base_resp": { "status_code": 0, "status_msg": "success" }
    }
    """

    private static func httpResponse(
        url: URL,
        body: String,
        statusCode: Int = 200,
        contentType: String) -> (Data, URLResponse)
    {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType])!
        return (Data(body.utf8), response)
    }
}
