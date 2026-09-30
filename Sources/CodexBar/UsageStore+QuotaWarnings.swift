import CodexBarCore
import Foundation

@MainActor
extension UsageStore {
    func handleQuotaWarningTransitions(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        accountDiscriminator: String? = nil,
        hookAccountDiscriminator: String? = nil,
        requiresKnownAccount: Bool = false)
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
        guard !requiresKnownAccount || accountDiscriminator != nil else { return }

        let account = QuotaWarningAccountContext(
            displayName: self.quotaWarningAccountDisplayName(provider: provider, snapshot: snapshot),
            discriminator: self.quotaWarningAccountDiscriminator(
                provider: provider,
                snapshot: snapshot,
                accountDiscriminatorOverride: accountDiscriminator),
            observedAt: snapshot.updatedAt)
        // Provider-specific by design: warning lanes follow Antigravity families, balance-only suppression, and
        // provider-authored dynamic labels rather than the generic primary/secondary pair.
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
            let suppressWindows = provider == .mimo || provider == .qoder
            primaryWindow = suppressWindows ? nil : snapshot.primary
            secondaryWindow = suppressWindows ? nil : snapshot.secondary
        }
        let primaryWindowDisplayLabel = provider == .amp
            ? AmpProviderDescriptor.primaryLabel(snapshot: snapshot)
            : nil
        let secondaryWindowDisplayLabel = provider == .amp
            ? AmpProviderDescriptor.secondaryLabel(snapshot: snapshot)
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
            let hookDiscriminator = hookAccountDiscriminator ?? account.discriminator
            self.dispatchQuotaLowHooks(
                provider: provider,
                lane: QuotaLowHookLane(
                    window: .session,
                    windowID: nil,
                    label: primaryWindowDisplayLabel ?? QuotaWarningWindow.session.displayName),
                rateWindow: primaryWindow,
                accountDiscriminator: hookDiscriminator,
                accountDisplayName: account.displayName)
            self.dispatchQuotaLowHooks(
                provider: provider,
                lane: QuotaLowHookLane(
                    window: .weekly,
                    windowID: nil,
                    label: secondaryWindowDisplayLabel ?? QuotaWarningWindow.weekly.displayName),
                rateWindow: secondaryWindow,
                accountDiscriminator: hookDiscriminator,
                accountDisplayName: account.displayName)
            let extraWindows = provider == .claude
                ? (snapshot.extraRateWindows ?? []).filter(Self.isClaudeNotifiableExtraWindow)
                : []
            for named in extraWindows {
                self.dispatchQuotaLowHooks(
                    provider: provider,
                    lane: QuotaLowHookLane(window: .weekly, windowID: named.id, label: named.title),
                    rateWindow: named.window,
                    accountDiscriminator: hookDiscriminator,
                    accountDisplayName: account.displayName)
            }
            self.pruneQuotaLowHookUsage(
                provider: provider,
                accountDiscriminator: hookDiscriminator,
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
        let unresolvedKey = QuotaWarningStateKey(
            provider: provider,
            window: transition.window,
            accountDiscriminator: account.discriminator,
            windowID: transition.windowID)
        var key = unresolvedKey
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
        // A weekly OAuth fallback may occupy primary when Claude omits its session payload.
        guard provider != .claude || transition.window != .session || Self.isSessionWindow(rateWindow) else { return }
        guard !rateWindow.isSyntheticPlaceholder else { return }

        let thresholds = self.settings.resolvedQuotaWarningThresholds(
            provider: provider,
            window: transition.window)
        let currentRemaining = rateWindow.remainingPercent
        var previousState = self.quotaWarningState[key]
        if provider == .claude,
           let accountDiscriminator = account.discriminator,
           accountDiscriminator == "claude-account:unknown",
           let verifiedAccount = self.lastVerifiedClaudeWarningAccountDiscriminator,
           verifiedAccount.hasPrefix("claude-account:"),
           verifiedAccount != accountDiscriminator
        {
            let verifiedKey = QuotaWarningStateKey(
                provider: .claude,
                window: transition.window,
                accountDiscriminator: verifiedAccount,
                windowID: transition.windowID)
            let verifiedState = self.quotaWarningState[verifiedKey]
            let resetContinues = verifiedState.map {
                rateWindow.resetsAt != nil && rateWindow.resetsAt == $0.resetsAt &&
                    currentRemaining <= ($0.lastRemaining ?? -Double.infinity)
            } ?? false
            if let reconciled = self.reconciledClaudeWarningState(
                current: previousState,
                candidate: verifiedState,
                currentRemaining: currentRemaining,
                resetsAt: rateWindow.resetsAt)
            {
                if resetContinues {
                    // Continue the verified lane while this unresolved sample still proves the
                    // same quota episode; the notification display still reflects this sample.
                    key = verifiedKey
                    self.quotaWarningState.removeValue(forKey: unresolvedKey)
                } else {
                    self.quotaWarningState[unresolvedKey] = reconciled
                }
                previousState = reconciled
            }
        } else if provider == .claude,
                  let accountDiscriminator = account.discriminator,
                  accountDiscriminator.hasPrefix("claude-account:"),
                  accountDiscriminator != "claude-account:unknown"
        {
            let unresolvedKey = QuotaWarningStateKey(
                provider: .claude,
                window: transition.window,
                accountDiscriminator: "claude-account:unknown",
                windowID: transition.windowID)
            if let unresolvedState = self.quotaWarningState[unresolvedKey] {
                if let reconciled = self.reconciledClaudeWarningState(
                    current: previousState,
                    candidate: unresolvedState,
                    currentRemaining: currentRemaining,
                    resetsAt: rateWindow.resetsAt)
                {
                    previousState = reconciled
                    self.quotaWarningState[key] = reconciled
                    self.quotaWarningState.removeValue(forKey: unresolvedKey)
                }
            }
        }
        if let previousState, previousState.source != transition.source {
            self.quotaWarningState[key] = QuotaWarningState(
                lastRemaining: currentRemaining,
                observedAt: account.observedAt,
                source: transition.source,
                resetsAt: rateWindow.resetsAt)
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

        state.observedAt = account.observedAt
        state.resetsAt = rateWindow.resetsAt
        state.lastRemaining = currentRemaining
        self.quotaWarningState[key] = state
    }

    private func reconciledClaudeWarningState(
        current: QuotaWarningState?,
        candidate: QuotaWarningState?,
        currentRemaining: Double,
        resetsAt: Date?) -> QuotaWarningState?
    {
        guard let candidate else { return nil }
        let sameReset = resetsAt != nil && resetsAt == candidate.resetsAt
        let nonincreasingUsage = candidate.lastRemaining.map { currentRemaining <= $0 } ?? false
        guard (sameReset && nonincreasingUsage) || candidate.sharedWithUnresolvedAccount else { return nil }

        var result = candidate
        if let current {
            result.firedThresholds.formUnion(current.firedThresholds)
            if current.observedAt > result.observedAt {
                result.lastRemaining = current.lastRemaining
                result.observedAt = current.observedAt
                result.source = current.source
                result.resetsAt = current.resetsAt
            }
        }
        result.sharedWithUnresolvedAccount = true
        return result
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
        // Command Code's login method includes the live monthly-credit balance, so it is display
        // metadata rather than a stable account identity. Keying warnings by it would split one
        // threshold episode every time the balance changes.
        if provider != .commandcode,
           let loginMethod = Self.normalizedQuotaWarningDiscriminatorValue(snapshot.loginMethod(for: provider))
        {
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
