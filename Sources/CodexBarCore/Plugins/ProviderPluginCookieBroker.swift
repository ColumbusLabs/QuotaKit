import Foundation

#if os(macOS)
import SweetCookieKit
#endif

/// One origin-bound candidate. Its opaque ID prevents a late rejection from targeting its successor.
public struct ProviderPluginCookieSession: Codable, Equatable, Sendable {
    public let id: String
    public let header: String
    public let source: String
    public let origin: String
    public let cachedAt: TimeInterval?
    let records: [ProviderPluginCookieRecord]?

    public init(
        header: String,
        source: String,
        origin: String,
        id: String = UUID().uuidString,
        cachedAt: TimeInterval? = nil)
    {
        self.init(header: header, source: source, origin: origin, id: id, cachedAt: cachedAt, records: nil)
    }

    init(
        header: String,
        source: String,
        origin: String,
        id: String = UUID().uuidString,
        cachedAt: TimeInterval? = nil,
        records: [ProviderPluginCookieRecord]?)
    {
        self.id = id
        self.header = header
        self.source = source
        self.origin = origin
        self.cachedAt = cachedAt
        self.records = records
    }

    func json(opaque: Bool = false) throws -> String {
        let data: Data = if opaque {
            try JSONSerialization.data(withJSONObject: [
                "id": self.id,
                "source": self.source,
                "origin": self.origin,
            ])
        } else {
            // Preserve the legacy raw-header payload while keeping internal cookie records private.
            try JSONEncoder().encode(LegacyPayload(
                id: self.id,
                header: self.header,
                source: self.source,
                origin: self.origin,
                cachedAt: self.cachedAt))
        }
        guard let json = String(data: data, encoding: .utf8) else {
            throw ProviderPluginError.secretAccess("cookie session encoding failed")
        }
        return json
    }

    private struct LegacyPayload: Encodable {
        let id: String
        let header: String
        let source: String
        let origin: String
        let cachedAt: TimeInterval?
    }
}

final class ProviderPluginCookieBroker: @unchecked Sendable {
    typealias Importer = @Sendable (String) throws -> [(header: String, source: String)]
    typealias BatchImporter = @Sendable (String, Int) throws -> [(header: String, source: String)]?
    typealias JarImporter = @Sendable (String) throws -> [(records: [ProviderPluginCookieRecord], source: String)]

    private struct Issued {
        let session: ProviderPluginCookieSession
        let cacheEntry: CookieHeaderCache.Entry?
        let cacheScope: CookieHeaderCache.Scope?
    }

    private let provider: UsageProvider
    private let domains: Set<String>
    private let settings: ProviderSettingsSnapshot.CookieProviderSettings
    private let importer: BatchImporter
    private let usesCookieJar: Bool
    let cookieJar: ProviderPluginCookieJar
    private let jarImporter: JarImporter?
    private var importedJar: [String: [(records: [ProviderPluginCookieRecord], source: String)]] = [:]
    private var loadedJarImports = Set<String>()
    private var exhaustedJarImports = Set<String>()
    private var seenJar: [String: Set<String>] = [:]
    private var importBatches: [String: Int] = [:]
    private var exhaustedImports = Set<String>()
    private let lock = NSLock()
    private var observed: [String: Issued] = [:]
    private var issuedSessions: [String: Issued] = [:]
    private var visited = Set<String>()
    private var imported: [String: [(header: String, source: String)]] = [:]
    private var seen: [String: Set<String>] = [:]
    private var manualDomain: String?

