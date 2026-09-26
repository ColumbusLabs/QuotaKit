import Foundation

#if os(macOS)
import SweetCookieKit

public enum VeniceCookieImporter {
    private static let log = CodexBarLog.logger(LogCategories.provider(.venice, scope: "cookie"))
    private static let cookieClient = BrowserCookieClient()
    private static let cookieDomains = ["venice.ai"]
    private static let cookieImportOrder: BrowserCookieImportOrder =
        ProviderDefaults.metadata[.venice]?.browserCookieOrder ?? [.chrome]

    public static func importSessions(
        browserDetection: BrowserDetection = BrowserDetection(),
        logger: ((String) -> Void)? = nil) throws -> [VeniceResolvedSession]
    {
        var sessions: [VeniceResolvedSession] = []
        let candidates = self.cookieImportOrder.cookieImportCandidates(using: browserDetection)
        for browserSource in candidates {
            do {
                let perSource = try self.importSessions(from: browserSource, logger: logger)
                sessions.append(contentsOf: perSource)
            } catch {
                BrowserCookieAccessGate.recordIfNeeded(error)
                self.emit(
                    "\(browserSource.displayName) cookie import failed: \(error.localizedDescription)",
                    logger: logger)
            }
        }

        guard !sessions.isEmpty else {
            throw VeniceUsageError.missingCredentials
        }
        return sessions
    }

    public static func importSessions(
        from browserSource: Browser,
        logger: ((String) -> Void)? = nil) throws -> [VeniceResolvedSession]
    {
        let query = BrowserCookieQuery(domains: self.cookieDomains, domainMatch: .exact)
        let log: (String) -> Void = { msg in self.emit(msg, logger: logger) }
        let sources = try Self.cookieClient.codexBarRecords(
            matching: query,
            in: browserSource,
            logger: log)

        var sessions: [VeniceResolvedSession] = []
        let grouped = Dictionary(grouping: sources, by: { $0.store.profile.id })
        let sortedGroups = grouped.values.sorted { lhs, rhs in
            self.mergedLabel(for: lhs) < self.mergedLabel(for: rhs)
        }

        for group in sortedGroups where !group.isEmpty {
            let label = self.mergedLabel(for: group)
            let mergedRecords = self.mergeRecords(group)

            let sessionRecords = mergedRecords.filter { VeniceCookieHeader.isSessionCookieName($0.name) }
            guard !sessionRecords.isEmpty else { continue }
            let httpCookies = BrowserCookieClient.makeHTTPCookies(sessionRecords, origin: query.origin)
            let cookieHeaders = VeniceCookieHeader.headers(from: httpCookies)
            guard !cookieHeaders.isEmpty else { continue }
            let names = Set(httpCookies.map(\.name)).sorted().joined(separator: ", ")
            log("Found Venice session cookie (\(names)) in \(label)")
            sessions.append(contentsOf: cookieHeaders.map {
                VeniceResolvedSession(cookieHeader: $0, sourceLabel: label)
            })
        }
        return sessions
    }

    private static func emit(_ message: String, logger: ((String) -> Void)?) {
        logger?("[venice-cookie] \(message)")
        self.log.debug("\(message)")
    }

    private static func mergedLabel(for sources: [BrowserCookieStoreRecords]) -> String {
        guard let base = sources.map(\.label).min() else { return "Unknown" }
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
        case let (lhs?, rhs?): rhs > lhs
        case (nil, .some): true
        case (.some, nil): false
        case (nil, nil): false
        }
    }
}
#endif
