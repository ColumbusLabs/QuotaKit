import CodexBarCore
import Foundation

enum UsagePaceText {
    private static let minimumExpectedPercent: Double = 3

    static func weekly(provider: UsageProvider, window: RateWindow, now: Date = .init()) -> String? {
        guard provider == .codex || provider == .claude else { return nil }
        guard let pace = UsagePace.weekly(window: window, now: now, defaultWindowMinutes: 10080) else { return nil }
        guard pace.expectedUsedPercent >= Self.minimumExpectedPercent else { return nil }

        let label = Self.label(for: pace.stage)
        let deltaSuffix = Self.deltaSuffix(for: pace)
        let etaSuffix = Self.etaSuffix(for: pace, now: now)

        if let etaSuffix {
            return "Pace: \(label)\(deltaSuffix) · \(etaSuffix)"
        }
        return "Pace: \(label)\(deltaSuffix)"
    }

    private static func label(for stage: UsagePace.Stage) -> String {
        switch stage {
        case .onTrack: "On pace"
        case .slightlyAhead, .ahead, .farAhead: "Ahead"
        case .slightlyBehind, .behind, .farBehind: "Behind"
        }
    }

    private static func deltaSuffix(for pace: UsagePace) -> String {
        let deltaValue = Int(abs(pace.deltaPercent).rounded())
        let sign = pace.deltaPercent >= 0 ? "+" : "-"
        return " (\(sign)\(deltaValue)%)"
    }

    private static func etaSuffix(for pace: UsagePace, now: Date) -> String? {
        if pace.willLastToReset { return "Lasts to reset" }
        guard let etaSeconds = pace.etaSeconds else { return nil }
        let etaText = Self.durationText(seconds: etaSeconds, now: now)
        if etaText == "now" { return "Runs out now" }
        return "Runs out in \(etaText)"
    }

    private static func durationText(seconds: TimeInterval, now: Date) -> String {
        let date = now.addingTimeInterval(seconds)
        let countdown = UsageFormatter.resetCountdownDescription(from: date, now: now)
        if countdown == "now" { return "now" }
        if countdown.hasPrefix("in ") { return String(countdown.dropFirst(3)) }
        return countdown
    }
}
