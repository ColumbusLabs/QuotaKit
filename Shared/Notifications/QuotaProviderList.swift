import Foundation

/// The providers QuotaKit currently emits quota transition notifications for. The ID
/// strings must match `UsageProvider` raw values in
/// `Sources/CodexBarCore/Providers/Providers.swift` — when a new provider is
/// added upstream, this list and the iOS app must ship an update together to
/// start receiving pushes for it.
///
/// Used on iOS to create one `CKRecordZoneSubscription` per
/// `(provider, state)` pair at app launch. Each subscription's static
/// `alertBody` is pre-filled with the `displayName` via `String(format:)` so
/// the push body shows e.g. "Codex quota depleted" without
/// needing CloudKit to substitute anything per record (see
/// `Research/007-push-per-provider-subscriptions.md`).
///
/// Used on Mac to pick the destination zone from a transition's provider ID
/// (e.g. `codex` depleted → `Quota-codex-depletedZone`).
public enum QuotaProviderList {
    public struct Provider: Sendable, Equatable {
        public let id: String
        public let displayName: String

        public init(id: String, displayName: String) {
            self.id = id
            self.displayName = displayName
        }
    }

    /// The current product inventory. Keep this byte-for-byte aligned with
    /// `QuotaKitProviderCatalog.providerIDs` and Mac's enabled-provider catalog.
    public static let providers: [Provider] = [
        Provider(id: "codex", displayName: "Codex"),
        Provider(id: "claude", displayName: "Claude"),
        Provider(id: "cursor", displayName: "Cursor"),
        Provider(id: "grok", displayName: "Grok"),
    ]

    /// Frozen migration inventory for the 60-provider notification catalog
    /// shipped before the four-provider contraction. Do not derive this from
    /// `providers`: clients can skip releases, so cleanup must continue to know
    /// every retired subscription ID after the live catalog has been reduced.
    public static let retiredProviderIDs: [String] = [
        "opencode", "opencodego", "alibaba", "factory", "gemini", "antigravity",
        "copilot", "zai", "perplexity", "minimax", "kimi", "kilo", "kiro",
        "vertexai", "augment", "jetbrains", "kimik2", "amp", "ollama", "synthetic",
        "warp", "openrouter", "abacus", "mistral", "openai", "manus", "windsurf",
        "mimo", "doubao", "deepseek", "codebuff", "crof", "venice", "commandcode",
        "stepfun", "moonshot", "bedrock", "groq", "elevenlabs", "deepgram", "llmproxy",
        "azureopenai", "alibabatokenplan", "t3chat", "sakana", "qoder", "sub2api",
        "zenmux", "clinepass", "longcat", "neuralwatt", "deepinfra", "qwencloud",
        "zoommate", "xai", "notion",
    ]

    /// Returns the CloudKit zone name for a given `(providerID, state)`. The
    /// zone name is the join point between Mac-side record writes and iOS-side
    /// per-provider subscriptions — both must compute the same string.
    ///
    /// `state` is expected to be `"depleted"` or `"restored"`. Other values
    /// produce a zone name that will never match any iOS subscription.
    ///
    /// **WIRE CONTRACT.** Format `"Quota-{providerID}-{state}Zone"` is
    /// literally the CKRecordZone name on the iCloud server. Every user's
    /// per-provider push subscriptions were registered with these exact
    /// strings. Any change to the template (separator, casing, suffix)
    /// silently breaks push delivery for every existing user — there is no
    /// migration path for zone renames on Apple's side short of having every
    /// user manually reinstall / re-subscribe. Mac-side writes and iOS-side
    /// subscriptions must compute the same string byte-for-byte.
    public static func quotaZoneName(providerID: String, state: String) -> String {
        "Quota-\(providerID)-\(state)Zone"
    }
}
