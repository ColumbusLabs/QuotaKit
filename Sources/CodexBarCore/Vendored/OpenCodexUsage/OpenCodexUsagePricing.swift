import Foundation

enum OpenCodexUsagePricing {
    static func targets(for entry: OpenCodexUsageEntry) -> [ModelsDevPricingTarget] {
        let provider = self.providerID(for: entry)
        let targets = ModelsDevPricingTargetResolver.targets(providerID: provider, modelID: entry.model)
        guard let first = targets.first,
              first.providerID == CostUsagePricing.codexModelsDevProviderID,
              !first.modelID.contains("/")
        else { return targets }
        return CostUsagePricing.codexModelsDevPricingTargets(for: first.modelID).map {
            ModelsDevPricingTarget(providerID: $0.providerID, modelID: $0.modelID)
        }
    }

    static func providerID(for entry: OpenCodexUsageEntry) -> String {
        let provider = entry.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let model = entry.model.trimmingCharacters(in: .whitespacesAndNewlines)
        // Provider-specific by design: legacy OpenAI-labelled rows may carry the actual provider
        // in the model prefix, but current rows retain their explicitly recorded provider.
        if provider == "openai",
           let slash = model.firstIndex(of: "/")
        {
            let prefix = String(model[..<slash]).lowercased()
            if CostUsagePricing.codexModelsDevProviderIDs.contains(prefix) {
                return prefix
            }
        }
        if provider.isEmpty {
            if let slash = model.firstIndex(of: "/") {
                let prefix = String(model[..<slash]).lowercased()
                return CostUsagePricing.codexModelsDevProviderIDs.contains(prefix) ? prefix : ""
            }
            // Provider-specific by design: pre-provider records without a route retain the legacy
            // OpenAI estimate; current records never borrow those rates from another provider.
            return "openai"
        }
        return provider
    }
}

extension OpenCodexUsageStore {
    /// Fresh-load refresh only. Cached snapshots remain synchronous and never start network work.
    public static func refreshPricingIfNeeded(entries: [OpenCodexUsageEntry], now: Date) async {
        guard !ProviderHTTPClient.isRunningTests else { return }
        await self.refreshPricingIfNeeded(entries: entries, now: now, cacheRoot: nil, client: ModelsDevClient())
    }

    static func refreshPricingIfNeeded(
        entries: [OpenCodexUsageEntry],
        now: Date,
        cacheRoot: URL?,
        client: ModelsDevClient) async
    {
        let targets = Set(entries.filter {
            $0.timestamp <= now && ($0.usageStatus == .reported || $0.usageStatus == .estimated)
        }.flatMap { OpenCodexUsagePricing.targets(for: $0) })
        guard !targets.isEmpty, !Task.isCancelled else { return }
        await ModelsDevPricingPipeline.refreshIfNeeded(now: now, cacheRoot: cacheRoot, client: client)
        let grouped = Dictionary(grouping: targets, by: \.providerID)
        for providerID in grouped.keys.sorted() {
            guard !Task.isCancelled else { return }
            _ = await ModelsDevPricingPipeline.refreshForUnknownModelsIfNeeded(
                providerID: providerID,
                modelIDs: Set(grouped[providerID, default: []].map(\.modelID)),
                exactModelIDs: true,
                now: now,
                cacheRoot: cacheRoot,
                client: client)
        }
    }
}
