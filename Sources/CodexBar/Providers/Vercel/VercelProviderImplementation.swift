import AppKit
import CodexBarCore
import Foundation
import SwiftUI

struct VercelProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .vercel
    private let base = PluginAPIKeyProviderImplementation(spec: VercelProviderDescriptor.spec)

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        self.base.observeSettings(settings)
        _ = settings.providerConfig(for: self.id)
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        var fields = self.base.settingsFields(context: context)
        fields.insert(
            ProviderSettingsFieldDescriptor(
                id: "vercel-access-token",
                title: "Vercel access token",
                subtitle: "Optional. Shows your personal budget instead of team credits. "
                    + "Saved in QuotaKit's local config file. Or set VERCEL_ACCESS_TOKEN.",
                kind: .secure,
                placeholder: nil,
                binding: context.providerConfigSecretBinding(key: "VERCEL_ACCESS_TOKEN", logField: "accessToken"),
                actions: [ProviderSettingsActionDescriptor(
                    id: "vercel-open-tokens",
                    title: "Open Vercel tokens",
                    style: .link,
                    isVisible: nil,
                    perform: {
                        if let url = URL(string: "https://vercel.com/account/settings/tokens") {
                            NSWorkspace.shared.open(url)
                        }
                    })],
                isVisible: nil,
                onActivate: nil),
            at: min(1, fields.count))
        return fields
    }
}
