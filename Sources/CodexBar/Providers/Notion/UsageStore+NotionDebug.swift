import CodexBarCore
import Foundation

extension UsageStore {
    static func debugNotionLog(
        browserDetection: BrowserDetection,
        notionCookieSource: ProviderCookieSource,
        notionCookieHeader: String,
        notionWorkspaceID: String,
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) async -> String
    {
        await runWithTimeout(seconds: 15) {
            let fetcher = NotionUsageFetcher(browserDetection: browserDetection)
            let manualHeader = notionCookieSource == .manual
                ? CookieHeaderNormalizer.normalize(notionCookieHeader)
                : nil
            return await fetcher.debugRawProbe(
                cookieHeaderOverride: manualHeader,
                preferredSpaceID: notionWorkspaceID.isEmpty ? nil : notionWorkspaceID,
                transport: transport)
        }
    }
}
