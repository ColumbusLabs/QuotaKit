/// The three providers Lite tracks (068 §1). Raw values match `QuotaProviderList` IDs on iOS.
public enum LiteProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case antigravity

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        }
    }

    /// Mirrors the full app's `ProviderPaceCapability.showsHeadroomHint`: only Codex appends "1.5× headroom".
    public var showsHeadroomHint: Bool {
        self == .codex
    }
}
