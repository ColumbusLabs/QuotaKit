import AppKit
import CodexBarCore
import Foundation

struct DevPassProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .devpass

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings[providerConfig: .devpass, field: .apiKey]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [ProviderSettingsFieldDescriptor(
            id: "devpass-api-key",
            title: "DevPass API key",
            subtitle: "Saved in QuotaKit's local config file. Or set DEVPASS_API_KEY.",
            kind: .secure,
            placeholder: "Regular LLM Gateway API key",
            binding: context.providerConfigBinding(.apiKey),
            actions: [ProviderSettingsActionDescriptor(
                id: "devpass-dashboard",
                title: "Open DevPass",
                style: .link,
                isVisible: nil,
                perform: {
                    if let url = URL(string: "https://devpass.llmgateway.io/dashboard") {
                        NSWorkspace.shared.open(url)
                    }
                })],
            isVisible: nil,
            onActivate: nil)]
    }
}
