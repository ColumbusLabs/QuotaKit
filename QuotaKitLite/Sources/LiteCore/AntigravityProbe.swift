import Foundation

/// Fetches Antigravity quota from its local language server (068 §4.3). Never launches anything: with no running
/// server the result is `.notRunning`, and the menu keeps the last data with its reset projection.
///
/// The working endpoint is cached and reused until a request to it fails to connect or its process is gone; only
/// then is the process table scanned again.
public actor AntigravityProbe {
    public typealias Discover = @Sendable () -> [AntigravityEndpoint]
    public typealias IsAlive = @Sendable (Int32) -> Bool

    static let quotaSummaryPath = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
    static let userStatusPath = "/exa.language_server_pb.LanguageServerService/GetUserStatus"

    private let transport: HTTPTransport
    private let discover: Discover
    private let isAlive: IsAlive
    private var cached: AntigravityEndpoint?
    /// The account, read once per server process.
    private var identity: (pid: Int32, email: String?, plan: String?)?

    public init(transport: HTTPTransport, discover: @escaping Discover, isAlive: @escaping IsAlive) {
        self.transport = transport
        self.discover = discover
        self.isAlive = isAlive
    }

    /// Forgets the cached endpoint, for example when the Antigravity app quit or launched.
    public func invalidate() {
        self.cached = nil
    }

    public func fetch(now _: Date) async -> Result<ProbeResult, ProbeFailure> {
        if let cached, self.isAlive(cached.pid) {
            let result = await self.fetch(from: [cached])
            if case .failure(.network) = result {
                self.cached = nil
            } else {
                return result
            }
        }
        self.cached = nil
        let endpoints = self.discover()
        guard !endpoints.isEmpty else { return .failure(.notRunning) }
        return await self.fetch(from: endpoints)
    }

    /// Tries each endpoint in order. A connection failure moves on; anything else is the answer.
    private func fetch(from endpoints: [AntigravityEndpoint]) async -> Result<ProbeResult, ProbeFailure> {
        var lastFailure = ProbeFailure.notRunning
        for endpoint in endpoints {
            let data: Data
            do {
                data = try await self.post(Self.quotaSummaryPath, body: ["forceRefresh": true], to: endpoint)
            } catch let failure as ProbeFailure {
                lastFailure = failure
                continue
            } catch {
                lastFailure = .network(error.localizedDescription)
                continue
            }
            self.cached = endpoint
            do {
                let windows = try AntigravityParser.quotaWindows(from: data)
                let identity = await self.identity(for: endpoint)
                // The full app keeps Antigravity out of `AccountIdentityComputer`'s merge set.
                return .success(ProbeResult(windows: windows, plan: identity.plan, accountEmail: identity.email))
            } catch let failure as ProbeFailure {
                return .failure(failure)
            } catch {
                return .failure(.unrecognizedResponse)
            }
        }
        return .failure(lastFailure)
    }

    private func identity(for endpoint: AntigravityEndpoint) async -> (email: String?, plan: String?) {
        if let identity, identity.pid == endpoint.pid {
            return (identity.email, identity.plan)
        }
        let body: [String: Any] = ["metadata": [
            "ideName": "antigravity",
            "extensionName": "antigravity",
            "ideVersion": "unknown",
            "locale": "en",
        ]]
        guard let data = try? await self.post(Self.userStatusPath, body: body, to: endpoint) else {
            return (nil, nil)
        }
        let parsed = AntigravityParser.identity(from: data)
        self.identity = (endpoint.pid, parsed.email, parsed.plan)
        return parsed
    }

    private func post(_ path: String, body: [String: Any], to endpoint: AntigravityEndpoint) async throws -> Data {
        guard let url = URL(string: "\(endpoint.scheme)://127.0.0.1:\(endpoint.port)\(path)") else {
            throw ProbeFailure.notRunning
        }
        let payload = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        if endpoint.kind != .cli {
            request.setValue(endpoint.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        }
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await self.transport.send(request)
        } catch {
            throw ProbeFailure.network(error.localizedDescription)
        }
        guard response.statusCode == 200 else {
            throw ProbeFailure.server(statusCode: response.statusCode)
        }
        return data
    }
}

/// HTTPS to 127.0.0.1 only, accepting the language server's self-signed certificate there and nowhere else
/// (the full app's `LocalhostTrustPolicy`). Created lazily and only for Antigravity (068 §3.2).
public struct LoopbackTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration, delegate: LoopbackTrust(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.host == "127.0.0.1" else { throw URLError(.badURL) }
        let (data, response) = try await self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

final class LoopbackTrust: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?)
    {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host == "127.0.0.1",
              let trust = space.serverTrust
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest) async -> URLRequest?
    {
        nil
    }
}
