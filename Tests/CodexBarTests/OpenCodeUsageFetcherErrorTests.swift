import CodexBarCore
import Foundation
import Testing

@Suite(.serialized)
struct OpenCodeUsageFetcherErrorTests {
    @Test
    func extractsApiErrorFromUppercaseHTMLTitle() async throws {
        let registered = URLProtocol.registerClass(OpenCodeStubURLProtocol.self)
        defer {
            if registered {
                URLProtocol.unregisterClass(OpenCodeStubURLProtocol.self)
            }
            OpenCodeStubURLProtocol.handler = nil
        }

        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let body = "<html><head><TITLE>403 Forbidden</TITLE></head><body>denied</body></html>"
            return Self.makeResponse(url: url, body: body, statusCode: 500, contentType: "text/html")
        }

        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                workspaceIDOverride: "wrk_TEST123")
            Issue.record("Expected OpenCodeUsageError.apiError")
        } catch let error as OpenCodeUsageError {
            switch error {
            case let .apiError(message):
                #expect(message.contains("HTTP 500"))
                #expect(message.contains("403 Forbidden"))
            default:
                Issue.record("Expected apiError, got: \(error)")
            }
        }
    }

    @Test
    func extractsApiErrorFromDetailField() async throws {
        let registered = URLProtocol.registerClass(OpenCodeStubURLProtocol.self)
        defer {
            if registered {
                URLProtocol.unregisterClass(OpenCodeStubURLProtocol.self)
            }
            OpenCodeStubURLProtocol.handler = nil
        }

        OpenCodeStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let body = #"{"detail":"Workspace missing"}"#
            return Self.makeResponse(url: url, body: body, statusCode: 500, contentType: "application/json")
        }

        do {
            _ = try await OpenCodeUsageFetcher.fetchUsage(
                cookieHeader: "auth=test",
                timeout: 2,
                workspaceIDOverride: "wrk_TEST123")
            Issue.record("Expected OpenCodeUsageError.apiError")
        } catch let error as OpenCodeUsageError {
            switch error {
            case let .apiError(message):
                #expect(message.contains("HTTP 500"))
                #expect(message.contains("Workspace missing"))
            default:
                Issue.record("Expected apiError, got: \(error)")
            }
        }
    }

    private static func makeResponse(
        url: URL,
        body: String,
        statusCode: Int,
        contentType: String) -> (HTTPURLResponse, Data)
    {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType])!
        return (response, Data(body.utf8))
    }
}

final class OpenCodeStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "opencode.ai"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
