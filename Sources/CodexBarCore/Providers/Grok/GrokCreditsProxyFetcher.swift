import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches credits from the Grok CLI's billing backend. The grok.com gRPC-web endpoint now requires
/// a browser-held WKE keypair (#2812), so the CLI proxy is the supported bearer-token path.
public enum GrokCreditsProxyFetcher {
    public static let defaultEndpoint = URL(
        string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    private static let requestTimeoutSeconds: TimeInterval = 15

    public static func fetch(
        credentials: GrokCredentials,
        session transport: any ProviderHTTPTransport = ProviderHTTPClient.shared,
        endpoint: URL = Self.defaultEndpoint) async throws -> GrokWebBillingSnapshot
    {
        guard !credentials.isExpired else {
            throw GrokWebBillingError.missingCredentials
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeoutSeconds
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QuotaKit", forHTTPHeaderField: "User-Agent")

        let response: ProviderHTTPResponse
        do {
            response = try await transport.response(for: request)
        } catch let error as URLError where error.code == .badServerResponse {
            throw GrokWebBillingError.invalidResponse
        } catch {
            throw error
        }
        guard response.statusCode == 200 else {
            let body = String(data: response.data.prefix(400), encoding: .utf8) ?? ""
            throw GrokWebBillingError.requestFailed(response.statusCode, body)
        }
        return try Self.parseSnapshot(response.data)
    }

    static func parseSnapshot(_ data: Data, now: Date = .now) throws -> GrokWebBillingSnapshot {
        let response: CreditsResponse
        do {
            response = try JSONDecoder().decode(CreditsResponse.self, from: data)
        } catch {
            throw GrokWebBillingError.parseFailed
        }
        guard let config = response.config else {
            throw GrokWebBillingError.parseFailed
        }

        let subscriptionTier = GrokPlan.displayName(
            from: config.subscriptionTier ?? response.subscriptionTier)
        let currentPeriodEnd = config.currentPeriod?.end.flatMap(Self.parseISO8601)
        let resetsAt = currentPeriodEnd ?? config.billingPeriodEnd.flatMap(Self.parseISO8601)
        // Match the start to the selected end; never combine different billing periods.
        let periodStart = currentPeriodEnd == nil ? config.billingPeriodStart : config.currentPeriod?.start
        let windowMinutes = Self.windowMinutes(start: periodStart, end: resetsAt, now: now)
        let allowsCadenceFallback = config.currentPeriod?.start == nil && config.billingPeriodStart == nil

        if let percent = config.creditUsagePercent, percent.isFinite {
            return GrokWebBillingSnapshot(
                usedPercent: min(100, max(0, percent)),
                resetsAt: resetsAt,
                windowMinutes: windowMinutes,
                allowsCadenceFallback: allowsCadenceFallback,
                subscriptionTier: subscriptionTier)
        }

        if let cap = config.onDemandCap?.val,
           cap > 0,
           let used = config.onDemandUsed?.val
        {
            let percent = min(100, max(0, used / cap * 100))
            return GrokWebBillingSnapshot(
                usedPercent: percent,
                resetsAt: resetsAt,
                windowMinutes: windowMinutes,
                allowsCadenceFallback: allowsCadenceFallback,
                subscriptionTier: subscriptionTier)
        }

        if resetsAt != nil {
            return GrokWebBillingSnapshot(
                usedPercent: 0,
                resetsAt: resetsAt,
                windowMinutes: windowMinutes,
                allowsCadenceFallback: allowsCadenceFallback,
                subscriptionTier: subscriptionTier)
        }

        throw GrokWebBillingError.parseFailed
    }

    private static func windowMinutes(start: String?, end: Date?, now: Date) -> Int? {
        guard let start,
              let startDate = parseISO8601(start),
              let end, end > startDate, startDate <= now,
              let minutes = Int(exactly: (end.timeIntervalSince(startDate) / 60).rounded(.down)),
              minutes > 0
        else { return nil }
        return minutes
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private struct CreditsResponse: Decodable {
        let config: CreditsConfig?
        let subscriptionTier: String?
    }

    private struct CreditsConfig: Decodable {
        let creditUsagePercent: Double?
        let currentPeriod: CurrentPeriod?
        let billingPeriodStart: String?
        let billingPeriodEnd: String?
        let onDemandCap: CreditsAmount?
        let onDemandUsed: CreditsAmount?
        let subscriptionTier: String?
    }

    private struct CurrentPeriod: Decodable {
        let start: String?
        let end: String?
    }

    /// The proxy reports amounts as `{ "val": <number> }`; accept fractional values so an unusual
    /// cap/used shape cannot fail decoding of an otherwise valid response.
    private struct CreditsAmount: Decodable {
        let val: Double?
    }
}
