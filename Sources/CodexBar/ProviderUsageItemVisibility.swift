import CodexBarCore
import Foundation

struct ProviderUsageItemID: Hashable, Sendable {
    private static let metricPrefix = "metric:"
    private static let detailSectionPrefix = "detailSection:"

    let rawValue: String

    var metricID: String? {
        self.rawValue.hasPrefix(Self.metricPrefix) ? String(self.rawValue.dropFirst(Self.metricPrefix.count)) : nil
    }

    var detailSectionTitle: String? {
        self.rawValue.hasPrefix(Self.detailSectionPrefix)
            ? String(self.rawValue.dropFirst(Self.detailSectionPrefix.count)) : nil
    }

    static let credits = Self(rawValue: "section:credits")
    static let codexResetCredits = Self(rawValue: "section:codex-reset-credits")
    static let claudeResetCredits = Self(rawValue: "section:claude-reset-credits")
    static let claudeExtraUsage = Self(rawValue: "section:claude-extra-usage")
    static let subscription = Self(rawValue: "section:subscription")

    static func metric(_ metricID: String) -> Self {
        Self(rawValue: "\(self.metricPrefix)\(metricID)")
    }

    static func detailSection(_ rawTitle: String) -> Self {
        let stableTitle = PersonalInfoRedactor.redactEmails(in: rawTitle, isEnabled: true) ?? rawTitle
        return Self(rawValue: "\(self.detailSectionPrefix)\(stableTitle)")
    }
}

struct ProviderUsageItemDescriptor: Identifiable, Equatable, Sendable {
    let id: ProviderUsageItemID
    let title: String
    var requiresOptionalUsage: Bool = false
}

extension ProviderUsageItemID {
    @MainActor
    func requiresOptionalUsage(for provider: UsageProvider) -> Bool {
        // Provider-specific by design: Codex optional limits and Claude extra usage retain their persisted
        // optional-display contract.
        if self == .credits || (provider == .claude && self == .claudeExtraUsage) { return true }
        if let metricID = self.metricID {
            return (provider == .codex && (metricID.hasPrefix("codex-") || metricID == "monthly")) ||
                (provider == .claude && metricID == "claude-routines")
        }
        guard let rawTitle = self.detailSectionTitle else { return false }
        let policy = ProviderDescriptorRegistry.descriptor(for: provider).presentation.optionalDetails
        return policy.hidesAllWithoutOptionalUsage || policy.hiddenTitlesWithoutOptionalUsage.contains(rawTitle)
    }

    /// Label used while an item is hidden but the provider is not currently reporting it.
    func unreportedTitle(for provider: UsageProvider) -> String {
        switch self {
        case .credits: return L("Credits")
        case .codexResetCredits, .claudeResetCredits: return L("Limit Reset Credits")
        case .claudeExtraUsage: return L("Extra usage")
        case .subscription: return L("Plan renewal / expiry")
        default:
            if let detailSectionTitle {
                return L(detailSectionTitle)
            }
            guard let metricID = self.metricID else { return self.rawValue }
            if metricID == "claude-routines" {
                return L("Daily Routines")
            }

            let providerPrefix = "\(provider.rawValue)-"
            let displayID = metricID.hasPrefix(providerPrefix)
                ? String(metricID.dropFirst(providerPrefix.count))
                : metricID
            return displayID
                .split(separator: "-")
                .map { component in
                    component.prefix(1).uppercased() + component.dropFirst()
                }
                .joined(separator: " ")
        }
    }
}

extension UsageMenuCardView.Model {
    var quotaSubscriptionNotes: [String] {
        // Provider-specific by design: Codex and Claude report quota subscription dates separately from supplemental
        // notes.
        self.provider == .codex || self.provider == .claude ? self.subscriptionNotes : []
    }

    var supplementalUsageNotes: [String] {
        self.usageNotes.filter { !self.quotaSubscriptionNotes.contains($0) }
    }

