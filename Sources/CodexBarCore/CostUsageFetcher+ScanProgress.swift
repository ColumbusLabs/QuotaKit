import Foundation

extension CostUsageFetcher {
    // swiftlint:disable:next function_body_length
    static func codexScanProgressKey(
        cache: CostUsageCache,
        scopedFiles: [String: CostUsageFileUsage]) -> String
    {
        var progressHasher = Hasher()
        progressHasher.combine(cache.codexScanCompletedFiles)

        for (path, usage) in scopedFiles.sorted(by: { $0.key < $1.key }) {
            progressHasher.combine(path)
            progressHasher.combine(usage.codexScanFileId)
            progressHasher.combine(usage.codexScanComplete)
            if usage.codexScanComplete == false {
                progressHasher.combine(usage.parsedBytes)
                progressHasher.combine(usage.size)
                progressHasher.combine(usage.codexJSONLResumeState?.offset)
            }
            let hasBufferedRetry = usage.hasBufferedCodexForkRetryLines
            progressHasher.combine(hasBufferedRetry)
            if hasBufferedRetry {
                progressHasher.combine(usage.forkedFromId)
                progressHasher.combine(usage.forkBaselineDependencyKey)
                progressHasher.combine(usage.codexBufferedSubagentLines?.isEmpty == false)
                progressHasher.combine(usage.codexBufferedUnresolvedForkLines?.isEmpty == false)
            }
        }

        if let discovery = cache.codexSessionDiscovery {
            progressHasher.combine(discovery.generation)
            progressHasher.combine(discovery.directoryPaths.count)
            progressHasher.combine(discovery.nextDirectoryIndex)
            progressHasher.combine(discovery.filePaths.count)
            progressHasher.combine(discovery.nextFileIndex)
            progressHasher.combine(discovery.headScan?.path)
            progressHasher.combine(discovery.headScan?.offset)
            progressHasher.combine(discovery.headScan?.resumeState?.offset)
            progressHasher.combine(discovery.filePathBySessionId.count)
            progressHasher.combine(discovery.missingSessionIds.sorted())
            progressHasher.combine(discovery.pendingSessionIds.sorted())
            progressHasher.combine(discovery.validationDirectoryIndex)
            progressHasher.combine(discovery.isComplete)
        } else {
            progressHasher.combine("no-discovery")
        }

        if let lookback = cache.codexActiveLookbackState {
            progressHasher.combine(lookback.scanSinceKey)
            progressHasher.combine(lookback.rootPaths.sorted())
            progressHasher.combine("next-day")
            for (root, dayKey) in lookback.nextDayKeyByRoot.sorted(by: { $0.key < $1.key }) {
                progressHasher.combine(root)
                progressHasher.combine(dayKey)
            }
            progressHasher.combine("next-directory-offset")
            progressHasher.combine(lookback.nextDirectoryOffsetByRoot == nil)
            for (root, offset) in (lookback.nextDirectoryOffsetByRoot ?? [:]).sorted(by: { $0.key < $1.key }) {
                progressHasher.combine(root)
                progressHasher.combine(offset)
            }
            progressHasher.combine(lookback.completedRootPaths.sorted())
            progressHasher.combine(lookback.pendingFilePaths.sorted())
            progressHasher.combine(lookback.legacyRecursivePendingRootPaths.sorted())
            progressHasher.combine("current-window-next-day")
            progressHasher.combine(lookback.currentWindowNextDayKeyByRoot == nil)
            for (root, dayKey) in (lookback.currentWindowNextDayKeyByRoot ?? [:]).sorted(by: { $0.key < $1.key }) {
                progressHasher.combine(root)
                progressHasher.combine(dayKey)
            }
            progressHasher.combine("current-window-directory-offset")
            progressHasher.combine(lookback.currentWindowDirectoryOffsetByRoot == nil)
            for (root, offset) in (lookback.currentWindowDirectoryOffsetByRoot ?? [:])
                .sorted(by: { $0.key < $1.key })
            {
                progressHasher.combine(root)
                progressHasher.combine(offset)
            }
            progressHasher.combine("completed-current-window-roots")
            progressHasher.combine(lookback.completedCurrentWindowRootPaths == nil)
            progressHasher.combine((lookback.completedCurrentWindowRootPaths ?? []).sorted())
            progressHasher.combine("current-window-flat-directory-offset")
            progressHasher.combine(lookback.currentWindowFlatDirectoryOffsetByRoot == nil)
            for (root, offset) in (lookback.currentWindowFlatDirectoryOffsetByRoot ?? [:])
                .sorted(by: { $0.key < $1.key })
            {
                progressHasher.combine(root)
                progressHasher.combine(offset)
            }
            progressHasher.combine("completed-current-window-flat-roots")
            progressHasher.combine(lookback.completedCurrentWindowFlatRootPaths == nil)
            progressHasher.combine((lookback.completedCurrentWindowFlatRootPaths ?? []).sorted())
            progressHasher.combine(lookback.directoryCursorVersion)
            for (cursor, names) in (lookback.directoryPendingNamesByCursor ?? [:])
                .sorted(by: { $0.key < $1.key })
            {
                progressHasher.combine(cursor)
                progressHasher.combine(names)
            }
            progressHasher.combine("legacy-recursive-directories")
            for (root, paths) in (lookback.legacyRecursiveDirectoryPathsByRoot ?? [:])
                .sorted(by: { $0.key < $1.key })
            {
                progressHasher.combine(root)
                progressHasher.combine(paths)
            }
            progressHasher.combine("legacy-recursive-offsets")
            for (path, offset) in (lookback.legacyRecursiveDirectoryOffsetByPath ?? [:])
                .sorted(by: { $0.key < $1.key })
            {
                progressHasher.combine(path)
                progressHasher.combine(offset)
            }
            progressHasher.combine("exact-inventory-roots")
            progressHasher.combine(lookback.exactInventoryPendingRootPaths)
            progressHasher.combine("exact-inventory-directories")
            for (root, paths) in (lookback.exactInventoryDirectoryPathsByRoot ?? [:])
                .sorted(by: { $0.key < $1.key })
            {
                progressHasher.combine(root)
                progressHasher.combine(paths)
            }
            progressHasher.combine("exact-inventory-offsets")
            for (path, offset) in (lookback.exactInventoryDirectoryOffsetByPath ?? [:])
                .sorted(by: { $0.key < $1.key })
            {
                progressHasher.combine(path)
                progressHasher.combine(offset)
            }
            progressHasher.combine(lookback.exactInventoryVisitedDirectoryPaths?.count)
            progressHasher.combine("exact-validation")
            progressHasher.combine(lookback.exactValidationPaths?.count)
            progressHasher.combine(lookback.exactValidationNextIndex)
            progressHasher.combine(lookback.exactValidationProcessedBytes)
            progressHasher.combine(lookback.exactValidationTotalBytes)
            progressHasher.combine(lookback.exactValidationCompletedFiles)
            progressHasher.combine(lookback.exactValidationTotalFiles)
            progressHasher.combine(lookback.exactValidationSeenIdentities?.count)
            progressHasher.combine(lookback.exactValidationInventoryPaths?.count)
            progressHasher.combine(lookback.exactInventoryGeneration)
            progressHasher.combine(lookback.exactInventoryScanSinceKey)
            progressHasher.combine(lookback.exactInventoryScanUntilKey)
            for (root, day) in (lookback.exactInventoryNextDayKeyByRoot ?? [:]).sorted(by: { $0.key < $1.key }) {
                progressHasher.combine(root)
                progressHasher.combine(day)
            }
            for (root, offset) in (lookback.exactInventoryDirectoryOffsetByRoot ?? [:])
                .sorted(by: { $0.key < $1.key })
            {
                progressHasher.combine(root)
                progressHasher.combine(offset)
            }
            progressHasher.combine(lookback.exactInventoryCompletedRootPaths)
            for (root, offset) in (lookback.exactInventoryFlatDirectoryOffsetByRoot ?? [:])
                .sorted(by: { $0.key < $1.key })
            {
                progressHasher.combine(root)
                progressHasher.combine(offset)
            }
            progressHasher.combine(lookback.exactInventoryCompletedFlatRootPaths)
            progressHasher.combine(lookback.exactCachedValidationLastPath)
            progressHasher.combine(lookback.cacheWideMigrationQueueActive)
        } else {
            progressHasher.combine("no-lookback")
        }

        if let inventoryPaths = cache.codexScanInventoryPaths {
            progressHasher.combine("inventory")
            progressHasher.combine(inventoryPaths.sorted())
        } else {
            progressHasher.combine("no-inventory")
        }

        return "v2:\(scopedFiles.count):\(progressHasher.finalize())"
    }
}
