import CodexBarCore
import Foundation

@MainActor
extension UsageStore {
    func handleQuotaWarningTransitions(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        accountDiscriminator: String? = nil)
    {
        let notificationsEnabled = self.settings.quotaWarningNotificationsEnabled
        // Hooks have their own enable switch and per-rule thresholds, so quota_low
        // hooks run on a separate path that does not depend on the notification
        // preference or the notification thresholds.
        self.resetQuotaLowHookUsageIfConfigurationChanged()
        let hooksActive = self.hasQuotaHookRule(event: .quotaLow, provider: provider)
        if !hooksActive {
            self.clearQuotaLowHookUsage(provider: provider)
        }
        guard notificationsEnabled || hooksActive else { return }
        if provider == .commandcode, snapshot.commandCodeSubscriptionEnrichmentUnavailable {
            return
        }

        let account = QuotaWarningAccountContext(
            displayName: self.quotaWarningAccountDisplayName(provider: provider, snapshot: snapshot),
            discriminator: self.quotaWarningAccountDiscriminator(
                provider: provider,
                snapshot: snapshot,
                accountDiscriminatorOverride: accountDiscriminator))
        let source: SessionQuotaWindowSource? = if provider == .antigravity {
            Self.hasAntigravityQuotaSummaryWindows(snapshot: snapshot)
                ? .antigravityQuotaSummary
                : .antigravityLegacy
        } else {
            nil
        }
        let primaryWindow: RateWindow?
        let secondaryWindow: RateWindow?
        if provider == .antigravity {
            primaryWindow = Self.antigravityWindow(snapshot: snapshot, windowMinutes: 5 * 60)
            secondaryWindow = Self.antigravityWindow(snapshot: snapshot, windowMinutes: 7 * 24 * 60)
        } else {
            // Crof credits-only accounts publish a duration-less balance as `primary`; a drained
            // prepaid balance is not a quota threshold crossing, so it must not raise warnings.
            // Crof accounts that do expose request quotas (secondary present) keep normal warnings.
            let isBalanceOnlyCrof = provider == .crof && snapshot.secondary == nil
            let suppressWindows = provider == .mimo || provider == .qoder || isBalanceOnlyCrof
            primaryWindow = suppressWindows ? nil : snapshot.primary
            secondaryWindow = suppressWindows ? nil : snapshot.secondary
        }
        let primaryWindowDisplayLabel = provider == .amp
            ? AmpProviderDescriptor.primaryLabel(details: snapshot.ampUsage)
            : nil
        let secondaryWindowDisplayLabel = provider == .amp
            ? AmpProviderDescriptor.secondaryLabel(details: snapshot.ampUsage)
            : nil
        if notificationsEnabled {
            self.handleQuotaWarningTransition(
                provider: provider,
                transition: QuotaWarningTransition(
                    window: .session,
                    rateWindow: primaryWindow,
                    source: source,
                    windowDisplayLabel: primaryWindowDisplayLabel),
                account: account)
            self.handleQuotaWarningTransition(
                provider: provider,
                transition: QuotaWarningTransition(
                    window: .weekly,
                    rateWindow: secondaryWindow,
                    source: source,
                    windowDisplayLabel: secondaryWindowDisplayLabel),
                account: account)
            self.handleClaudeExtraWindowQuotaWarnings(
                provider: provider,
                snapshot: snapshot,
                account: account)
        }

        if hooksActive {
            self.dispatchQuotaLowHooks(
                provider: provider,
                lane: QuotaLowHookLane(
                    window: .session,
                    windowID: nil,
                    label: primaryWindowDisplayLabel ?? QuotaWarningWindow.session.displayName),
                rateWindow: primaryWindow,
                accountDiscriminator: account.discriminator,
                accountDisplayName: account.displayName)
            self.dispatchQuotaLowHooks(
                provider: provider,
                lane: QuotaLowHookLane(
                    window: .weekly,
                    windowID: nil,
                    label: secondaryWindowDisplayLabel ?? QuotaWarningWindow.weekly.displayName),
                rateWindow: secondaryWindow,
                accountDiscriminator: account.discriminator,
                accountDisplayName: account.displayName)
            let extraWindows = provider == .claude
                ? (snapshot.extraRateWindows ?? []).filter(Self.isClaudeNotifiableExtraWindow)
                : []
            for named in extraWindows {
                self.dispatchQuotaLowHooks(
                    provider: provider,
                    lane: QuotaLowHookLane(window: .weekly, windowID: named.id, label: named.title),
                    rateWindow: named.window,
                    accountDiscriminator: account.discriminator,
                    accountDisplayName: account.displayName)
            }
            self.pruneQuotaLowHookUsage(
                provider: provider,
                accountDiscriminator: account.discriminator,
                keepingExtraWindowIDs: Set(extraWindows.map(\.id)))
        }
    }

