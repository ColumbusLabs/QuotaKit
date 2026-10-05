import Foundation
import Testing
@testable import CodexBar

struct CodexCostCatchUpPolicyTests {
    @Test
    func `only accelerated mode uses the longer dashboard scan burst`() {
        #expect(CodexCostCatchUpMode.automatic.scanDurationPerRefresh() == 2)
        #expect(CodexCostCatchUpMode.accelerated.scanDurationPerRefresh() == 10)
    }

    @Test
    func `automatic discovery shares a bounded burst without initial sleep debt`() {
        for passes in 0..<CodexCostCatchUpPolicy.automaticMaximumBurstPasses {
            let activeDuration = Double(passes) / 10
            let decision = CodexCostCatchUpPolicy().decision(for: .init(
                mode: .automatic,
                previousActiveDuration: passes == 0 ? nil : activeDuration,
                powerSource: .ac,
                lowPowerModeEnabled: false,
                thermalState: .nominal,
                completedPasses: passes))
            #expect(decision.action == .runAfter(0))
        }

        let capped = CodexCostCatchUpPolicy().decision(for: .init(
            mode: .automatic,
            previousActiveDuration: 0.8,
            powerSource: .ac,
            lowPowerModeEnabled: false,
            thermalState: .nominal,
            completedPasses: CodexCostCatchUpPolicy.automaticMaximumBurstPasses))
        #expect(capped.action == .runAfter(1998))
        #expect(CodexCostCatchUpMode.automatic.scanDurationPerRefresh(after: 1.5) == 0.5)
        #expect(CodexCostCatchUpMode.automatic.scanDurationPerRefresh(after: 2) == 0.001)
        #expect(CodexCostCatchUpMode.accelerated.scanDurationPerRefresh(after: 20) == 10)
    }

    @Test
    func `automatic mode targets one tenth percent duty cycle on AC power`() {
        let decision = CodexCostCatchUpPolicy().decision(for: .init(
            mode: .automatic,
            previousActiveDuration: 2,
            powerSource: .ac,
            lowPowerModeEnabled: false,
            thermalState: .nominal))

        #expect(decision == .init(action: .runAfter(1998), targetDutyCycle: 0.001))
    }

    @Test
    func `automatic mode targets five hundredths percent duty cycle for unknown power`() {
        let decision = CodexCostCatchUpPolicy().decision(for: .init(
            mode: .automatic,
            previousActiveDuration: 2,
            powerSource: .unknown,
            lowPowerModeEnabled: false,
            thermalState: .nominal))

        guard case let .runAfter(delay) = decision.action else {
            Issue.record("Expected automatic catch-up to schedule another pass")
            return
        }
        #expect(abs(delay - 3998) < 0.000_001)
        #expect(decision.targetDutyCycle == 0.0005)
    }

    @Test
    func `automatic mode targets two hundredths percent duty cycle on battery`() {
        let decision = CodexCostCatchUpPolicy().decision(for: .init(
            mode: .automatic,
            previousActiveDuration: 2,
            powerSource: .battery,
            lowPowerModeEnabled: false,
            thermalState: .nominal))

        guard case let .runAfter(delay) = decision.action else {
            Issue.record("Expected automatic battery catch-up to schedule another pass")
            return
        }
        #expect(abs(delay - 9998) < 0.000_001)
        #expect(decision.targetDutyCycle == 0.0002)
    }

    @Test
    func `automatic mode keeps a minimum duration after a bounded burst`() {
        let decision = CodexCostCatchUpPolicy().decision(for: .init(
            mode: .automatic,
            previousActiveDuration: 0,
            powerSource: .ac,
            lowPowerModeEnabled: false,
            thermalState: .nominal,
            completedPasses: CodexCostCatchUpPolicy.automaticMaximumBurstPasses))

        #expect(decision == .init(action: .runAfter(1998), targetDutyCycle: 0.001))
    }

    @Test
    func `automatic mode pauses for low power mode`() {
        let decision = CodexCostCatchUpPolicy().decision(for: .init(
            mode: .automatic,
            previousActiveDuration: 2,
            powerSource: .battery,
            lowPowerModeEnabled: true,
            thermalState: .nominal))

        #expect(decision == .init(
            action: .pause(CodexCostCatchUpPolicy.constrainedRetryDelay, .lowPower),
            targetDutyCycle: nil))
    }

    @Test
    func `automatic mode keeps thermal precedence over low power mode`() {
        for powerSource in [CodexCostCatchUpPowerSource.ac, .unknown, .battery] {
            let decision = CodexCostCatchUpPolicy().decision(for: .init(
                mode: .automatic,
                previousActiveDuration: 2,
                powerSource: powerSource,
                lowPowerModeEnabled: true,
                thermalState: .serious))

            #expect(decision == .init(
                action: .pause(CodexCostCatchUpPolicy.constrainedRetryDelay, .thermal),
                targetDutyCycle: nil))
        }
    }

    @Test
    func `accelerated mode ignores low power but not critical thermal pressure`() {
        let lowPowerDecision = CodexCostCatchUpPolicy().decision(for: .init(
            mode: .accelerated,
            previousActiveDuration: 2,
            powerSource: .battery,
            lowPowerModeEnabled: true,
            thermalState: .serious))
        let criticalDecision = CodexCostCatchUpPolicy().decision(for: .init(
            mode: .accelerated,
            previousActiveDuration: 2,
            powerSource: .ac,
            lowPowerModeEnabled: false,
            thermalState: .critical))

        #expect(lowPowerDecision == .init(action: .runAfter(0), targetDutyCycle: 1))
        #expect(criticalDecision == .init(
            action: .pause(CodexCostCatchUpPolicy.constrainedRetryDelay, .thermal),
            targetDutyCycle: nil))
    }
}
