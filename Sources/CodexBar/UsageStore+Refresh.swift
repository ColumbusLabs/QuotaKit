import CodexBarCore
import Foundation

extension UsageStore {
    func restartAugmentKeepaliveIfNeeded() {
        #if os(macOS)
        let shouldRun = self.isEnabled(.augment)
        let isRunning = self.augmentKeepalive != nil

        if shouldRun, !isRunning {
            self.startAugmentKeepalive()
        } else if !shouldRun, isRunning {
            Task { @MainActor in
                self.augmentKeepalive?.stop()
                self.augmentKeepalive = nil
                self.augmentLogger.info("Augment keepalive stopped (provider disabled)")
            }
        }
        #endif
    }

    func startAugmentKeepalive() {
        #if os(macOS)
        self.augmentLogger.info(
            "Augment keepalive check",
            metadata: [
                "enabled": self.isEnabled(.augment) ? "1" : "0",
                "available": self.isProviderAvailable(.augment) ? "1" : "0",
            ])

        // Only start keepalive if Augment is enabled
        guard self.isEnabled(.augment) else {
            self.augmentLogger.warning("Augment keepalive not started (provider disabled)")
            return
        }

        let logger: (String) -> Void = { [augmentLogger = self.augmentLogger] message in
            augmentLogger.verbose(message)
        }

        // Callback to refresh Augment usage after successful session recovery
        let onSessionRecovered: () async -> Void = { [weak self] in
            guard let self else { return }
            self.augmentLogger.info("Augment session recovered; refreshing usage")
            await self.refreshProvider(.augment)
        }

        self.augmentKeepalive = AugmentSessionKeepalive(logger: logger, onSessionRecovered: onSessionRecovered)
        self.augmentKeepalive?.start()
        self.augmentLogger.info("Augment keepalive started")
        #endif
    }

    /// Force refresh Augment session (called from UI button)
    func forceRefreshAugmentSession() async {
        #if os(macOS)
        self.augmentLogger.info("Augment force refresh requested")
        guard let keepalive = self.augmentKeepalive else {
            self.augmentLogger.warning("Augment keepalive not running; starting")
            self.startAugmentKeepalive()
            // Give it a moment to start
            try? await Task.sleep(for: .seconds(1))
            guard let keepalive = self.augmentKeepalive else {
                self.augmentLogger.error("Augment keepalive failed to start")
                return
            }
            await keepalive.forceRefresh()
            return
        }

        await keepalive.forceRefresh()

        // Refresh usage after forcing session refresh
        self.augmentLogger.info("Refreshing Augment usage after session refresh")
        await self.refreshProvider(.augment)
        #endif
    }

    func refreshProvider(_ provider: UsageProvider, allowDisabled: Bool = false) async {
        guard let spec = self.providerSpecs[provider] else { return }

        if !spec.isEnabled(), !allowDisabled {
            self.refreshingProviders.remove(provider)
            await MainActor.run {
                self.snapshots.removeValue(forKey: provider)
                self.errors[provider] = nil
                self.lastSourceLabels.removeValue(forKey: provider)
                self.lastFetchAttempts.removeValue(forKey: provider)
                self.accountSnapshots.removeValue(forKey: provider)
                self.tokenSnapshots.removeValue(forKey: provider)
                self.tokenErrors[provider] = nil
                self.failureGates[provider]?.reset()
                self.tokenFailureGates[provider]?.reset()
                self.statuses.removeValue(forKey: provider)
                self.lastKnownSessionRemaining.removeValue(forKey: provider)
                self.lastTokenFetchAt.removeValue(forKey: provider)
            }
            return
        }

        self.refreshingProviders.insert(provider)
        defer { self.refreshingProviders.remove(provider) }

        let tokenAccounts = self.tokenAccounts(for: provider)
        if self.shouldFetchAllTokenAccounts(provider: provider, accounts: tokenAccounts) {
            await self.refreshTokenAccounts(provider: provider, accounts: tokenAccounts)
            return
        } else {
            _ = await MainActor.run {
                self.accountSnapshots.removeValue(forKey: provider)
            }
        }

        let outcome = await spec.fetch()
        await MainActor.run {
            self.lastFetchAttempts[provider] = outcome.attempts
        }

        switch outcome.result {
        case let .success(result):
            let scoped = result.usage.scoped(to: provider)
            await MainActor.run {
                self.handleSessionQuotaTransition(provider: provider, snapshot: scoped)
                self.snapshots[provider] = scoped
                self.lastSourceLabels[provider] = result.sourceLabel
                self.errors[provider] = nil
                self.failureGates[provider]?.recordSuccess()
            }
        case let .failure(error):
            await MainActor.run {
                let hadPriorData = self.snapshots[provider] != nil
                let shouldSurface = self.failureGates[provider]?
                    .shouldSurfaceError(onFailureWithPriorData: hadPriorData) ?? true
                if shouldSurface {
                    self.errors[provider] = error.localizedDescription
                    self.snapshots.removeValue(forKey: provider)
                } else {
                    self.errors[provider] = nil
                }

                // Trigger immediate session recovery for Augment when session expires
                if provider == .augment, error.localizedDescription.contains("session expired") {
                    self.augmentLogger.warning("Augment session expired; triggering recovery")
                    Task {
                        await self.forceRefreshAugmentSession()
                    }
                }
            }
        }
    }
}
