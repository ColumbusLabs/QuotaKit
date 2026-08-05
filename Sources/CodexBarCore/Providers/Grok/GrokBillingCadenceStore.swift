import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Learns Grok's billing cadence from successive reset timestamps.
///
/// The grok.com billing payload reports only a used percent and a reset timestamp — never the
/// period start or its duration — so a single fetch cannot say whether the window is weekly or
/// monthly. Deriving the cadence from the *remaining* time fails for most of a cycle: a weekly
/// window two days from reset is indistinguishable from a monthly one two days from reset. That
/// ambiguity used to leave the bar unlabeled and suppress pace for the back half of every week.
///
/// An unambiguous time-to-reset can seed the cadence on the first fetch. After that, a rollover can
/// replace it only with a recognized weekly period, or with a monthly period whose new reset is
/// still monthly-distance away. That second check keeps four missed weekly rollovers from looking
/// like a 28-day monthly plan while allowing real plan changes to take effect immediately.
public struct GrokBillingCadenceStore: Sendable {
    public static let currentVersion = 3

    /// SuperGrok's documented cadence, used until a rollover has been observed.
    public static let defaultWindowMinutes = 7 * 24 * 60

    static let monthlyWindowMinutes = 30 * 24 * 60

    private struct Payload: Codable {
        let version: Int
        var accountScope: String?
        var lastResetsAt: Date?
        var learnedWindowMinutes: Int?

        init(
            version: Int = GrokBillingCadenceStore.currentVersion,
            accountScope: String? = nil,
            lastResetsAt: Date? = nil,
            learnedWindowMinutes: Int? = nil)
        {
            self.version = version
            self.accountScope = accountScope
            self.lastResetsAt = lastResetsAt
            self.learnedWindowMinutes = learnedWindowMinutes
        }
    }

    private let fileURL: URL

    public init(fileURL: URL = Self.defaultURL()) {
        self.fileURL = fileURL
    }

    /// Records `resetsAt` and returns the billing window length to attach to the web-billing
    /// `RateWindow`. Callers pass this on every fetch; the file is rewritten only when the stored
    /// state actually changes, so a steady-state refresh loop does no writes.
    @discardableResult
    public func resolveWindowMinutes(
        resetsAt: Date?,
        now: Date = .now,
        accountScope: String? = nil) -> Int?
    {
        var payload = self.loadPayload()
        if let accountScope, payload.accountScope != accountScope {
            payload = Payload(accountScope: accountScope)
        }
        guard let resetsAt else { return payload.learnedWindowMinutes }

        let previous = payload.lastResetsAt
        let inferred = Self.inferredWindowMinutes(resetsAt: resetsAt, now: now)
        if previous == nil {
            payload.learnedWindowMinutes = inferred
        } else if let previous, resetsAt > previous {
            let observed = Self.recognizedWindowMinutes(from: previous, to: resetsAt)
            if let observed {
                switch Self.cadence(for: observed) {
                case .weekly:
                    payload.learnedWindowMinutes = observed
                case .monthly where Self.cadence(for: inferred) == .monthly:
                    // A 28-day gap can also be four missed weekly rollovers. Only accept it when
                    // the replacement reset is still far enough away to independently say monthly.
                    payload.learnedWindowMinutes = observed
                case .monthly, nil:
                    break
                }
            } else if inferred != nil,
                      Self.cadence(for: inferred) != Self.cadence(for: payload.learnedWindowMinutes)
            {
                // A recognized remaining-time category is useful plan-change evidence even when
                // the observed gap spans missed cycles and is not itself a real period.
                payload.learnedWindowMinutes = inferred
            }
        }

        if previous != resetsAt {
            payload.lastResetsAt = resetsAt
            self.store(payload)
        }
        return payload.learnedWindowMinutes
    }

    /// The cadence learned so far, or `nil` when no rollover has been observed yet.
    public func learnedWindowMinutes() -> Int? {
        self.loadPayload().learnedWindowMinutes
    }

    public static func accountScopeFingerprint(_ value: String) -> String {
        SHA256.hash(data: Data("quotakit.grok-cadence.v1\0\(value)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func inferredWindowMinutes(resetsAt: Date, now: Date) -> Int? {
        let remainingMinutes = Int((resetsAt.timeIntervalSince(now) / 60).rounded())
        guard remainingMinutes > 0 else { return nil }
        switch remainingMinutes {
        case (4 * 24 * 60)...(12 * 24 * 60):
            return self.defaultWindowMinutes
        case (20 * 24 * 60)...(45 * 24 * 60):
            return self.monthlyWindowMinutes
        default:
            return nil
        }
    }

    static func recognizedWindowMinutes(from previous: Date, to current: Date) -> Int? {
        let minutes = Int((current.timeIntervalSince(previous) / 60).rounded())
        switch minutes {
        case (6 * 24 * 60)...(8 * 24 * 60), (27 * 24 * 60)...(33 * 24 * 60):
            return minutes
        default:
            return nil
        }
    }

    private enum Cadence {
        case weekly
        case monthly
    }

    private static func cadence(for minutes: Int?) -> Cadence? {
        guard let minutes else { return nil }
        switch minutes {
        case (4 * 24 * 60)...(12 * 24 * 60): return .weekly
        case (20 * 24 * 60)...(45 * 24 * 60): return .monthly
        default: return nil
        }
    }

    private func loadPayload() -> Payload {
        guard FileManager.default.fileExists(atPath: self.fileURL.path),
              let data = try? Data(contentsOf: self.fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == Self.currentVersion
        else {
            return Payload()
        }
        return payload
    }

    /// Best effort: a cadence estimate is a display refinement, so a failed write must never break
    /// the fetch that produced it. The next rollover re-observes the same gap.
    private func store(_ payload: Payload) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        let directory = self.fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try? data.write(to: self.fileURL, options: [.atomic])
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("QuotaKit", isDirectory: true)
            .appendingPathComponent("grok-billing-cadence.json")
    }
}