    convenience init(
        provider: UsageProvider,
        domains: Set<String>,
        context: ProviderFetchContext,
        importer: BatchImporter? = nil,
        usesCookieJar: Bool = false)
    {
        let detection = context.browserDetection
        let canImportJar = context.runtime == .app && ProviderInteractionContext.current == .userInitiated
        let jarImporter: JarImporter? = if usesCookieJar {
            { domain in
                guard canImportJar else { return [] }
                return try Self.importCookieRecords(
                    provider: provider,
                    domain: domain,
                    browserDetection: detection)
            }
        } else {
            nil
        }
        self.init(
            provider: provider,
            domains: domains,
            settings: context.settings.flatMap {
                ProviderDescriptorRegistry.descriptor(for: provider).settingsSection.cookieSettings(from: $0)
            } ?? .init(cookieSource: .auto, manualCookieHeader: nil),
            batches: importer ?? { domain, batch in
                guard batch == 0 else { return nil }
                return try Self.importCookieHeaders(
                    provider: provider, domain: domain, browserDetection: context.browserDetection)
            },
            usesCookieJar: usesCookieJar,
            jarImporter: jarImporter)
    }

    convenience init(
        provider: UsageProvider,
        domains: Set<String>,
        settings: ProviderSettingsSnapshot.CookieProviderSettings,
        importer: @escaping Importer)
    {
        self.init(provider: provider, domains: domains, settings: settings, batches: { domain, batch in
            try batch == 0 ? importer(domain) : nil
        })
    }

    init(
        provider: UsageProvider,
        domains: Set<String>,
        settings: ProviderSettingsSnapshot.CookieProviderSettings,
        batches: @escaping BatchImporter,
        usesCookieJar: Bool = false,
        jarImporter: JarImporter? = nil,
        cookieJar: ProviderPluginCookieJar = ProviderPluginCookieJar())
    {
        self.provider = provider
        self.domains = domains
        self.settings = settings
        self.importer = batches
        self.usesCookieJar = usesCookieJar
        #if os(macOS)
        if let jarImporter {
            let contextualJarImporter: JarImporter =
                BrowserCookieAccessGate.operationPreservingAccessContext(jarImporter)
            self.jarImporter = contextualJarImporter
        } else {
            self.jarImporter = nil
        }
        #else
        self.jarImporter = jarImporter
        #endif
        self.cookieJar = cookieJar
    }

    var cookieSource: ProviderCookieSource {
        self.settings.cookieSource
    }

    func cookieHeader(domain: String) throws -> String {
        try self.lock.withLock {
            try self.validate(domain)
            guard !self.usesCookieJar else {
                throw ProviderPluginError.secretAccess("cookie jars do not expose headers")
            }
            if let issued = self.observed[domain] { return issued.session.header }
            guard let session = try self.advance(domain: domain) else {
                throw ProviderPluginError.secretAccess("no session cookies were found for this domain")
            }
            return session.header
        }
    }

    func nextSession(domain: String, cachedOnly: Bool = false) throws -> ProviderPluginCookieSession? {
        try self.lock.withLock {
            try self.validate(domain)
            return try self.advance(domain: domain, cachedOnly: cachedOnly)
        }
    }

    func rejectCookie(domain: String, id: String? = nil) {
        self.lock.withLock {
            guard self.domains.contains(domain),
                  let issued = id.flatMap({ self.issuedSessions[$0] }) ?? self.observed[domain],
                  id == nil || id == issued.session.id,
                  issued.session.origin == "https://\(domain)" else { return }
            if self.observed[domain]?.session.id == issued.session.id { self.observed[domain] = nil }
            self.issuedSessions[issued.session.id] = nil
            if self.usesCookieJar { self.cookieJar.reject(id: issued.session.id) }
            if let expected = issued.cacheEntry {
                CookieHeaderCache.clearIfCurrent(provider: self.provider, scope: issued.cacheScope, expected: expected)
            }
        }
    }

    private func validate(_ domain: String) throws {
        guard self.domains.contains(domain) else {
            throw ProviderPluginError.secretAccess("cookie domain is not declared")
        }
        guard self.settings.cookieSource != .off else {
            throw ProviderPluginError.secretAccess("browser cookies are disabled for this provider")
        }
    }

