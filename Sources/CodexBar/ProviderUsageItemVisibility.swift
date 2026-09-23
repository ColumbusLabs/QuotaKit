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
}

extension ProviderUsageItemID {
    /// Label used while an item is hidden but the provider is not currently reporting it.
    func unreportedTitle(for provider: UsageProvider) -> String {
        switch self {
        case .credits: return L("Credits")
        case .codexResetCredits: return L("Limit Reset Credits")
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
    @MainActor
    var usageItemDescriptors: [ProviderUsageItemDescriptor] {
        var descriptors = self.metrics.map { metric in
            ProviderUsageItemDescriptor(
                id: .metric(metric.id),
                title: UsageMenuCardView.popupMetricTitle(provider: self.provider, metric: metric))
        }
        // Provider-specific by design: reset credits are a non-metric section with their own visibility choice.
        if self.provider == .codex, self.codexResetCredits != nil {
            descriptors.append(ProviderUsageItemDescriptor(
                id: .codexResetCredits,
                title: L("Limit Reset Credits")))
        }
        if self.creditsText != nil {
            descriptors.append(ProviderUsageItemDescriptor(id: .credits, title: L("Credits")))
        }
        let costSummaryTitles = ProviderDescriptorRegistry
            .descriptor(for: self.provider).presentation.optionalDetails.costSummaryTitles
        descriptors.append(contentsOf: zip(self.providerDetails, self.providerDetailRawTitles)
            .compactMap { section, rawTitle in
                guard let rawTitle,
                      let title = section.title,
                      !costSummaryTitles.contains(rawTitle)
                else { return nil }
                return ProviderUsageItemDescriptor(id: .detailSection(rawTitle), title: title)
            })

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
                title: L("%@ (unavailable)", title)))
        }
        return descriptors
    }

    func applyingUsageItemVisibility(hiddenItemIDs: Set<ProviderUsageItemID>) -> Self {
        guard !hiddenItemIDs.isEmpty else { return self }
        var projected = self
        projected.metrics.removeAll { hiddenItemIDs.contains(.metric($0.id)) }
        if hiddenItemIDs.contains(.credits) {
            projected.creditsText = nil
            projected.creditsRemaining = nil
            projected.creditsProgressPercent = nil
            projected.creditsScaleText = nil
            projected.creditsHintText = nil
            projected.creditsHintCopyText = nil
        }
        if hiddenItemIDs.contains(.codexResetCredits) {
            projected.codexResetCredits = nil
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
                if let rawTitle = itemID.detailSectionTitle {
                    return .detailSection(rawTitle)
                }
                return itemID
            })
        }

        var hiddenIDs = Set<ProviderUsageItemID>()
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
        guard !self.hiddenUsageItemIDs(for: provider).isEmpty ||
            self.providerConfig(for: provider)?.hiddenUsageItemIDs == nil
        else { return }

        self.persistHiddenUsageItemIDs([], for: provider)
        self.updateLegacyUsageVisibility(provider: provider, hiddenItemIDs: [])
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
