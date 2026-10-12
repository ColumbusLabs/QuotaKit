import Foundation
import Testing
@testable import LiteCore

struct ProbeContractTests {
    @Test
    func `failures map to the menu status they show as`() {
        #expect(ProbeFailure.tokenExpired.status == .tokenExpired)
        #expect(ProbeFailure.tokenUnavailable.status == .tokenUnavailable)
        #expect(ProbeFailure.signInRequired.status == .signInRequired)
        #expect(ProbeFailure.notRunning.status == .notRunning)
        #expect(ProbeFailure.unrecognizedResponse.status == .unrecognizedResponse)
        #expect(ProbeFailure.server(statusCode: 503).status == .error("Server error 503"))
    }

    @Test
    func `the real session refuses redirects`() async throws {
        let session = URLSessionTransport.makeSession()
        defer { session.invalidateAndCancel() }
        let delegate = try #require(session.delegate as? RefuseRedirects)
        let url = try #require(URL(string: "https://api.anthropic.com/api/oauth/usage"))
        let elsewhere = try #require(URL(string: "https://example.com/"))
        let redirect = try #require(HTTPURLResponse(
            url: url,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": elsewhere.absoluteString]))

        let next = await delegate.urlSession(
            session,
            task: session.dataTask(with: url),
            willPerformHTTPRedirection: redirect,
            newRequest: URLRequest(url: elsewhere))

        #expect(next == nil)
        #expect(session.configuration.urlCache == nil)
        #expect(session.configuration.httpMaximumConnectionsPerHost == 2)
    }
}
