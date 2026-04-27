import Foundation

/// Structured decomposition of a model identifier.
///
/// The fallback resolver uses (`family`, `majorVersion`, `minorVersion`)
/// to find a "nearby" pricing entry when the exact model isn't in our
/// local table — e.g. unknown `claude-opus-4-8` falls back to known
/// `claude-opus-4-7`. See `Research/018-model-fallback-pricing.md`.
public struct ParsedModel: Equatable, Sendable {
    /// `"claude"` / `"codex"` — used only for logging; the resolver carries
    /// its own provider tag and never inspects this field.
    public let providerKey: String
    /// `"opus"` / `"sonnet"` / `"haiku"` for Claude. For Codex we use the
    /// post-`gpt-X.Y` variant string: `""` for the base (`gpt-5`),
    /// `"codex"`, `"codex-mini"`, `"codex-max"`, `"codex-spark"`,
    /// `"mini"`, `"nano"`, `"pro"`, etc.
    public let family: String
    /// Major version (e.g. `4` in `claude-opus-4-7`, `5` in `gpt-5.4`).
    public let majorVersion: Int
    /// Minor version. `nil` represents "base of major" — Claude
    /// `claude-opus-4` (with date) parses to minor=nil; Codex `gpt-5`
    /// parses to minor=0.
    public let minorVersion: Int?
    /// `"YYYYMMDD"` date suffix when present (Anthropic-style dated models).
    public let dateSuffix: String?
    /// Original input string, retained for diagnostic logging.
    public let raw: String

    public init(
        providerKey: String,
        family: String,
        majorVersion: Int,
        minorVersion: Int?,
        dateSuffix: String?,
        raw: String)
    {
        self.providerKey = providerKey
        self.family = family
        self.majorVersion = majorVersion
        self.minorVersion = minorVersion
        self.dateSuffix = dateSuffix
        self.raw = raw
    }
}

/// Records which step of the fallback chain produced a match. P6 diagnostics
/// surface this back to the user so unfamiliar model names are debuggable
/// without us shipping a Mac update first.
public enum ModelFallbackStrategy: String, Sendable, Equatable {
    /// Step 1: same family, same major, closest known minor ≤ requested.
    case sameFamilyMinorBelow
    /// Step 2: same family, same major, closest known minor ≥ requested.
    case sameFamilyMinorAbove
    /// Step 3: same family, older major, top minor of newest available.
    case sameFamilyOlderMajor
    /// Step 4: family default (e.g. Claude opus → fixed flagship).
    case familyDefault
    /// Step 5: provider default (terminal fallback).
    case providerDefault
}

/// Result of a fallback walk, including which strategy was used.
public struct ModelFallbackResult<Pricing> {
    public let key: String
    public let pricing: Pricing
    public let strategy: ModelFallbackStrategy

    public init(key: String, pricing: Pricing, strategy: ModelFallbackStrategy) {
        self.key = key
        self.pricing = pricing
        self.strategy = strategy
    }
}

/// Provider-specific resolver that knows the grammar of its model names
/// and the family-level / provider-level fallbacks.
///
/// `Pricing` is whatever value type the provider's pricing dictionary holds
/// (e.g. `CostUsagePricing.ClaudePricing`). The protocol stays generic so
/// the same algorithm applies to Codex and Claude despite their different
/// Pricing structs.
public protocol ModelFamilyResolver {
    associatedtype Pricing

    /// `"claude"` / `"codex"` — passed through to ParsedModel and to logging.
    var providerKey: String { get }

    /// Parse a normalized model identifier into a ParsedModel.
    /// Returns nil if the grammar doesn't match this provider's space —
    /// the caller should treat that as "unmappable" (i.e. no fallback at all).
    func parse(_ raw: String) -> ParsedModel?

    /// Pinned family-level fallback used when no entry in `known` matches by
    /// (family, major). Claude → `"claude-opus-4-7"` for opus, etc.
    /// Returning nil means "skip Step 4 and go straight to provider default".
    func familyDefault(family: String, in known: [String: Pricing])
        -> (key: String, pricing: Pricing)?

    /// Terminal fallback when nothing else works. Resolver subtypes should
    /// always provide this so we never return nil for an unparseable model
    /// in a recognized provider's space.
    func providerDefault(in known: [String: Pricing])
        -> (key: String, pricing: Pricing)?
}

extension ModelFamilyResolver {
    /// Walk the known table for a sensible fallback. Algorithm and rationale
    /// in `Research/018-model-fallback-pricing.md` §5. Always returns
    /// `isEstimated`-worthy data — caller must mark the resulting cost as
    /// estimated upstream.
    public func findFallback(
        for parsed: ParsedModel,
        in known: [String: Pricing])
        -> ModelFallbackResult<Pricing>?
    {
        // Decompose the table once; ignore entries whose keys don't parse
        // (e.g. dated forms like `claude-opus-4-20250514` whose parse
        // succeeds with minor=nil). Subclasses control parser strictness.
        let parsedKnown: [(parsed: ParsedModel, key: String, pricing: Pricing)] =
            known.compactMap { key, pricing in
                guard let parsed = self.parse(key) else { return nil }
                return (parsed, key, pricing)
            }

        let sameFamily = parsedKnown.filter { $0.parsed.family == parsed.family }
        let sameMajor = sameFamily.filter { $0.parsed.majorVersion == parsed.majorVersion }
        let lowerMajor = sameFamily.filter { $0.parsed.majorVersion < parsed.majorVersion }

        // Step 1: same family, same major, closest minor ≤ requested.
        // Treat nil minor as "0" for comparison so `claude-opus-4` (no
        // minor) participates in the ladder.
        let req = parsed.minorVersion ?? 0
        let belowOrEqual = sameMajor.filter { ($0.parsed.minorVersion ?? 0) <= req }
        if let pick = belowOrEqual.max(by: { lhs, rhs in
            (lhs.parsed.minorVersion ?? 0) < (rhs.parsed.minorVersion ?? 0)
        }) {
            return ModelFallbackResult(
                key: pick.key,
                pricing: pick.pricing,
                strategy: .sameFamilyMinorBelow)
        }

        // Step 2: same family, same major, closest minor ≥ requested.
        let aboveOrEqual = sameMajor.filter { ($0.parsed.minorVersion ?? 0) >= req }
        if let pick = aboveOrEqual.min(by: { lhs, rhs in
            (lhs.parsed.minorVersion ?? 0) < (rhs.parsed.minorVersion ?? 0)
        }) {
            return ModelFallbackResult(
                key: pick.key,
                pricing: pick.pricing,
                strategy: .sameFamilyMinorAbove)
        }

        // Step 3: same family, strictly older major; pick highest minor
        // of newest available major.
        if let pick = lowerMajor.max(by: { lhs, rhs in
            if lhs.parsed.majorVersion != rhs.parsed.majorVersion {
                return lhs.parsed.majorVersion < rhs.parsed.majorVersion
            }
            return (lhs.parsed.minorVersion ?? 0) < (rhs.parsed.minorVersion ?? 0)
        }) {
            return ModelFallbackResult(
                key: pick.key,
                pricing: pick.pricing,
                strategy: .sameFamilyOlderMajor)
        }

        // Step 4: family default.
        if let fallback = self.familyDefault(family: parsed.family, in: known) {
            return ModelFallbackResult(
                key: fallback.key,
                pricing: fallback.pricing,
                strategy: .familyDefault)
        }

        // Step 5: provider default.
        if let fallback = self.providerDefault(in: known) {
            return ModelFallbackResult(
                key: fallback.key,
                pricing: fallback.pricing,
                strategy: .providerDefault)
        }

        return nil
    }
}
