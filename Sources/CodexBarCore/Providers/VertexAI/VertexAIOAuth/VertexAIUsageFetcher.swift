import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum VertexAIFetchError: LocalizedError, Sendable {
    case unauthorized
    case forbidden
    case noProject
    case networkError(Error)
    case invalidResponse(String)
    case noData

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Vertex AI request unauthorized. Run `gcloud auth application-default login`."
        case .forbidden:
            "Access forbidden. Check your IAM permissions for Cloud Monitoring."
        case .noProject:
            "No Google Cloud project configured. Run `gcloud config set project PROJECT_ID`."
        case let .networkError(error):
            "Vertex AI network error: \(error.localizedDescription)"
        case let .invalidResponse(message):
            "Vertex AI response was invalid: \(message)"
        case .noData:
            "No Vertex AI usage data found for the current project."
        }
    }
}

public struct VertexAIUsageResponse: Sendable {
    public let requestsUsedPercent: Double
    public let tokensUsedPercent: Double?
    public let resetsAt: Date?
    public let resetDescription: String?
    public let rawData: String?

    public init(
        requestsUsedPercent: Double,
        tokensUsedPercent: Double?,
        resetsAt: Date?,
        resetDescription: String?,
        rawData: String?)
    {
        self.requestsUsedPercent = requestsUsedPercent
        self.tokensUsedPercent = tokensUsedPercent
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
        self.rawData = rawData
    }
}

public enum VertexAIUsageFetcher {
    private static let log = CodexBarLog.logger("vertexai-fetcher")

    // Cloud Monitoring API endpoint for time series
    private static let monitoringEndpoint = "https://monitoring.googleapis.com/v3/projects"

    // Service Usage API for quota info
    private static let serviceUsageEndpoint = "https://serviceusage.googleapis.com/v1beta1"

    public static func fetchUsage(
        accessToken: String,
        projectId: String?) async throws -> VertexAIUsageResponse
    {
        guard let projectId, !projectId.isEmpty else {
            throw VertexAIFetchError.noProject
        }

        // Try to get quota limits and usage from Service Usage API
        let quotaUsage = try await Self.fetchQuotaUsage(
            accessToken: accessToken,
            projectId: projectId)

        return quotaUsage
    }

    private static func fetchQuotaUsage(
        accessToken: String,
        projectId: String) async throws -> VertexAIUsageResponse
    {
        // Use Service Usage API to get consumer quota metrics
        // Endpoint: GET /v1beta1/projects/{project}/services/aiplatform.googleapis.com/consumerQuotaMetrics
        let urlString = "\(serviceUsageEndpoint)/projects/\(projectId)/services/aiplatform.googleapis.com/consumerQuotaMetrics"

        guard let url = URL(string: urlString) else {
            throw VertexAIFetchError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw VertexAIFetchError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw VertexAIFetchError.invalidResponse("No HTTP response")
        }

        Self.log.debug("Quota API response", metadata: [
            "statusCode": "\(http.statusCode)",
        ])

        switch http.statusCode {
        case 401:
            throw VertexAIFetchError.unauthorized
        case 403:
            throw VertexAIFetchError.forbidden
        case 200:
            break
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw VertexAIFetchError.invalidResponse("HTTP \(http.statusCode): \(body)")
        }

        return try Self.parseQuotaResponse(data)
    }

    private static func parseQuotaResponse(_ data: Data) throws -> VertexAIUsageResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VertexAIFetchError.invalidResponse("Invalid JSON")
        }

        guard let metrics = json["metrics"] as? [[String: Any]], !metrics.isEmpty else {
            // No metrics means the API is not enabled or no usage yet
            Self.log.info("No quota metrics found")
            return VertexAIUsageResponse(
                requestsUsedPercent: 0,
                tokensUsedPercent: nil,
                resetsAt: nil,
                resetDescription: nil,
                rawData: String(data: data, encoding: .utf8))
        }

        var totalLimit: Double = 0
        var totalUsage: Double = 0

        // Look for relevant Vertex AI quotas
        for metric in metrics {
            guard let consumerQuotaLimits = metric["consumerQuotaLimits"] as? [[String: Any]] else {
                continue
            }

            for limit in consumerQuotaLimits {
                guard let quotaBuckets = limit["quotaBuckets"] as? [[String: Any]] else {
                    continue
                }

                for bucket in quotaBuckets {
                    if let effectiveLimit = bucket["effectiveLimit"] as? String,
                       let limitValue = Double(effectiveLimit),
                       limitValue > 0
                    {
                        totalLimit += limitValue

                        // Get producer quota override or default usage
                        if let producerOverride = bucket["producerOverride"] as? [String: Any],
                           let overrideValue = producerOverride["overrideValue"] as? String,
                           let usage = Double(overrideValue)
                        {
                            totalUsage += usage
                        }
                    }
                }
            }
        }

        let usedPercent: Double
        if totalLimit > 0 {
            usedPercent = (totalUsage / totalLimit) * 100.0
        } else {
            usedPercent = 0
        }

        Self.log.info("Parsed quota", metadata: [
            "usedPercent": "\(usedPercent)",
            "totalLimit": "\(totalLimit)",
            "totalUsage": "\(totalUsage)",
        ])

        return VertexAIUsageResponse(
            requestsUsedPercent: usedPercent,
            tokensUsedPercent: nil,
            resetsAt: nil,
            resetDescription: "Quota resets daily",
            rawData: String(data: data, encoding: .utf8))
    }
}
