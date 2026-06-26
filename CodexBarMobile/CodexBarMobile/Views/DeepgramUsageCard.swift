import CodexBarSync
import SwiftUI

/// Deepgram speech / agent / TTS usage card. Renders when
/// `ProviderUsageSnapshot.deepgramUsage` is populated. Hidden for
/// Mac versions older than 0.27.0.
///
/// Shows the active project (with "(of N)" hint when Mac has >1
/// project) plus the hour breakdown and request count. LLM token
/// + TTS character lanes appear only when non-zero.
struct DeepgramUsageCard: View {
    let usage: SyncDeepgramUsage
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(String(localized: "deepgram_usage_title", defaultValue: "Deepgram usage"))
                    .font(.headline)
                Spacer()
                if let project = usage.projectName, !project.isEmpty {
                    self.projectBadge(project)
                }
            }

            self.hoursRow

            if self.usage.requests > 0 {
                HStack {
                    Text(String(localized: "deepgram_requests_label", defaultValue: "Requests"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.formatInt(self.usage.requests))
                        .font(.caption.bold().monospacedDigit())
                }
            }

            if self.usage.tokensIn > 0 || self.usage.tokensOut > 0 {
                HStack {
                    Text(String(localized: "deepgram_agent_tokens_label", defaultValue: "Agent tokens"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Self.formatInt(self.usage.tokensIn)) → \(Self.formatInt(self.usage.tokensOut))")
                        .font(.caption.bold().monospacedDigit())
                }
            }

            if self.usage.ttsCharacters > 0 {
                HStack {
                    Text(String(localized: "deepgram_tts_characters_label", defaultValue: "TTS characters"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.formatInt(self.usage.ttsCharacters))
                        .font(.caption.bold().monospacedDigit())
                }
            }
        }
        .padding(16)
        .qkCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deepgram-usage-card")
    }

    private func projectBadge(_ name: String) -> some View {
        let suffix = self.usage.projectCount > 1
            ? " · \(self.usage.projectCount)"
            : ""
        return Text(name + suffix)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(self.tintColor.opacity(0.16)))
            .foregroundStyle(self.tintColor)
    }

    private var hoursRow: some View {
        let speech = self.usage.speechHours
        let agent = self.usage.agentHours
        let total = self.usage.totalHours
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "deepgram_speech_hours_label", defaultValue: "Speech / Agent / Total"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Self.formatHours(speech)) · \(Self.formatHours(agent)) · \(Self.formatHours(total))")
                    .font(.subheadline.monospacedDigit())
            }
        }
    }

    private static func formatHours(_ value: Double) -> String {
        if value <= 0 { return "0h" }
        if value < 1 {
            return String(format: "%.2fh", value)
        }
        return String(format: "%.1fh", value)
    }

    private static func formatInt(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

#Preview {
    DeepgramUsageCard(
        usage: SyncDeepgramUsage(
            projectName: "ProductionAssistant",
            projectCount: 3,
            speechHours: 8.4,
            totalHours: 12.7,
            agentHours: 4.3,
            requests: 1215,
            tokensIn: 320_000,
            tokensOut: 180_000,
            ttsCharacters: 45000,
            updatedAt: Date()),
        tintColor: Color(red: 0.49, green: 0.23, blue: 0.93))
        .padding()
}
