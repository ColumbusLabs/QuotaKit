import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct KiloProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .kilo

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.kiloAPIToken
    }

    @MainActor
    func isAvailable(context _: ProviderAvailabilityContext) -> Bool {
        // Keep availability permissive to avoid main-thread auth-file I/O while still showing Kilo for auth.json-only
        // setups. Fetch-time auth resolution remains authoritative (env first, then auth file fallback).
        true
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "kilo-api-key",
                title: "API key",
                subtitle: "Stored in ~/.codexbar/config.json. You can also provide KILO_API_KEY or "
                    + "~/.local/share/kilo/auth.json (kilo.access).",
                kind: .secure,
                placeholder: "kilo_...",
                binding: context.stringBinding(\.kiloAPIToken),
                actions: [],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
