import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct ProviderTransportRegressionFixtures: TestTrait, SuiteTrait, TestScoping {
    static let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("provider-transport-regression-\(UUID().uuidString)", isDirectory: true)

    var isRecursive: Bool {
        true
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void) async throws
    {
        try await function()
    }
}

enum ProviderTransportRegressionSupport {
    static let capturedAt = Date(timeIntervalSince1970: 1_790_000_000)
    static let codes: [URLError.Code] = [
        .timedOut, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet, .cancelled,
    ]

    static func urlError(_ code: URLError.Code = .cannotFindHost) -> URLError {
        URLError(code)
    }

    static func browser(root: URL) -> BrowserDetection {
        BrowserDetection(homeDirectory: root.path, cacheTTL: 0)
    }

    static func captureFailure(_ operation: () async throws -> Void) async -> Error {
        do {
            try await operation()
            Issue.record("Expected transport failure")
            return URLError(.unknown)
        } catch {
            return error
        }
    }

    @MainActor
    static func withStore(
        provider: UsageProvider,
        hasPriorData: Bool,
        operation: @MainActor (UsageStore, Bool) async throws -> Void) async throws
    {
        let settings = testSettingsStore(
            suiteName: "ProviderTransportRegression-\(provider.rawValue)",
            userDefaults: InMemoryUserDefaults())
        settings.setProviderEnabled(
            provider: provider,
            metadata: ProviderDescriptorRegistry.descriptor(for: provider).metadata,
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: browser(root: ProviderTransportRegressionFixtures.root),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        try await operation(store, hasPriorData)
    }
}