    private func advance(domain: String, cachedOnly: Bool = false) throws -> ProviderPluginCookieSession? {
        self.observed[domain] = nil
        if self.settings.cookieSource == .manual {
            // Legacy origin-less headers are pinned to the first selected domain for this fetch.
            let origin = self.settings.manualCookieOrigin ?? self.manualDomain.map { "https://\($0)" }
            guard origin == nil || origin == "https://\(domain)",
                  !self.visited.contains(domain),
                  let header = CookieHeaderNormalizer.normalize(self.settings.manualCookieHeader)
            else { return nil }
            self.manualDomain = domain
            self.visited.insert(domain)
            if self.usesCookieJar {
                let records = Self.manualRecords(header, domain: domain)
                return self.issue(header: "", source: "manual", domain: domain, cacheEntry: nil, records: records)
            }
            return self.issue(header: header, source: "manual", domain: domain, cacheEntry: nil)
        }
        if self.usesCookieJar {
            guard !cachedOnly, let jarImporter, !self.exhaustedJarImports.contains(domain) else { return nil }
            if self.loadedJarImports.insert(domain).inserted {
                let candidates = try jarImporter(domain)
                self.importedJar[domain] = candidates
                if candidates.isEmpty { self.exhaustedJarImports.insert(domain) }
            }
            while self.importedJar[domain]?.isEmpty == false {
                var candidates = self.importedJar[domain] ?? []
                let candidate = candidates.removeFirst()
                self.importedJar[domain] = candidates
                let signature = candidate.records.map {
                    [$0.name, $0.value, $0.domain, $0.path, String($0.hostOnly), String($0.secure)]
                        .joined(separator: "\u{1f}")
                }.sorted().joined(separator: "\u{1e}")
                guard !candidate.records.isEmpty,
                      self.seenJar[domain, default: []].insert(signature).inserted
                else { continue }
                return self.issue(
                    header: "",
                    source: candidate.source,
                    domain: domain,
                    cacheEntry: nil,
                    records: candidate.records)
            }
            self.exhaustedJarImports.insert(domain)
            return nil
        }
        if self.visited.insert(domain).inserted,
           let (cached, scope) = self.cachedEntry(domain: domain),
           let header = CookieHeaderNormalizer.normalize(cached.cookieHeader)
        {
            self.seen[domain, default: []].insert(header)
            return self.issue(
                header: header,
                source: cached.sourceLabel,
                domain: domain,
                cacheEntry: cached,
                cacheScope: scope,
                cachedAt: cached.storedAt.timeIntervalSince1970)
        }
        guard !cachedOnly else { return nil }
        while !self.exhaustedImports.contains(domain) {
            if self.imported[domain]?.isEmpty != false {
                let batch = self.importBatches[domain, default: 0]
                self.importBatches[domain] = batch + 1
                guard let candidates = try self.importer(domain, batch) else {
                    self.exhaustedImports.insert(domain)
                    break
                }
                self.imported[domain] = candidates
                if candidates.isEmpty { continue }
            }
            var candidates = self.imported[domain] ?? []
            let candidate = candidates.removeFirst()
            self.imported[domain] = candidates
            guard let header = CookieHeaderNormalizer.normalize(candidate.header),
                  self.seen[domain, default: []].insert(header).inserted else { continue }
            // Cache dates round to whole seconds. Keep the issued identity even if persistence fails.
            let entry = CookieHeaderCache.Entry(
                cookieHeader: header,
                storedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
                sourceLabel: candidate.source)
            CookieHeaderCache.store(
                provider: self.provider,
                scope: self.scope(domain),
                cookieHeader: header,
                sourceLabel: entry.sourceLabel,
                now: entry.storedAt)
            return self.issue(
                header: header,
                source: candidate.source,
                domain: domain,
                cacheEntry: entry,
                cacheScope: self.scope(domain))
        }
        return nil
    }

