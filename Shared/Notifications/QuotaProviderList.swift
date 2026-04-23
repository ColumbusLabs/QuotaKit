import Foundation

/// The providers CodexBar can emit quota transition notifications for. The ID
/// strings must match `UsageProvider` raw values in
/// `Sources/CodexBarCore/Providers/Providers.swift` — when a new provider is
/// added upstream, this list and the iOS app must ship an update together to
/// start receiving pushes for it.
///
/// Used on iOS to create one `CKRecordZoneSubscription` per
/// `(provider, state)` pair at app launch. Each subscription's static
/// `alertBody` is pre-filled with the `displayName` via `String(format:)` so
/// the push body shows e.g. "Codex 会话额度已耗尽" on a Chinese iPhone without
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

    /// Display names track `ProviderDescriptor.metadata.displayName` on Mac as
    /// of 2026-04-22. If a Mac-side rename lands later, iOS subscriptions
    /// still fire — the body just shows the stale name until the iOS app ships
    /// an update.
    public static let providers: [Provider] = [
        // Each displayName must match the string in the corresponding
        // `ProviderDescriptor.metadata.displayName` on Mac (grep for
        // `displayName:` in Sources/CodexBarCore/Providers/*/*ProviderDescriptor.swift).
        Provider(id: "codex", displayName: "Codex"),
        Provider(id: "claude", displayName: "Claude"),
        Provider(id: "cursor", displayName: "Cursor"),
        Provider(id: "opencode", displayName: "OpenCode"),
        Provider(id: "opencodego", displayName: "OpenCode Go"),
        Provider(id: "alibaba", displayName: "Alibaba"),
        Provider(id: "factory", displayName: "Droid"),
        Provider(id: "gemini", displayName: "Gemini"),
        Provider(id: "antigravity", displayName: "Antigravity"),
        Provider(id: "copilot", displayName: "Copilot"),
        Provider(id: "zai", displayName: "z.ai"),
        Provider(id: "perplexity", displayName: "Perplexity"),
        Provider(id: "minimax", displayName: "MiniMax"),
        Provider(id: "kimi", displayName: "Kimi"),
        Provider(id: "kilo", displayName: "Kilo"),
        Provider(id: "kiro", displayName: "Kiro"),
        Provider(id: "vertexai", displayName: "Vertex AI"),
        Provider(id: "augment", displayName: "Augment"),
        Provider(id: "jetbrains", displayName: "JetBrains AI"),
        Provider(id: "kimik2", displayName: "Kimi K2"),
        Provider(id: "amp", displayName: "Amp"),
        Provider(id: "ollama", displayName: "Ollama"),
        Provider(id: "synthetic", displayName: "Synthetic"),
        Provider(id: "warp", displayName: "Warp"),
        Provider(id: "openrouter", displayName: "OpenRouter"),
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
        return "Quota-\(providerID)-\(state)Zone"
    }
}
