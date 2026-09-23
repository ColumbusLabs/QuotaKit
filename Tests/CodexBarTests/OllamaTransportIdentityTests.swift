import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct OllamaTransportIdentityTests {
    @Test(arguments: ["validation", "tags"])
    func `API transport diagnostics retain DNS failure identity`(failingEndpoint: String) async {
        let transportFailure = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: [
            NSLocalizedDescriptionKey: "fixture transport failure",
            "fixture-marker": "preserved",
        ])
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            if failingEndpoint == "tags", url.path == "/api/web_search" {
                let response = try #require(HTTPURLResponse(
                    url: url, statusCode: 400, httpVersion: nil, headerFields: nil))
                return (Data("{}".utf8), response)
            }
            throw transportFailure
        }

        do {
            _ = try await OllamaAPIUsageFetcher.fetchUsage(apiKey: "fixture-key", transport: transport)
            Issue.record("Expected the injected transport failure")
        } catch {
            let wrapped = error as NSError
            #expect(wrapped.domain == NSURLErrorDomain)
            #expect(wrapped.code == NSURLErrorCannotFindHost)
            #expect(wrapped.userInfo["fixture-marker"] as? String == "preserved")
            #expect(error.localizedDescription == "Ollama request failed: fixture transport failure")
        }
    }

    @Test(arguments: ["validation", "tags"])
    func `API cancellation stays typed at either transport request`(failingEndpoint: String) async {
        let transport = ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            if failingEndpoint == "tags", url.path == "/api/web_search" {
                let response = try #require(HTTPURLResponse(
                    url: url, statusCode: 400, httpVersion: nil, headerFields: nil))
                return (Data("{}".utf8), response)
            }
            throw CancellationError()
        }

        await #expect(throws: CancellationError.self) {
            _ = try await OllamaAPIUsageFetcher.fetchUsage(apiKey: "fixture-key", transport: transport)
        }
    }
}
