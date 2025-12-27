import Foundation

public enum BrowserCookieSource: String, Sendable {
    case safari
    case chrome
    case firefox

    public var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        }
    }
}

public enum BrowserCookieImportOrder: Sendable {
    case safariChromeFirefox

    public var sources: [BrowserCookieSource] {
        switch self {
        case .safariChromeFirefox:
            [.safari, .chrome, .firefox]
        }
    }

    public var displayLabel: String {
        switch self {
        case .safariChromeFirefox:
            "Safari → Chrome → Firefox"
        }
    }

    public var shortLabel: String {
        switch self {
        case .safariChromeFirefox:
            "Safari/Chrome/Firefox"
        }
    }

    public var loginHint: String {
        switch self {
        case .safariChromeFirefox:
            "Safari, Chrome, or Firefox"
        }
    }
}

#if os(macOS)

public enum BrowserCookieOriginStrategy {
    case domainBased
    case fixed(URL)
    case custom(@Sendable (String) -> URL?)

    func resolve(domain: String) -> URL? {
        switch self {
        case .domainBased:
            URL(string: "https://\(domain)")
        case let .fixed(url):
            url
        case let .custom(resolver):
            resolver(domain)
        }
    }
}

public struct BrowserCookieRecord: Sendable {
    public let domain: String
    public let name: String
    public let path: String
    public let value: String
    public let expires: Date?
    public let isSecure: Bool
    public let isHTTPOnly: Bool
}

public struct BrowserCookieSourceRecords: Sendable {
    public let source: BrowserCookieSource
    public let label: String
    public let records: [BrowserCookieRecord]
}

public enum BrowserCookieImporter {
    public enum ImportError: LocalizedError {
        case notFound(source: BrowserCookieSource, details: String)
        case accessDenied(source: BrowserCookieSource, details: String)
        case loadFailed(source: BrowserCookieSource, details: String)

        public var errorDescription: String? {
            switch self {
            case let .notFound(_, details), let .accessDenied(_, details), let .loadFailed(_, details):
                details
            }
        }

        public var source: BrowserCookieSource {
            switch self {
            case let .notFound(source, _), let .accessDenied(source, _), let .loadFailed(source, _):
                source
            }
        }

        public var accessDeniedHint: String? {
            switch self {
            case let .accessDenied(_, details):
                details
            case .notFound, .loadFailed:
                nil
            }
        }
    }

    public static func loadCookieSources(
        from source: BrowserCookieSource,
        matchingDomains domains: [String],
        logger: ((String) -> Void)? = nil) throws -> [BrowserCookieSourceRecords]
    {
        switch source {
        case .safari:
            do {
                let records = try SafariCookieImporter.loadCookies(matchingDomains: domains, logger: logger)
                guard !records.isEmpty else { return [] }
                return [BrowserCookieSourceRecords(
                    source: .safari,
                    label: source.displayName,
                    records: records.map { BrowserCookieRecord(
                        domain: Self.normalizeDomain($0.domain),
                        name: $0.name,
                        path: $0.path,
                        value: $0.value,
                        expires: $0.expires,
                        isSecure: $0.isSecure,
                        isHTTPOnly: $0.isHTTPOnly)
                    })]
            } catch let error as SafariCookieImporter.ImportError {
                throw Self.mapSafariError(error)
            } catch {
                throw ImportError.loadFailed(
                    source: .safari,
                    details: "Safari cookie load failed: \(error.localizedDescription)")
            }
        case .chrome:
            do {
                let sources = try ChromeCookieImporter.loadCookiesFromAllProfiles(matchingDomains: domains)
                return sources.compactMap { source in
                    guard !source.records.isEmpty else { return nil }
                    let mapped = source.records.map { record in
                        BrowserCookieRecord(
                            domain: Self.normalizeDomain(record.hostKey),
                            name: record.name,
                            path: record.path,
                            value: record.value,
                            expires: Self.chromeExpiryDate(expiresUTC: record.expiresUTC),
                            isSecure: record.isSecure,
                            isHTTPOnly: record.isHTTPOnly)
                    }
                    return BrowserCookieSourceRecords(source: .chrome, label: source.label, records: mapped)
                }
            } catch let error as ChromeCookieImporter.ImportError {
                throw Self.mapChromeError(error)
            } catch {
                throw ImportError.loadFailed(
                    source: .chrome,
                    details: "Chrome cookie load failed: \(error.localizedDescription)")
            }
        case .firefox:
            do {
                let sources = try FirefoxCookieImporter.loadCookiesFromAllProfiles(matchingDomains: domains)
                return sources.compactMap { source in
                    guard !source.records.isEmpty else { return nil }
                    let mapped = source.records.map { record in
                        BrowserCookieRecord(
                            domain: Self.normalizeDomain(record.host),
                            name: record.name,
                            path: record.path,
                            value: record.value,
                            expires: record.expires,
                            isSecure: record.isSecure,
                            isHTTPOnly: record.isHTTPOnly)
                    }
                    return BrowserCookieSourceRecords(source: .firefox, label: source.label, records: mapped)
                }
            } catch let error as FirefoxCookieImporter.ImportError {
                throw Self.mapFirefoxError(error)
            } catch {
                throw ImportError.loadFailed(
                    source: .firefox,
                    details: "Firefox cookie load failed: \(error.localizedDescription)")
            }
        }
    }

