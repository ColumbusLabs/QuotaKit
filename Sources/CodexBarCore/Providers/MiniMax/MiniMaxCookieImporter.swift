import Foundation

#if os(macOS)
import SweetCookieKit

private let minimaxCookieImportOrder: BrowserCookieImportOrder =
    ProviderDefaults.metadata[.minimax]?.browserCookieOrder ?? Browser.defaultImportOrder

public enum MiniMaxCookieImporter {
    private static let log = CodexBarLog.logger(LogCategories.provider(.minimax, scope: "cookie"))
    private static let cookieClient = BrowserCookieClient()
    static var cookieQuery: BrowserCookieQuery {
        BrowserCookieQuery(domains: [
            "platform.minimax.io",
            "openplatform.minimax.io",
            "account.minimax.io",
            "www.minimax.io",
            "minimax.io",
            "platform.minimax.cn",
            "account.minimax.cn",
            "www.minimax.cn",
            "minimax.cn",
            "platform.minimaxi.com",
            "openplatform.minimaxi.com",
            "account.minimaxi.com",
            "www.minimaxi.com",
            "minimaxi.com",
        ], domainMatch: .exact)
    }

    public struct SessionInfo: Sendable {
        public let cookies: [HTTPCookie]
        public let sourceLabel: String
        let scopedRecords: [ProviderPluginCookieRecord]
        let authority: String?
        let scopeDomain: String?
        let hostOnly: Bool?

        public init(cookies: [HTTPCookie], sourceLabel: String) {
            self.cookies = cookies
            self.sourceLabel = sourceLabel
            self.scopedRecords = []
            self.authority = nil
            self.scopeDomain = nil
            self.hostOnly = nil
        }

        init(
            cookies: [HTTPCookie],
            records: [ProviderPluginCookieRecord],
            authority: String,
            scopeDomain: String,
            hostOnly: Bool,
            sourceLabel: String)
        {
            self.cookies = cookies
            self.scopedRecords = records
            self.authority = authority
            self.scopeDomain = scopeDomain
            self.hostOnly = hostOnly
            self.sourceLabel = sourceLabel
        }

        public var cookieHeader: String {
            self.cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
    }

    public static func importSessions(
        browserDetection: BrowserDetection,
        logger: ((String) -> Void)? = nil) throws -> [SessionInfo]
    {
        try Array(self.sessionCandidates(browserDetection: browserDetection, logger: logger))
    }

    static func sessionCandidates(
        browserDetection: BrowserDetection,
        region: MiniMaxAPIRegion? = nil,
        logger: ((String) -> Void)? = nil,
        loadRecords: ((Browser, BrowserCookieQuery, ((String) -> Void)?) throws -> [BrowserCookieStoreRecords])? = nil)
        throws -> AnySequence<SessionInfo>
    {
        try BrowserCookieImportSupport.collectSessions(
            from: minimaxCookieImportOrder.lazyCookieImportCandidates(using: browserDetection),
            missingError: MiniMaxCookieImportError.noCookies,
            logger: { self.emit(
                $0,
                logger: logger) },
            load: { try self.sessions(
                from: $0,
                region: region,
                logger: logger,
                loadRecords: loadRecords) })
    }

    public static func importSessions(
        from browserSource: Browser,
        region: MiniMaxAPIRegion? = nil,
        logger: ((String) -> Void)? = nil) throws -> [SessionInfo]
    {
        try self.sessions(from: browserSource, region: region, logger: logger, loadRecords: nil)
    }

    private static func sessions(
        from browserSource: Browser,
        region: MiniMaxAPIRegion?,
        logger: ((String) -> Void)?,
        loadRecords: ((Browser, BrowserCookieQuery, ((String) -> Void)?) throws -> [BrowserCookieStoreRecords])?)
        throws -> [SessionInfo]
    {
        let query = self.cookieQuery
        let log: (String) -> Void = { msg in self.emit(msg, logger: logger) }
        let sources = try loadRecords?(browserSource, query, log)
            ?? Self.cookieClient.codexBarRecords(matching: query, in: browserSource, logger: log)

        var sessions: [SessionInfo] = []
        let grouped = Dictionary(grouping: sources, by: { $0.store.profile.id })
        let sortedGroups = grouped.values.sorted { lhs, rhs in
            self.mergedLabel(for: lhs) < self.mergedLabel(for: rhs)
        }

        for group in sortedGroups where !group.isEmpty {
            let label = self.mergedLabel(for: group)
            let mergedRecords = self.mergeRecords(group)
            guard !mergedRecords.isEmpty else { continue }
            let records = mergedRecords.map(ProviderPluginCookieRecord.init(record:))
            for scoped in self.scopedGroups(records, region: region) {
                guard let first = scoped.first, let authority = self.authority(for: first.domain) else { continue }
                let originalRecords = mergedRecords.filter {
                    let item = ProviderPluginCookieRecord(record: $0)
                    return item.domain == first.domain && item.hostOnly == first.hostOnly
                }
                let cookies = BrowserCookieClient.makeHTTPCookies(originalRecords, origin: query.origin)
                log("Found \(scoped.count) MiniMax cookies in \(label) for \(first.domain)")
                sessions.append(SessionInfo(
                    cookies: cookies,
                    records: scoped,
                    authority: authority,
                    scopeDomain: first.domain,
                    hostOnly: first.hostOnly,
                    sourceLabel: label))
            }
        }
        return sessions
    }

