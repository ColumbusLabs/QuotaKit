import AppKit
import CodexBarCore
import CodexBarMacroSupport
import SwiftUI

@ProviderImplementationRegistration
struct CopilotProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .copilot
    let supportsLoginFlow: Bool = true

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "copilot-api-token",
                title: "GitHub Login",
                subtitle: "Requires authentication via GitHub Device Flow.",
                kind: .secure,
                placeholder: "Sign in via button below",
                binding: context.stringBinding(\.copilotAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "copilot-login",
                        title: "Sign in with GitHub",
                        style: .bordered,
                        isVisible: { context.settings.copilotAPIToken.isEmpty },
                        perform: {
                            await CopilotLoginFlow.run(settings: context.settings)
                        }),
                    ProviderSettingsActionDescriptor(
                        id: "copilot-relogin",
                        title: "Sign in again",
                        style: .link,
                        isVisible: { !context.settings.copilotAPIToken.isEmpty },
                        perform: {
                            await CopilotLoginFlow.run(settings: context.settings)
                        }),
                ],
                isVisible: { !context.settings.debugDisableKeychainAccess },
                onActivate: { context.settings.ensureCopilotAPITokenLoaded() }),
        ]
    }

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await CopilotLoginFlow.run(settings: context.controller.settings)
        return true
    }
}
