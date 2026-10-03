import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CursorSandUsageTests {
    @Test
    func `parses sand usage status`() throws {
        let json = """
        {
            "currentPeriodStart": "2026-08-17T07:57:50.647Z",
            "nextResetTimestampUtc": "2026-08-24T07:57:50.647Z",
            "usagePercent": 100,
            "hasAvailableUsage": true,
            "includedLimitZero": false
        }
        """
        let data = try #require(json.data(using: .utf8))
        let status = try JSONDecoder().decode(CursorSandUsageStatus.self, from: data)

        #expect(status.usagePercent == 100)
        #expect(status.hasAvailableUsage == true)
        #expect(status.includedLimitZero == false)
        let window = try #require(status.extraRateWindow(resetDescription: { _ in "Resets" }))
        #expect(window.id == CursorSandUsageStatus.extraWindowID)
        #expect(window.title == "Grok Bot")
        #expect(window.window.usedPercent == 100)
        #expect(window.window.windowMinutes == 10080)
        #expect(window.window.resetsAt != nil)
    }

    @Test
    func `hides grok bot extra window without an included limit`() {
        let status = CursorSandUsageStatus(
            currentPeriodStart: "2026-08-17T07:57:50.647Z",
            nextResetTimestampUtc: "2026-08-24T07:57:50.647Z",
            usagePercent: 100,
            hasAvailableUsage: false,
            includedLimitZero: true)
        #expect(status.extraRateWindow(resetDescription: { _ in "Resets" }) == nil)
    }

    @Test
    func `paid grok bot cadence uses a full week when period starts mid-week`() throws {
        let now = try #require(ISO8601DateParser.parse("2026-10-03T00:02:00Z"))
        let status = CursorSandUsageStatus(
            currentPeriodStart: "2026-10-02T18:03:04Z",
            nextResetTimestampUtc: "2026-10-05T11:20:04Z",
            usagePercent: 44.935,
            hasAvailableUsage: true,
            includedLimitZero: false)
        let window = try #require(status.extraRateWindow(now: now, resetDescription: { _ in "Resets" }))
        #expect(window.window.windowMinutes == 7 * 24 * 60)
        #expect(window.window.usedPercent == 44.935)

        let pace = try #require(UsagePace.weekly(window: window.window, now: now))
        #expect(abs(pace.expectedUsedPercent - 64.702) < 0.001)
        #expect(abs(pace.deltaPercent + 19.767) < 0.001)
        #expect(pace.willLastToReset)
    }

    @Test(arguments: [nil, "not-a-date", "2026-10-02T18:03:04Z"] as [String?])
    func `paid grok bot weekly cadence ignores its reported start`(start: String?) throws {
        let status = CursorSandUsageStatus(
            currentPeriodStart: start,
            nextResetTimestampUtc: "2026-10-05T11:20:04Z",
            usagePercent: 10,
            hasAvailableUsage: true,
            includedLimitZero: false)
        let window = try #require(status.extraRateWindow(resetDescription: { _ in "Resets" }))
        #expect(window.window.windowMinutes == 7 * 24 * 60)
    }

    @Test(arguments: [12.3, 100.0])
    func `reported trial schema keeps available and exhausted usage without recurring reset`(used: Double) throws {
        let status = try Self.status(expiry: "2026-09-21T09:12:32.776Z", used: used)
        let window = try #require(status.extraRateWindow(now: Self.now, resetDescription: { _ in "Resets" }))
        #expect(window.window.usedPercent == used)
        #expect(window.window.windowMinutes == nil)
        #expect(window.window.resetsAt == nil)
        #expect(window.window.resetDescription == nil)
    }

    @Test(arguments: [nil, "", "not-a-date", "2026-09-14T00:00:00Z", "2026-09-13T23:59:59.999Z"])
    func `missing malformed and expired trials require a paid allowance`(expiry: String?) throws {
        let trial = try Self.status(expiry: expiry)
        #expect(trial.extraRateWindow(now: Self.now, resetDescription: { _ in "Resets" }) == nil)
        let paid = try Self.status(expiry: expiry, includedLimitZero: false)
        let window = try #require(paid.extraRateWindow(now: Self.now, resetDescription: { _ in "Resets" }))
        #expect(window.window.windowMinutes == 10080)
        #expect(window.window.resetsAt != nil)
    }

    @Test
    func `trial without percentage remains unavailable`() throws {
        let status = try Self.status(expiry: "2026-09-21T09:12:32.776Z", used: nil)
        #expect(status.extraRateWindow(now: Self.now, resetDescription: { _ in "Resets" }) == nil)
    }

    @Test
    func `current allowance field wins while released API and old payload stay readable`() throws {
        let oldPayload = Data(#"{"hasNonZeroIncludedLimit":true,"usagePercent":42}"#.utf8)
        let old = try JSONDecoder().decode(CursorSandUsageStatus.self, from: oldPayload)
        #expect(old.extraRateWindow(resetDescription: { _ in "Resets" })?.window.usedPercent == 42)
        let status = CursorSandUsageStatus(
            currentPeriodStart: nil,
            nextResetTimestampUtc: nil,
            usagePercent: 42,
            hasAvailableUsage: true,
            hasNonZeroIncludedLimit: true)
        #expect(status.hasNonZeroIncludedLimit == true)
        #expect(status.extraRateWindow(resetDescription: { _ in "Resets" })?.window.usedPercent == 42)
        let conflicting = Data(#"{"hasNonZeroIncludedLimit":true,"includedLimitZero":true,"usagePercent":42}"#.utf8)
        let current = try JSONDecoder().decode(CursorSandUsageStatus.self, from: conflicting)
        #expect(current.extraRateWindow(resetDescription: { _ in "Resets" }) == nil)
    }

    @Test(arguments: [true, false])
    func `paid allowance preserves timing even with a future trial expiry`(hasTrial: Bool) {
        let snapshot = CursorStatusSnapshot(
            planPercentUsed: 0.6,
            autoPercentUsed: 0.75,
            apiPercentUsed: 0,
            planUsedUSD: 14.99,
            planLimitUSD: 400.0,
            onDemandUsedUSD: 0,
            onDemandLimitUSD: nil,
            teamOnDemandUsedUSD: nil,
            teamOnDemandLimitUSD: nil,
            billingCycleEnd: nil,
            membershipType: "ultra",
            accountEmail: nil,
            accountName: nil,
            rawJSON: nil,
            sandUsage: CursorSandUsageStatus(
                currentPeriodStart: "2026-08-17T07:57:50.647Z",
                nextResetTimestampUtc: "2026-08-24T07:57:50.647Z",
                usagePercent: 100,
                hasAvailableUsage: true,
                includedLimitZero: false,
                sandTrialExpiresAt: hasTrial ? "2026-09-21T09:12:32.776Z" : nil))

        let usageSnapshot = snapshot.toUsageSnapshot(now: Self.now)
        let grokBot = usageSnapshot.extraRateWindows?.first { $0.id == CursorSandUsageStatus.extraWindowID }
        #expect(grokBot?.title == "Grok Bot")
        #expect(grokBot?.window.usedPercent == 100)
        #expect(grokBot?.window.windowMinutes == 10080)
        #expect(grokBot?.window.resetsAt != nil)
        #expect(usageSnapshot.updatedAt == Self.now)
        #expect(usageSnapshot.primary?.usedPercent == 0.75)
        #expect(usageSnapshot.secondary?.usedPercent == 0)
        #expect(usageSnapshot.tertiary == nil)
    }

    @Test(arguments: [true, false])
    func `sand endpoint maps paid and trial usage onto grok bot extra window`(isTrial: Bool) async throws {
        let testSession = CursorStatusProbeTestSession { request in
            let requestURL = try #require(request.url)
            switch requestURL.path {
            case CursorSandUsageStatus.endpointPath:
                #expect(request.httpMethod == "POST")
                #expect(request.timeoutInterval == 5)
                #expect(request.value(forHTTPHeaderField: "Origin") == "https://cursor.test")
                #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=test")
                return makeCursorStatusProbeResponse(
                    url: requestURL,
                    body: """
                    {
                      "currentPeriodStart": "2026-09-14T09:12:32.776Z",
                      "nextResetTimestampUtc": "2026-09-21T09:12:32.776Z",
                      "usagePercent": 100,
                      "hasAvailableUsage": true,
                      "includedLimitZero": \(isTrial ? "true" : "false"),
                      "sandTrialExpiresAt": "2026-09-21T09:12:32.776Z"
                    }
                    """,
                    statusCode: 200)
            default:
                throw URLError(.badURL)
            }
        }

        let baseURL = try #require(URL(string: "https://cursor.test"))
        let probe = CursorStatusProbe(
            baseURL: baseURL,
            browserDetection: BrowserDetection(cacheTTL: 0),
            urlSession: testSession.urlSession)
        let (sandUsage, rawJSON) = try await probe.fetchSandUsage(cookieHeader: "auth=test", deadline: nil)
        let snapshot = CursorStatusSnapshot(
            planPercentUsed: 0.6,
            planUsedUSD: 14.99,
            planLimitUSD: 400,
            onDemandUsedUSD: 0,
            onDemandLimitUSD: nil,
            teamOnDemandUsedUSD: nil,
            teamOnDemandLimitUSD: nil,
            billingCycleEnd: nil,
            membershipType: "ultra",
            accountEmail: nil,
            accountName: nil,
            rawJSON: rawJSON,
            sandUsage: sandUsage)

        #expect(snapshot.sandUsage?.usagePercent == 100)
        #expect(snapshot.sandUsage?.includedLimitZero == isTrial)
        let grokBot = snapshot.toUsageSnapshot(now: Self.now).extraRateWindows?.first {
            $0.id == CursorSandUsageStatus.extraWindowID
        }
        #expect(grokBot?.window.usedPercent == 100)
        #expect(grokBot?.window.windowMinutes == (isTrial ? nil : 10080))
        #expect((grokBot?.window.resetsAt == nil) == isTrial)
        #expect(testSession.requestPaths == [CursorSandUsageStatus.endpointPath])
        #expect(snapshot.rawJSON?.contains("sandTrialExpiresAt") == true)
    }

    @Test(arguments: [true, false])
    func `full cursor fetch attaches sand usage completed before required responses`(isTrial: Bool) async throws {
        CursorSandOrderedURLProtocol.reset(isTrial: isTrial)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CursorSandOrderedURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let baseURL = try #require(URL(string: "https://cursor.test"))

        let snapshot = try await CursorStatusProbe(
            baseURL: baseURL,
            browserDetection: BrowserDetection(cacheTTL: 0),
            urlSession: session).fetchWithManualCookies("auth=test")

        #expect(CursorSandOrderedURLProtocol.sandResponseFinished)
        #expect(snapshot.sandUsage?.usagePercent == 100)
        #expect(snapshot.sandUsage?.includedLimitZero == isTrial)
        let grokBot = snapshot.toUsageSnapshot(now: Self.now).extraRateWindows?.first {
            $0.id == CursorSandUsageStatus.extraWindowID
        }
        #expect(grokBot?.window.usedPercent == 100)
        #expect(grokBot?.window.windowMinutes == (isTrial ? nil : 10080))
        #expect(snapshot.rawJSON?.contains("--- /api/dashboard/get-sand-usage-status ---") == true)
    }

    private static let now = Date(timeIntervalSince1970: 1_789_344_000)

    private static func status(
        expiry: String?,
        used: Double? = 12.3,
        includedLimitZero: Bool = true) throws -> CursorSandUsageStatus
    {
        var payload: [String: Any] = [
            "currentPeriodStart": "2026-09-14T09:12:32.776Z",
            "nextResetTimestampUtc": "2026-09-21T09:12:32.776Z",
            "includedLimitZero": includedLimitZero,
            "hasAvailableUsage": used.map { $0 < 100 } ?? false,
        ]
        payload["sandTrialExpiresAt"] = expiry
        payload["usagePercent"] = used
        return try JSONDecoder().decode(
            CursorSandUsageStatus.self,
            from: JSONSerialization.data(withJSONObject: payload))
    }
}

private final class CursorSandOrderedURLProtocol: URLProtocol, @unchecked Sendable {
    private static let condition = NSCondition()
    private nonisolated(unsafe) static var finishedSand = false
    private nonisolated(unsafe) static var trial = false
    private var requiredResponse: DispatchWorkItem?

    static var sandResponseFinished: Bool {
        self.condition.lock()
        defer { self.condition.unlock() }
        return self.finishedSand
    }

    static func reset(isTrial: Bool) {
        self.condition.lock()
        self.finishedSand = false
        self.trial = isTrial
        self.condition.unlock()
    }

    override static func canInit(with _: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let path = self.request.url?.path else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if path == CursorSandUsageStatus.endpointPath {
            self.sendResponse(body: """
            {
              "currentPeriodStart": "2026-09-14T09:12:32.776Z",
              "nextResetTimestampUtc": "2026-09-21T09:12:32.776Z",
              "usagePercent": 100,
              "hasAvailableUsage": true,
              "includedLimitZero": \(Self.trial),
              "sandTrialExpiresAt": "2026-09-21T09:12:32.776Z"
            }
            """, statusCode: 200)
            Self.condition.lock()
            Self.finishedSand = true
            Self.condition.broadcast()
            Self.condition.unlock()
            return
        }

        // Required responses run off the URLProtocol callback so a request that
        // arrives first cannot block delivery of the optional Sand response.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Self.condition.lock()
            let deadline = Date().addingTimeInterval(3)
            while !Self.finishedSand, Self.condition.wait(until: deadline) {}
            let sandFinished = Self.finishedSand
            Self.condition.unlock()
            guard sandFinished else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                return
            }
            switch path {
            case "/api/usage-summary":
                self.sendResponse(body: """
                {
                  "membershipType": "ultra",
                  "individualUsage": {"plan": {"used": 1499, "limit": 40000, "totalPercentUsed": 0.6}}
                }
                """, statusCode: 200)
            case "/api/auth/me":
                self.sendResponse(body: #"{"error":"nope"}"#, statusCode: 500)
            default:
                self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            }
        }
        self.requiredResponse = work
        DispatchQueue.global().async(execute: work)
    }

    override func stopLoading() {
        self.requiredResponse?.cancel()
    }

    private func sendResponse(body: String, statusCode: Int) {
        guard let url = self.request.url else { return }
        let (response, data) = makeCursorStatusProbeResponse(url: url, body: body, statusCode: statusCode)
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: data)
        self.client?.urlProtocolDidFinishLoading(self)
    }
}
