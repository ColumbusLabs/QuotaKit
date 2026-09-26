import CodexBarCore
import Foundation

struct PluginAPIKeyProviderImplementation: ProviderImplementation {
    let spec: PluginProviderSpec
    var id: UsageProvider {
        self.spec.id
    }

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            self.spec.showsAPIDetail ? "api" : ProviderPresentation.standardDetailLine(context: context)
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings[providerConfig: self.id, field: .apiKey]
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        !self.spec.requiresCredentialForAvailability || self.spec.apiKey(environment: context.environment) != nil ||
            !context.settings[providerConfig: self.id, field: .apiKey]
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        guard let field = self.spec.apiKeyField else { return [] }
        return [ProviderSettingsFieldDescriptor(
            id: field.id, title: field.title, subtitle: field.subtitle,
            kind: .secure, placeholder: field.placeholder,
            binding: context.providerConfigBinding(.apiKey),
            actions: field.action.map { [.openURL(id: $0.id, title: $0.title, url: URL(string: $0.url))] } ?? [],
            isVisible: nil)]
    }
}
