import Foundation
#if os(macOS)
import SweetCookieKit
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Host-owned browser cookie metadata. Opted-in scripts receive only an opaque session ID.
struct ProviderPluginCookieRecord: Codable, Equatable, Sendable {
    let name: String
    let value: String
    let domain: String
    let hostOnly: Bool
    let path: String
    let secure: Bool
    let expires: Date?

    init(
        name: String,
        value: String,
        domain: String,
        hostOnly: Bool,
        path: String,
        secure: Bool,
        expires: Date?)
    {
        self.name = name
        self.value = value
        self.domain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        self.hostOnly = hostOnly
        self.path = path.isEmpty ? "/" : path
        self.secure = secure
        self.expires = expires
    }

    #if os(macOS)
    init(record: BrowserCookieRecord) {
        self.init(
            name: record.name,
            value: record.value,
            domain: record.domain,
            hostOnly: record.scope == .hostOnly,
            path: record.path,
            secure: record.isSecure,
            expires: record.expires)
    }
    #endif

    func matches(_ url: URL, now: Date) -> Bool {
        guard let host = url.host?.lowercased(),
              self.expires.map({ $0 > now }) ?? true,
              !self.secure || url.scheme?.lowercased() == "https",
              host == self.domain || (!self.hostOnly && host.hasSuffix("." + self.domain))
        else { return false }
        let requestPath = Array((url.path(percentEncoded: true).isEmpty ? "/" : url.path(percentEncoded: true)).utf8)
        let cookiePath = Array(self.path.utf8)
        guard requestPath.starts(with: cookiePath) else { return false }
        return requestPath.count == cookiePath.count || cookiePath.last == 47 || requestPath[cookiePath.count] == 47
    }

    static func header(_ records: [Self], for url: URL, now: Date = Date()) -> String? {
        let matching = records.filter { $0.matches(url, now: now) && $0.hasSafeHeaderFields }.sorted {
            if $0.path.utf8.count != $1.path.utf8.count { return $0.path.utf8.count > $1.path.utf8.count }
            if $0.name != $1.name { return $0.name < $1.name }
            if $0.domain != $1.domain { return $0.domain < $1.domain }
            return $0.value < $1.value
        }
        return matching.isEmpty ? nil : matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private var hasSafeHeaderFields: Bool {
        let name = Array(self.name.utf8)
        let value = Array(self.value.utf8)
        let separators: Set<UInt8> = [34, 40, 41, 44, 47, 58, 59, 60, 61, 62, 63, 64, 91, 92, 93, 123, 125]
        let validName = !name.isEmpty && name.allSatisfy { byte in
            (33...126).contains(byte) && !separators.contains(byte)
        }
        let validValue = value.allSatisfy { byte in
            byte == 33 || (35...43).contains(byte) || (45...58).contains(byte) ||
                (60...91).contains(byte) || (93...126).contains(byte)
        }
        return validName && validValue
    }
}

/// Per-fetch registry. It is intentionally discarded with the plugin fetch and never persists Set-Cookie.
public final class ProviderPluginCookieJar: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [String: ProviderPluginCookieSession] = [:]
    private let headerEcho: ProviderPluginCookieHeaderEcho?

    init(headerEcho: ProviderPluginCookieHeaderEcho? = nil) {
        self.headerEcho = headerEcho
    }

    func register(_ session: ProviderPluginCookieSession) {
        self.lock.withLock { self.sessions[session.id] = session }
    }

    func reject(id: String) {
        _ = self.lock.withLock { self.sessions.removeValue(forKey: id) }
    }

    func header(id: String, url: URL, now: Date = Date()) throws -> String {
        guard let session = self.lock.withLock({ self.sessions[id] }),
              url.scheme?.lowercased() == "https",
              url.port == nil || url.port == 443,
              url.user == nil,
              url.password == nil,
              session.source != "manual" || url.host?.lowercased() == URL(string: session.origin)?.host?.lowercased(),
              let records = session.records,
              let header = ProviderPluginCookieRecord.header(records, for: url, now: now),
              !header.isEmpty
        else {
            throw ProviderFetchClassifiedError(
                kind: .missingCredential,
                message: "No session cookies match this request URL.")
        }
        return header
    }

    static func authenticate(
        _ request: inout URLRequest,
        sessionID: Any?,
        required: Bool,
        jar: ProviderPluginCookieJar?) throws
    {
        guard required || sessionID != nil else { return }
        guard required,
              let id = sessionID as? String,
              !id.isEmpty,
              let jar,
              request.url != nil,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Host") == nil
        else {
            throw ProviderPluginError.secretAccess("request requires an opaque cookie session without header overrides")
        }
        if let echo = jar.headerEcho, request.value(forHTTPHeaderField: echo.header) != nil {
            throw ProviderPluginError.secretAccess("plugins may not override the cookie echo header")
        }
        try jar.apply(to: &request, id: id)
    }

    func apply(to request: inout URLRequest, id: String, now: Date = Date()) throws {
        guard let url = request.url else { throw URLError(.badURL) }
        let cookies = try self.header(id: id, url: url, now: now)
        try request.setValue(cookies, forHTTPHeaderField: "Cookie")
        guard let echo = self.headerEcho else { return }
        try request.setValue(nil, forHTTPHeaderField: echo.header)
        guard echo.origin == "https://\(url.host?.lowercased() ?? "")" else { return }
        guard self.lock.withLock({ self.sessions[id]?.origin }) == echo.origin else {
            throw ProviderPluginError.secretAccess("cookie echo session does not match its origin")
        }
        let value = try echo.value(from: cookies)
        try request.setValue(value, forHTTPHeaderField: echo.header)
    }
}

/// This transport never consults or writes shared URLSession cookie storage. It reselects records on redirects.
struct ProviderPluginCookieTransport: ProviderHTTPTransport {
    let base: any ProviderHTTPTransport
    let jar: ProviderPluginCookieJar
    let id: String

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        try self.jar.apply(to: &request, id: self.id)
        if let client = self.base as? ProviderHTTPClient, client === ProviderHTTPClient.shared {
            return try await Self.session.data(
                for: request,
                delegate: CookieRedirectDelegate(jar: self.jar, id: self.id))
        }
        return try await self.base.data(for: request)
    }

    final class CookieRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
        let jar: ProviderPluginCookieJar
        let id: String

        init(jar: ProviderPluginCookieJar, id: String) {
            self.jar = jar
            self.id = id
        }

        func urlSession(
            _: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection _: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void)
        {
            completionHandler(self.redirectedRequest(originalURL: task.originalRequest?.url, request: request))
        }

        func redirectedRequest(originalURL: URL?, request: URLRequest) -> URLRequest? {
            guard var redirected = ProviderHTTPRedirectGuardDelegate.guardedRedirectRequest(
                originalURL: originalURL,
                redirectRequest: request)
            else { return nil }
            do {
                try self.jar.apply(to: &redirected, id: self.id)
                return redirected
            } catch {
                return nil
            }
        }
    }
}
