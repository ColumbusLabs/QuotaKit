import AppKit
import CodexBarCore
import QuartzCore

extension StatusItemController {
    func updateBlinkingState() {
        let blinkingEnabled = self.isBlinkingAllowed()
        let anyVisible = UsageProvider.allCases.contains { self.isVisible($0) }
        if blinkingEnabled, anyVisible {
            if self.blinkTask == nil {
                self.seedBlinkStatesIfNeeded()
                self.blinkTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(75))
                        await MainActor.run { self?.tickBlink() }
                    }
                }
            }
        } else {
            self.stopBlinking()
        }
    }

    private func seedBlinkStatesIfNeeded() {
        let now = Date()
        for provider in UsageProvider.allCases where self.blinkStates[provider] == nil {
            self.blinkStates[provider] = BlinkState(nextBlink: now.addingTimeInterval(BlinkState.randomDelay()))
        }
    }

    private func stopBlinking() {
        self.blinkTask?.cancel()
        self.blinkTask = nil
        self.blinkAmounts.removeAll()
        UsageProvider.allCases.forEach { self.applyIcon(for: $0, phase: nil) }
    }

    private func tickBlink(now: Date = .init()) {
        guard self.isBlinkingAllowed(at: now) else {
            self.stopBlinking()
            return
        }

        let blinkDuration: TimeInterval = 0.36
        let doubleBlinkChance = 0.18
        let doubleDelayRange: ClosedRange<TimeInterval> = 0.22...0.34

        for provider in UsageProvider.allCases {
            guard self.isVisible(provider), !self.shouldAnimate(provider: provider) else {
                self.clearMotion(for: provider)
                continue
            }

            var state = self
                .blinkStates[provider] ?? BlinkState(nextBlink: now.addingTimeInterval(BlinkState.randomDelay()))

            if let pendingSecond = state.pendingSecondStart, now >= pendingSecond {
                state.blinkStart = now
                state.pendingSecondStart = nil
            }

            if let start = state.blinkStart {
                let elapsed = now.timeIntervalSince(start)
                if elapsed >= blinkDuration {
                    state.blinkStart = nil
                    if let pending = state.pendingSecondStart, now < pending {
                        // Wait for the planned double-blink.
                    } else {
                        state.pendingSecondStart = nil
                        state.nextBlink = now.addingTimeInterval(BlinkState.randomDelay())
                    }
                    self.clearMotion(for: provider)
                } else {
                    let progress = max(0, min(elapsed / blinkDuration, 1))
                    let symmetric = progress < 0.5 ? progress * 2 : (1 - progress) * 2
                    let eased = pow(symmetric, 2.2) // slightly punchier than smoothstep
                    self.assignMotion(amount: CGFloat(eased), for: provider, effect: state.effect)
                }
            } else if now >= state.nextBlink {
                state.blinkStart = now
                state.effect = self.randomEffect(for: provider)
                if state.effect == .blink, Double.random(in: 0...1) < doubleBlinkChance {
                    state.pendingSecondStart = now.addingTimeInterval(Double.random(in: doubleDelayRange))
                }
                self.clearMotion(for: provider)
            } else {
                self.clearMotion(for: provider)
            }

            self.blinkStates[provider] = state
            self.applyIcon(for: provider, phase: nil)
        }
    }

    private func blinkAmount(for provider: UsageProvider) -> CGFloat {
        guard self.isBlinkingAllowed() else { return 0 }
        return self.blinkAmounts[provider] ?? 0
    }

    private func wiggleAmount(for provider: UsageProvider) -> CGFloat {
        guard self.isBlinkingAllowed() else { return 0 }
        return self.wiggleAmounts[provider] ?? 0
    }

    private func tiltAmount(for provider: UsageProvider) -> CGFloat {
        guard self.isBlinkingAllowed() else { return 0 }
        return self.tiltAmounts[provider] ?? 0
    }

    private func assignMotion(amount: CGFloat, for provider: UsageProvider, effect: MotionEffect) {
        switch effect {
        case .blink:
            self.blinkAmounts[provider] = amount
            self.wiggleAmounts[provider] = 0
            self.tiltAmounts[provider] = 0
        case .wiggle:
            self.wiggleAmounts[provider] = amount
            self.blinkAmounts[provider] = 0
            self.tiltAmounts[provider] = 0
        case .tilt:
            self.tiltAmounts[provider] = amount
            self.blinkAmounts[provider] = 0
            self.wiggleAmounts[provider] = 0
        }
    }

    private func clearMotion(for provider: UsageProvider) {
        self.blinkAmounts[provider] = 0
        self.wiggleAmounts[provider] = 0
        self.tiltAmounts[provider] = 0
    }

    private func randomEffect(for provider: UsageProvider) -> MotionEffect {
        if provider == .claude {
            Bool.random() ? .blink : .wiggle
        } else {
            Bool.random() ? .blink : .tilt
        }
    }

    private func isBlinkingAllowed(at date: Date = .init()) -> Bool {
        if self.settings.randomBlinkEnabled { return true }
        if let until = self.blinkForceUntil, until > date { return true }
        self.blinkForceUntil = nil
        return false
    }

    func applyIcon(for provider: UsageProvider, phase: Double?) {
        guard let button = self.statusItems[provider]?.button else { return }
        let snapshot = self.store.snapshot(for: provider)
        // IconRenderer treats these values as a left-to-right "progress fill" percentage; depending on the
        // user setting we pass either "percent left" or "percent used".
        let showUsed = self.settings.usageBarsShowUsed
        var primary = showUsed ? snapshot?.primary.usedPercent : snapshot?.primary.remainingPercent
        var weekly = showUsed ? snapshot?.secondary?.usedPercent : snapshot?.secondary?.remainingPercent
        var credits: Double? = provider == .codex ? self.store.credits?.remaining : nil
        var stale = self.store.isStale(provider: provider)
        var morphProgress: Double?

        if let phase, self.shouldAnimate(provider: provider) {
            var pattern = self.animationPattern
            if provider == .claude, pattern == .unbraid {
                pattern = .cylon
            }
            if pattern == .unbraid {
                morphProgress = pattern.value(phase: phase) / 100
                primary = nil
                weekly = nil
                credits = nil
                stale = false
            } else {
                primary = pattern.value(phase: phase)
                weekly = pattern.value(phase: phase + pattern.secondaryOffset)
                credits = nil
                stale = false
            }
        }

        let style: IconStyle = self.store.style(for: provider)
        let blink = self.blinkAmount(for: provider)
        let wiggle = self.wiggleAmount(for: provider)
        let tilt = self.tiltAmount(for: provider) * .pi / 28 // limit to ~6.4°
        if let morphProgress {
            button.image = IconRenderer.makeMorphIcon(progress: morphProgress, style: style)
        } else {
            button.image = IconRenderer.makeIcon(
                primaryRemaining: primary,
                weeklyRemaining: weekly,
                creditsRemaining: credits,
                stale: stale,
                style: style,
                blink: blink,
                wiggle: wiggle,
                tilt: tilt,
                statusIndicator: self.store.statusIndicator(for: provider))
        }
    }

    @objc func handleDebugBlinkNotification() {
        self.forceBlinkNow()
    }

    private func forceBlinkNow() {
        let now = Date()
        self.blinkForceUntil = now.addingTimeInterval(0.6)
        self.seedBlinkStatesIfNeeded()

        for provider in UsageProvider.allCases
            where self.isVisible(provider) && !self.shouldAnimate(provider: provider)
        {
            var state = self
                .blinkStates[provider] ?? BlinkState(nextBlink: now.addingTimeInterval(BlinkState.randomDelay()))
            state.blinkStart = now
            state.pendingSecondStart = nil
            state.effect = self.randomEffect(for: provider)
            state.nextBlink = now.addingTimeInterval(BlinkState.randomDelay())
            self.blinkStates[provider] = state
            self.assignMotion(amount: 0, for: provider, effect: state.effect)
        }

        self.updateBlinkingState()
        self.tickBlink(now: now)
    }

    private func shouldAnimate(provider: UsageProvider) -> Bool {
        if self.store.debugForceAnimation { return true }

        let visible = self.store.debugForceAnimation || self.isEnabled(provider) || self.fallbackProvider == provider
        guard visible else { return false }

        let isStale = self.store.isStale(provider: provider)
        let hasData = self.store.snapshot(for: provider) != nil
        return !hasData && !isStale
    }

    func updateAnimationState() {
        let needsAnimation = UsageProvider.allCases.contains { self.shouldAnimate(provider: $0) }
        if needsAnimation {
            if self.animationDisplayLink == nil {
                if let forced = self.settings.debugLoadingPattern {
                    self.animationPattern = forced
                } else if !LoadingPattern.allCases.contains(self.animationPattern) {
                    self.animationPattern = .knightRider
                }
                self.animationPhase = 0
                if let link = NSScreen.main?.displayLink(target: self, selector: #selector(self.animateIcons(_:))) {
                    link.add(to: .main, forMode: .common)
                    self.animationDisplayLink = link
                }
            } else if let forced = self.settings.debugLoadingPattern, forced != self.animationPattern {
                self.animationPattern = forced
                self.animationPhase = 0
            }
        } else {
            self.animationDisplayLink?.invalidate()
            self.animationDisplayLink = nil
            self.animationPhase = 0
            UsageProvider.allCases.forEach { self.applyIcon(for: $0, phase: nil) }
        }
    }

    @objc func animateIcons(_ link: CADisplayLink) {
        self.animationPhase += 0.045 // half-speed animation
        UsageProvider.allCases.forEach { self.applyIcon(for: $0, phase: self.animationPhase) }
    }

    private func advanceAnimationPattern() {
        let patterns = LoadingPattern.allCases
        if let idx = patterns.firstIndex(of: self.animationPattern) {
            let next = patterns.indices.contains(idx + 1) ? patterns[idx + 1] : patterns.first
            self.animationPattern = next ?? .knightRider
        } else {
            self.animationPattern = .knightRider
        }
    }

    @objc func handleDebugReplayNotification(_ notification: Notification) {
        if let raw = notification.userInfo?["pattern"] as? String,
           let selected = LoadingPattern(rawValue: raw)
        {
            self.animationPattern = selected
        } else if let forced = self.settings.debugLoadingPattern {
            self.animationPattern = forced
        } else {
            self.advanceAnimationPattern()
        }
        self.animationPhase = 0
        self.updateAnimationState()
    }
}
