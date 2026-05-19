import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ProviderHTTPClientTests {
    @Test
    func `default client configuration fails blocked connections promptly`() {
        let configuration = ProviderHTTPClient.defaultConfiguration()

        #expect(configuration.timeoutIntervalForRequest == 30)
        #expect(configuration.timeoutIntervalForResource == 90)
        #if !os(Linux)
        #expect(configuration.waitsForConnectivity == false)
        #endif
    }

    @Test
    func `client loads requests through an injected session`() async throws {
        StubURLProtocol.requests = []
        StubURLProtocol.handler = { request in
            StubURLProtocol.requests.append(request)
            let response = try HTTPURLResponse(
                url: #require(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            return (Data(#"{"ok":true}"#.utf8), response)
        }
        defer {
            StubURLProtocol.handler = nil
            StubURLProtocol.requests = []
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = ProviderHTTPClient(session: URLSession(configuration: configuration))
        let request = try URLRequest(url: #require(URL(string: "https://example.com/status")))

        let (data, response) = try await client.data(for: request)

        let body = try #require(String(data: data, encoding: .utf8))
        #expect(body == #"{"ok":true}"#)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(StubURLProtocol.requests.count == 1)
        #expect(StubURLProtocol.requests.first?.url?.host == "example.com")
    }

    @Test
    func `response helper unwraps HTTP responses`() async throws {
        let transport = ProviderHTTPTransportHandler { request in
            let response = try HTTPURLResponse(
                url: #require(request.url),
                statusCode: 204,
                httpVersion: "HTTP/1.1",
                headerFields: ["X-Test": "ok"])!
            return (Data("done".utf8), response)
        }
        let request = try URLRequest(url: #require(URL(string: "https://example.com/ok")))

        let response = try await transport.response(for: request)

        #expect(response.statusCode == 204)
        #expect(response.response.value(forHTTPHeaderField: "X-Test") == "ok")
        #expect(String(data: response.data, encoding: .utf8) == "done")
    }

    @Test
    func `response helper rejects non HTTP responses`() async throws {
        let transport = ProviderHTTPTransportHandler { request in
            let response = URLResponse(
                url: request.url ?? URL(string: "https://example.com/not-http")!,
                mimeType: nil,
                expectedContentLength: 0,
                textEncodingName: nil)
            return (Data(), response)
        }
        let request = try URLRequest(url: #require(URL(string: "https://example.com/not-http")))

        await #expect(throws: URLError.self) {
            _ = try await transport.response(for: request)
        }
    }
}

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, URLResponse))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.cannotLoadFromNetwork))
            return
        }

        do {
            let (data, response) = try handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