    @MainActor
    var usageItemDescriptors: [ProviderUsageItemDescriptor] {
        var descriptors = self.metrics.map { metric in
            let itemID: ProviderUsageItemID = self.provider == .claude && metric.id == "claude-extra-usage"
                ? .claudeExtraUsage
                : .metric(metric.id)
            return ProviderUsageItemDescriptor(
                id: itemID,
                title: UsageMenuCardView.popupMetricTitle(provider: self.provider, metric: metric),
                requiresOptionalUsage: itemID.requiresOptionalUsage(for: self.provider))
        }
        if !self.quotaSubscriptionNotes.isEmpty {
            descriptors.append(.init(id: .subscription, title: L("Plan renewal / expiry")))
        }
        // Provider-specific by design: the shared reset-credit presentation keeps distinct saved Claude and Codex/Grok
        // visibility choices.
        if self.codexResetCredits != nil {
            if self.provider == .claude {
                descriptors.append(.init(id: .claudeResetCredits, title: L("Limit Reset Credits")))
            } else if self.provider == .codex || self.provider == .grok {
                descriptors.append(.init(id: .codexResetCredits, title: L("Limit Reset Credits")))
            }
        }
        if self.creditsText != nil {
            descriptors.append(ProviderUsageItemDescriptor(
                id: .credits, title: L("Credits"), requiresOptionalUsage: true))
        }
        let costSummaryTitles = ProviderDescriptorRegistry
            .descriptor(for: self.provider).presentation.optionalDetails.costSummaryTitles
        descriptors.append(contentsOf: zip(self.providerDetails, self.providerDetailRawTitles)
            .compactMap { section, rawTitle in
                guard let rawTitle,
                      let title = section.title,
                      !costSummaryTitles.contains(rawTitle)
                else { return nil }
                let itemID = ProviderUsageItemID.detailSection(rawTitle)
                return ProviderUsageItemDescriptor(
                    id: itemID,
                    title: title,
                    requiresOptionalUsage: itemID.requiresOptionalUsage(for: self.provider))
            })

        // Claude cloud credits have their own inline balance row instead of a generic details section.
        if let cloudCredits = self.cloudCredits {
            descriptors.append(ProviderUsageItemDescriptor(
                id: .detailSection(ClaudeCloudCreditsSnapshot.detailTitle),
                title: cloudCredits.title,
                requiresOptionalUsage: true))
        }
        // Provider-specific by design: Claude financial extra usage uses the same stable visibility ID as its meter.
        if self.provider == .claude, let cost = self.providerCost,
           cost.title == L("Extra usage") || cost.title == L("Credits")
        {
            descriptors.append(.init(id: .claudeExtraUsage, title: cost.title, requiresOptionalUsage: true))
        }

        var seen = Set<ProviderUsageItemID>()
        return descriptors.filter { seen.insert($0.id).inserted }
    }

    /// Include stored hidden choices when a temporary outage or plan change stops reporting them.
    @MainActor
    func usageItemDescriptors(
        includingHidden hiddenItemIDs: Set<ProviderUsageItemID>,
        hidePersonalInfo: Bool = false) -> [ProviderUsageItemDescriptor]
    {
        var descriptors = self.usageItemDescriptors
        guard !hiddenItemIDs.isEmpty else { return descriptors }

        let reported = Set(descriptors.map(\.id))
        for itemID in hiddenItemIDs.subtracting(reported).sorted(by: { $0.rawValue < $1.rawValue }) {
            let rawTitle = itemID.unreportedTitle(for: self.provider)
            let title = PersonalInfoRedactor.redactEmails(in: rawTitle, isEnabled: hidePersonalInfo) ?? rawTitle
            descriptors.append(ProviderUsageItemDescriptor(
                id: itemID,
                title: L("%@ (unavailable)", title),
                requiresOptionalUsage: itemID.requiresOptionalUsage(for: self.provider)))
        }
        return descriptors
    }

    func applyingUsageItemVisibility(hiddenItemIDs: Set<ProviderUsageItemID>) -> Self {
        guard !hiddenItemIDs.isEmpty else { return self }
        var projected = self
        // Provider-specific by design: preserve independent Claude financial and reset-credit choices alongside
        // Codex/Grok reset credits.
        projected.metrics.removeAll { metric in
            hiddenItemIDs.contains(.metric(metric.id)) ||
                (self.provider == .claude && metric.id == "claude-extra-usage" &&
                    hiddenItemIDs.contains(.claudeExtraUsage))
        }
        if hiddenItemIDs.contains(.credits) {
            projected.creditsText = nil
            projected.creditsRemaining = nil
            projected.creditsProgressPercent = nil
            projected.creditsScaleText = nil
            projected.creditsHintText = nil
            projected.creditsHintCopyText = nil
        }
        if self.provider == .claude, hiddenItemIDs.contains(.claudeExtraUsage),
           let cost = self.providerCost, cost.title == L("Extra usage") || cost.title == L("Credits")
        {
            projected.providerCost = nil
        }
        if hiddenItemIDs.contains(.subscription), !self.quotaSubscriptionNotes.isEmpty {
            projected.usageNotes.removeAll { self.subscriptionNotes.contains($0) }
            projected.subscriptionNotes = []
        }
        if (self.provider == .claude && hiddenItemIDs.contains(.claudeResetCredits)) ||
            ((self.provider == .codex || self.provider == .grok) && hiddenItemIDs.contains(.codexResetCredits))
        {
            projected.codexResetCredits = nil
        }
        if hiddenItemIDs.contains(.detailSection(ClaudeCloudCreditsSnapshot.detailTitle)) {
            projected.cloudCredits = nil
            // A quota-unavailable placeholder can be synthesized alongside an otherwise empty
            // Cloud credits-only snapshot. Hiding that sole optional item should leave no card,
            // while a truly quota-less snapshot without Cloud credits keeps its message.
            let hidReportedCloudCredits = self.provider == .claude && self.cloudCredits != nil
            if hidReportedCloudCredits,
               projected.placeholder != nil,
               !projected.hasUsageContentAboveCloudCredits,
               projected.openAIAPIUsage == nil,
               projected.providerCost == nil,
               projected.tokenUsage == nil,
               projected.creditsText == nil,
               projected.creditsRemaining == nil
            {
                projected.placeholder = nil
            }
        }
        let hiddenSectionIDs = Set(hiddenItemIDs.filter { $0.detailSectionTitle != nil })
        if !hiddenSectionIDs.isEmpty {
            let kept = self.providerDetails.enumerated().compactMap { index, section
                -> (section: ProviderDetailSection, rawTitle: String?)? in
                let rawTitle = self.providerDetailRawTitles.indices.contains(index)
                    ? self.providerDetailRawTitles[index] : nil
                guard rawTitle.map({ !hiddenSectionIDs.contains(.detailSection($0)) }) ?? true else { return nil }
                return (section, rawTitle)
            }
            projected.providerDetails = kept.map(\.section)
            projected.providerDetailRawTitles = kept.map(\.rawTitle)
        }
        return projected
    }
}

