import Foundation

// MARK: - OS seams (implemented in the app target, stubbed in tests)

/// What an attributes-only Keychain query found for Claude Code's `Claude Code-credentials` item (068 §4.1 step 3).
public enum ClaudeKeychainItemState: Sendable, Equatable {
    /// The item exists. `modifiedAt` is the newest `kSecAttrModificationDate` when there are several, or nil when
    /// the item has none.
    case found(modifiedAt: Date?)
    case notFound
    /// The query failed for another reason. Nothing was read.
    case unavailable
}

/// Reads only the metadata of Claude Code's Keychain item. Phase 0 showed an attributes-only query never prompts.
public protocol ClaudeKeychainMetadataReading: Sendable {
    /// Must never request the item's data and must never show UI.
    func claudeCredentialsItemState() -> ClaudeKeychainItemState
}

/// Why reading Claude Code's secret through `/usr/bin/security` failed (068 §4.1 step 4).
public enum ClaudeSecretReadFailure: Error, Sendable, Equatable {
    /// It couldn't launch or exited non-zero, for example because Claude Code dropped `security` from the ACL.
    case failed
    /// It ran past the 5 s limit and was killed.
    case timedOut
}

/// Reads the secret of Claude Code's Keychain item without a dialog (068 §4.1 step 3). Never via `SecItem`.
public protocol ClaudeKeychainSecretReading: Sendable {
    func readClaudeCredentialsSecret() async -> Result<Data, ClaudeSecretReadFailure>
}

/// Lite's own Keychain item holding the last token it read (068 §4.1 step 2). Lite created it, so reads never prompt.
public protocol ClaudeTokenCaching: Sendable {
    func loadCachedToken() -> Data?
    func saveCachedToken(_ data: Data)
    func clearCachedToken()
}

// MARK: - Cached token

/// What Lite stores in its own Keychain item: the usable credential fields (never the refresh token) plus the
/// modification date of the Claude Code item they were read from, so a relaunch doesn't re-run `security` until that
/// item changes.
struct ClaudeCachedToken: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var accessToken: String
    /// Seconds since the reference date, so it round-trips a `Date` exactly.
    var expiresAt: Double?
    var scopes: [String]
    var subscriptionType: String?
    var rateLimitTier: String?
    var source: ClaudeKeychainFingerprint

    init(credentials: ClaudeCredentials, source: ClaudeKeychainFingerprint) {
        self.version = Self.currentVersion
        self.accessToken = credentials.accessToken
        self.expiresAt = credentials.expiresAt?.timeIntervalSinceReferenceDate
        self.scopes = credentials.scopes
        self.subscriptionType = credentials.subscriptionType
        self.rateLimitTier = credentials.rateLimitTier
        self.source = source
    }

    var credentials: ClaudeCredentials {
        ClaudeCredentials(
            accessToken: self.accessToken,
            expiresAt: self.expiresAt.map(Date.init(timeIntervalSinceReferenceDate:)),
            scopes: self.scopes,
            subscriptionType: self.subscriptionType,
            rateLimitTier: self.rateLimitTier)
    }

    static func decode(_ data: Data) -> ClaudeCachedToken? {
        guard let token = try? JSONDecoder().decode(ClaudeCachedToken.self, from: data),
              token.version == Self.currentVersion,
              !token.accessToken.isEmpty
        else { return nil }
        return token
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}

/// Identifies one version of Claude Code's Keychain item by its modification date (the full app's fingerprint
/// trick, `ClaudeOAuthCredentials.swift:2441-2630`).
enum ClaudeKeychainFingerprint: Codable, Equatable {
    /// Seconds since the reference date.
    case modified(Double)
    /// The item has no modification date, so changes can't be detected: read it at most once per launch.
    case undated

    init(modifiedAt: Date?) {
        self = modifiedAt.map { .modified($0.timeIntervalSinceReferenceDate) } ?? .undated
    }
}

// MARK: - Resolver

