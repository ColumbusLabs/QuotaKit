import Foundation

/// Stored only in the native encrypted cache. Request scope survives across fetches without exposing values to JS.
struct ProviderPluginCachedCookieSession: Codable, Equatable, Sendable {
    let origin: String
    let records: [ProviderPluginCookieRecord]
    var generation: UUID = .init()
}

/// Broker-lock protected validated sessions; importing and script acceptance alone never write credentials.
final class ProviderPluginValidatedCookies {
    private struct DomainState {
        var observation: CookieHeaderCache.ConditionalMutationObservation
        var visitedCache = false
        let blocksBackgroundImport: Bool
    }

    private struct Issued {
        let session: ProviderPluginCookieSession
        var observation: CookieHeaderCache.ConditionalMutationObservation
        var ownsCache: Bool
    }

    private let provider: UsageProvider
    private let policy: ProviderPluginCookiePolicy
    private let background: Bool
    private let accountID: UUID?
    private var states: [String: DomainState] = [:]
    private var issued: [String: Issued] = [:]
    private var accepted: String?
    /// Session cookies have no browser expiry. Bound reuse to 30 days without successful server validation.
    private static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    init(provider: UsageProvider, policy: ProviderPluginCookiePolicy, background: Bool, accountID: UUID?) {
        self.provider = provider
        self.policy = policy
        self.background = background
        self.accountID = accountID
    }

    static func scope(domain: String, accountID: UUID? = nil) -> CookieHeaderCache.Scope {
        .providerVariant("validated-cookie:\(domain):\(accountID?.uuidString.lowercased() ?? "default")")
    }

    func cachedSession(domain: String, now: Date = Date()) -> ProviderPluginCookieSession? {
        if self.states[domain] == nil {
            let observation = CookieHeaderCache.observeForConditionalMutation(
                provider: self.provider, scope: Self.scope(domain: domain, accountID: self.accountID),
                preserveInvalidEntry: self.background)
            let blocksBackgroundImport: Bool = switch observation {
            case let .authoritative(entry, _, _): entry != nil
            case .keychainTemporarilyUnavailable: true
            }
            self.states[domain] = DomainState(
                observation: observation, blocksBackgroundImport: blocksBackgroundImport)
        }
        guard var state = self.states[domain], !state.visitedCache else { return nil }
        state.visitedCache = true
        self.states[domain] = state
        guard let entry = state.observation.entry,
              now.timeIntervalSince(entry.storedAt) >= 0,
              now.timeIntervalSince(entry.storedAt) < Self.maximumAge,
              let payload = entry.pluginCookieSession,
              payload.origin == "https://\(domain)",
              let records = self.selected(payload.records, domain: domain, now: now)
        else { return nil }
        return self.issue(
            records: records, domain: domain, source: entry.sourceLabel,
            cachedAt: entry.storedAt.timeIntervalSince1970, ownsCache: true)
    }

    func mayImport(domain: String) -> Bool {
        !self.background || self.states[domain]?.blocksBackgroundImport == false
    }

    func importedSession(
        records: [ProviderPluginCookieRecord], domain: String, source: String) -> ProviderPluginCookieSession?
    {
        guard let records = self.selected(records, domain: domain, now: Date()) else { return nil }
        return self.issue(records: records, domain: domain, source: source, ownsCache: false)
    }

    func accept(domain: String, id: String) throws {
        guard let issued = self.issued[id], issued.session.origin == "https://\(domain)" else {
            throw ProviderPluginError.secretAccess("validated cookie session is unavailable")
        }
        // A fetch publishes one winning session. Rejecting it later revokes this pending acceptance.
        self.accepted = id
    }

    func commit() throws {
        try Task.checkCancellation()
        guard let id = self.accepted, var issued = self.issued[id], let records = issued.session.records,
              let domain = URL(string: issued.session.origin)?.host,
              let currentRecords = self.selected(records, domain: domain, now: Date())
        else { return }
        let payload = ProviderPluginCachedCookieSession(origin: issued.session.origin, records: currentRecords)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(currentRecords)
        // Generic cache display/header consumers get an opaque fingerprint, never a header assembled without URL scope.
        let fingerprint = CookieHeaderCache.credentialFingerprint(issued.session.origin + String(
            decoding: encoded,
            as: UTF8.self))
        var entry = CookieHeaderCache.Entry(
            cookieHeader: "__quotakit_cookie_session=\(fingerprint)",
            storedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
            sourceLabel: issued.session.source)
        entry.pluginCookieSession = payload
        try Task.checkCancellation()
        let result = CookieHeaderCache.storeIfObservationCurrentReceipt(
            provider: self.provider, scope: Self.scope(domain: domain, accountID: self.accountID),
            expected: issued.observation, entry: entry)
        if let receipt = result.receipt {
            issued.observation = receipt.observation
            issued.ownsCache = true
            self.issued[id] = issued
            self.states[domain]?.observation = receipt.observation
        }
        self.accepted = nil
    }

    func reject(domain: String, id: String) {
        guard let issued = self.issued[id], issued.session.origin == "https://\(domain)" else { return }
        self.issued[id] = nil
        if self.accepted == id { self.accepted = nil }
        // Keep durable account pinning across background polls. Explicit Refresh may evict and replace it.
        guard issued.ownsCache, !self.background else { return }
        if CookieHeaderCache.clearIfObservationCurrent(
            provider: self.provider, scope: Self.scope(domain: domain, accountID: self.accountID),
            expected: issued.observation) == .stored
        {
            self.states[domain]?.observation = issued.observation.afterOwnedClear()
        }
    }

    private func issue(
        records: [ProviderPluginCookieRecord], domain: String, source: String,
        cachedAt: TimeInterval? = nil, ownsCache: Bool) -> ProviderPluginCookieSession
    {
        let session = ProviderPluginCookieSession(
            header: "", source: source, origin: "https://\(domain)", cachedAt: cachedAt, records: records)
        if let state = self.states[domain] {
            self.issued[session.id] = Issued(
                session: session, observation: state.observation, ownsCache: ownsCache)
        }
        return session
    }

    private func selected(
        _ records: [ProviderPluginCookieRecord], domain: String, now: Date) -> [ProviderPluginCookieRecord]?
    {
        let selected = records.filter { record in
            guard let url = URL(string: "https://\(domain)" + record.path) else { return false }
            return record.hasSafeHeaderFields && record.matches(url, now: now)
        }
        return !selected.isEmpty && self.policy.hasRequiredCookies(selected, now: now) ? selected : nil
    }
}
