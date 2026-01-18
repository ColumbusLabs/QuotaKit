import CodexBarCore
import Foundation

extension SettingsStore {
    func orderedProviders() -> [UsageProvider] {
        let raw = self.providerOrderRaw
        if raw == self.cachedProviderOrderRaw, !self.cachedProviderOrder.isEmpty {
            return self.cachedProviderOrder
        }
        let ordered = Self.effectiveProviderOrder(raw: raw)
        self.cachedProviderOrderRaw = raw
        self.cachedProviderOrder = ordered
        return ordered
    }

    func moveProvider(fromOffsets: IndexSet, toOffset: Int) {
        var order = self.orderedProviders()
        order.move(fromOffsets: fromOffsets, toOffset: toOffset)
        self.providerOrderRaw = order.map(\.rawValue)
    }

    func isProviderEnabled(provider: UsageProvider, metadata: ProviderMetadata) -> Bool {
        _ = self.providerToggleRevision
        return self.toggleStore.isEnabled(metadata: metadata)
    }

    func isProviderEnabledCached(
        provider: UsageProvider,
        metadataByProvider: [UsageProvider: ProviderMetadata]) -> Bool
    {
        self.refreshProviderEnablementCacheIfNeeded(metadataByProvider: metadataByProvider)
        return self.cachedProviderEnablement[provider] ?? false
    }

    func enabledProvidersOrdered(metadataByProvider: [UsageProvider: ProviderMetadata]) -> [UsageProvider] {
        self.refreshProviderEnablementCacheIfNeeded(metadataByProvider: metadataByProvider)
        let orderRaw = self.providerOrderRaw
        let revision = self.cachedProviderEnablementRevision
        if revision == self.cachedEnabledProvidersRevision,
           orderRaw == self.cachedEnabledProvidersOrderRaw,
           !self.cachedEnabledProviders.isEmpty
        {
            return self.cachedEnabledProviders
        }
        let enabled = self.orderedProviders().filter { self.cachedProviderEnablement[$0] ?? false }
        self.cachedEnabledProviders = enabled
        self.cachedEnabledProvidersRevision = revision
        self.cachedEnabledProvidersOrderRaw = orderRaw
        return enabled
    }

    func setProviderEnabled(provider: UsageProvider, metadata: ProviderMetadata, enabled: Bool) {
        self.providerToggleRevision &+= 1
        self.toggleStore.setEnabled(enabled, metadata: metadata)
    }

    func rerunProviderDetection() {
        self.runInitialProviderDetectionIfNeeded(force: true)
    }

    // MARK: - Private

    func isCostUsageEffectivelyEnabled(for provider: UsageProvider) -> Bool {
        self.costUsageEnabled
            && ProviderDescriptorRegistry.descriptor(for: provider).tokenCost.supportsTokenCost
    }

    private static func effectiveProviderOrder(raw: [String]) -> [UsageProvider] {
        var seen: Set<UsageProvider> = []
        var ordered: [UsageProvider] = []

        for rawValue in raw {
            guard let provider = UsageProvider(rawValue: rawValue) else { continue }
            guard !seen.contains(provider) else { continue }
            seen.insert(provider)
            ordered.append(provider)
        }

        if ordered.isEmpty {
            ordered = UsageProvider.allCases
            seen = Set(ordered)
        }

        if !seen.contains(.factory), let zaiIndex = ordered.firstIndex(of: .zai) {
            ordered.insert(.factory, at: zaiIndex)
            seen.insert(.factory)
        }

        if !seen.contains(.minimax), let zaiIndex = ordered.firstIndex(of: .zai) {
            let insertIndex = ordered.index(after: zaiIndex)
            ordered.insert(.minimax, at: insertIndex)
            seen.insert(.minimax)
        }

        for provider in UsageProvider.allCases where !seen.contains(provider) {
            ordered.append(provider)
        }

        return ordered
    }

    private func refreshProviderEnablementCacheIfNeeded(
        metadataByProvider: [UsageProvider: ProviderMetadata])
    {
        let revision = self.providerToggleRevision
        guard revision != self.cachedProviderEnablementRevision else { return }
        var cache: [UsageProvider: Bool] = [:]
        for (provider, metadata) in metadataByProvider {
            cache[provider] = self.toggleStore.isEnabled(metadata: metadata)
        }
        self.cachedProviderEnablement = cache
        self.cachedProviderEnablementRevision = revision
    }
}
