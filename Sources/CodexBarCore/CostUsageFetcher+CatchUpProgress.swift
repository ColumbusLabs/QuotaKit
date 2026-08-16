import Foundation

extension CostUsageFetcher {
    static func codexScanProgressKey(
        projection: CostUsageStoreCatchUpProjection,
        scopedFiles: [CostUsageStoreCatchUpFile]) -> String
    {
        var progressHasher = Hasher()
        progressHasher.combine(projection.completedFiles)
        progressHasher.combine(projection.processedBytes)

        for file in scopedFiles.sorted(by: { $0.path < $1.path }) {
            progressHasher.combine(file.path)
            progressHasher.combine(file.fileIdentity)
            progressHasher.combine(file.scanComplete)
            if !file.scanComplete {
                progressHasher.combine(file.parsedBytes)
                progressHasher.combine(file.size)
                progressHasher.combine(file.scanTargetSize)
                progressHasher.combine(file.resumeOffset)
            }
            let hasBufferedRetry = file.hasBufferedForkRetryLines
            progressHasher.combine(hasBufferedRetry)
            if hasBufferedRetry {
                progressHasher.combine(file.forkedFromID)
                progressHasher.combine(file.forkBaselineDependencyKey)
                progressHasher.combine(file.hasBufferedSubagentLines)
                progressHasher.combine(file.hasBufferedUnresolvedForkLines)
            }
        }

        progressHasher.combine(self.codexScanProgressStateData(projection.discoveryState))
        if let discoveryPayload = projection.discoveryState?.payload,
           let discovery = try? JSONDecoder().decode(
               CostUsageCodexSessionDiscovery.self,
               from: discoveryPayload)
        {
            progressHasher.combine(discovery.headScan?.path)
            progressHasher.combine(discovery.headScan?.offset)
            progressHasher.combine(discovery.headScan?.resumeState?.offset)
        }
        progressHasher.combine(self.codexScanProgressStateData(projection.lookbackState))
        if let inventoryPaths = projection.scanInventoryPaths {
            progressHasher.combine("inventory")
            progressHasher.combine(inventoryPaths.sorted())
        } else {
            progressHasher.combine("no-inventory")
        }

        return "v3:\(scopedFiles.count):\(progressHasher.finalize())"
    }

    private static func codexScanProgressStateData(
        _ state: CostUsageStoreDiscoveryState?) -> Data?
    {
        guard var state else { return nil }
        state.payload = nil
        return self.codexScanProgressStateData(state)
    }

    private static func codexScanProgressStateData(
        _ state: CostUsageStoreLookbackState?) -> Data?
    {
        guard let state else { return nil }
        return self.codexScanProgressStateData(state)
    }

    private static func codexScanProgressStateData(_ state: some Encodable) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(state)
    }
}
