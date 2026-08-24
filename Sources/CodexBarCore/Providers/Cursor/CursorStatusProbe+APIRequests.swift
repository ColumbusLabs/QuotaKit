import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if os(macOS) || os(Linux)
extension CursorStatusProbe {
    func fetchSandUsage(
        cookieHeader: String,
        deadline: Date?) async throws -> (CursorSandUsageStatus, String)
    {
        let url = self.baseURL.appendingPathComponent(CursorSandUsageStatus.endpointPath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        guard let sandTimeout = self.optionalRequestTimeout(deadline: deadline, budget: Self.sandUsageTimeout) else {
            throw CursorStatusProbeError.networkError("Sand usage skipped after login deadline")
        }
        request.timeoutInterval = sandTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(self.originHeader, forHTTPHeaderField: "Origin")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await self.urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorStatusProbeError.networkError("Invalid response")
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw CursorStatusProbeError.notLoggedIn
        }
        guard httpResponse.statusCode == 200 else {
            throw CursorStatusProbeError.networkError("HTTP \(httpResponse.statusCode)")
        }

        let rawJSON = String(data: data, encoding: .utf8) ?? "<binary>"
        do {
            let status = try JSONDecoder().decode(CursorSandUsageStatus.self, from: data)
            return (status, rawJSON)
        } catch {
            throw CursorStatusProbeError
                .parseFailed("Sand usage decode failed: \(error.localizedDescription). Raw: \(rawJSON.prefix(200))")
        }
    }

    func fetchUserInfo(cookieHeader: String, deadline: Date?) async throws -> CursorUserInfo {
        let url = self.baseURL.appendingPathComponent("/api/auth/me")
        var request = URLRequest(url: url)
        request.timeoutInterval = try self.requestTimeout(deadline: deadline)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await self.urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CursorStatusProbeError.networkError("Failed to fetch user info")
        }
        return try JSONDecoder().decode(CursorUserInfo.self, from: data)
    }

    func fetchRequestUsage(
        userId: String,
        cookieHeader: String,
        deadline: Date?) async throws -> (CursorUsageResponse, String)
    {
        let url = self.baseURL.appendingPathComponent("/api/usage")
            .appending(queryItems: [URLQueryItem(name: "user", value: userId)])
        var request = URLRequest(url: url)
        request.timeoutInterval = try self.requestTimeout(deadline: deadline)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await self.urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CursorStatusProbeError.networkError("Failed to fetch request usage")
        }
        let rawJSON = String(data: data, encoding: .utf8) ?? "<binary>"
        let usage = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
        return (usage, rawJSON)
    }

    private var originHeader: String {
        guard let scheme = self.baseURL.scheme, let host = self.baseURL.host else { return "https://cursor.com" }
        return "\(scheme)://\(host)"
    }

    private static let sandUsageTimeout: TimeInterval = 5
}
#endif
