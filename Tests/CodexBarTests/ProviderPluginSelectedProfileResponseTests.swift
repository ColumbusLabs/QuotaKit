import Foundation
import Testing
@testable import CodexBarCore

struct ProviderPluginSelectedProfileResponseTests {
    @Test(arguments: BundledPluginTestSupport.engines)
    func `rejecting a selected session revokes it from the shared HTTP cookie jar`(
        engine: ProviderPluginEngineKind) async throws
    {
        let requests = LockIsolated(0)
        let source = ProviderPluginSelectedProfileTests.source.replacingOccurrences(
            of: "return {primary: {usedPercent: response.json.percent}};", with: """
            ctx.browser.rejectCookie('app.langdock.com', session);
            let revoked = false;
            try {
              await ctx.http.getJSON('https://app.langdock.com/api/usage', {cookieSession: session.id});
            } catch {
              revoked = true;
            }
            if (!revoked) throw new Error('Rejected session remained usable');
            return {primary: {usedPercent: response.json.percent}};
            """)
        let runtime = try ProviderPluginRuntime(
            source: source,
            transport: ProviderHTTPTransportHandler { request in
                requests.setValue(requests.value + 1)
                #expect(request.value(forHTTPHeaderField: "Cookie") == "auth_token=synthetic-account-a")
                let url = try #require(request.url)
                return try (Data(#"{"percent":42}"#.utf8), #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil)))
            },
            engine: engine)

        let result = try await runtime.fetchResult(cookies: LangdockPluginTests.broker(runtime))
        #expect(result.usage.primary?.usedPercent == 42)
        #expect(requests.value == 1)
    }

    @Test(arguments: BundledPluginTestSupport.engines, [true, false])
    func `selected profiles hide response cookie headers while preserving ordinary headers`(
        engine: ProviderPluginEngineKind, selected: Bool) async throws
    {
        var source = ProviderPluginSelectedProfileTests.source.replacingOccurrences(
            of: "return {primary: {usedPercent: response.json.percent}};", with: """
            const exposed = response.headers['set-cookie'] !== undefined ||
              response.headers['set-cookie2'] !== undefined || response.headers.cookie !== undefined;
            if (exposed !== \(!selected)) throw new Error('Incorrect response cookie visibility');
            if (response.headers['x-safe'] !== 'visible') throw new Error('Missing ordinary response header');
            return {primary: {usedPercent: response.json.percent}};
            """)
        if !selected {
            source = source.replacingOccurrences(of: "store: 'selected-profile', ", with: "")
                .replacingOccurrences(of: "sessionURL: 'https://app.langdock.com/api/usage'", with: "")
        }
        let runtime = try ProviderPluginRuntime(
            source: source,
            transport: ProviderHTTPTransportHandler { request in
                let url = try #require(request.url)
                return try (Data(#"{"percent":42}"#.utf8), #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Set-Cookie": "auth_token=synthetic-rotated",
                        "Set-Cookie2": "auth_token=synthetic-rotated",
                        "Cookie": "auth_token=synthetic-echoed",
                        "X-Safe": "visible",
                    ])))
            },
            engine: engine)
        let record = try LangdockPluginTests.record()
        var settings = CookieProviderSettings()
        settings.selectedBrowserProfile = LangdockPluginTests.profile
        let broker = ProviderPluginCookieBroker(
            provider: .langdock,
            domains: runtime.manifest.cookieDomains,
            settings: settings,
            batches: { _, _ in nil },
            jarImporter: { [(records: [record], source: "Fixture")] },
            policy: runtime.manifest.cookiePolicy,
            profileReader: { _ in [record] })
        let result = try await runtime.fetchResult(cookies: broker)
        #expect(result.usage.primary?.usedPercent == 42)
    }
}
