import Foundation
import SweetCookieKit
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
struct ReplicateCookieStrategyTests {
    @Test
    func `descriptor registers spend-only web billing without a quota`() throws {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .replicate)
        #expect(descriptor.metadata.displayName == "Replicate")
        #expect(descriptor.metadata.dashboardURL == "https://replicate.com/account/billing")
        #expect(!descriptor.metadata.supportsCredits)
        #expect(!descriptor.metadata.supportsOpus)
        #expect(!descriptor.tokenCost.supportsTokenCost)
        #expect(descriptor.fetchPlan.sourceModes == [.auto, .web])
        let tokenSupport = try #require(TokenAccountSupportCatalog.support(for: .replicate))
        #expect(tokenSupport.requiresManualCookieSource)
        #expect(tokenSupport.cookieName == nil)
        #expect(ProviderImplementationRegistry.implementation(for: .replicate) != nil)
    }

    @Test
    func `manual session requires sessionid and never switches to a browser candidate`() async throws {
        let recorder = ReplicateStrategyRecorder()
        let strategy = ReplicateWebFetchStrategy(
            usageLoader: { header in
                recorder.record(header)
                return Self.usage()
            },
            sessionLoader: { _ in
                recorder.browserLoad()
                return [ReplicateResolvedSession(cookieHeader: "sessionid=browser", sourceLabel: "Chrome")]
            })

        let result = try await strategy.fetch(Self.context(source: .manual, header: "sessionid=manual"))

        #expect(result.sourceLabel == "manual")
        #expect(recorder.headers == ["sessionid=manual"])
        #expect(recorder.browserLoads == 0)
    }

    @Test
    func `invalid manual cookie is rejected before transport`() async {
        let recorder = ReplicateStrategyRecorder()
        let strategy = ReplicateWebFetchStrategy(
            usageLoader: { header in
                recorder.record(header)
                return Self.usage()
            },
            sessionLoader: { _ in [] })

        await #expect(throws: ReplicateCredentialError.invalidCookie) {
            _ = try await strategy.fetch(Self.context(source: .manual, header: "csrftoken=missing-session"))
        }
        #expect(recorder.headers.isEmpty)
    }

    @Test
    func `manual authentication failure remains pinned and does not probe browsers`() async {
        let recorder = ReplicateStrategyRecorder()
        let strategy = ReplicateWebFetchStrategy(
            usageLoader: { _ in throw Self.authFailure() },
            sessionLoader: { _ in
                recorder.browserLoad()
                return [ReplicateResolvedSession(cookieHeader: "sessionid=other", sourceLabel: "Chrome")]
            })

        await #expect(throws: ProviderFetchClassifiedError.self) {
            _ = try await strategy.fetch(Self.context(source: .manual, header: "sessionid=selected"))
        }
        #expect(recorder.browserLoads == 0)
    }

    @Test
    func `automatic refresh clears stale cache and retries only authentication failures`() async throws {
        try await Self.withTestCookieStore {
            CookieHeaderCache.store(
                provider: .replicate,
                cookieHeader: "sessionid=stale",
                sourceLabel: "Chrome Default")
            let recorder = ReplicateStrategyRecorder()
            let strategy = ReplicateWebFetchStrategy(
                usageLoader: { header in
                    recorder.record(header)
                    if header == "sessionid=stale" { throw Self.authFailure() }
                    return Self.usage()
                },
                sessionLoader: { _ in
                    recorder.browserLoad()
                    return [ReplicateResolvedSession(cookieHeader: "sessionid=fresh", sourceLabel: "Chrome Profile")]
                })

            let result = try await strategy.fetch(Self.context(source: .auto))

            #expect(result.sourceLabel == "Chrome Profile")
            #expect(recorder.headers == ["sessionid=stale", "sessionid=fresh"])
            #expect(CookieHeaderCache.load(provider: .replicate)?.cookieHeader == "sessionid=fresh")
        }
    }

    @Test
    func `pinned cached session stops after authentication failure`() async throws {
        try await Self.withTestCookieStore {
            #expect(CookieHeaderCache.storeResult(
                provider: .replicate,
                cookieHeader: "sessionid=pinned",
                sourceLabel: "Selected account",
                authenticationFailurePolicy: .stopFallback))
            let recorder = ReplicateStrategyRecorder()
            let strategy = ReplicateWebFetchStrategy(
                usageLoader: { header in
                    recorder.record(header)
                    throw Self.authFailure()
                },
                sessionLoader: { _ in
                    recorder.browserLoad()
                    return [ReplicateResolvedSession(cookieHeader: "sessionid=other", sourceLabel: "Chrome")]
                })

            await #expect(throws: ProviderFetchClassifiedError.self) {
                _ = try await strategy.fetch(Self.context(source: .auto))
            }
            #expect(recorder.headers == ["sessionid=pinned"])
            #expect(recorder.browserLoads == 0)
            #expect(CookieHeaderCache.load(provider: .replicate)?.cookieHeader == "sessionid=pinned")
        }
    }

    @Test
    func `late auth failure cannot clear a newer cache owner or fall back to another account`() async throws {
        try await Self.withTestCookieStore {
            CookieHeaderCache.store(provider: .replicate, cookieHeader: "sessionid=old", sourceLabel: "Chrome")
            let recorder = ReplicateStrategyRecorder()
            let strategy = ReplicateWebFetchStrategy(
                usageLoader: { header in
                    recorder.record(header)
                    if header == "sessionid=old" {
                        CookieHeaderCache.store(
                            provider: .replicate,
                            cookieHeader: "sessionid=concurrent",
                            sourceLabel: "Other refresh")
                        throw Self.authFailure()
                    }
                    return Self.usage()
                },
                sessionLoader: { _ in
                    [ReplicateResolvedSession(cookieHeader: "sessionid=browser", sourceLabel: "Chrome")]
                })

            await #expect(throws: ProviderFetchClassifiedError.self) {
                _ = try await strategy.fetch(Self.context(source: .auto))
            }

            #expect(recorder.headers == ["sessionid=old"])
            #expect(recorder.browserLoads == 0)
            #expect(CookieHeaderCache.load(provider: .replicate)?.cookieHeader == "sessionid=concurrent")
        }
    }

    @Test
    func `new cache owner after stale clear prevents returning fallback account usage`() async throws {
        try await Self.withTestCookieStore {
            CookieHeaderCache.store(provider: .replicate, cookieHeader: "sessionid=old", sourceLabel: "Chrome")
            let recorder = ReplicateStrategyRecorder()
            let strategy = ReplicateWebFetchStrategy(
                usageLoader: { header in
                    recorder.record(header)
                    if header == "sessionid=old" { throw Self.authFailure() }
                    return Self.usage()
                },
                sessionLoader: { _ in
                    CookieHeaderCache.store(
                        provider: .replicate,
                        cookieHeader: "sessionid=concurrent",
                        sourceLabel: "Other refresh")
                    return [ReplicateResolvedSession(cookieHeader: "sessionid=browser", sourceLabel: "Chrome")]
                })

            await #expect(throws: ReplicateCredentialError.cacheChanged) {
                _ = try await strategy.fetch(Self.context(source: .auto))
            }

            #expect(recorder.headers == ["sessionid=old", "sessionid=browser"])
            #expect(CookieHeaderCache.load(provider: .replicate)?.cookieHeader == "sessionid=concurrent")
        }
    }

    @Test
    func `cancelled manual fetch propagates cancellation without loading browser cookies`() async {
        let recorder = ReplicateStrategyRecorder()
        let strategy = ReplicateWebFetchStrategy(
            usageLoader: { _ in
                try await Task.sleep(for: .seconds(10))
                return Self.usage()
            },
            sessionLoader: { _ in
                recorder.browserLoad()
                return []
            })
        let task = Task { try await strategy.fetch(Self.context(source: .manual, header: "sessionid=manual")) }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            #expect(recorder.browserLoads == 0)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `browser import defaults to Chrome and filters sessions without sessionid`() throws {
        #expect(ReplicateCookieImporter.resolvedImportOrder(nil) == [.chrome])
        #expect(ReplicateCookieImporter.resolvedImportOrder([]) == [.chrome])
        #expect(ReplicateCookieImporter.resolvedImportOrder([.firefox, .chrome]) == [.firefox, .chrome])
        let session = try #require(HTTPCookie(properties: [
            .domain: "replicate.com",
            .path: "/",
            .name: "sessionid",
            .value: "fixture",
        ]))
        let csrf = try #require(HTTPCookie(properties: [
            .domain: "replicate.com",
            .path: "/",
            .name: "csrftoken",
            .value: "fixture",
        ]))
        #expect(ReplicateCookieImporter.hasSessionCookie([session]))
        #expect(!ReplicateCookieImporter.hasSessionCookie([csrf]))
        #expect(ReplicateCookieImporter.cookieQuery().domains == ["replicate.com"])
        #expect(ReplicateCookieImporter.cookieQuery().includeExpired == false)
    }

    private static func withTestCookieStore<T>(operation: () async throws -> T) async throws -> T {
        let service = "com.columbuslabs.quotakit.tests.replicate.\(UUID().uuidString)"
        return try await KeychainCacheStore.withServiceOverrideForTesting(service) {
            try await KeychainCacheStore.withImplicitTestStoreForTesting(operation: operation)
        }
    }

    private static func context(source: ProviderCookieSource, header: String? = nil) -> ProviderFetchContext {
        let detection = BrowserDetection(cacheTTL: 0)
        let environment: [String: String] = [:]
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: .web,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: .make(replicate: ReplicateProviderSettings(cookieSource: source, manualCookieHeader: header)),
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: ReplicateUnusedClaudeFetcher(),
            browserDetection: detection)
    }

    private static func usage() -> UsageSnapshot {
        UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date())
    }

    private static func authFailure() -> ProviderFetchClassifiedError {
        ProviderFetchClassifiedError(kind: .authenticationExpired, message: "fixture auth failure")
    }
}

private final class ReplicateStrategyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedHeaders: [String] = []
    private var storedBrowserLoads = 0

    var headers: [String] {
        self.lock.withLock { self.storedHeaders }
    }

    var browserLoads: Int {
        self.lock.withLock { self.storedBrowserLoads }
    }

    func record(_ header: String) {
        self.lock.withLock { self.storedHeaders.append(header) }
    }

    func browserLoad() {
        self.lock.withLock { self.storedBrowserLoads += 1 }
    }
}

private struct ReplicateUnusedClaudeFetcher: ClaudeUsageFetching {
    func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
        throw CancellationError()
    }

    func debugRawProbe(model _: String) async -> String {
        "unused"
    }

    func detectVersion() -> String? {
        nil
    }
}
