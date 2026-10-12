import Foundation

/// Fetches Claude's rate limits (068 §4.1): resolves a token without prompting, calls the usage endpoint exactly as
/// the full app does, and adds the account identity from the profile endpoint once per token.
///
/// An actor because it keeps state across fetches: the per-token 429 block, the per-token profile identity, and
/// (through `ClaudeCredentialResolver`) the token cache and Keychain fingerprint. Concurrent `fetch` calls share one
/// in-flight fetch, so credential resolution, the `security` read and the requests never interleave.
public actor ClaudeProbe {
    /// The shortest 429 block (068 §4.1).
    public static let minimumRateLimitBlock: TimeInterval = 5 * 60
    /// How long to wait before retrying a failed profile request for the same token. Identity is optional, so a
    /// failure doesn't fail the fetch.
    public static let profileRetryInterval: TimeInterval = 60 * 60

    private enum UsageAttempt {
        case success(Data)
        case unauthorized
        case failure(ProbeFailure)
    }

    private struct Identity {
        var email: String?
        var accountIdentities: [String]
    }

    private let transport: any HTTPTransport
    private let resolver: ClaudeCredentialResolver

    private var inFlight: Task<Result<ProbeResult, ProbeFailure>, Never>?
    /// Access token → blocked until. In memory only; the scheduler persists `.rateLimited(until:)` itself.
    private var rateLimitBlocks: [String: Date] = [:]
    /// The identity for the token it was fetched with. The token is the fingerprint: it changes exactly when the
    /// credential does, whichever source it came from.
    private var identity: (accessToken: String, value: Identity)?
    private var profileFailure: (accessToken: String, retryAt: Date)?

    public init(transport: any HTTPTransport, resolver: ClaudeCredentialResolver) {
        self.transport = transport
        self.resolver = resolver
    }

    public init(
        transport: any HTTPTransport,
        credentialsFile: any ClaudeCredentialsFileReading,
        keychainMetadata: any ClaudeKeychainMetadataReading,
        keychainSecret: any ClaudeKeychainSecretReading,
        tokenCache: any ClaudeTokenCaching)
    {
        self.init(
            transport: transport,
            resolver: ClaudeCredentialResolver(
                credentialsFile: credentialsFile,
                keychainMetadata: keychainMetadata,
                keychainSecret: keychainSecret,
                tokenCache: tokenCache))
    }

    public func fetch(now: Date) async -> Result<ProbeResult, ProbeFailure> {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { await self.performFetch(now: now) }
        self.inFlight = task
        let result = await task.value
        self.inFlight = nil
        return result
    }

    private func performFetch(now: Date) async -> Result<ProbeResult, ProbeFailure> {
        let credentials: ClaudeCredentials
        switch await self.resolver.resolve(now: now) {
        case let .failure(failure):
            return .failure(failure)
        case let .credentials(resolved):
            credentials = resolved
        }

        switch await self.fetchUsage(accessToken: credentials.accessToken, now: now) {
        case let .success(data):
            return await self.makeResult(data: data, credentials: credentials, now: now)
        case let .failure(failure):
            return .failure(failure)
        case .unauthorized:
            break
        }

        // 401: drop the cached token, resolve once more, and retry once if that produced a different token.
        await self.resolver.invalidateCachedToken()
        let fresh: ClaudeCredentials
        switch await self.resolver.resolve(now: now) {
        case .failure(.tokenExpired):
            return .failure(.tokenExpired)
        case .failure(.tokenUnavailable):
            return .failure(.tokenUnavailable)
        case .failure:
            return .failure(.signInRequired)
        case let .credentials(resolved):
            fresh = resolved
        }
        guard fresh.accessToken != credentials.accessToken else { return .failure(.signInRequired) }

        switch await self.fetchUsage(accessToken: fresh.accessToken, now: now) {
        case let .success(data):
            return await self.makeResult(data: data, credentials: fresh, now: now)
        case let .failure(failure):
            return .failure(failure)
        case .unauthorized:
            return .failure(.signInRequired)
        }
    }

    /// One usage fetch with the `cedar_ember` retry (§2.1) and the per-token 429 gate.
    private func fetchUsage(accessToken: String, now: Date) async -> UsageAttempt {
        self.rateLimitBlocks = self.rateLimitBlocks.filter { $0.value > now }
        if let blockedUntil = self.rateLimitBlocks[accessToken] {
            return .failure(.rateLimited(until: blockedUntil))
        }

        var data: Data
        var response: HTTPURLResponse
        do {
            (data, response) = try await self.transport.send(ClaudeUsageAPI.usageRequest(accessToken: accessToken))
            if ClaudeUsageAPI.shouldRetryWithoutInventory(statusCode: response.statusCode, body: data) {
                (data, response) = try await self.transport.send(
                    ClaudeUsageAPI.usageRequest(accessToken: accessToken, includeInventory: false))
            }
        } catch {
            return .failure(.network(error.localizedDescription))
        }

        switch response.statusCode {
        case 200:
            self.rateLimitBlocks[accessToken] = nil
            return .success(data)
        case 401:
            return .unauthorized
        case 403 where ClaudeUsageAPI.isScopeError(statusCode: response.statusCode, body: data):
            return .failure(.signInRequired)
        case 429:
            let floor = now.addingTimeInterval(Self.minimumRateLimitBlock)
            let retryAfter = ClaudeUsageAPI.retryAfter(from: response, now: now) ?? floor
            let blockedUntil = max(retryAfter, floor)
            self.rateLimitBlocks[accessToken] = blockedUntil
            return .failure(.rateLimited(until: blockedUntil))
        default:
            return .failure(.server(statusCode: response.statusCode))
        }
    }

    private func makeResult(
        data: Data,
        credentials: ClaudeCredentials,
        now: Date) async -> Result<ProbeResult, ProbeFailure>
    {
        guard let windows = ClaudeUsageAPI.parseUsage(data), !windows.isEmpty else {
            return .failure(.unrecognizedResponse)
        }
        let identity = await self.identity(for: credentials.accessToken, now: now)
        return .success(ProbeResult(
            windows: windows,
            plan: credentials.plan,
            accountEmail: identity?.email,
            accountIdentities: identity?.accountIdentities ?? []))
    }

    /// The profile identity, fetched once per token (§4.1). A failure returns nil and never fails the fetch.
    private func identity(for accessToken: String, now: Date) async -> Identity? {
        if let identity, identity.accessToken == accessToken {
            return identity.value
        }
        if let profileFailure, profileFailure.accessToken == accessToken, now < profileFailure.retryAt {
            return nil
        }

        let profile: ClaudeUsageAPI.Profile?
        do {
            let (data, response) = try await self.transport.send(
                ClaudeUsageAPI.profileRequest(accessToken: accessToken))
            profile = response.statusCode == 200 ? ClaudeUsageAPI.parseProfile(data) : nil
        } catch {
            profile = nil
        }

        guard let profile else {
            self.profileFailure = (accessToken, now.addingTimeInterval(Self.profileRetryInterval))
            return nil
        }
        let value = Identity(
            email: profile.email,
            accountIdentities: ClaudeUsageAPI.accountIdentities(accountUUID: profile.accountUUID, email: profile.email))
        self.identity = (accessToken, value)
        self.profileFailure = nil
        return value
    }
}