    private func issue(
        header: String,
        source: String,
        domain: String,
        cacheEntry: CookieHeaderCache.Entry?,
        cacheScope: CookieHeaderCache.Scope? = nil,
        cachedAt: TimeInterval? = nil,
        records: [ProviderPluginCookieRecord]? = nil)
        -> ProviderPluginCookieSession
    {
        let session = ProviderPluginCookieSession(
            header: header,
            source: source,
            origin: "https://\(domain)",
            cachedAt: cachedAt,
            records: records)
        let issued = Issued(session: session, cacheEntry: cacheEntry, cacheScope: cacheScope)
        self.observed[domain] = issued
        self.issuedSessions[session.id] = issued
        if self.usesCookieJar { self.cookieJar.register(session) }
        return session
    }

    private static func manualRecords(_ header: String, domain: String) -> [ProviderPluginCookieRecord] {
        CookieHeaderNormalizer.pairs(from: header).map { pair in
            ProviderPluginCookieRecord(
                name: pair.name,
                value: pair.value,
                domain: domain,
                hostOnly: true,
                path: "/",
                secure: true,
                expires: nil)
        }
    }

    #if os(macOS)
    private static func importCookieRecords(
        provider: UsageProvider,
        domain: String,
        browserDetection: BrowserDetection) throws
        -> [(records: [ProviderPluginCookieRecord], source: String)]
    {
        let client = BrowserCookieClient()
        let order = ProviderDefaults.metadata[provider]?.browserCookieOrder ?? Browser.defaultImportOrder
        var sessions: [(records: [ProviderPluginCookieRecord], source: String)] = []
        let query = Self.cookieQuery(domain: domain, provider: provider)
        for browser in order.cookieImportCandidates(using: browserDetection) {
            do {
                for source in try client.codexBarRecords(matching: query, in: browser) where !source.records.isEmpty {
                    let records = source.records.map(ProviderPluginCookieRecord.init(record:))
                    sessions.append((records, source.label))
                }
            } catch {
                BrowserCookieAccessGate.recordIfNeeded(error)
            }
        }
        return sessions
    }
    #else
    private static func importCookieRecords(
        provider _: UsageProvider,
        domain _: String,
        browserDetection _: BrowserDetection) throws
        -> [(records: [ProviderPluginCookieRecord], source: String)]
    {
        []
    }
    #endif

    private func cachedEntry(domain: String) -> (CookieHeaderCache.Entry, CookieHeaderCache.Scope?)? {
        let scope = self.scope(domain)
        if let entry = CookieHeaderCache.load(provider: self.provider, scope: scope) { return (entry, scope) }
        // Older regional fetchers recorded their origin in the source suffix of the unscoped cache.
        if scope != nil, let legacy = CookieHeaderCache.load(provider: self.provider),
           legacy.sourceLabel.hasSuffix(" / \(domain)")
        {
            return (legacy, nil)
        }
        return nil
    }

    private func scope(_ domain: String) -> CookieHeaderCache.Scope? {
        self.domains.count == 1 ? nil : .providerVariant(domain)
    }

    static func importCookieHeaders(
        provider: UsageProvider? = nil, domain: String, browserDetection: BrowserDetection) throws
        -> [(header: String, source: String)]
    {
        #if os(macOS)
        let query = Self.cookieQuery(domain: domain, provider: provider)
        let client = BrowserCookieClient()
        let order = provider.map { ProviderDefaults.metadata[$0]?.browserCookieOrder ?? Browser.defaultImportOrder }
            ?? [Browser.chrome]
        var sessions: [(header: String, source: String)] = []
        for browser in order.cookieImportCandidates(using: browserDetection) {
            do {
                let sources = try client.codexBarRecords(matching: query, in: browser)
                for source in sources where !source.records.isEmpty {
                    let cookies = Self.cookiesForRequest(
                        BrowserCookieClient.makeHTTPCookies(source.records, origin: query.origin),
                        domain: domain,
                        provider: provider)
                    let rawHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    if let header = CookieHeaderNormalizer.normalize(rawHeader) {
                        sessions.append((header, source.label))
                    }
                }
            } catch {
                BrowserCookieAccessGate.recordIfNeeded(error)
            }
        }
        return sessions
        #else
        return []
        #endif
    }

