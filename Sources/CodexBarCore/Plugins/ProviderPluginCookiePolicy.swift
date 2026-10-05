import Foundation

/// Bundled-only authority for selecting and retaining a single browser profile.
public struct ProviderPluginCookiePolicy: Sendable {
    public enum Selection: String, Sendable {
        case requestURL = "request-url"
        case rankedSourceDomains = "ranked-source-domains"
    }

    public enum Persistence: String, Sendable {
        case nonpersistent
        case validatedSingleEntry = "validated-single-entry"
    }

    public enum Imports: String, Sendable {
        case appInteractive = "app-interactive"
        case accessGated = "access-gated"
    }

    public enum MissingCookies: String, Sendable {
        case reject
        case omit
    }

    public struct SessionFile: Sendable {
        let tokenField: String
        let cookieName: String
    }

    let selection: Selection
    let cache: Persistence
    let sourceDomains: [String]
    let requiredCookies: Set<String>
    let requestHosts: Set<String>
    let sessionFile: SessionFile?
    let missingCookies: MissingCookies
    let imports: Imports
    let headerEcho: ProviderPluginCookieHeaderEcho?
    let selectedProfile: Bool
    let sessionURL: URL?

    init(_ value: any ProviderPluginValue, domains: Set<String>, endpoints: Set<ProviderPluginEndpoint>) throws {
        let invalid = ProviderPluginError.invalidManifest("invalid bundled cookiePolicy")
        guard value.isObject, !value.isArray,
              try Set(value.propertyNames()).isSubset(of: [
                  "selection", "cache", "sourceDomains", "requiredCookies", "sessionFile", "missingCookies", "imports",
                  "headerEcho", "store", "sessionURL",
              ]),
              let selection = value.property("selection"), selection.isString,
              let selection = Selection(rawValue: selection.stringValue()),
              let cache = value.property("cache"), cache.isString,
              let cache = Persistence(rawValue: cache.stringValue())
        else { throw invalid }
        guard endpoints.allSatisfy({
            if case let .fixed(origin) = $0,
               let url = URL(string: origin), url.scheme?.lowercased() == "https"
            { return true }
            if case .setting(_, .https) = $0 { return true }
            return false
        }) else { throw invalid }
        if let missing = value.property("missingCookies"), !missing.isUndefined {
            guard missing.isString, let policy = MissingCookies(rawValue: missing.stringValue()) else { throw invalid }
            self.missingCookies = policy
        } else {
            self.missingCookies = .reject
        }
        if let imports = value.property("imports"), !imports.isUndefined {
            guard imports.isString, let policy = Imports(rawValue: imports.stringValue()) else { throw invalid }
            self.imports = policy
        } else {
            self.imports = .appInteractive
        }
        self.selection = selection
        self.cache = cache
        self.sourceDomains = try Self.strings(value.property("sourceDomains"))
        self.requiredCookies = try Set(Self.strings(value.property("requiredCookies")))
        self.requestHosts = Set(endpoints.compactMap { endpoint in
            guard case let .fixed(origin) = endpoint, let url = URL(string: origin), url.scheme == "https" else {
                return nil
            }
            return url.host
        })
        if let store = value.property("store"), !store.isUndefined {
            guard store.isString, store.stringValue() == "selected-profile",
                  cache == .nonpersistent, selection == .requestURL, self.imports == .accessGated,
                  !self.requiredCookies.isEmpty, self.requestHosts.count == 1,
                  let rawURL = value.property("sessionURL"), rawURL.isString,
                  let url = URL(string: rawURL.stringValue()), url.query == nil, url.fragment == nil,
                  let origin = try? ProviderPluginOrigin.normalizedOrigin(of: url),
                  endpoints.contains(.fixed(origin))
            else { throw invalid }
            self.selectedProfile = true
            self.sessionURL = url
        } else {
            guard value.property("sessionURL")?.isUndefined != false else { throw invalid }
            self.selectedProfile = false
            self.sessionURL = nil
        }
        guard !self.requestHosts.isEmpty,
              self.sourceDomains.count == Set(self.sourceDomains).count,
              Set(self.sourceDomains).isSubset(of: domains),
              self.requiredCookies
                  .allSatisfy({ $0.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil }),
                  selection == .requestURL ? self.sourceDomains.isEmpty : !self.sourceDomains.isEmpty
        else { throw invalid }
        if let echo = value.property("headerEcho"), !echo.isUndefined {
            guard selection == .requestURL else { throw invalid }
            self.headerEcho = try ProviderPluginCookieHeaderEcho(
                echo, domains: domains, endpoints: endpoints, requiredCookies: self.requiredCookies)
        } else {
            self.headerEcho = nil
        }
        if let file = value.property("sessionFile"), !file.isUndefined {
            guard cache == .validatedSingleEntry, selection == .rankedSourceDomains,
                  self.requestHosts.count == 1, file.isObject, !file.isArray,
                  try Set(file.propertyNames()) == ["tokenField", "cookieName"],
                  let field = file.property("tokenField"), field.isString,
                  field.stringValue().range(of: #"^[A-Za-z][A-Za-z0-9]{0,63}$"#, options: .regularExpression) != nil,
                  let cookie = file.property("cookieName"), cookie.isString,
                  self.requiredCookies.contains(cookie.stringValue())
            else { throw invalid }
            self.sessionFile = SessionFile(tokenField: field.stringValue(), cookieName: cookie.stringValue())
        } else {
            self.sessionFile = nil
        }
    }

    func allowsImportAttempt(runtime: ProviderRuntime, interaction: ProviderInteraction) -> Bool {
        self.imports == .accessGated || (runtime == .app && interaction == .userInitiated)
    }

    func hasRequiredCookies(_ records: [ProviderPluginCookieRecord], now: Date = Date()) -> Bool {
        let available = Set(records.filter { $0.expires.map { $0 > now } ?? true }.map(\.name))
        return self.requiredCookies.isSubset(of: available)
    }

    private static func strings(_ value: (any ProviderPluginValue)?) throws -> [String] {
        guard let value, !value.isUndefined else { return [] }
        guard value.isArray, let count = value.property("length"), (1...16).contains(count.int32Value()) else {
            throw ProviderPluginError.invalidManifest("cookie policy lists must contain 1-16 strings")
        }
        let strings = try (0..<Int(count.int32Value())).map { index in
            guard let item = value.element(at: index), item.isString else {
                throw ProviderPluginError.invalidManifest("cookie policy lists must contain strings")
            }
            return item.stringValue()
        }
        guard Set(strings).count == strings.count else {
            throw ProviderPluginError.invalidManifest("cookie policy lists must not contain duplicates")
        }
        return strings
    }
}
