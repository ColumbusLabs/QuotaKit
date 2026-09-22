import Foundation
import Testing
@testable import CodexBarCore

struct VertexAIRefreshTests {
    @Test
    func `refresh form preserves opaque credentials`() async throws {
        let credentials = Self.credentials()
        let transport = Self.transport(body: #"{"access_token":"new-access"}"#)

        let refreshed = try await VertexAITokenRefresher.refresh(credentials, session: transport)

        #expect(refreshed.accessToken == "new-access")
        #expect(refreshed.refreshToken == credentials.refreshToken)
        #expect(refreshed.clientId == credentials.clientId)
        #expect(refreshed.clientSecret == credentials.clientSecret)
        let request = try #require(await transport.requests().first)
        #expect(try FormBodyTestSupport.decode(#require(request.httpBody)) == [
            "client_id": credentials.clientId,
            "client_secret": credentials.clientSecret,
            "refresh_token": credentials.refreshToken,
            "grant_type": "refresh_token",
        ])
    }

    @Test(arguments: [
        "{}",
        #"{"access_token":null}"#,
        #"{"access_token":42}"#,
        #"{"access_token":""}"#,
        #"{"access_token":" \t\n "}"#,
    ])
    func `successful refresh without usable access token is rejected`(body: String) async {
        let transport = Self.transport(body: body)
        do {
            _ = try await VertexAITokenRefresher.refresh(Self.credentials(), session: transport)
            Issue.record("Expected malformed successful refresh response to fail")
        } catch let error as VertexAITokenRefresher.RefreshError {
            guard case .invalidResponse = error else {
                Issue.record("Expected invalid response error")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static func credentials() -> VertexAIOAuthCredentials {
        VertexAIOAuthCredentials(
            accessToken: "old-access",
            refreshToken: "refresh+token&extra=value%2B /東京",
            clientId: "client+id&name=value",
            clientSecret: "secret+value&name=secret%2B /東京",
            projectId: "fixture-project",
            email: "fixture@example.test",
            expiryDate: Date(timeIntervalSince1970: 0))
    }

    private static func transport(body: String) -> ProviderHTTPTransportStub {
        ProviderHTTPTransportStub { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data(body.utf8), response)
        }
    }
}
