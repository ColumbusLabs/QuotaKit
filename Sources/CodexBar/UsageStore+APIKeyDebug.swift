import CodexBarCore
import Foundation

// MARK: - API key debug contexts

// Extracted from the debug-dump extension in UsageStore.swift to keep that
// file under the SwiftLint file_length limit. `private` became internal in
// the move; these remain debug-only helpers for `debugLog(for:)`.

@MainActor
extension UsageStore {
    struct APIKeyDebugContext {
        let label: String
        let resolution: ProviderTokenResolution?
        let configToken: String?
        let hasEnvToken: Bool
        let hasTokenAccount: Bool
    }

    func openAIAPIKeyDebugContext(processEnvironment: [String: String]) -> APIKeyDebugContext {
        let config = self.settings.providerConfig(for: .openai)
        let environment = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: processEnvironment,
            provider: .openai,
            config: config)
        return APIKeyDebugContext(
            label: "OPENAI_API_KEY",
            resolution: ProviderTokenResolver.openAIAPIResolution(environment: environment),
            configToken: config?.sanitizedAPIKey,
            hasEnvToken: OpenAIAPISettingsReader.apiKey(environment: processEnvironment) != nil,
            hasTokenAccount: false)
    }

    func azureOpenAIAPIKeyDebugContext(processEnvironment: [String: String]) -> APIKeyDebugContext {
        let config = self.settings.providerConfig(for: .azureopenai)
        let environment = ProviderConfigEnvironment.applyProviderConfigOverrides(
            base: processEnvironment,
            provider: .azureopenai,
            config: config)
        return APIKeyDebugContext(
            label: "AZURE_OPENAI_API_KEY",
            resolution: ProviderTokenResolver.azureOpenAIResolution(environment: environment),
            configToken: config?.sanitizedAPIKey,
            hasEnvToken: AzureOpenAISettingsReader.apiKey(environment: processEnvironment) != nil,
            hasTokenAccount: false)
    }

    func openRouterAPIKeyDebugContext(processEnvironment: [String: String]) -> APIKeyDebugContext {
        let config = self.settings.providerConfig(for: .openrouter)
        let environment = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: processEnvironment,
            provider: .openrouter,
            config: config)
        return APIKeyDebugContext(
            label: "OPENROUTER_API_KEY",
            resolution: ProviderTokenResolver.openRouterResolution(environment: environment),
            configToken: config?.sanitizedAPIKey,
            hasEnvToken: OpenRouterSettingsReader.apiToken(environment: processEnvironment) != nil,
            hasTokenAccount: false)
    }

    func elevenLabsAPIKeyDebugContext(processEnvironment: [String: String]) -> APIKeyDebugContext {
        let config = self.settings.providerConfig(for: .elevenlabs)
        let environment = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: processEnvironment,
            provider: .elevenlabs,
            config: config)
        return APIKeyDebugContext(
            label: "ELEVENLABS_API_KEY",
            resolution: ProviderTokenResolver.elevenLabsResolution(environment: environment),
            configToken: config?.sanitizedAPIKey,
            hasEnvToken: ElevenLabsSettingsReader.apiKey(environment: processEnvironment) != nil,
            hasTokenAccount: false)
    }
}
