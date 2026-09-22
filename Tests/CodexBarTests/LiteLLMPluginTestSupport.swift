import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

enum LiteLLMPluginTestSupport {
    #if canImport(JavaScriptCore)
    static let engines: [ProviderPluginEngineKind] = [.quickJS, .javaScriptCore]
    #else
    static let engines: [ProviderPluginEngineKind] = [.quickJS]
    #endif

    static func runtime(
        engine: ProviderPluginEngineKind = .quickJS,
        transport: any ProviderHTTPTransport) throws -> ProviderPluginRuntime
    {
        guard let bundle = CodexBarCoreResources.bundle,
              let url = bundle.url(forResource: "litellm", withExtension: "js")
        else {
            throw ProviderPluginError.load("bundled plugin 'litellm.js' was not found")
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        return try ProviderPluginRuntime(source: source, transport: transport, engine: engine)
    }

    static func fetch(
        _ body: String,
        key: String = #"{"info":{"user_id":"user-123","team_id":"team-456"}}"#,
        engine: ProviderPluginEngineKind = .quickJS,
        now: Date = Date(timeIntervalSince1970: 1)) async throws -> UsageSnapshot
    {
        let transport = ProviderHTTPTransportHandler { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            let keyRequest = request.url?.path == "/key/info"
            if keyRequest { #expect(request.url?.query == nil) }
            return (Data((keyRequest ? key : body).utf8), HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return try await self.runtime(engine: engine, transport: transport)
            .fetchUsage(
                settings: ["LITELLM_BASE_URL": "https://proxy.example.com/v1"],
                secrets: ["LITELLM_API_KEY": "fixture-key"],
                now: now)
    }
}