    func handleQuotaWarningTransitions(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        accountDiscriminatorOverride: String?)
    {
        self.handleQuotaWarningTransitions(
            provider: provider,
            snapshot: snapshot,
            accountDiscriminator: accountDiscriminatorOverride)
    }

    /// Emit weekly-lane quota warnings for Claude's extra rate windows — model-scoped weekly
    /// carve-outs (`claude-weekly-scoped-*`, e.g. Fable) and Daily Routines — which surface in the
    /// menu but were otherwise silent. Antigravity's summary windows are already covered by the
    /// primary and weekly lanes above, so they are excluded here.
    private func handleClaudeExtraWindowQuotaWarnings(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        account: QuotaWarningAccountContext)
    {
        guard provider == .claude else { return }
        guard self.settings.quotaWarningEnabled(provider: provider, window: .weekly) else {
            self.clearQuotaWarningState(provider: provider, window: .weekly)
            return
        }

        let windows = (snapshot.extraRateWindows ?? []).filter(Self.isClaudeNotifiableExtraWindow)
        for named in windows {
            self.handleQuotaWarningTransition(
                provider: provider,
                transition: QuotaWarningTransition(
                    window: .weekly,
                    rateWindow: named.window,
                    source: nil,
                    windowID: named.id,
                    windowDisplayLabel: named.title),
                account: account)
        }
        // A missing extras payload is not authoritative, but when another notifiable window remains,
        // reconcile tracked IDs so a later incarnation of a disappeared window can warn again.
        guard !windows.isEmpty else { return }
        let activeIDs = Set(windows.map(\.id))
        let staleKeys = self.quotaWarningState.keys.filter { key in
            guard key.provider == provider,
                  key.accountDiscriminator == account.discriminator,
                  let windowID = key.windowID
            else { return false }
            return !activeIDs.contains(windowID)
        }
        for key in staleKeys {
            self.quotaWarningState.removeValue(forKey: key)
        }
    }

    private static func isClaudeNotifiableExtraWindow(_ named: NamedRateWindow) -> Bool {
        guard named.usageKnown else { return false }
        return named.id.hasPrefix("claude-weekly-scoped-") || named.id == "claude-routines"
    }

    private func clearQuotaWarningState(provider: UsageProvider, window: QuotaWarningWindow) {
        let keys = self.quotaWarningState.keys.filter {
            $0.provider == provider && $0.window == window
        }
        for key in keys {
            self.quotaWarningState.removeValue(forKey: key)
        }
    }

    private func handleQuotaWarningTransition(
        provider: UsageProvider,
        transition: QuotaWarningTransition,
        account: QuotaWarningAccountContext)
    {
        let key = QuotaWarningStateKey(
            provider: provider,
            window: transition.window,
            accountDiscriminator: account.discriminator,
            windowID: transition.windowID)
        guard self.settings.quotaWarningEnabled(provider: provider, window: transition.window) else {
            self.quotaWarningState = self.quotaWarningState.filter { existing in
                !(existing.key.provider == provider &&
                    existing.key.window == transition.window &&
                    existing.key.windowID == transition.windowID)
            }
            return
        }
        guard let rateWindow = transition.rateWindow else {
            if account.discriminator == nil {
                self.quotaWarningState = self.quotaWarningState.filter { existing in
                    !(existing.key.provider == provider &&
                        existing.key.window == transition.window &&
                        existing.key.windowID == transition.windowID)
                }
            } else {
                self.quotaWarningState.removeValue(forKey: key)
            }
            return
        }
        guard !rateWindow.isSyntheticPlaceholder else { return }

        let thresholds = self.settings.resolvedQuotaWarningThresholds(
            provider: provider,
            window: transition.window)
        let currentRemaining = rateWindow.remainingPercent
        let previousState = self.quotaWarningState[key]
        if let previousState, previousState.source != transition.source {
            self.quotaWarningState[key] = QuotaWarningState(
                lastRemaining: currentRemaining,
                source: transition.source)
            return
        }
        var state = previousState ?? QuotaWarningState(source: transition.source)
        let cleared = QuotaWarningNotificationLogic.thresholdsToClear(
            currentRemaining: currentRemaining,
            alreadyFired: state.firedThresholds)
        state.firedThresholds.subtract(cleared)

        if let threshold = QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: state.lastRemaining,
            currentRemaining: currentRemaining,
            thresholds: thresholds,
            alreadyFired: state.firedThresholds)
        {
            state.firedThresholds.formUnion(QuotaWarningNotificationLogic.firedThresholdsAfterWarning(
                threshold: threshold,
                thresholds: thresholds))
            self.postQuotaWarning(
                QuotaWarningEvent(
                    window: transition.window,
                    threshold: threshold,
                    currentRemaining: currentRemaining,
                    accountDisplayName: account.displayName,
                    accountDiscriminator: account.discriminator,
                    windowID: transition.windowID,
                    windowDisplayLabel: transition.windowDisplayLabel),
                provider: provider)
        }

