import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct MiniMaxProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .minimax

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "minimax-cookie",
                title: "Session cookie",
                subtitle: [
                    "Automatically imports browser cookies when available.",
                    "Stored in Keychain; paste a Cookie header or Copy as cURL from platform.minimax.io if needed.",
                ].joined(separator: " "),
                kind: .secure,
                placeholder: "Paste Cookie header or cURL…",
                binding: context.stringBinding(\.minimaxCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "minimax-open-dashboard",
                        title: "Open Coding Plan",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(
                                string: "https://platform.minimax.io/user-center/payment/coding-plan?cycle_type=3")
                            {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: { context.settings.ensureMiniMaxCookieLoaded() }),
        ]
    }
}