    public static func makeHTTPCookies(
        _ records: [BrowserCookieRecord],
        origin: BrowserCookieOriginStrategy = .domainBased) -> [HTTPCookie]
    {
        records.compactMap { record in
            let domain = Self.normalizeDomain(record.domain)
            guard !domain.isEmpty else { return nil }
            var props: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: record.path,
                .name: record.name,
                .value: record.value,
                .secure: record.isSecure,
            ]
            if let originURL = origin.resolve(domain: domain) {
                props[.originURL] = originURL
            }
            if record.isHTTPOnly {
                props[.init("HttpOnly")] = "TRUE"
            }
            if let expires = record.expires {
                props[.expires] = expires
            }
            return HTTPCookie(properties: props)
        }
    }

    private static func mapSafariError(_ error: SafariCookieImporter.ImportError) -> ImportError {
        switch error {
        case .cookieFileNotFound:
            ImportError.notFound(source: .safari, details: error.localizedDescription)
        case .cookieFileNotReadable:
            ImportError.accessDenied(source: .safari, details: error.localizedDescription)
        case .invalidFile:
            ImportError.loadFailed(source: .safari, details: error.localizedDescription)
        }
    }

    private static func mapChromeError(_ error: ChromeCookieImporter.ImportError) -> ImportError {
        switch error {
        case .cookieDBNotFound:
            ImportError.notFound(source: .chrome, details: error.localizedDescription)
        case .keychainDenied:
            ImportError.accessDenied(source: .chrome, details: error.localizedDescription)
        case .sqliteFailed:
            ImportError.loadFailed(source: .chrome, details: error.localizedDescription)
        }
    }

    private static func mapFirefoxError(_ error: FirefoxCookieImporter.ImportError) -> ImportError {
        switch error {
        case .cookieDBNotFound:
            ImportError.notFound(source: .firefox, details: error.localizedDescription)
        case .cookieDBNotReadable:
            ImportError.accessDenied(source: .firefox, details: error.localizedDescription)
        case .sqliteFailed:
            ImportError.loadFailed(source: .firefox, details: error.localizedDescription)
        }
    }

    private static func chromeExpiryDate(expiresUTC: Int64) -> Date? {
        guard expiresUTC > 0 else { return nil }
        let seconds = (Double(expiresUTC) / 1_000_000.0) - 11_644_473_600.0
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func normalizeDomain(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(".") { return String(trimmed.dropFirst()) }
        return trimmed
    }
}

#endif
