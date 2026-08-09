import CodexBarSync
import SwiftUI

enum ProviderDetailPrimarySection {
    case genericRateLimits
}

enum ProviderDetailSection: Identifiable {
    case grok(SyncGrokBilling)
    case claudeAdmin(SyncClaudeAdminUsage)
    case claudeExtra(SyncClaudeExtraUsage)
    case codexWorkspace(SyncCodexWorkspaceContext, showsPace: Bool)
    case codexResetCredits(SyncCodexResetCredits)

    var id: String {
        switch self {
        case .grok:
            "grok"
        case .claudeAdmin:
            "claude-admin"
        case .claudeExtra:
            "claude-extra"
        case .codexWorkspace:
            "codex-workspace"
        case .codexResetCredits:
            "codex-reset-credits"
        }
    }
}

enum ProviderDetailSectionDispatcher {
    static func primarySection(for provider: ProviderUsageSnapshot) -> ProviderDetailPrimarySection {
        .genericRateLimits
    }

    static func sections(
        for provider: ProviderUsageSnapshot,
        hasRateWindowPace: Bool) -> [ProviderDetailSection]
    {
        var sections: [ProviderDetailSection] = []

        if provider.providerID == "grok", let value = provider.grokBilling {
            sections.append(.grok(value))
        }
        if provider.providerID == "claude", let value = provider.claudeAdminUsage {
            sections.append(.claudeAdmin(value))
        }
        if provider.providerID == "claude", let value = provider.claudeExtraUsage {
            sections.append(.claudeExtra(value))
        }
        if provider.providerID == "codex",
           let value = provider.codexWorkspace,
           value.workspaceName?.isEmpty == false ||
           (!hasRateWindowPace && value.weeklyPaceLabel?.isEmpty == false)
        {
            sections.append(.codexWorkspace(value, showsPace: !hasRateWindowPace))
        }
        if provider.providerID == "codex",
           let value = provider.codexResetCredits,
           value.authoritativeAvailableCount > 0
        {
            sections.append(.codexResetCredits(value))
        }

        return sections
    }
}

struct ProviderDetailPrimarySectionView<GenericContent: View>: View {
    let section: ProviderDetailPrimarySection
    let tintColor: Color
    @ViewBuilder let genericContent: GenericContent

    var body: some View {
        switch self.section {
        case .genericRateLimits:
            self.genericContent
        }
    }
}

struct ProviderDetailSectionView: View {
    let section: ProviderDetailSection
    let tintColor: Color

    var body: some View {
        switch self.section {
        case let .grok(billing):
            GrokBillingCard(billing: billing, tintColor: self.tintColor)
        case let .claudeAdmin(usage):
            ClaudeAdminUsageCard(usage: usage, tintColor: self.tintColor)
        case let .claudeExtra(extraUsage):
            ClaudeExtraUsageCard(extraUsage: extraUsage, tintColor: self.tintColor)
        case let .codexWorkspace(context, showsPace):
            CodexWorkspaceBadge(
                context: context,
                tintColor: self.tintColor,
                showsPace: showsPace)
        case let .codexResetCredits(credits):
            CodexResetCreditsCard(credits: credits, tintColor: self.tintColor)
        }
    }
}
