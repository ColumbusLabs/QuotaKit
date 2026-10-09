#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Computes a stable identifier set for a provider snapshot, used by iOS
/// `CloudSyncReader.mergeSnapshots` to group snapshots from multiple Macs
/// into a single logical account card. See
/// `Research/019-account-identity-multi-version-merge.md` for the full
/// architecture.
///
/// **Discipline (load-bearing):**
/// - Identifiers are **additive**. Once an identifier scheme is published
///   for a provider in a release, it MUST keep being written for ≥3 minor
///   releases before removal. See `Research/019-account-identity-multi-version-merge.md`
///   §6.
/// - Identifiers are **opaque to iOS**. Format is `{providerID}:{scheme}:{value}`
///   but iOS does string-equality only — never parses. New schemes can be
///   added at any time.
/// - **Time-bounded values** (JWT exp, session tokens, refresh tokens)
///   MUST NEVER appear here. Only stable identifiers.
/// - **Group / shared aliases** (`team@company.com`, etc.) MUST NOT be
///   written. Only authenticated primary identifiers.
public enum AccountIdentityComputer {
    /// Maximum length of any single identifier string. Over-limit values keep
    /// a readable prefix plus SHA-256 suffix so distinct long identifiers do
    /// not collapse into the same merge key.
    ///
    /// **Must equal** `AccountIdentityNormalize.maxAccountIdentifierLength`
    /// in `Shared/iCloud/AccountIdentityNormalize.swift` so iOS legacy-email
    /// synthesis truncates at the same point. A unit test
    /// (`AccountIdentityComputerTests.normalize_matches_iOSSharedNormalize`)
    /// pins this contract.
    public static let maxIdentifierLength = 256

    /// Compute the identifier set for a provider snapshot.
    ///
    /// Returns nil for providers that don't have a stable account model
    /// (most quota-only providers): iOS uses its legacy email or provider-only
    /// grouping for those — current behavior, no regression.
    ///
    /// Returns `[]` only when this provider DOES participate (Tier-A) but
    /// no identifier could be derived (e.g. user signed out, fetch failed).
    /// iOS treats `[]` like nil for grouping purposes.
    /// Copilot callers must pass the configured API host. Legacy hostless
    /// GitHub IDs must not become public identities on Enterprise hosts.
    public static func compute(
        provider: UsageProvider,
        identity: ProviderIdentitySnapshot?,
        externalIdentifier: String? = nil,
        copilotExpectedAPIHost: String? = nil) -> [String]?
    {
        switch provider {
        case .codex:
            self.codex(identity: identity)
        case .claude:
            self.claude(identity: identity)
        case .vertexai:
            self.vertexAI(identity: identity)
        case .replicate:
            self.replicate(identity: identity)
        case .copilot:
            self.copilot(
                externalIdentifier: externalIdentifier,
                expectedAPIHost: copilotExpectedAPIHost)
        case .zai, .gemini, .antigravity, .cursor, .opencode, .opencodego, .alibaba, .factory,
             .minimax, .kilo, .kiro, .kimi, .augment, .jetbrains, .amp, .ollama, .synthetic,
             .openrouter, .warp, .perplexity, .abacus, .mistral,
             // Upstream 0.24–0.25.1 providers. Kept non-Tier-A for now —
             // iOS uses legacy email or provider-only grouping. Promote to a
             // dedicated case (with stable identifier extraction) only
             // after we ship corresponding iOS render support and have a
             // real cross-Mac merge use case for that provider.
             .openai, .manus, .windsurf, .mimo, .doubao, .deepseek,
             .codebuff, .venice, .commandcode, .stepfun,
             // Upstream v0.26.0 new providers. Same rationale as above —
             // iOS 1.7 surfaces these via single-account cards; promote
             // to Tier-A only when cross-Mac merging is needed.
             .moonshot, .bedrock,
             // Upstream v0.27.0 new providers. iOS 1.8 surfaces these
             // via single-account cards. Promote to Tier-A only if a
             // user files a cross-Mac merging request for them.
             .grok, .groq, .elevenlabs, .deepgram, .llmproxy, .litellm,
             // Upstream v0.28.0–v0.29.0 new providers. iOS 1.9 surfaces
             // these via single-account cards. Promote to Tier-A only if a
             // user files a cross-Mac merging request for them.
             .azureopenai, .alibabatokenplan, .t3chat,
             // Upstream 0.33+ new providers. Same rationale as above.
             .devin, .zed, .sakana, .poe, .chutes, .qoder, .clawrouter, .wayfinder, .sub2api, .xai,
             .zenmux, .clinepass, .longcat, .neuralwatt, .deepinfra, .aiand, .qwencloud, .zoommate, .notion,
             .fireworks, .ibmbob, .gitkraken, .v0, .coderabbit, .huggingface, .hyper,
             .bifrost, .devpass, .aixy, .xkiro, .raycast, .helmcode, .typesafe,
             .atlascloud, .vercel, .llmman, .nous, .muse, .pi, .museai, .lithosai, .workbuddy, .langdock, .xapi,
             // Provider-specific by design: these eight remain non-Tier-A until iOS has stable identity support
             // and a cross-Mac merge need.
             .tavily, .linkup, .tinyapi, .exa, .cosmic, .aerostack, .sailresearch, .sofya:
            // Non-Tier-A providers: no stable account model required by
            // iOS today. Return nil → iOS uses legacy email or provider-only
            // grouping. If a future provider needs account-specific merging, add
            // a case here with its identifier sources.
            nil
        }
    }

