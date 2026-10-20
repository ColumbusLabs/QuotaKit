import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Additional spend on unified Cursor/Grok accounts. The legacy summary can report a false zero.
public struct CursorUnifiedUsageStatus: Decodable, Sendable {
    static let endpointPath = "/api/dashboard/v2/usage-status"

    public struct MonthlyUsage: Decodable, Sendable {
        public let usedCents: Double
        public let limitCents: Double
        public let periodStart: String
        public let resetsAt: String
    }

    public let availability: String
    public let monthlyUsage: MonthlyUsage?

    static func fetch(
        urlSession: any ProviderHTTPTransport,
        baseURL: URL,
        cookieHeader: String,
        timeout: TimeInterval) async throws -> Self
    {
        let url = baseURL.appendingPathComponent(Self.endpointPath)
            .appending(queryItems: [URLQueryItem(name: "scope", value: "user")])
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CursorStatusProbeError.networkError("Unified additional spend is unavailable")
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    func currentMonthlyUsage(at now: Date) -> MonthlyUsage? {
        guard self.availability == "available",
              let usage = self.monthlyUsage,
              usage.usedCents.isFinite, usage.usedCents >= 0,
              usage.limitCents.isFinite, usage.limitCents >= 0,
              let start = ISO8601DateParser.parse(usage.periodStart),
              let reset = ISO8601DateParser.parse(usage.resetsAt),
              start <= now, now < reset
        else { return nil }
        return usage
    }
}

extension CursorUsageSummary {
    var usesUnifiedPersonalBilling: Bool {
        self.membershipType?.lowercased().hasPrefix("unified_") == true
            && self.limitType?.lowercased() == "user"
    }
}
