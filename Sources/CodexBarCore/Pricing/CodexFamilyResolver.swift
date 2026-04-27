import Foundation

/// Resolver for OpenAI Codex (gpt-5*) model family.
///
/// Grammar: `gpt-{major}.{minor}[-{variant}]` where `variant` is the
/// remainder string (free-form). Examples:
///
///   - `gpt-5`              → major=5, minor=0, family=""
///   - `gpt-5.4-mini`       → major=5, minor=4, family="mini"
///   - `gpt-5.1-codex-max`  → major=5, minor=1, family="codex-max"
///   - `gpt-5.3-codex-spark`→ major=5, minor=3, family="codex-spark"
///
/// Family is the entire post-version string, so `codex-mini` and `mini`
/// fall back among themselves rather than collapsing into a shared
/// "mini" bucket. This protects the case where future minors on
/// `codex-mini` should not be priced like base `mini`.
///
/// Note on `codex-spark`: the production `gpt-5.3-codex-spark` row
/// is intentionally priced at zero (`displayLabel: "Research Preview"`).
/// If a future `gpt-5.4-codex-spark` arrives, the fallback ladder will
/// resolve it to the zero-priced row — that's the conservative call
/// (don't bill experimental research previews) and consistent with
/// upstream's own behavior.
struct CodexFamilyResolver: ModelFamilyResolver {
    typealias Pricing = CostUsagePricing.CodexPricing
    let providerKey = "codex"

    /// Provider-wide terminal fallback. `gpt-5` is the simplest / oldest
    /// stable row in the Codex pricing table; using its rate as a floor
    /// for an unknown variant is conservative (matches base GPT-5 input
    /// pricing rather than over-quoting a "pro" or "spark" tier).
    private static let providerFlagship = "gpt-5"

    init() {}

    func parse(_ raw: String) -> ParsedModel? {
        guard raw.hasPrefix("gpt-") else { return nil }
        let body = String(raw.dropFirst("gpt-".count))

        // Split version part from the remainder. The first hyphen (if any)
        // separates `{M}.{m}` from `{variant}`.
        let firstHyphen = body.firstIndex(of: "-")
        let versionPart: String
        let variant: String
        if let firstHyphen {
            versionPart = String(body[..<firstHyphen])
            variant = String(body[body.index(after: firstHyphen)...])
        } else {
            versionPart = body
            variant = ""
        }

        // Empty version slot ("gpt--mini") — reject.
        guard !versionPart.isEmpty else { return nil }

        // Parse `{major}` or `{major}.{minor}`.
        let versionTokens = versionPart.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !versionTokens.isEmpty, !versionTokens[0].isEmpty,
              let major = Int(versionTokens[0])
        else { return nil }

        var minor: Int?
        if versionTokens.count == 2 {
            guard !versionTokens[1].isEmpty, let parsedMinor = Int(versionTokens[1]) else {
                return nil
            }
            minor = parsedMinor
        } else if versionTokens.count > 2 {
            return nil
        }

        return ParsedModel(
            providerKey: self.providerKey,
            family: variant,
            majorVersion: major,
            minorVersion: minor,
            // Codex models don't carry a date suffix; the upstream
            // `normalizeCodexModel` already strips Anthropic-style date
            // suffixes that occasionally appear on imported logs.
            dateSuffix: nil,
            raw: raw)
    }

    func familyDefault(family _: String, in _: [String: Pricing])
        -> (key: String, pricing: Pricing)?
    {
        // No per-family pin: Codex variants are too heterogeneous (mini /
        // pro / nano / codex-spark / codex-max are not interchangeable).
        // We skip Step 4 and let Step 5 (provider default) handle the
        // truly-unknown case.
        nil
    }

    func providerDefault(in known: [String: Pricing])
        -> (key: String, pricing: Pricing)?
    {
        guard let pricing = known[Self.providerFlagship] else { return nil }
        return (Self.providerFlagship, pricing)
    }
}
