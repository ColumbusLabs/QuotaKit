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
                title: "Session",
                subtitle: [
                    "Automatically imports browser cookies and local-storage tokens when available.",
                    "Stored in Keychain; leave blank for automatic.",
                ].joined(separator: " "),
                kind: .secure,
                placeholder: "Automatic (leave blank)",
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
