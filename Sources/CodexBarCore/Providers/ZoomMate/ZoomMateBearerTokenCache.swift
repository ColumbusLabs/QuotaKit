import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Process-lifetime, in-memory cache of freshly-minted ZoomMate bearer JWTs.
///
/// The `.auto` cookie-mint path exchanges long-lived browser session cookies for a short-lived
/// (~hourly) bearer JWT on demand. Without a cache that mint happens on *every* refresh; this cache
/// lets a still-valid token be reused across refreshes instead.
///
/// Safety properties (why reuse can't serve a bad token):
///   - Entries are keyed by a non-reversible SHA-256 of the originating host-scoped cookie headers, so distinct
///     browser sessions / accounts never collide and the raw cookies are never stored as a key.
///   - A token is cached *only* when its JWT carries a decodable `exp` claim, and is served only
///     while `now < exp - refreshSkew`. A token whose expiry cannot be determined is never cached
///     (the caller mints fresh), so the cache can never hand back a token past its own expiry.
///   - Nothing is persisted — the cache is empty on every launch.
///
/// A revoked-before-expiry session is handled by the caller: a `401/403` from a downstream request
/// evicts the entry (see `ZoomMateWebFetchStrategy`) so the next refresh mints fresh.
actor ZoomMateBearerTokenCache {
    static let shared = ZoomMateBearerTokenCache()

    /// Refresh this many seconds before the JWT's own `exp`, so an in-flight request never rides a
    /// token that expires mid-flight.
    static let refreshSkew: TimeInterval = 60

    struct Entry: Equatable, Sendable {
        let token: String
        let accountEmail: String?
        let expiry: Date
    }

    private var entries: [String: Entry] = [:]
    private var generations: [String: UInt64] = [:]

    struct Observation: Equatable, Sendable {
        fileprivate let key: String
        fileprivate let generation: UInt64
        let entry: Entry?
    }

    /// Non-reversible cache key for a cookie session. SHA-256 hex of its canonical host map.
    static func key(forCookieHeaders cookieHeaders: ZoomMateCookieHeaders) -> String {
        let canonical = cookieHeaders.encodedForStorage() ?? ""
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the cached entry for `key` when it is still comfortably in-date, evicting and
    /// returning `nil` once it enters the `refreshSkew` window (or has passed `exp`).
    func validEntry(forKey key: String, now: Date) -> Entry? {
        self.observeValidEntry(forKey: key, now: now).entry
    }

    func observeValidEntry(forKey key: String, now: Date) -> Observation {
        let currentGeneration = self.generations[key, default: 0]
        guard let entry = self.entries[key] else {
            return Observation(key: key, generation: currentGeneration, entry: nil)
        }
        guard entry.expiry.addingTimeInterval(-Self.refreshSkew) > now else {
            self.entries[key] = nil
            let nextGeneration = currentGeneration &+ 1
            self.generations[key] = nextGeneration
            return Observation(key: key, generation: nextGeneration, entry: nil)
        }
        return Observation(key: key, generation: currentGeneration, entry: entry)
    }

    func storeIfUnchanged(_ entry: Entry, expected: Observation) -> Observation? {
        guard self.generations[expected.key, default: 0] == expected.generation else { return nil }
        self.entries[expected.key] = entry
        let nextGeneration = expected.generation &+ 1
        self.generations[expected.key] = nextGeneration
        return Observation(key: expected.key, generation: nextGeneration, entry: entry)
    }

    func invalidateIfCurrent(_ observation: Observation) -> Bool {
        guard self.generations[observation.key, default: 0] == observation.generation else { return false }
        if let expectedEntry = observation.entry {
            guard self.entries[observation.key] == expectedEntry else { return false }
            self.entries[observation.key] = nil
            self.generations[observation.key] = observation.generation &+ 1
        } else {
            guard self.entries[observation.key] == nil else { return false }
            // The request used a token that was not cached, so there is no bearer entry to clear.
            return true
        }
        return true
    }

    func store(_ entry: Entry, forKey key: String) {
        self.entries[key] = entry
        self.generations[key, default: 0] &+= 1
    }

    func invalidate(forKey key: String) {
        self.entries[key] = nil
        self.generations[key, default: 0] &+= 1
    }
}
