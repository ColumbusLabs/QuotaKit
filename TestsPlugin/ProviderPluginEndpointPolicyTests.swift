import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct ProviderPluginEndpointPolicyTests {
    private static let engines: [ProviderPluginEngineKind] = {
        #if canImport(JavaScriptCore)
        [.javaScriptCore, .quickJS]
        #else
        [.quickJS]
        #endif
    }()

    @Test(arguments: Self.engines)
    func `private network HTTP policy accepts a private endpoint`(engine: ProviderPluginEngineKind) async throws {
        let requests = EndpointPolicyRequestRecorder()
        let runtime = try ProviderPluginRuntime(
            source: Self.plugin(policy: .httpsOrPrivateNetworkHTTP),
            transport: Self.transport(recorder: requests, body: #"{"used":31}"#),
            engine: engine)

        #expect(runtime.manifest.endpoints.contains(
            .setting(key: "BASE_URL", policy: .httpsOrPrivateNetworkHTTP)))
        let snapshot = try await runtime.fetchUsage(settings: ["BASE_URL": "http://192.168.1.2:4000"])

        #expect(snapshot.primary?.usedPercent == 31)
        #expect(await requests.first?.url?.absoluteString == "http://192.168.1.2:4000/usage")
    }

    @Test(arguments: Self.engines, ["http://example.test", "http://203.0.113.2"])
    func `private network HTTP policy rejects public HTTP before transport`(
        engine: ProviderPluginEngineKind,
        baseURL: String) async throws
    {
        let requests = EndpointPolicyRequestRecorder()
        let runtime = try ProviderPluginRuntime(
            source: Self.plugin(policy: .httpsOrPrivateNetworkHTTP),
            transport: Self.transport(recorder: requests),
            engine: engine)

        await #expect(throws: ProviderPluginError.self) {
            _ = try await runtime.fetchUsage(settings: ["BASE_URL": baseURL])
        }
        #expect(await requests.isEmpty)
    }

    @Test(arguments: Self.engines)
    func `loopback HTTP policy permits loopback but rejects LAN endpoints`(
        engine: ProviderPluginEngineKind) async throws
    {
        let allowedRequests = EndpointPolicyRequestRecorder()
        let allowed = try ProviderPluginRuntime(
            source: Self.plugin(policy: .httpsOrLoopbackHTTP),
            transport: Self.transport(recorder: allowedRequests, body: #"{"used":23}"#),
            engine: engine)
        let snapshot = try await allowed.fetchUsage(settings: ["BASE_URL": "http://127.0.0.1:8787"])

        #expect(snapshot.primary?.usedPercent == 23)
        #expect(await allowedRequests.first?.url?.absoluteString == "http://127.0.0.1:8787/usage")

        let rejectedRequests = EndpointPolicyRequestRecorder()
        let rejected = try ProviderPluginRuntime(
            source: Self.plugin(policy: .httpsOrLoopbackHTTP),
            transport: Self.transport(recorder: rejectedRequests),
            engine: engine)
        await #expect(throws: ProviderPluginError.self) {
            _ = try await rejected.fetchUsage(settings: ["BASE_URL": "http://192.168.1.2:4000"])
        }
        #expect(await rejectedRequests.isEmpty)
    }

    private static func plugin(policy: ProviderPluginEndpoint.Policy) -> String {
        """
        defineProvider({
          id: "synthetic",
          name: "Fixture",
          endpoints: [{ setting: "BASE_URL", policy: "\(policy.rawValue)" }],
          settings: [{ key: "BASE_URL", title: "Base URL", type: "plain" }],
          async fetchUsage(ctx) {
            const base = ctx.settings.get("BASE_URL");
            const response = await ctx.http.getJSON(`${base}/usage`);
            return { primary: { usedPercent: response.json.used } };
          },
        });
        """
    }

    private static func transport(
        recorder: EndpointPolicyRequestRecorder,
        body: String = #"{"ok":true}"#) -> ProviderHTTPTransportHandler
    {
        ProviderHTTPTransportHandler { request in
            await recorder.append(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]))
            return (Data(body.utf8), response)
        }
    }
}

private actor EndpointPolicyRequestRecorder {
    private var requests: [URLRequest] = []

    var first: URLRequest? {
        self.requests.first
    }

    var isEmpty: Bool {
        self.requests.isEmpty
    }

    func append(_ request: URLRequest) {
        self.requests.append(request)
    }
}
