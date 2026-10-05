import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ProviderPluginValidatedCookieTests {
    private let domain = "api.example.test"
    private var scope: CookieHeaderCache.Scope {
        ProviderPluginValidatedCookies.scope(domain: self.domain)
    }

    @Test
    func `import and acceptance remain transient until a successful commit`() throws {
        try self.isolated {
            let broker = self.broker()
            let session = try #require(try broker.nextSession(domain: self.domain))
            #expect(CookieHeaderCache.load(provider: .manus, scope: self.scope) == nil)
            try broker.acceptCookie(domain: self.domain, id: session.id)
            #expect(CookieHeaderCache.load(provider: .manus, scope: self.scope) == nil)
            try broker.commitAcceptedCookies()
            let entry = try #require(CookieHeaderCache.load(provider: .manus, scope: self.scope))
            #expect(!entry.cookieHeader.contains("fixture-secret"))
            #expect(entry.pluginCookieSession?.origin == "https://\(self.domain)")
            #expect(entry.pluginCookieSession?.records.map(\.value) == ["fixture-secret"])
            let cached = self.broker(background: true, importer: { _ in
                Issue.record("Validated sessions must survive a background fetch without browser import")
                return []
            })
            let reused = try #require(try cached.nextSession(domain: self.domain, cachedOnly: true))
            #expect(reused.id != session.id)
            #expect(reused.cachedAt != nil)
            #expect(try cached.cookieJar.header(
                id: reused.id, url: #require(URL(string: "https://\(self.domain)/usage"))) == "session=fixture-secret")
        }
    }

    @Test
    func `unaccepted and rejected candidates never replace a durable credential`() throws {
        try self.isolated {
            try self.seed()
            let baseline = CookieHeaderCache.load(provider: .manus, scope: self.scope)
            let broker = self.broker()
            let session = try #require(try broker.nextSession(domain: self.domain))
            try broker.commitAcceptedCookies()
            #expect(CookieHeaderCache.load(provider: .manus, scope: self.scope) == baseline)
            let fresh = self.broker(domain: "fresh.example.test")
            let freshSession = try #require(try fresh.nextSession(domain: "fresh.example.test"))
            try fresh.acceptCookie(domain: "fresh.example.test", id: freshSession.id)
            fresh.rejectCookie(domain: "fresh.example.test", id: freshSession.id)
            try fresh.commitAcceptedCookies()
            #expect(CookieHeaderCache.load(
                provider: .manus,
                scope: ProviderPluginValidatedCookies.scope(domain: "fresh.example.test")) ==
                nil)
            #expect(throws: ProviderPluginError.self) { try broker.acceptCookie(domain: self.domain, id: "forged") }
            #expect(throws: ProviderPluginError.self) {
                try fresh.acceptCookie(domain: "fresh.example.test", id: session.id)
            }
        }
    }

    @Test
    func `late accepted and rejected sessions preserve the winning successor`() throws {
        try self.isolated {
            let stale = self.broker()
            let staleSession = try #require(try stale.nextSession(domain: self.domain))
            let winner = self.broker(importer: { domain in [(Self.records(domain, value: "winner"), "Winner")] })
            let winnerSession = try #require(try winner.nextSession(domain: self.domain))
            try winner.acceptCookie(domain: self.domain, id: winnerSession.id)
            try winner.commitAcceptedCookies()
            let baseline = CookieHeaderCache.load(provider: .manus, scope: self.scope)
            try stale.acceptCookie(domain: self.domain, id: staleSession.id)
            try stale.commitAcceptedCookies()
            stale.rejectCookie(domain: self.domain, id: staleSession.id)
            #expect(CookieHeaderCache.load(provider: .manus, scope: self.scope) == baseline)
            let cached = self.broker()
            let old = try #require(try cached.nextSession(domain: self.domain))
            let replacement = self.broker()
            let replacementSession = try #require(try replacement.nextSession(domain: self.domain))
            try replacement.acceptCookie(domain: self.domain, id: replacementSession.id)
            try replacement.commitAcceptedCookies()
            let newer = CookieHeaderCache.load(provider: .manus, scope: self.scope)
            cached.rejectCookie(domain: self.domain, id: old.id)
            #expect(CookieHeaderCache.load(provider: .manus, scope: self.scope) == newer)
        }
    }

    @Test
    func `background expired rejected and malformed caches never switch browser accounts`() throws {
        try self.isolated {
            try self.seed()
            let broker = self.broker(background: true, importer: { _ in
                Issue.record("Rejected background credentials must require explicit refresh")
                return []
            })
            let cached = try #require(try broker.nextSession(domain: self.domain))
            broker.rejectCookie(domain: self.domain, id: cached.id)
            #expect(try broker.nextSession(domain: self.domain) == nil)
            let nextPoll = self.broker(background: true, importer: { _ in
                Issue.record("A later background poll must not switch after cached rejection")
                return []
            })
            let pinned = try #require(try nextPoll.nextSession(domain: self.domain))
            #expect(pinned.records?.first?.value == "fixture-secret")
            nextPoll.rejectCookie(domain: self.domain, id: pinned.id)
            #expect(try nextPoll.nextSession(domain: self.domain) == nil)
            for payload in [nil, ProviderPluginCachedCookieSession(
                origin: "https://other.example.test", records: Self.records(self.domain))]
            {
                var malformed = CookieHeaderCache.Entry(
                    cookieHeader: "session=legacy",
                    storedAt: Date(),
                    sourceLabel: "Fixture")
                malformed.pluginCookieSession = payload
                let observation = CookieHeaderCache.observeForConditionalMutation(provider: .manus, scope: self.scope)
                _ = CookieHeaderCache.storeIfObservationCurrentReceipt(
                    provider: .manus, scope: self.scope, expected: observation, entry: malformed)
                let invalid = self.broker(background: true, importer: { _ in
                    Issue.record("Originless and mismatched caches must not import in background")
                    return []
                })
                #expect(try invalid.nextSession(domain: self.domain) == nil)
            }
            var expired = CookieHeaderCache.Entry(
                cookieHeader: "session=old", storedAt: Date().addingTimeInterval(-31 * 24 * 60 * 60),
                sourceLabel: "Fixture")
            expired.pluginCookieSession = .init(origin: "https://\(self.domain)", records: Self.records(self.domain))
            let observation = CookieHeaderCache.observeForConditionalMutation(provider: .manus, scope: self.scope)
            _ = CookieHeaderCache.storeIfObservationCurrentReceipt(
                provider: .manus, scope: self.scope, expected: observation, entry: expired)
            let invalid = self.broker(background: true, importer: { _ in
                Issue.record("Session cookies past the cache age must require explicit refresh")
                return []
            })
            #expect(try invalid.nextSession(domain: self.domain) == nil)
        }
    }

    @Test
    func `malformed serialized cache stays pinned until interactive repair`() throws {
        try self.isolated {
            let key = KeychainCacheStore.Key.cookie(
                provider: UsageProvider.manus.instanceID,
                scopeIdentifier: self.scope.isolationIdentifier)
            #expect(KeychainCacheStore.storeResult(key: key, entry: "malformed-fixture"))
            let background = self.broker(background: true, importer: { _ in
                Issue.record("Decode failure must not erase durable background account pinning")
                return []
            })
            #expect(try background.nextSession(domain: self.domain) == nil)
            if case let .found(value) = KeychainCacheStore.load(key: key, as: String.self) {
                #expect(value == "malformed-fixture")
            } else {
                Issue.record("Malformed baseline was removed by a background refresh")
            }
            let interactive = self.broker()
            let repaired = try #require(try interactive.nextSession(domain: self.domain))
            try interactive.acceptCookie(domain: self.domain, id: repaired.id)
            try interactive.commitAcceptedCookies()
            #expect(CookieHeaderCache.load(provider: .manus, scope: self.scope)?.pluginCookieSession != nil)
        }
    }

    @Test
    func `old native header rows decode without granting cookie provenance`() throws {
        let legacy = Data(#"{"cookieHeader":"session=fixture","storedAt":0,"sourceLabel":"Legacy"}"#.utf8)
        let entry = try JSONDecoder().decode(CookieHeaderCache.Entry.self, from: legacy)
        #expect(entry.pluginCookieSession == nil)
        #expect(entry.cookieHeader == "session=fixture")
        try self.isolated {
            CookieHeaderCache.store(provider: .manus, cookieHeader: entry.cookieHeader, sourceLabel: entry.sourceLabel)
            let broker = self.broker(background: true)
            let candidate = try #require(try broker.nextSession(domain: self.domain))
            #expect(candidate.cachedAt == nil)
            #expect(CookieHeaderCache.load(provider: .manus)?.pluginCookieSession == nil)
        }
    }

    @Test
    func `refresh rollback preserves baseline and successful commit replaces one scoped row`() throws {
        try self.isolated {
            try self.seed()
            let baseline = CookieHeaderCache.load(provider: .manus, scope: self.scope)
            let gate = try #require(CookieHeaderCache.beginRefreshReadSuppression(provider: .manus))
            let replacement = self
                .broker(importer: { domain in [(Self.records(domain, value: "replacement"), "Refresh")] })
            let session = try #require(try replacement.nextSession(domain: self.domain))
            try replacement.acceptCookie(domain: self.domain, id: session.id)
            try replacement.commitAcceptedCookies()
            CookieHeaderCache.endRefreshReadSuppression(gate)
            #expect(CookieHeaderCache.load(provider: .manus, scope: self.scope) == baseline)
            let retry = try #require(CookieHeaderCache.beginRefreshReadSuppression(provider: .manus))
            let successful = self
                .broker(importer: { domain in [(Self.records(domain, value: "replacement"), "Refresh")] })
            let successfulSession = try #require(try successful.nextSession(domain: self.domain))
            try successful.acceptCookie(domain: self.domain, id: successfulSession.id)
            try successful.commitAcceptedCookies()
            let summary = CookieHeaderCache.commitRefreshReadSuppression(retry)
            #expect(summary.stagedCount == 1 && summary.committedCount == 1 && summary.failedCount == 0)
            #expect(CookieHeaderCache.load(provider: .manus, scope: self.scope)?.pluginCookieSession?.records.first?
                .value == "replacement")
        }
    }

    @Test
    func `cancelled accepted fetch cannot persist its session`() async throws {
        try await KeychainCacheStore.withImplicitTestStoreForTesting {
            try await KeychainCacheStore.withServiceOverrideForTesting("cancelled-plugin-\(UUID().uuidString)") {
                let task = Task {
                    let broker = self.broker()
                    let session = try #require(try broker.nextSession(domain: self.domain))
                    try broker.acceptCookie(domain: self.domain, id: session.id)
                    withUnsafeCurrentTask { $0?.cancel() }
                    #expect(throws: CancellationError.self) { try broker.commitAcceptedCookies() }
                    #expect(CookieHeaderCache.load(provider: .manus, scope: self.scope) == nil)
                }
                try await task.value
            }
        }
    }

    @Test
    func `interactive mutation gates prevent stale accepted sessions from writing`() throws {
        try self.isolated {
            let broker = self.broker()
            let session = try #require(try broker.nextSession(domain: self.domain))
            let gate = CookieHeaderCache.beginConditionalMutationGate(provider: .manus, scope: self.scope)
            defer { CookieHeaderCache.endConditionalMutationGate(gate) }
            try broker.acceptCookie(domain: self.domain, id: session.id)
            try broker.commitAcceptedCookies()
            #expect(CookieHeaderCache.load(provider: .manus, scope: self.scope) == nil)
        }
    }

    @Test
    func `manual off providers accounts and typed identity stay isolated`() throws {
        try self.isolated {
            try self.seed()
            let baseline = CookieHeaderCache.load(provider: .manus, scope: self.scope)
            for source in [ProviderCookieSource.manual, .off] {
                let broker = self.broker(source: source, importer: { _ in
                    Issue.record("Manual and Off must not import")
                    return []
                })
                if source == .manual {
                    let manual = try #require(try broker.nextSession(domain: self.domain))
                    try broker.acceptCookie(domain: self.domain, id: manual.id)
                    broker.rejectCookie(domain: self.domain, id: manual.id)
                } else {
                    #expect(throws: ProviderPluginError.self) { try broker.nextSession(domain: self.domain) }
                }
                try broker.commitAcceptedCookies()
                #expect(CookieHeaderCache.load(provider: .manus, scope: self.scope) == baseline)
            }
            let accountID = UUID()
            let account = self.broker(accountID: accountID)
            let session = try #require(try account.nextSession(domain: self.domain))
            #expect(session.cachedAt == nil)
            try account.acceptCookie(domain: self.domain, id: session.id)
            try account.commitAcceptedCookies()
            #expect(CookieHeaderCache.load(provider: .manus, scope: self.scope) == baseline)
            #expect(CookieHeaderCache.load(
                provider: .manus,
                scope: ProviderPluginValidatedCookies.scope(domain: self.domain, accountID: accountID)) != nil)
            #expect(CookieHeaderCache.load(provider: .abacus, scope: self.scope) == nil)
            let observation = CookieHeaderCache.observeForConditionalMutation(provider: .manus, scope: self.scope)
            var changed = try #require(baseline)
            changed.pluginCookieSession = .init(
                origin: "https://\(self.domain)",
                records: Self.records(self.domain, value: "changed"))
            #expect(CookieHeaderCache.storeIfObservationCurrentReceipt(
                provider: .manus, scope: self.scope, expected: observation, entry: changed).result == .stored)
            #expect(CookieHeaderCache.clearIfObservationCurrent(
                provider: .manus, scope: self.scope, expected: observation) == .rejected)
        }
    }

    @Test
    func `validated cache retains host path expiry and secure request selection`() throws {
        try self.isolated {
            let broker = self.broker(importer: { domain in [([
                Self.record(domain, value: "root"),
                Self.record(domain, name: "path", value: "path", path: "/billing"),
                Self.record("sibling.example.test", name: "sibling", value: "excluded"),
                Self.record(domain, name: "expired", value: "excluded", expires: Date().addingTimeInterval(-1)),
            ], "Fixture")] })
            let session = try #require(try broker.nextSession(domain: self.domain))
            try broker.acceptCookie(domain: self.domain, id: session.id)
            try broker.commitAcceptedCookies()
            let cached = self.broker(background: true)
            let reused = try #require(try cached.nextSession(domain: self.domain))
            #expect(try cached.cookieJar.header(
                id: reused.id,
                url: #require(URL(string: "https://\(self.domain)/billing/usage"))) ==
                "path=path; session=root")
            #expect(try cached.cookieJar.header(
                id: reused.id,
                url: #require(URL(string: "https://\(self.domain)/billing-other"))) ==
                "session=root")
            for url in ["http://\(self.domain)/billing", "https://sibling.example.test/billing"] {
                #expect(throws: ProviderFetchClassifiedError.self) {
                    try cached.cookieJar.header(id: reused.id, url: #require(URL(string: url)))
                }
            }
        }
    }

    private func broker(
        domain: String? = nil, source: ProviderCookieSource = .auto, background: Bool = false, accountID: UUID? = nil,
        importer: @escaping ProviderPluginCookieBroker.JarImporter = { [(Self.records($0), "Fixture")] })
        -> ProviderPluginCookieBroker
    {
        ProviderPluginCookieBroker(
            provider: .manus, domains: [domain ?? self.domain],
            settings: .init(cookieSource: source, manualCookieHeader: "session=manual"),
            batches: { _, _ in nil }, usesCookieJar: true, jarImporter: importer,
            policy: .init(imports: .accessGated, cache: .validatedSingleEntry, requiredCookies: ["session"]),
            background: background, accountID: accountID)
    }

    private func seed() throws {
        let broker = self.broker()
        let session = try #require(try broker.nextSession(domain: self.domain))
        try broker.acceptCookie(domain: self.domain, id: session.id)
        try broker.commitAcceptedCookies()
    }

    private static func records(_ domain: String, value: String = "fixture-secret") -> [ProviderPluginCookieRecord] {
        [self.record(domain, value: value)]
    }

    private static func record(
        _ domain: String, name: String = "session", value: String, path: String = "/", expires: Date? = nil)
        -> ProviderPluginCookieRecord
    {
        .init(name: name, value: value, domain: domain, hostOnly: true, path: path, secure: true, expires: expires)
    }

    private func isolated(_ body: () throws -> Void) rethrows {
        try KeychainCacheStore.withImplicitTestStoreForTesting {
            try KeychainCacheStore.withServiceOverrideForTesting("validated-plugin-\(UUID().uuidString)") {
                let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: base) }
                try CookieHeaderCache.withLegacyBaseURLOverrideForTesting(base, operation: body)
            }
        }
    }
}
