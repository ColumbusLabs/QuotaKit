import CodexBarCore
import Foundation
import Testing

@Suite("Gemini Plan", .serialized)
struct GeminiStatusProbePlanTests {
    @Test
    func selectsProjectIdForQuotaRequests() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: nil)

        let expectedProject = "gen-lang-client-123"
        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                let json = GeminiAPITestHelpers.jsonData([
                    "projects": [
                        ["projectId": expectedProject],
                    ],
                ])
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 200, body: json)
            case "cloudcode-pa.googleapis.com":
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                let bodyText = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                if !bodyText.contains(expectedProject) {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 400, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleFlashQuotaResponse())
            case "www.googleapis.com":
                if url.path != "/drive/v3/about" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 500, body: Data())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.modelQuotas.contains { $0.percentLeft == 40 })
    }

    @Test
    func detectsAIUltraFromDriveQuota() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: nil)

        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.jsonData(["projects": []]))
            case "cloudcode-pa.googleapis.com":
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleQuotaResponse())
            case "www.googleapis.com":
                if url.path != "/drive/v3/about" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                let json = GeminiAPITestHelpers.jsonData(["storageQuota": ["limit": "32985348833280"]])
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 200, body: json)
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.accountPlan == "AI Ultra")
    }

    @Test
    func usesModelFallbackWhenDriveQuotaUnavailable() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: nil)

        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.jsonData(["projects": []]))
            case "cloudcode-pa.googleapis.com":
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleQuotaResponse())
            case "www.googleapis.com":
                if url.path != "/drive/v3/about" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 500, body: Data())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.accountPlan == "AI Pro")
    }

    @Test
    func returnsNilPlanWhenNoProModels() async throws {
        let env = try GeminiTestEnvironment()
        defer { env.cleanup() }
        try env.writeCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3600),
            idToken: nil)

        let dataLoader = GeminiAPITestHelpers.dataLoader { request in
            guard let url = request.url, let host = url.host else {
                throw URLError(.badURL)
            }
            switch host {
            case "cloudresourcemanager.googleapis.com":
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.jsonData(["projects": []]))
            case "cloudcode-pa.googleapis.com":
                if url.path != "/v1internal:retrieveUserQuota" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(
                    url: url.absoluteString,
                    status: 200,
                    body: GeminiAPITestHelpers.sampleFlashQuotaResponse())
            case "www.googleapis.com":
                if url.path != "/drive/v3/about" {
                    return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
                }
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 500, body: Data())
            default:
                return GeminiAPITestHelpers.response(url: url.absoluteString, status: 404, body: Data())
            }
        }

        let probe = GeminiStatusProbe(timeout: 1, homeDirectory: env.homeURL.path, dataLoader: dataLoader)
        let snapshot = try await probe.fetch()
        #expect(snapshot.accountPlan == nil)
    }
}
