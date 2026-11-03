import CodexBarCore
import CryptoKit
import Foundation

@MainActor
struct CodexResetCreditExpiryNotifier {
    static let expiryWindow: TimeInterval = 3 * 24 * 60 * 60
    static let notificationPrefix = "codex-reset-credit-expiry"
    static let countdownNotificationPrefix = "codex-reset-credit-countdown"
    static let summaryFingerprintsKey = "codexResetCreditExpirySummaryFingerprints"
    static let maximumRememberedSummaries = 192
    private static let reminderThresholds: [TimeInterval] = [86400, 3600]

    private static var inFlight: Set<String> = []
    var userDefaults: UserDefaults
    var ownerScope: String
    var deliveryPoster: (String, String, String, @escaping @MainActor (Bool) -> Void) -> Void

    init(
        userDefaults: UserDefaults = .standard,
        ownerScope: String = "",
        deliveryPoster: @escaping (String, String, String, @escaping @MainActor (Bool) -> Void) -> Void)
    {
        self.userDefaults = userDefaults
        self.ownerScope = ownerScope
        self.deliveryPoster = deliveryPoster
    }

    init(userDefaults: UserDefaults = .standard, notificationPoster: @escaping (String, String, String) -> Void) {
        self.init(userDefaults: userDefaults) { prefix, title, body, completion in
            notificationPoster(prefix, title, body)
            completion(true)
        }
    }

    func postExpiringCreditsIfNeeded(
        snapshot: CodexRateLimitResetCreditsSnapshot,
        summaryEnabled: Bool = true,
        countdownEnabled: Bool = false,
        resetStyle: ResetTimeDisplayStyle,
        now: Date = Date())
    {
        guard summaryEnabled || countdownEnabled else { return }
        let expiringCredits = snapshot.availableInventory(at: now).credits.filter { credit in
            guard let expiresAt = credit.expiresAt else { return false }
            return expiresAt.timeIntervalSince(now) <= Self.expiryWindow
        }
        guard !expiringCredits.isEmpty else { return }

        let fingerprint = Self.summaryFingerprint(expiringCredits)
        let notifiedFingerprints = self.userDefaults.stringArray(forKey: Self.summaryFingerprintsKey) ?? []
        var receiptsToRecord: [String] = []
        let sendsSummary = summaryEnabled && !notifiedFingerprints.contains(fingerprint)
        var reminders: [CodexRateLimitResetCredit] = []
        if countdownEnabled {
            for credit in expiringCredits {
                guard let expiresAt = credit.expiresAt,
                      let threshold = Self.reminderThresholds.last(where: { expiresAt.timeIntervalSince(now) <= $0 })
                else { continue }
                let receipt = Self.summaryFingerprint([credit], threshold: threshold)
                guard !notifiedFingerprints.contains(receipt) else { continue }
                reminders.append(credit)
                // A late first refresh consumes earlier stages too, so they cannot arrive after the last call.
                for stage in Self.reminderThresholds where stage >= threshold {
                    let receipt = Self.summaryFingerprint([credit], threshold: stage)
                    if !notifiedFingerprints.contains(receipt) { receiptsToRecord.append(receipt) }
                }
            }
        }
        let creditsToPost = sendsSummary ? expiringCredits : reminders
        guard !creditsToPost.isEmpty else { return }
        if sendsSummary { receiptsToRecord.append(fingerprint) }

        let expiringSnapshot = CodexRateLimitResetCreditsSnapshot(
            credits: creditsToPost,
            availableCount: creditsToPost.count,
            updatedAt: now)
        guard let presentation = CodexResetCreditsPresentation.make(
            snapshot: expiringSnapshot,
            resetStyle: resetStyle,
            now: now)
        else {
            return
        }
        let inFlightKey = "\(ObjectIdentifier(self.userDefaults)):\(self.ownerScope):\(fingerprint)"
        guard !Self.inFlight.contains(inFlightKey), Self.inFlight.count < 256 else { return }
        Self.inFlight.insert(inFlightKey)
        self.deliveryPoster(
            sendsSummary ? Self.notificationPrefix : Self.countdownNotificationPrefix,
            L("Limit Reset Credits"),
            presentation.helpText)
        { delivered in
            Self.inFlight.remove(inFlightKey)
            guard delivered else { return }
            var latest = self.userDefaults.stringArray(forKey: Self.summaryFingerprintsKey) ?? []
            for receipt in receiptsToRecord where !latest.contains(receipt) {
                latest.append(receipt)
            }
            if latest.count > Self.maximumRememberedSummaries {
                latest.removeFirst(latest.count - Self.maximumRememberedSummaries)
            }
            self.userDefaults.set(latest, forKey: Self.summaryFingerprintsKey)
        }
    }

    private static func summaryFingerprint(
        _ credits: [CodexRateLimitResetCredit],
        threshold: TimeInterval? = nil) -> String
    {
        let material = credits.map { credit in
            "\(credit.id)\u{1f}\(credit.expiresAt?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: "\u{1e}") + (threshold.map { "\u{1f}\($0)" } ?? "")
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
