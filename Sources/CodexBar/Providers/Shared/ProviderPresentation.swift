import CodexBarCore
import Foundation

struct ProviderPresentation {
    let showsVersionInSettings: Bool
    let detailLine: @MainActor (ProviderPresentationContext) -> String

    init(
        showsVersionInSettings: Bool = true,
        detailLine: @escaping @MainActor (ProviderPresentationContext) -> String)
    {
        self.showsVersionInSettings = showsVersionInSettings
        self.detailLine = detailLine
    }

    static func showsVersionRow(provider: UsageProvider, presentation: ProviderPresentation) -> Bool {
        provider != .antigravity && presentation.showsVersionInSettings
    }

    @MainActor
    static func standardDetailLine(context: ProviderPresentationContext) -> String {
        let versionText = context.store.version(for: context.provider) ?? "not detected"
        return "\(context.metadata.cliName) \(versionText)"
    }
}