/// Finds a usable Claude token without ever showing a Keychain dialog (068 §4.1, §10 Phase 0).
///
/// The chain, in order:
/// 1. `.credentials.json`, when present and unexpired.
/// 2. Lite's own cache (memory, then Lite's Keychain item once per launch), when unexpired.
/// 3. An attributes-only change check of `Claude Code-credentials`, then `/usr/bin/security`, but only when the
///    item's modification date differs from the one last read, and at most once per modification date.
///
/// It never refreshes a token, never calls `platform.claude.com/v1/oauth/token`, and never asks for an interactive
/// grant: an expired token is `.tokenExpired` and a failed `security` read is `.tokenUnavailable`.
///
/// It's an actor so its state is safe to share; `ClaudeProbe` additionally runs one fetch at a time, so a resolution
/// is never interleaved with another.
public actor ClaudeCredentialResolver {
    public enum Outcome: Sendable, Equatable {
        case credentials(ClaudeCredentials)
        case failure(ProbeFailure)
    }

    private let credentialsFile: any ClaudeCredentialsFileReading
    private let keychainMetadata: any ClaudeKeychainMetadataReading
    private let keychainSecret: any ClaudeKeychainSecretReading
    private let tokenCache: any ClaudeTokenCaching

    private var cached: ClaudeCachedToken?
    private var didLoadCache = false
    /// The Claude Code item version last passed to `security`, successfully or not.
    private var lastReadFingerprint: ClaudeKeychainFingerprint?
    /// Why that read didn't produce a token, so later checks of the same version report the same thing.
    private var lastReadFailure: ProbeFailure?

    public init(
        credentialsFile: any ClaudeCredentialsFileReading,
        keychainMetadata: any ClaudeKeychainMetadataReading,
        keychainSecret: any ClaudeKeychainSecretReading,
        tokenCache: any ClaudeTokenCaching)
    {
        self.credentialsFile = credentialsFile
        self.keychainMetadata = keychainMetadata
        self.keychainSecret = keychainSecret
        self.tokenCache = tokenCache
    }

    public func resolve(now: Date) async -> Outcome {
        // An expired token from any source; reported as `.tokenExpired` if nothing better turns up.
        var expired: ClaudeCredentials?

        // 1. The plain-text file wins when it holds a live token.
        if let data = self.credentialsFile.readCredentialsFile(),
           let credentials = try? ClaudeCredentials.parse(data)
        {
            if !credentials.isExpired(at: now) { return .credentials(credentials) }
            expired = credentials
        }

        // 2. Lite's own cache.
        if let cached = self.loadCacheIfNeeded() {
            let credentials = cached.credentials
            if !credentials.isExpired(at: now) { return .credentials(credentials) }
            expired = expired ?? credentials
        }

        // 3. Attributes-only change check, then at most one `security` read per item version.
        let fingerprint: ClaudeKeychainFingerprint
        switch self.keychainMetadata.claudeCredentialsItemState() {
        case .notFound:
            return .failure(expired == nil ? .signInRequired : .tokenExpired)
        case .unavailable:
            return .failure(expired == nil ? .tokenUnavailable : .tokenExpired)
        case let .found(modifiedAt):
            fingerprint = ClaudeKeychainFingerprint(modifiedAt: modifiedAt)
        }

        if fingerprint == self.lastReadFingerprint {
            // Nothing new since the last read: no subprocess.
            if expired != nil { return .failure(.tokenExpired) }
            return .failure(self.lastReadFailure ?? .signInRequired)
        }

        // Recorded before the read, so a failed or timed-out read isn't repeated for this version.
        self.lastReadFingerprint = fingerprint
        let data: Data
        switch await self.keychainSecret.readClaudeCredentialsSecret() {
        case .failure:
            self.lastReadFailure = .tokenUnavailable
            return .failure(.tokenUnavailable)
        case let .success(secret):
            data = secret
        }

        let credentials: ClaudeCredentials
        do {
            credentials = try ClaudeCredentials.parse(data)
        } catch {
            let failure: ProbeFailure = error == .invalidJSON ? .tokenUnavailable : .signInRequired
            self.lastReadFailure = failure
            return .failure(failure)
        }

        self.lastReadFailure = nil
        self.store(ClaudeCachedToken(credentials: credentials, source: fingerprint))
        if credentials.isExpired(at: now) { return .failure(.tokenExpired) }
        return .credentials(credentials)
    }

    /// Drops the cached token after a 401 (068 §4.1). The last-read fingerprint is kept, so the next `resolve` only
    /// runs `security` if Claude Code has rewritten its item since.
    public func invalidateCachedToken() {
        self.cached = nil
        self.didLoadCache = true
        self.tokenCache.clearCachedToken()
    }

    private func loadCacheIfNeeded() -> ClaudeCachedToken? {
        if !self.didLoadCache {
            self.didLoadCache = true
            if let data = self.tokenCache.loadCachedToken(), let token = ClaudeCachedToken.decode(data) {
                self.cached = token
                self.lastReadFingerprint = token.source
            }
        }
        return self.cached
    }

    private func store(_ token: ClaudeCachedToken) {
        self.cached = token
        self.didLoadCache = true
        if let data = token.encoded() {
            self.tokenCache.saveCachedToken(data)
        }
    }
}