    // MARK: - Per-provider identifier extraction

    private static func codex(identity: ProviderIdentitySnapshot?) -> [String]? {
        guard let identity else { return [] }
        var ids: [String] = []
        // Primary: organization ID. Stable across email changes, IdP swaps.
        if let normalized = Self.normalize(identity.accountOrganization) {
            ids.append("codex:account:\(normalized)")
        }
        // Secondary: email. Less stable but useful for transitional
        // grouping (Mac without org-id can still merge via email).
        if let normalized = Self.normalize(identity.accountEmail) {
            ids.append("codex:email:\(normalized)")
        }
        return ids
    }

    private static func claude(identity: ProviderIdentitySnapshot?) -> [String]? {
        guard let identity else { return [] }
        var ids: [String] = []
        // Primary: organization ID (Anthropic Team / Enterprise org).
        // For consumer plans this is often nil — falls back to email.
        if let normalized = Self.normalize(identity.accountOrganization) {
            ids.append("claude:account:\(normalized)")
        }
        // Secondary: email. For consumer Claude OAuth this is the only
        // stable handle we have today. Future work may add the OAuth
        // `sub` claim as a third identifier (Research/019 §4.2).
        if let normalized = Self.normalize(identity.accountEmail) {
            ids.append("claude:email:\(normalized)")
        }
        return ids
    }

    private static func vertexAI(identity: ProviderIdentitySnapshot?) -> [String]? {
        guard let identity else { return [] }
        var ids: [String] = []
        // Primary: GCP project / org identifier.
        if let normalized = Self.normalize(identity.accountOrganization) {
            ids.append("vertexai:project:\(normalized)")
        }
        // Secondary: GCP user account email.
        if let normalized = Self.normalize(identity.accountEmail) {
            ids.append("vertexai:email:\(normalized)")
        }
        return ids
    }

    private static func replicate(identity: ProviderIdentitySnapshot?) -> [String]? {
        guard let identity,
              let username = self.normalize(identity.accountID)
        else { return [] }
        // The billing endpoint separates users from organizations; their
        // usernames can coincide. Labels and cookies are not stable identities.
        let kind = self.normalize(identity.accountOrganization) == username ? "organization" : "user"
        return ["replicate:\(kind):\(username)"]
    }

    /// GitHub's numeric user ID is stable; the API issuer keeps Enterprise
    /// accounts with identical numeric IDs in separate identity namespaces.
    /// Legacy login-only identifiers are deliberately not promoted to a
    /// cross-device identity, since a login can exist on several hosts.
    /// Older public label-only snapshots may remain separate until their Mac
    /// upgrades; editable labels cannot safely bridge verified identities.
    private static func copilot(
        externalIdentifier: String?,
        expectedAPIHost: String?) -> [String]
    {
        guard let components = self.copilotComponents(externalIdentifier: externalIdentifier),
              expectedAPIHost == nil || components.apiHost == expectedAPIHost?.lowercased(),
              let normalized = self.normalize(components.raw)
        else { return [] }
        return ["copilot:github-user:\(normalized)"]
    }

    private static func copilotComponents(externalIdentifier: String?)
        -> (raw: String, apiHost: String)?
    {
        guard let raw = externalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              let marker = raw.range(of: ":user:"),
              !raw[marker.upperBound...].isEmpty,
              raw[marker.upperBound...].utf8.allSatisfy({ $0 >= 48 && $0 <= 57 })
        else { return nil }
        let prefix = String(raw[..<marker.lowerBound])
        if prefix == "github" { return (raw, "api.github.com") }
        guard prefix.hasPrefix("github:") else { return nil }
        let issuer = String(prefix.dropFirst("github:".count))
        guard !issuer.isEmpty,
              issuer.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90)
                      || (byte >= 97 && byte <= 122) || byte == 45 || byte == 46 || byte == 58
              })
        else { return nil }
        return (raw, issuer.lowercased())
    }

    // MARK: - Normalization

    /// Apply the normalization rules from Research/019 §4.4:
    /// - lowercase
    /// - Unicode NFC
    /// - trim whitespace
    /// - URL-percent-encode the value (safe across `:` / `|` / `/` etc.)
    /// - skip empty / whitespace-only
    /// - cap at `maxIdentifierLength` chars using prefix + SHA-256 suffix
    ///
    /// **Mirrors `AccountIdentityNormalize.normalize`** in Shared/ —
    /// iOS uses that copy to synthesize the legacy-email fallback so
    /// it lands on the SAME bytes Mac writes for `codex:email:...` etc.
    /// If you change this, change Shared/ too. A unit test pins them.
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        let nfc = lowered.precomposedStringWithCanonicalMapping
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: ":|/"))
        guard let encoded = nfc.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        if encoded.count > Self.maxIdentifierLength {
            return Self.capWithDigest(encoded)
        }
        return encoded
    }

    private static let hashMarker = "#sha256#"
    private static let sha256HexLength = 64

    private static func capWithDigest(_ encoded: String) -> String {
        let digest = SHA256.hash(data: Data(encoded.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let prefixLength = Self.maxIdentifierLength
            - Self.hashMarker.count
            - Self.sha256HexLength
        return String(encoded.prefix(prefixLength)) + Self.hashMarker + digest
    }
}
