import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct OpenRouterProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .openrouter

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "api" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.openRouterAPIToken
        _ = settings.openRouterAPIURL
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        if OpenRouterSettingsReader.apiToken(environment: context.environment) != nil {
            return true
        }
        return !context.settings.openRouterAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    func settingsPickers(context _: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        []
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "openrouter-api-key",
                title: "API key",
                subtitle: "Stored in ~/.quotakit/config.json. "
                    + "Get your key from openrouter.ai/settings/keys and set a key spending limit "
                    + "there to enable API key quota tracking.",
                kind: .secure,
                placeholder: "sk-or-v1-...",
                binding: context.stringBinding(\.openRouterAPIToken),
                actions: [],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "openrouter-api-url",
                title: "API URL",
                subtitle: "Optional. Defaults to the hosted OpenRouter API.",
                kind: .plain,
                placeholder: "https://openrouter.ai/api/v1",
                binding: context.stringBinding(\.openRouterAPIURL),
                actions: [],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
