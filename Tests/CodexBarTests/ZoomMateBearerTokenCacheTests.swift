import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ZoomMateBearerTokenCacheTests {
    @Test
    func `bearer generation rejects stale writes and stale invalidation`() async {
        let cache = ZoomMateBearerTokenCache()
        let cookieHeaders = ZoomMateCookieHeaders(headersByHost: [
            "ai.zoom.us": "session=cas",
            "zoommate.zoom.us": "session=cas",
        ])
        let key = ZoomMateBearerTokenCache.key(forCookieHeaders: cookieHeaders)
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let initial = await cache.observeValidEntry(forKey: key, now: now)
        let first = await cache.storeIfUnchanged(
            ZoomMateBearerTokenCache.Entry(token: "bearer-a", accountEmail: nil, expiry: now.addingTimeInterval(600)),
            expected: initial)
        #expect(first != nil)
        guard let first else { return }

        let current = await cache.observeValidEntry(forKey: key, now: now)
        let second = await cache.storeIfUnchanged(
            ZoomMateBearerTokenCache.Entry(token: "bearer-b", accountEmail: nil, expiry: now.addingTimeInterval(900)),
            expected: current)
        #expect(second?.entry?.token == "bearer-b")
        #expect(await !(cache.invalidateIfCurrent(first)))
        #expect(await cache.validEntry(forKey: key, now: now)?.token == "bearer-b")
        #expect(await cache.storeIfUnchanged(
            ZoomMateBearerTokenCache.Entry(token: "stale", accountEmail: nil, expiry: now.addingTimeInterval(1200)),
            expected: initial) == nil)

        let emptyCache = ZoomMateBearerTokenCache()
        let emptyObservation = await emptyCache.observeValidEntry(forKey: key, now: now)
        let laterToken = await emptyCache.storeIfUnchanged(
            ZoomMateBearerTokenCache.Entry(token: "later", accountEmail: nil, expiry: now.addingTimeInterval(1200)),
            expected: emptyObservation)
        #expect(laterToken != nil)
        #expect(await !(emptyCache.invalidateIfCurrent(emptyObservation)))
        #expect(await emptyCache.validEntry(forKey: key, now: now)?.token == "later")

        let uncachedTokenCache = ZoomMateBearerTokenCache()
        let uncachedObservation = await uncachedTokenCache.observeValidEntry(forKey: key, now: now)
        #expect(await uncachedTokenCache.invalidateIfCurrent(uncachedObservation))
    }

    #if os(macOS)
    @Test
    func `cached bootstrap rejection clears its observed cookie and authorizes one retry`() async throws {
        try await Self.withIsolatedCookieCache {
            let cookieHeaders = ZoomMateCookieHeaders(headersByHost: [
                "ai.zoom.us": "session=fixture",
                "zoommate.zoom.us": "session=fixture",
            ])
            let encoded = try #require(cookieHeaders.encodedForStorage())
            let before = CookieHeaderCache.observeForConditionalMutation(provider: .zoommate)
            #expect(CookieHeaderCache.storeIfObservationCurrent(
                provider: .zoommate,
                expected: before,
                cookieHeader: encoded,
                sourceLabel: "Synthetic fixture"))
            let observed = CookieHeaderCache.observeForConditionalMutation(provider: .zoommate)
            let transport = ProviderHTTPTransportHandler { request in
                #expect(request.value(forHTTPHeaderField: "Cookie") == "session=fixture")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil)!
                return (Data(), response)
            }
            let error = await #expect(throws: ZoomMateCachedCookieRejection.self) {
                try await ZoomMateUsageFetcher.cachedCookieRequestContext(
                    cookieHeaders: cookieHeaders,
                    observation: observed,
                    cache: ZoomMateBearerTokenCache(),
                    timeout: 1,
                    transport: transport,
                    logger: nil)
            }
            #expect(error?.mayRetryWithFreshImport == true)
            #expect(CookieHeaderCache.load(provider: .zoommate) == nil)
        }
    }
    #endif

    private static func withIsolatedCookieCache<T>(
        _ operation: () async throws -> T) async rethrows -> T
    {
        try await KeychainCacheStore.withServiceOverrideForTesting("zoommate-bearer-cache-\(UUID().uuidString)") {
            let legacy = FileManager.default.temporaryDirectory
                .appendingPathComponent("zoommate-cookie-legacy-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: legacy) }
            return try await CookieHeaderCache.withLegacyBaseURLOverrideForTesting(legacy) {
                KeychainCacheStore.setTestStoreForTesting(true)
                defer { KeychainCacheStore.setTestStoreForTesting(false) }
                return try await operation()
            }
        }
    }
}
