import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct FactoryProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .factory
    let supportsLoginFlow: Bool = true

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await context.controller.runFactoryLoginFlow()
        return true
    }
}
