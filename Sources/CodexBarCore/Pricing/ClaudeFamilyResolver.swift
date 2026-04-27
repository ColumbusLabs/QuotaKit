import Foundation

/// Resolver for the Anthropic Claude model family.
///
/// Grammar: `claude-{family}-{major}[-{minor}][-{YYYYMMDD}]`
/// where `family ∈ {opus, sonnet, haiku, instant}`. Anything outside that
/// family set parses to nil — `claude-design`, `claude-routines`, and
/// other gate identifiers are intentionally excluded so they never resolve
/// to real Claude pricing.
///
/// Vertex variants (`claude-opus-4-5@20251101`) flow in already normalized
/// by `CostUsagePricing.normalizeClaudeModel` — by the time the resolver
/// sees them, the `@`-separator is gone and they look identical to the
/// Anthropic API form.
struct ClaudeFamilyResolver: ModelFamilyResolver {
    typealias Pricing = CostUsagePricing.ClaudePricing
    let providerKey = "claude"

    /// Real Claude model families. `claude-design` and `claude-routines`
    /// surface in our codebase as gate IDs (not API model names) and must
    /// be rejected here so they never accidentally resolve to a Claude
    /// pricing entry via the fallback ladder.
    private static let knownFamilies: Set<String> = ["opus", "sonnet", "haiku", "instant"]

    /// Family-default flagships, used when `findFallback` Step 4 fires.
    /// Pinned values must always exist in the live pricing table; the
    /// `known[key] != nil` guard keeps the resolver honest if the
    /// dictionary ever drops one of these keys.
    private static let familyFlagships: [String: String] = [
        "opus": "claude-opus-4-7",
        "sonnet": "claude-sonnet-4-6",
        "haiku": "claude-haiku-4-5",
    ]

    /// Provider-wide terminal fallback. Claude Opus 4.7 is the latest
    /// flagship as of 2026-04-27 — pricing is the most conservative
    /// (highest) we'd quote, so estimates can never silently *under*-count
    /// a user's spend on a totally unrecognized Claude variant.
    private static let providerFlagship = "claude-opus-4-7"

    init() {}

    func parse(_ raw: String) -> ParsedModel? {
        guard raw.hasPrefix("claude-") else { return nil }
        let body = String(raw.dropFirst("claude-".count))
        let parts = body.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        // Need at least `family-major`.
        guard parts.count >= 2 else { return nil }
        // Reject empty leading family slot (e.g. "claude--4-5").
        let family = parts[0]
        guard Self.knownFamilies.contains(family) else { return nil }
        guard let major = Int(parts[1]) else { return nil }

        var minor: Int?
        var date: String?

        // parts[2] could be either `{minor}` or a date (`YYYYMMDD`).
        if parts.count >= 3 {
            if Self.isDateSuffix(parts[2]) {
                date = parts[2]
            } else if let parsedMinor = Int(parts[2]) {
                minor = parsedMinor
            } else {
                return nil
            }
        }

        // parts[3] is always a date suffix when present.
        if parts.count == 4 {
            guard date == nil, Self.isDateSuffix(parts[3]) else { return nil }
            date = parts[3]
        }

        // Reject longer forms — extra hyphenated tokens we don't expect.
        if parts.count > 4 { return nil }

        return ParsedModel(
            providerKey: self.providerKey,
            family: family,
            majorVersion: major,
            minorVersion: minor,
            dateSuffix: date,
            raw: raw)
    }

    func familyDefault(family: String, in known: [String: Pricing])
        -> (key: String, pricing: Pricing)?
    {
        guard let key = Self.familyFlagships[family], let pricing = known[key] else { return nil }
        return (key, pricing)
    }

    func providerDefault(in known: [String: Pricing])
        -> (key: String, pricing: Pricing)?
    {
        guard let pricing = known[Self.providerFlagship] else { return nil }
        return (Self.providerFlagship, pricing)
    }

    private static func isDateSuffix(_ token: String) -> Bool {
        token.count == 8 && token.allSatisfy(\.isNumber)
    }
}