        state.lastRemaining = currentRemaining
        self.quotaWarningState[key] = state
    }

    func quotaWarningAccountDisplayName(provider: UsageProvider, snapshot: UsageSnapshot) -> String? {
        guard !self.settings.hidePersonalInfo else { return nil }
        let account = snapshot.accountEmail(for: provider)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account, !account.isEmpty else { return nil }
        return account
    }

    func quotaWarningAccountDiscriminator(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        accountDiscriminatorOverride: String? = nil) -> String?
    {
        if let override = Self.normalizedQuotaWarningDiscriminatorValue(accountDiscriminatorOverride) {
            return override
        }
        if let organization = Self.normalizedQuotaWarningDiscriminatorValue(
            snapshot.accountOrganization(for: provider))
        {
            return "organization:\(organization)"
        }
        if let email = Self.normalizedQuotaWarningDiscriminatorValue(snapshot.accountEmail(for: provider)) {
            return "email:\(email)"
        }
        if let loginMethod = Self.normalizedQuotaWarningDiscriminatorValue(snapshot.loginMethod(for: provider)) {
            return "login:\(loginMethod)"
        }
        return nil
    }

    private static func normalizedQuotaWarningDiscriminatorValue(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

    func postQuotaWarning(_ event: QuotaWarningEvent, provider: UsageProvider) {
        self.sessionQuotaNotifier.postQuotaWarning(
            event: event,
            provider: provider,
            soundEnabled: self.settings.quotaWarningSoundEnabled,
            onScreenAlertEnabled: self.settings.quotaWarningOnScreenAlertEnabled)
        if self.settings.notificationPushToiOSEnabled {
            self.quotaTransitionWriter.writeQuotaWarning(
                provider: provider,
                window: event.window,
                threshold: event.threshold,
                accountDisplayName: event.accountDisplayName,
                accountDiscriminator: event.accountDiscriminator,
                windowID: event.windowID,
                windowDisplayLabel: event.windowDisplayLabel)
        }
    }

    func postPredictivePaceWarning(_ event: PredictivePaceWarningEvent, provider: UsageProvider, now: Date) {
        self.sessionQuotaNotifier.postPredictivePaceWarning(
            event: event,
            provider: provider,
            soundEnabled: self.settings.quotaWarningSoundEnabled,
            onScreenAlertEnabled: self.settings.quotaWarningOnScreenAlertEnabled,
            now: now)
    }

    // swiftlint:disable:next cyclomatic_complexity
    func handleSessionQuotaTransition(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        codexOwnerKey: CodexSessionQuotaOwnerKey? = nil,
        accountDiscriminatorOverride: String? = nil,
        now: Date = Date())
    {
        let accountDisplayName = self.quotaWarningAccountDisplayName(provider: provider, snapshot: snapshot)
        let accountDiscriminator = accountDiscriminatorOverride.flatMap {
            self.quotaWarningAccountDiscriminator(
                provider: provider,
                snapshot: snapshot,
                accountDiscriminatorOverride: $0)
        }
        let stateKey = SessionQuotaStateKey(provider: provider, accountDiscriminator: accountDiscriminator)
        if provider == .commandcode,
           snapshot.commandCodeSubscriptionEnrichmentUnavailable,
           SessionQuotaNotificationLogic.isDepleted(snapshot.primary?.remainingPercent)
        {
            return
        }
        let quotaReachedHookActive = self.hasQuotaHookRule(event: .quotaReached, provider: provider)
        if provider == .codex,
           !self.settings.sessionQuotaNotificationsEnabled,
           !self.settings.notificationPushToiOSEnabled,
           !quotaReachedHookActive
        {
            self.requireFreshCodexSessionQuotaBaseline(observedAt: snapshot.updatedAt)
            self.sessionQuotaLogger.debug("Codex session notifications disabled; cleared notification baseline")
            return
        }
        if provider == .codex, codexOwnerKey == nil {
            self.requireFreshCodexSessionQuotaBaseline(observedAt: snapshot.updatedAt)
            self.sessionQuotaLogger.debug("missing Codex session owner; cleared notification baseline")
            return
        }
        guard let sessionWindow = self.sessionQuotaWindow(provider: provider, snapshot: snapshot) else {
            if provider == .commandcode, snapshot.commandCodeSubscriptionEnrichmentUnavailable {
                return
            }
            if provider == .codex {
                if let previous = self.sessionQuotaTransitionStates[stateKey] {
                    if previous.codexOwnerKey != codexOwnerKey {
                        self.requireFreshCodexSessionQuotaBaseline(observedAt: snapshot.updatedAt)
                    } else {
                        self.sessionQuotaTransitionStates[stateKey] = previous.advancingObservationWatermark(
                            to: snapshot.updatedAt)
                    }
                } else if self.codexSessionQuotaBaselineRequirement != nil {
                    self.requireFreshCodexSessionQuotaBaseline(observedAt: snapshot.updatedAt)
                }
                self.sessionQuotaLogger.debug("missing Codex session window; retained notification baseline")
            } else {
                self.clearSessionQuotaTransitionState(provider: provider)
            }
            return
        }
        guard !sessionWindow.window.isSyntheticPlaceholder else { return }
        let currentRemaining = sessionWindow.window.remainingPercent
        let currentSource = sessionWindow.source
        let currentResetBoundary = sessionWindow.window.resetsAt
        if provider == .codex,
           let requirement = self.codexSessionQuotaBaselineRequirement,
           !requirement.admits(observedAt: snapshot.updatedAt)
        {
            self.sessionQuotaLogger.debug("ignored stale session observation while awaiting a fresh Codex baseline")
            return
        }
        let previousState = self.sessionQuotaTransitionStates[stateKey]
        let forceBaseline = provider == .codex && self.codexSessionQuotaBaselineRequirement != nil
        let evaluation = SessionQuotaTransitionReducer.evaluate(
            previous: previousState,
            observation: SessionQuotaTransitionObservation(
                provider: provider,
                remaining: currentRemaining,
                source: currentSource,
                resetBoundary: currentResetBoundary,
                observedAt: snapshot.updatedAt,
                evaluationTime: now,
                codexOwnerKey: codexOwnerKey),
            notificationsEnabled: self.settings.sessionQuotaNotificationsEnabled ||
                self.settings.notificationPushToiOSEnabled || quotaReachedHookActive,
            forceBaseline: forceBaseline)
        self.sessionQuotaTransitionStates[stateKey] = evaluation.state
        if provider == .codex {
            self.codexSessionQuotaBaselineRequirement = nil
        }

        let providerText = provider.rawValue
        let previousRemaining = previousState?.remaining
        switch evaluation.outcome {
        case .none:
            if SessionQuotaNotificationLogic.isDepleted(currentRemaining) ||
                SessionQuotaNotificationLogic.isDepleted(previousRemaining)
            {
                let reason = self.settings.sessionQuotaNotificationsEnabled ? "no transition" : "notifications disabled"
                self.sessionQuotaLogger.debug(
                    "\(reason): provider=\(providerText) prev=\(previousRemaining ?? -1) curr=\(currentRemaining)")
            }
        case .baselineChanged:
            self.sessionQuotaLogger.debug(
                "session notification baseline changed: provider=\(providerText) curr=\(currentRemaining)")
        case .staleCodexObservation:
            self.sessionQuotaLogger.debug(
                "ignored stale session observation: provider=\(providerText) curr=\(currentRemaining)")
        case .suppressedCodexRestore:
            self.sessionQuotaLogger.info(
                "suppressed transient restore: provider=\(providerText) " +
                    "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)")
        case .awaitingCodexRestoreConfirmation:
            self.sessionQuotaLogger.info(
                "awaiting restore confirmation: provider=\(providerText) " +
                    "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)")
        case .depleted, .restored:
            let transition = evaluation.outcome.transition
            self.sessionQuotaLogger.info(
                "transition \(String(describing: transition)): provider=\(providerText) " +
                    "prev=\(previousRemaining ?? -1) curr=\(currentRemaining)")
            if self.settings.sessionQuotaNotificationsEnabled {
                self.sessionQuotaNotifier.post(transition: transition, provider: provider, badge: nil)
            }
            if self.settings.notificationPushToiOSEnabled {
                self.quotaTransitionWriter.write(
                    transition: transition,
                    provider: provider,
                    accountDisplayName: accountDisplayName,
                    accountDiscriminator: accountDiscriminator)
            }
            if transition == .depleted, quotaReachedHookActive {
                self.emitQuotaReachedHook(provider: provider, sessionWindow: sessionWindow, snapshot: snapshot)
            }
        }
    }
}
