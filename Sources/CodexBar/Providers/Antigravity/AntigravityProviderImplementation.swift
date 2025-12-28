import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct AntigravityProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .antigravity

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await context.controller.runAntigravityLoginFlow()
        return false
    }
}