    #if os(macOS)
    static func cookieQuery(domain: String, provider: UsageProvider? = nil) -> BrowserCookieQuery {
        BrowserCookieQuery(domains: self.cookieHosts(domain: domain, provider: provider), domainMatch: .exact)
    }

    static func cookiesForRequest(
        _ cookies: [HTTPCookie], domain: String, provider: UsageProvider? = nil) -> [HTTPCookie]
    {
        var chosen: [String: HTTPCookie] = [:]
        var order: [String] = []
        let preferredHost = provider == .helmcode && ["helmcode.com", "nan.builders"].contains(domain)
            ? "cloud.\(domain)" : domain
        for cookie in cookies where Self.matches(cookieDomain: cookie.domain, domain: domain, provider: provider) {
            if let existing = chosen[cookie.name] {
                // A host-specific session must not be shadowed by its parent-domain cookie.
                if Self.normalizedDomain(cookie.domain) == preferredHost,
                   Self.normalizedDomain(existing.domain) != preferredHost
                {
                    chosen[cookie.name] = cookie
                }
            } else {
                chosen[cookie.name] = cookie
                order.append(cookie.name)
            }
        }
        return order.compactMap { chosen[$0] }
    }
    #endif

    private static func normalizedDomain(_ domain: String) -> String {
        domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func cookieHosts(domain: String, provider: UsageProvider?) -> [String] {
        let alternate = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : "www.\(domain)"
        var hosts = [domain, alternate]
        if provider == .helmcode, ["helmcode.com", "nan.builders"].contains(domain) {
            hosts.append("cloud.\(domain)")
        }
        return hosts
    }

    static func matches(cookieDomain: String, domain: String, provider: UsageProvider? = nil) -> Bool {
        let cookieDomain = Self.normalizedDomain(cookieDomain)
        return Self.cookieHosts(domain: domain, provider: provider).contains(cookieDomain)
    }
}

public enum UserProviderPluginCookieBroker {
    public static func resolver(
        browserDetection: BrowserDetection) -> ProviderPluginRuntime.InstanceCookieResolver
    {
        { _, domain in
            guard let session = try ProviderPluginCookieBroker.importCookieHeaders(
                domain: domain, browserDetection: browserDetection).first
            else {
                throw ProviderPluginError.secretAccess("no browser session cookies were found")
            }
            return session.header
        }
    }
}

extension ProviderPluginCookieSession {
    /// Existing injected header resolvers represent one candidate per domain, not a profile iterator.
    static func legacyResolver(
        provider: ProviderInstanceID,
        source: ProviderCookieSource,
        resolver: ProviderPluginRuntime.CookieResolver?,
        instanceResolver: ProviderPluginRuntime.InstanceCookieResolver?) -> ProviderPluginRuntime.CookieSessionResolver?
    {
        guard (provider.firstPartyProvider != nil && resolver != nil) || instanceResolver != nil else { return nil }
        let state = LegacySessionDomains()
        return { domain, cachedOnly in
            guard !cachedOnly else { return nil }
            guard state.take(domain, manual: source == .manual) else { return nil }
            let header: String
            if let firstParty = provider.firstPartyProvider, let resolver {
                header = try await resolver(firstParty, domain)
            } else if let instanceResolver {
                header = try await instanceResolver(provider, domain)
            } else {
                return nil
            }
            return Self(header: header, source: source == .manual ? "manual" : "browser", origin: "https://\(domain)")
        }
    }
}

private final class LegacySessionDomains: @unchecked Sendable {
    private let lock = NSLock()
    private var domains = Set<String>()

    func take(_ domain: String, manual: Bool) -> Bool {
        self.lock.withLock {
            guard !manual || self.domains.isEmpty else { return false }
            return self.domains.insert(domain).inserted
        }
    }
}
