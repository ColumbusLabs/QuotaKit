import AppKit
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
        let actions: [ProviderSettingsActionDescriptor] = field.action.flatMap { action in
            guard let url = URL(string: action.url) else { return nil }
            return ProviderSettingsActionDescriptor(
                id: action.id,
                title: action.title,
                style: .link,
                isVisible: nil,
                perform: { NSWorkspace.shared.open(url) })
        }.map { [$0] } ?? []
        return [ProviderSettingsFieldDescriptor(
            id: field.id,
            title: field.title,
            subtitle: field.subtitle,
            kind: .secure,
            placeholder: field.placeholder,
            binding: context.providerConfigBinding(.apiKey),
            actions: actions,
            isVisible: nil,
            onActivate: nil)]
    }
}