extension SettingsStore {
    func hiddenUsageItemIDs(for provider: UsageProvider) -> Set<ProviderUsageItemID> {
        if let storedIDs = self.providerConfig(for: provider)?.hiddenUsageItemIDs {
            return Set(storedIDs.map { rawID in
                let itemID = ProviderUsageItemID(rawValue: rawID)
                // Provider-specific by design: migrate legacy Claude reset-credit choices from the formerly shared
                // Codex ID.
                if provider == .claude, itemID == .codexResetCredits { return .claudeResetCredits }
                if let rawTitle = itemID.detailSectionTitle {
                    return .detailSection(rawTitle)
                }
                return itemID
            })
        }

        var hiddenIDs = Self.defaultHiddenUsageItemIDs(for: provider)
        // Provider-specific by design: preserve choices from versions with the two legacy toggles.
        if provider == .codex, !self.codexSparkUsageVisible {
            hiddenIDs.insert(.metric("codex-spark"))
            hiddenIDs.insert(.metric("codex-spark-weekly"))
        }
        if provider == .claude, !self.claudeDailyRoutinesUsageVisible {
            hiddenIDs.insert(.metric("claude-routines"))
        }
        return hiddenIDs
    }

    func isUsageItemVisible(_ itemID: ProviderUsageItemID, for provider: UsageProvider) -> Bool {
        !self.hiddenUsageItemIDs(for: provider).contains(itemID)
    }

    func hasCustomUsageItemVisibility(for provider: UsageProvider) -> Bool {
        self.hiddenUsageItemIDs(for: provider) != Self.defaultHiddenUsageItemIDs(for: provider)
    }

    private static func defaultHiddenUsageItemIDs(for provider: UsageProvider) -> Set<ProviderUsageItemID> {
        Set(ProviderDescriptorRegistry.descriptor(for: provider).presentation.menuCard.defaultHiddenUsageItemIDs
            .map(ProviderUsageItemID.init(rawValue:)))
    }

    func setUsageItemVisible(
        _ isVisible: Bool,
        itemID: ProviderUsageItemID,
        for provider: UsageProvider)
    {
        var hiddenIDs = self.hiddenUsageItemIDs(for: provider)
        let changed = if isVisible {
            hiddenIDs.remove(itemID) != nil
        } else {
            hiddenIDs.insert(itemID).inserted
        }
        guard changed else { return }

        self.persistHiddenUsageItemIDs(hiddenIDs, for: provider)
        self.updateLegacyUsageVisibility(provider: provider, hiddenItemIDs: hiddenIDs)
    }

    func restoreDefaultUsageItemVisibility(for provider: UsageProvider) {
        guard self.hasCustomUsageItemVisibility(for: provider) ||
            self.providerConfig(for: provider)?.hiddenUsageItemIDs == nil
        else { return }

        let defaultIDs = Self.defaultHiddenUsageItemIDs(for: provider)
        self.persistHiddenUsageItemIDs(defaultIDs, for: provider)
        self.updateLegacyUsageVisibility(provider: provider, hiddenItemIDs: defaultIDs)
    }

    private func persistHiddenUsageItemIDs(
        _ hiddenItemIDs: Set<ProviderUsageItemID>,
        for provider: UsageProvider)
    {
        let rawIDs = hiddenItemIDs.map(\.rawValue).sorted()
        self.updateProviderConfig(provider: provider, affectsBackgroundWork: false) { entry in
            entry.hiddenUsageItemIDs = rawIDs
        }
    }

    private func updateLegacyUsageVisibility(
        provider: UsageProvider,
        hiddenItemIDs: Set<ProviderUsageItemID>)
    {
        // Provider-specific by design: older QuotaKit versions use these keys for Codex Spark snapshots.
        if provider == .codex {
            let sparkIDs: Set<ProviderUsageItemID> = [
                .metric("codex-spark"),
                .metric("codex-spark-weekly"),
            ]
            self.codexSparkUsageVisible = !sparkIDs.isSubset(of: hiddenItemIDs)
        }
        if provider == .claude {
            self.claudeDailyRoutinesUsageVisible = !hiddenItemIDs.contains(.metric("claude-routines"))
        }
    }
}
