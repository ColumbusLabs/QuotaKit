import CodexBarCore

extension UsageStore {
    enum SessionQuotaWindowSource: String {
        case primary
        case copilotSecondaryFallback
        case zaiTertiary
        case antigravityQuotaSummary
        case antigravityLegacy
    }

    struct QuotaWarningStateKey: Hashable {
        let provider: UsageProvider
        let window: QuotaWarningWindow
        /// Distinguishes independent extra rate windows that share a provider/window lane
        /// (e.g. multiple `claude-weekly-scoped-*` windows) so their fired-threshold state
        /// does not clobber each other or the primary session/weekly lanes. `nil` for the
        /// primary session and weekly lanes.
        let windowID: String?
        let accountDiscriminator: String?

        init(
            provider: UsageProvider,
            window: QuotaWarningWindow,
            windowID: String? = nil,
            accountDiscriminator: String? = nil)
        {
            self.provider = provider
            self.window = window
            self.windowID = windowID
            self.accountDiscriminator = accountDiscriminator
        }
    }

    struct SessionQuotaStateKey: Hashable {
        let provider: UsageProvider
        let accountDiscriminator: String?

        init(provider: UsageProvider, accountDiscriminator: String? = nil) {
            self.provider = provider
            self.accountDiscriminator = accountDiscriminator
        }

        static let codex = Self(provider: .codex)
        static let claude = Self(provider: .claude)
    }

    struct QuotaWarningAccountContext {
        let displayName: String?
        let discriminator: String?
    }

    struct QuotaWarningTransition {
        let window: QuotaWarningWindow
        let rateWindow: RateWindow?
        let source: SessionQuotaWindowSource?
        let windowID: String?
        let windowDisplayLabel: String?

        init(
            window: QuotaWarningWindow,
            rateWindow: RateWindow?,
            source: SessionQuotaWindowSource?,
            windowID: String? = nil,
            windowDisplayLabel: String? = nil)
        {
            self.window = window
            self.rateWindow = rateWindow
            self.source = source
            self.windowID = windowID
            self.windowDisplayLabel = windowDisplayLabel
        }
    }

    struct QuotaWarningState {
        var lastRemaining: Double?
        var firedThresholds: Set<Int> = []
        var source: SessionQuotaWindowSource?
    }
}
