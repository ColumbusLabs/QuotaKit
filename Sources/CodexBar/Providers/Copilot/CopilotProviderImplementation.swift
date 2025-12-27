import AppKit
import CodexBarCore
import SwiftUI

struct CopilotProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .copilot
    let style: IconStyle = .copilot

    func makeFetch(context: ProviderBuildContext) -> @Sendable () async throws -> UsageSnapshot {
        let settings = context.settings
        return {
            let token = await settings.copilotAPIToken
            guard !token.isEmpty else {
                throw URLError(.userAuthenticationRequired)
            }
            return try await CopilotUsageFetcher(token: token).fetch()
        }
    }

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
                isVisible: nil),
        ]
    }
}
