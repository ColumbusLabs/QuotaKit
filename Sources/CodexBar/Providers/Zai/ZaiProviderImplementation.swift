import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct ZaiProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .zai

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "zai-api-token",
                title: "API token",
                subtitle: "Stored in Keychain. Paste the token from the z.ai dashboard.",
                kind: .secure,
                placeholder: "Paste token…",
                binding: context.stringBinding(\.zaiAPIToken),
                actions: [],
                isVisible: nil,
                onActivate: { context.settings.ensureZaiAPITokenLoaded() }),
        ]
    }
}
