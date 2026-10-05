import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeRateLimitResetCreditsTests {
    @Test
    func `decodes eligible reset grants without retaining grant identifiers`() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let laterExpiry = now.addingTimeInterval(14400)
        let json = Self.usageJSON(
            grants: [
                Self.grant(
                    id: "redemption-secret",
                    resetsLeft: 2,
                    resetsTotal: 2,
                    startsAt: now,
                    endsAt: laterExpiry),
                #"{"resets_left":"invalid","paused":false,"id":"discard-this"}"#,
                Self.grant(id: "paused", resetsLeft: 4, resetsTotal: 4, startsAt: nil, endsAt: nil, paused: true),
                Self.grant(
                    id: "not-started",
                    resetsLeft: 1,
                    resetsTotal: 1,
                    startsAt: now.addingTimeInterval(3600),
                    endsAt: nil),
                Self.grant(
                    id: "expired",
                    resetsLeft: 1,
                    resetsTotal: 1,
                    startsAt: nil,
                    endsAt: now),
                Self.grant(id: "no-expiry", resetsLeft: 1, resetsTotal: 1, startsAt: nil, endsAt: nil),
            ],
            eligible: true)

        let usage = try ClaudeWebAPIFetcher._parseUsageResponseForTesting(Data(json.utf8), now: now)
        let resetCredits = try #require(usage.resetCredits)

        #expect(usage.sessionPercentUsed == 17)
        #expect(usage.weeklyPercentUsed == 42)
        #expect(resetCredits.expirations == [laterExpiry, laterExpiry, nil])
        #expect(resetCredits.updatedAt == now)
        #expect(!String(describing: resetCredits).contains("redemption-secret"))
        #expect(!String(describing: resetCredits).contains("discard-this"))
    }

    @Test
    func `missing ineligible or unreadable reset block preserves ordinary usage`() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let inputs = [
            #"{"five_hour":{"utilization":17},"seven_day":{"utilization":42}}"#,
            #"""
            {
              "five_hour":{"utilization":17},
              "cedar_ember":{"eligible":false,"grants":[{"resets_left":1,"paused":false}]}
            }
            """#,
            #"{"five_hour":{"utilization":17},"cedar_ember":"not-an-object"}"#,
            #"{"five_hour":{"utilization":17},"cedar_ember":{"grants":[]}}"#,
        ]

        for input in inputs {
            let usage = try ClaudeWebAPIFetcher._parseUsageResponseForTesting(Data(input.utf8), now: now)
            #expect(usage.sessionPercentUsed == 17)
            #expect(usage.resetCredits == nil)
        }
    }

    @Test
    func `rejects implausible reset counts and grant record counts`() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let overCount = Self.usageJSON(
            grants: [Self.grant(id: "too-many", resetsLeft: 51, resetsTotal: 51, startsAt: nil, endsAt: nil)],
            eligible: true)
        let tooManyRecords = Array(repeating: Self.grant(
            id: "record",
            resetsLeft: 1,
            resetsTotal: 1,
            startsAt: nil,
            endsAt: nil), count: ClaudeLimitResetStatusResponse.maximumGrantRecords + 1)
        let overRecords = Self.usageJSON(grants: tooManyRecords, eligible: true)

        #expect(try ClaudeWebAPIFetcher._parseUsageResponseForTesting(Data(overCount.utf8), now: now)
            .resetCredits == nil)
        #expect(try ClaudeWebAPIFetcher._parseUsageResponseForTesting(Data(overRecords.utf8), now: now)
            .resetCredits == nil)
    }

    @Test
    func `unsupported reset opt in retries once with the original cookie`() async throws {
        let requests = ClaudeResetRequestCapture()
        let transport = ProviderHTTPTransportHandler { request in
            requests.record(request)
            let isOptIn = try URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?.contains(where: { $0.name == "cedar_ember" && $0.value == "1" }) == true
            if isOptIn {
                return try Self.response(
                    request,
                    statusCode: 403,
                    headers: ["Set-Cookie": "sessionKey=renewed-cookie; Path=/"],
                    body: "forbidden")
            }
            return try Self.response(
                request,
                statusCode: 200,
                body: #"""
                {"five_hour":{"utilization":17,"resets_at":"2033-05-18T00:00:00Z"},"seven_day":{"utilization":42}}
                """#)
        }

        let usage = try await ClaudeWebHTTPTransport.$overrideForTesting.withValue(transport) {
            try await ClaudeWebAPIFetcher._fetchUsageDataForTesting(orgId: "org-123", sessionKey: "original-cookie")
        }
        let captured = requests.requests

        #expect(captured.count == 2)
        #expect(captured[0].url?.query == "cedar_ember=1")
        #expect(captured[1].url?.query == nil)
        #expect(captured.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == "sessionKey=original-cookie" })
        #expect(usage.sessionPercentUsed == 17)
        #expect(usage.weeklyPercentUsed == 42)
        #expect(usage.resetCredits == nil)
    }

    @Test
    func `unauthorized rate limited and Cloudflare challenge responses do not retry`() async throws {
        let cases: [(Int, [String: String], String)] = [
            (401, [:], ClaudeWebAPIFetcher.FetchError.unauthorized.localizedDescription),
            (429, [:], ClaudeWebAPIFetcher.FetchError.serverError(statusCode: 429).localizedDescription),
            (
                403,
                ["cf-mitigated": "challenge"],
                ClaudeWebAPIFetcher.FetchError.cloudflareChallenge.localizedDescription),
        ]

        for (statusCode, headers, expectedMessage) in cases {
            let requests = ClaudeResetRequestCapture()
            let transport = ProviderHTTPTransportHandler { request in
                requests.record(request)
                return try Self.response(request, statusCode: statusCode, headers: headers, body: "rejected")
            }
            var message: String?
            do {
                _ = try await ClaudeWebHTTPTransport.$overrideForTesting.withValue(transport) {
                    try await ClaudeWebAPIFetcher._fetchUsageDataForTesting(
                        orgId: "org-123",
                        sessionKey: "fixture-cookie")
                }
            } catch {
                message = error.localizedDescription
            }
            #expect(message == expectedMessage)
            #expect(requests.requests.count == 1)
        }
    }

    @Test
    func `failed fallback stops after its single ordinary usage request`() async throws {
        let requests = ClaudeResetRequestCapture()
        let transport = ProviderHTTPTransportHandler { request in
            requests.record(request)
            let status = request.url?.query == nil ? 500 : 403
            return try Self.response(request, statusCode: status, body: "unsupported")
        }
        var message: String?
        do {
            _ = try await ClaudeWebHTTPTransport.$overrideForTesting.withValue(transport) {
                try await ClaudeWebAPIFetcher._fetchUsageDataForTesting(
                    orgId: "org-123",
                    sessionKey: "fixture-cookie")
            }
        } catch {
            message = error.localizedDescription
        }

        #expect(message == ClaudeWebAPIFetcher.FetchError.serverError(statusCode: 500).localizedDescription)
        #expect(requests.requests.count == 2)
    }

    @Test
    func `reset credits project only for the Web primary snapshot`() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let resets = ClaudeRateLimitResetCreditsSnapshot(
            expirations: [now.addingTimeInterval(3600)],
            updatedAt: now)
        let claudeUsage = ClaudeUsageSnapshot(
            primary: RateWindow(usedPercent: 17, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            opus: nil,
            resetCredits: resets,
            updatedAt: now,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil,
            rawText: nil)
        let oauthUsage = ClaudeUsageSnapshot(
            primary: claudeUsage.primary,
            secondary: nil,
            opus: nil,
            updatedAt: now,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil,
            rawText: nil)

        let ordinary = ClaudeOAuthFetchStrategy._snapshotForTesting(from: claudeUsage)
        let webPrimary = ClaudeOAuthFetchStrategy._snapshotForTesting(
            from: claudeUsage,
            includeResetCredits: true)
        let optionalWebEnrichment = oauthUsage.replacingWebExtras(extraRateWindows: [], providerCost: nil)

        #expect(ordinary.claudeResetCredits == nil)
        #expect(ordinary.details.isEmpty)
        #expect(webPrimary.claudeResetCredits == resets)
        #expect(webPrimary.details.flatMap(\.rows).contains { $0.label == "Limit Reset Credits" })
        #expect(optionalWebEnrichment.resetCredits == nil)
    }

    @Test
    func `live reset inventory is neither persisted nor restored from Claude details`() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let grantID = "must-not-be-serialized"
        let resets = ClaudeRateLimitResetCreditsSnapshot(
            expirations: [now.addingTimeInterval(3600)],
            updatedAt: now)
        let live = UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: resets.detailSections(now: now),
            claudeResetCredits: resets,
            updatedAt: now,
            identity: ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: nil))

        let data = try JSONEncoder().encode(live)
        let encoded = try #require(String(data: data, encoding: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let restored = try JSONDecoder().decode(UsageSnapshot.self, from: data)

        #expect(json["claudeResetCredits"] == nil)
        #expect(!encoded.contains(grantID))
        #expect(restored.claudeResetCredits == nil)
        #expect(restored.details.flatMap(\.rows).contains { $0.label == "Limit Reset Credits" } == false)
        #expect(restored.primary == live.primary)
    }

    @MainActor
    @Test
    func `Claude menu exposes ordered reset expiries and optional visibility`() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let sooner = now.addingTimeInterval(3600)
        let later = now.addingTimeInterval(7200)
        let resets = ClaudeRateLimitResetCreditsSnapshot(
            expirations: [later, now, nil, sooner],
            updatedAt: now)
        let model = try Self.menuModel(resets: resets, showOptionalUsage: true, now: now)
        let presentation = try #require(model.codexResetCredits)

        #expect(presentation.text == "3 available")
        #expect(presentation.items.map(\.expiryText) == [
            "Expires \(CodexResetCreditsPresentation.exactExpiryTimeText(sooner))",
            "Expires \(CodexResetCreditsPresentation.exactExpiryTimeText(later))",
            "No expiry",
        ])
        #expect(presentation.accessibilityLabel.contains(presentation.helpText))
        #expect(model.usageItemDescriptors.contains { $0.id == .codexResetCredits })
        #expect(model.providerDetails.flatMap(\.rows).contains { $0.label == "Limit Reset Credits" } == false)
        #expect(model.applyingUsageItemVisibility(hiddenItemIDs: [.codexResetCredits]).codexResetCredits == nil)

        let hiddenByPreference = try Self.menuModel(resets: resets, showOptionalUsage: false, now: now)
        #expect(hiddenByPreference.codexResetCredits == nil)
    }

    private static func usageJSON(grants: [String], eligible: Bool) -> String {
        let block = """
        {"eligible":\(eligible),"grants":[\(grants.joined(separator: ","))]}
        """
        return """
        {"five_hour":{"utilization":17},"seven_day":{"utilization":42},"cedar_ember":\(block)}
        """
    }

    private static func grant(
        id: String,
        resetsLeft: Int,
        resetsTotal: Int,
        startsAt: Date?,
        endsAt: Date?,
        paused: Bool = false) -> String
    {
        let starts = startsAt.map { "\"\(Self.iso8601($0))\"" } ?? "null"
        let ends = endsAt.map { "\"\(Self.iso8601($0))\"" } ?? "null"
        return """
        {
          "id":"\(id)",
          "resets_left":\(resetsLeft),
          "resets_total":\(resetsTotal),
          "starts_at":\(starts),
          "ends_at":\(ends),
          "paused":\(paused)
        }
        """
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func response(
        _ request: URLRequest,
        statusCode: Int,
        headers: [String: String] = [:],
        body: String) throws -> (Data, HTTPURLResponse)
    {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers))
        return (Data(body.utf8), response)
    }

    @MainActor
    private static func menuModel(
        resets: ClaudeRateLimitResetCreditsSnapshot,
        showOptionalUsage: Bool,
        now: Date) throws -> UsageMenuCardView.Model
    {
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: resets.detailSections(now: now),
            claudeResetCredits: resets,
            updatedAt: now,
            identity: identity)
        return UsageMenuCardView.Model.make(UsageMenuCardView.Model.Input(
            provider: .claude,
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
            resetTimeDisplayStyle: .absolute,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: showOptionalUsage,
            hidePersonalInfo: false,
            now: now))
    }
}

private final class ClaudeResetRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        self.lock.withLock { self.storedRequests }
    }

    func record(_ request: URLRequest) {
        self.lock.withLock { self.storedRequests.append(request) }
    }
}
