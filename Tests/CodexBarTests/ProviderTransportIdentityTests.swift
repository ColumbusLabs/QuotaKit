import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct ProviderTransportIdentityTests {
    @Test
    func `provider diagnostics preserve URL error identity and metadata`() {
        let transport = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: [
            NSLocalizedDescriptionKey: "fixture transport failure",
            "fixture-marker": "preserved",
        ])
        let diagnostic = NSError(domain: "FixtureProvider", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Provider request failed: fixture transport failure",
        ])

        let result = ProviderTransportError.preservingIdentity(of: transport, describedBy: diagnostic) as NSError

        #expect(result.domain == NSURLErrorDomain)
        #expect(result.code == NSURLErrorCannotFindHost)
        #expect(result.userInfo["fixture-marker"] as? String == "preserved")
        #expect(result.localizedDescription == "Provider request failed: fixture transport failure")
        #expect(UsageStore.shouldPreservePriorSnapshot(after: result, hadPriorData: true))
        #expect(UsageStore.isStartupConnectivityRetryableError(result))
        #expect(UsageStore.refreshFailureHookStatus(result) == "offline")
    }

    @Test
    func `provider diagnostics keep terminal URL and parse failures outside retention policy`() {
        let badResponse = URLError(.badServerResponse)
        let terminal = ProviderTransportError.preservingIdentity(
            of: badResponse,
            describedBy: OllamaUsageError.networkError(badResponse.localizedDescription))
        let parse = ProviderTransportError.preservingIdentity(
            of: CocoaError(.fileReadCorruptFile),
            describedBy: OllamaUsageError.parseFailed("invalid fixture payload"))

        #expect((terminal as NSError).domain == NSURLErrorDomain)
        #expect((terminal as NSError).code == NSURLErrorBadServerResponse)
        #expect(!UsageStore.shouldPreservePriorSnapshot(after: terminal, hadPriorData: true))
        #expect(!UsageStore.isStartupConnectivityRetryableError(terminal))
        #expect(UsageStore.refreshFailureHookStatus(terminal) == "network_error")
        if let parseError = parse as? OllamaUsageError,
           case let .parseFailed(message) = parseError
        {
            #expect(message == "invalid fixture payload")
        } else {
            Issue.record("Expected the original parse error")
        }
        #expect(!UsageStore.shouldPreservePriorSnapshot(after: parse, hadPriorData: true))
        #expect(!UsageStore.isStartupConnectivityRetryableError(parse))
    }

    @Test
    func `wrapped Vertex cancellation remains cancellation without a startup retry`() {
        let wrapped = VertexAIFetchError.networkError(CancellationError())

        #expect(UsageStore.shouldPreservePriorSnapshot(after: wrapped, hadPriorData: true))
        #expect(!UsageStore.shouldPreservePriorSnapshot(after: wrapped, hadPriorData: false))
        #expect(!UsageStore.isStartupConnectivityRetryableError(wrapped))
        #expect(UsageStore.errorIsCancellation(wrapped))
        #expect(UsageStore.refreshFailureHookStatus(wrapped) == "cancelled")
    }

    @Test
    func `URL cancellation identity survives provider diagnostics and wrapper classification`() {
        let transport = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: [
            NSLocalizedDescriptionKey: "fixture cancelled transport",
        ])
        let diagnostic = OllamaUsageError.networkError("fixture provider diagnostic")
        let preserved = ProviderTransportError.preservingIdentity(of: transport, describedBy: diagnostic)
        let wrapped = VertexAIFetchError.networkError(preserved)

        #expect((preserved as NSError).domain == NSURLErrorDomain)
        #expect((preserved as NSError).code == NSURLErrorCancelled)
        #expect(UsageStore.errorIsCancellation(wrapped))
        #expect(UsageStore.shouldPreservePriorSnapshot(after: wrapped, hadPriorData: true))
        #expect(!UsageStore.isStartupConnectivityRetryableError(wrapped))
        #expect(UsageStore.refreshFailureHookStatus(wrapped) == "cancelled")
    }
}
