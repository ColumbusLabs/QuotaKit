import Foundation
@testable import CodexBarCore

final class CursorStatusProbeDelayedSandURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var sandCancelled = false
    private var isSandRequest = false

    static var sandRequestWasCancelled: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.sandCancelled
    }

    static func reset() {
        self.lock.lock()
        self.sandCancelled = false
        self.lock.unlock()
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = self.request.url else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if url.path == CursorSandUsageStatus.endpointPath {
            self.isSandRequest = true
            return
        }

        let body: String
        switch url.path {
        case "/api/usage-summary":
            body = #"{"membershipType":"pro","individualUsage":{"plan":{"used":1500,"limit":5000,"# +
                #""totalPercentUsed":30}}}"#
        case "/api/auth/me":
            body = #"{"email":"user@example.com","name":"Test User"}"#
        default:
            self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: Data(body.utf8))
        self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        guard self.isSandRequest else { return }
        Self.lock.lock()
        Self.sandCancelled = true
        Self.lock.unlock()
    }
}