    public static func importSession(
        browserDetection: BrowserDetection,
        logger: ((String) -> Void)? = nil) throws -> SessionInfo
    {
        let sessions = try self.sessionCandidates(browserDetection: browserDetection, logger: logger)
        guard let first = sessions.first(where: { _ in true }) else {
            throw MiniMaxCookieImportError.noCookies
        }
        return first
    }

    public static func hasSession(browserDetection: BrowserDetection, logger: ((String) -> Void)? = nil) -> Bool {
        do {
            return try self.sessionCandidates(browserDetection: browserDetection, logger: logger)
                .contains(where: { _ in true })
        } catch {
            return false
        }
    }

    static func scopedGroups(
        _ records: [ProviderPluginCookieRecord], region: MiniMaxAPIRegion?) -> [[ProviderPluginCookieRecord]]
    {
        // Parent-domain and host-only accounts can coexist in one browser profile.
        let groups = Dictionary(grouping: records) { "\($0.domain)|\($0.hostOnly ? "host" : "domain")" }
        return groups.keys.sorted().compactMap { key in
            guard let group = groups[key], let first = group.first,
                  let authority = self.authority(for: first.domain),
                  self.isAllowed(authority: authority, region: region) else { return nil }
            return group
        }
    }

    static func authority(for rawDomain: String) -> String? {
        let domain = rawDomain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return ["minimax.io", "minimax.cn", "minimaxi.com"].first {
            domain == $0 || domain.hasSuffix("." + $0)
        }
    }

    static func isAllowed(authority: String, region: MiniMaxAPIRegion?) -> Bool {
        guard let region else { return true }
        return region == .global ? authority == "minimax.io" : ["minimax.cn", "minimaxi.com"].contains(authority)
    }

    private static func cookieNames(from cookies: [HTTPCookie]) -> String {
        let names = Set(cookies.map { "\($0.name)@\($0.domain)" }).sorted()
        return names.joined(separator: ", ")
    }

    private static func emit(_ message: String, logger: ((String) -> Void)?) {
        logger?("[minimax-cookie] \(message)")
        self.log.debug(message)
    }

    private static func mergedLabel(for sources: [BrowserCookieStoreRecords]) -> String {
        guard let base = sources.map(\.label).min() else {
            return "Unknown"
        }
        if base.hasSuffix(" (Network)") {
            return String(base.dropLast(" (Network)".count))
        }
        return base
    }

    private static func mergeRecords(_ sources: [BrowserCookieStoreRecords]) -> [BrowserCookieRecord] {
        let sortedSources = sources.sorted { lhs, rhs in
            self.storePriority(lhs.store.kind) < self.storePriority(rhs.store.kind)
        }
        var mergedByKey: [String: BrowserCookieRecord] = [:]
        for source in sortedSources {
            for record in source.records {
                let key = self.recordKey(record)
                if let existing = mergedByKey[key] {
                    if self.shouldReplace(existing: existing, candidate: record) {
                        mergedByKey[key] = record
                    }
                } else {
                    mergedByKey[key] = record
                }
            }
        }
        return Array(mergedByKey.values)
    }

    private static func storePriority(_ kind: BrowserCookieStoreKind) -> Int {
        switch kind {
        case .network: 0
        case .primary: 1
        case .safari: 2
        }
    }

    private static func recordKey(_ record: BrowserCookieRecord) -> String {
        "\(record.name)|\(record.domain)|\(record.path)"
    }

    private static func shouldReplace(existing: BrowserCookieRecord, candidate: BrowserCookieRecord) -> Bool {
        switch (existing.expires, candidate.expires) {
        case let (lhs?, rhs?):
            rhs > lhs
        case (nil, .some):
            true
        case (.some, nil):
            false
        case (nil, nil):
            false
        }
    }
}

enum MiniMaxCookieImportError: LocalizedError {
    case noCookies

    var errorDescription: String? {
        switch self {
        case .noCookies:
            "No MiniMax session cookies found in browsers."
        }
    }
}
#endif
