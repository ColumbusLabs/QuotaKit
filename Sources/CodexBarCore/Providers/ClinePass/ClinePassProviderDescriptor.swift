import Foundation

public enum ClinePassProviderDescriptor {
    public static let descriptor = Self.spec.makeDescriptor()
    public static let spec = PluginProviderSpec(
        id: .clinepass,
        displayName: "ClinePass",
        sessionLabel: "5-hour",
        weeklyLabel: "Weekly",
        opusLabel: "Monthly",
        debugLogUnavailableMessage: "ClinePass debug log not yet implemented",
        dashboardURL: "https://app.cline.bot/dashboard/subscription?personal=true",
        color: .init(red: 0.38, green: 0.64, blue: 0.98),
        confetti: [0x61A3FA, 0x111111, 0xFFFFFF],
        noDataMessage: "ClinePass cost history is not available via the usage-limits API.",
        environmentKey: "CLINE_API_KEY",
        environmentAliases: ["CLINEPASS_API_KEY"],
        presentation: ProviderUsagePresentation(primaryBindingQuotaLanes: [.secondary, .tertiary]),
        apiKeyField: .init(
            id: "clinepass-api-key", title: "API key",
            subtitle: "Stored in ~/.quotakit/config.json. Paste a ClinePass API key.",
            placeholder: "ClinePass API key..."),
        showsAPIDetail: true,
        requiresCredentialForAvailability: true)
}
