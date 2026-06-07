import CodexBarSync
import SwiftUI

/// ElevenLabs character-credit + voice-slot card. Renders when
/// `ProviderUsageSnapshot.elevenLabsCredits` is populated. Hidden
/// for Mac versions older than 0.27.0.
struct ElevenLabsCreditsCard: View {
    let credits: SyncElevenLabsCredits
    let tintColor: Color

    private var hasVoiceSlots: Bool {
        (credits.voiceLimit ?? 0) > 0 || (credits.professionalVoiceLimit ?? 0) > 0
    }

    private var characterFraction: Double {
        guard credits.characterLimit > 0 else { return 0 }
        return min(max(Double(credits.characterCount) / Double(credits.characterLimit), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(String(localized: "elevenlabs_credits_title", defaultValue: "ElevenLabs credits"))
                    .font(.headline)
                if let tier = credits.tier, !tier.isEmpty {
                    Text(tier.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(self.tintColor.opacity(0.16)))
                        .foregroundStyle(self.tintColor)
                }
                Spacer()
                Text("\(Int(credits.usedPercent.rounded()))%")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(self.tintColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(self.characterLabel)
                        .font(.subheadline.monospacedDigit())
                    Spacer()
                    Text(String(localized: "elevenlabs_characters_label", defaultValue: "characters"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: self.characterFraction)
                    .progressViewStyle(.linear)
                    .tint(self.tintColor)
            }

            if self.hasVoiceSlots {
                Divider()
                self.voiceSlotRows
            }

            if let resetAt = credits.resetsAt {
                HStack {
                    Text(String(localized: "elevenlabs_renews_label", defaultValue: "Renews"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(resetAt, style: .date)
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("elevenlabs-credits-card")
    }

    private var characterLabel: String {
        if credits.characterLimit > 0 {
            return "\(Self.formatInt(credits.characterCount)) / \(Self.formatInt(credits.characterLimit))"
        }
        return Self.formatInt(credits.characterCount)
    }

    @ViewBuilder
    private var voiceSlotRows: some View {
        if let used = credits.voiceSlotsUsed, let limit = credits.voiceLimit, limit > 0 {
            HStack {
                Text(String(localized: "elevenlabs_voice_slots_label", defaultValue: "Voice slots"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(used) / \(limit)")
                    .font(.caption.bold().monospacedDigit())
            }
        }
        if let used = credits.professionalVoiceSlotsUsed,
           let limit = credits.professionalVoiceLimit,
           limit > 0
        {
            HStack {
                Text(String(localized: "elevenlabs_pro_voice_slots_label", defaultValue: "Pro voice slots"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(used) / \(limit)")
                    .font(.caption.bold().monospacedDigit())
            }
        }
    }

    private static func formatInt(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

#Preview {
    ElevenLabsCreditsCard(
        credits: SyncElevenLabsCredits(
            tier: "creator",
            characterCount: 30_500,
            characterLimit: 100_000,
            usedPercent: 30.5,
            voiceSlotsUsed: 4,
            voiceLimit: 30,
            professionalVoiceSlotsUsed: 1,
            professionalVoiceLimit: 5,
            resetsAt: Date().addingTimeInterval(14 * 86400),
            updatedAt: Date()),
        tintColor: Color(red: 0.48, green: 0.68, blue: 0.51))
        .padding()
}
