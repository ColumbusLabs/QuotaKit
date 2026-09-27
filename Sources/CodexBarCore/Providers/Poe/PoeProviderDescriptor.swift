import Foundation

public enum PoeProviderDescriptor {
    public static let descriptor = Self.spec.makeDescriptor()
    public static let spec = PluginProviderSpec(
        id: .poe,
        displayName: "Poe",
        sessionLabel: "Points",
        weeklyLabel: "Points",
        balanceOnly: true,
        dashboardURL: "https://poe.com/api/keys",
        color: .init(red: 93 / 255, green: 92 / 255, blue: 222 / 255),
        confetti: [0x5D5CDE, 0x2A2AA2, 0xE051ED],
        noDataMessage: "Poe usage history is unavailable.",
        environmentKey: "POE_API_KEY",
        presentation: ProviderUsagePresentation(
            menuCard: ProviderMenuCardPresentation(primaryDetailKind: .poeBalance),
            planRow: ProviderPlanRowPresentation(label: "Balance", stripsBalancePrefix: true)),
        apiKeyField: .init(
            id: "poe-api-key",
            title: "API key",
            subtitle: "Stored in ~/.quotakit/config.json. Get your key from poe.com/api/keys.",
            placeholder: nil),
        showsAPIDetail: true,
        requiresCredentialForAvailability: true)
}

struct PoeAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "poe.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveToken(environment: context.env) else {
            throw PoeUsageError.missingCredentials
        }
        let usage = try await PoeUsageFetcher.fetchUsage(apiKey: apiKey)
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        ProviderTokenResolver.token(for: .poe, environment: environment)
    }
}
