import AppKit
import SwiftUI

@MainActor
struct GeneralPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var store: UsageStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(contentSpacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        PreferenceToggleRow(
                            title: self.store.metadata(for: .codex).toggleTitle,
                            subtitle: self.providerSubtitle(.codex),
                            binding: self.codexBinding)

                        self.codexSigningStatus()
                    }
                    .padding(.bottom, 18)

                    PreferenceToggleRow(
                        title: self.store.metadata(for: .claude).toggleTitle,
                        subtitle: self.providerSubtitle(.claude),
                        binding: self.claudeBinding)

                    if let claudeError = self.providerError(.claude) {
                        Text(claudeError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                SettingsSection(contentSpacing: 6) {
                    PreferenceToggleRow(
                        title: "Check provider status",
                        subtitle: "Polls OpenAI/Claude status pages and surfaces incidents in the icon and menu.",
                        binding: self.$settings.statusChecksEnabled)
                }

                Divider()

                SettingsSection(contentSpacing: 6) {
                    Text("Refresh cadence")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Picker("", selection: self.$settings.refreshFrequency) {
                        ForEach(RefreshFrequency.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if self.settings.refreshFrequency == .manual {
                        Text("Auto-refresh is off; use the menu's Refresh command.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                SettingsSection(contentSpacing: 16) {
                    PreferenceToggleRow(
                        title: "Start at Login",
                        subtitle: "Automatically opens CodexBar when you start your Mac.",
                        binding: self.$settings.launchAtLogin)
                    PreferenceToggleRow(
                        title: "Show Debug Settings",
                        subtitle: "Expose troubleshooting tools in the Debug tab.",
                        binding: self.$settings.debugMenuEnabled)
                    HStack {
                        Spacer()
                        Button("Quit CodexBar") { NSApp.terminate(nil) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                    .padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var codexBinding: Binding<Bool> { self.binding(for: .codex) }
    private var claudeBinding: Binding<Bool> { self.binding(for: .claude) }

    private func binding(for provider: UsageProvider) -> Binding<Bool> {
        let meta = self.store.metadata(for: provider)
        return Binding(
            get: { self.settings.isProviderEnabled(provider: provider, metadata: meta) },
            set: { self.settings.setProviderEnabled(provider: provider, metadata: meta, enabled: $0) })
    }

    private func providerSubtitle(_ provider: UsageProvider) -> String {
        let meta = self.store.metadata(for: provider)
        let cliName = meta.cliName
        let version = self.store.version(for: provider)
        var versionText = version ?? "not detected"
        if provider == .claude, let parenRange = versionText.range(of: "(") {
            versionText = versionText[..<parenRange.lowerBound].trimmingCharacters(in: .whitespaces)
        }

        let usageText: String
        if let snapshot = self.store.snapshot(for: provider) {
            let timestamp = snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened)
            usageText = "usage fetched \(timestamp)"
        } else if self.store.isStale(provider: provider) {
            usageText = "last fetch failed"
        } else {
            usageText = "usage not fetched yet"
        }

        if cliName == "codex" {
            return "\(versionText) • \(usageText)"
        } else {
            return "\(cliName) \(versionText) • \(usageText)"
        }
    }

    private func providerError(_ provider: UsageProvider) -> String? {
        guard self.store.isStale(provider: provider), let raw = self.store.error(for: provider) else { return nil }
        let meta = self.store.metadata(for: provider)
        let prefix = "Last \(meta.displayName) fetch failed: "
        return self.truncated(raw, prefix: prefix)
    }

    @ViewBuilder
    private func codexSigningStatus() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let credits = self.store.credits {
                Text("Codex credits")
                    .font(.footnote.weight(.semibold))
                Text(self.creditsSummary(credits))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let hint = self.store.lastCreditsError ?? "Credits unavailable; keep Codex running to refresh."
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let lastError = self.store.lastCreditsError {
                Text(self.truncated(lastError, prefix: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func truncated(_ text: String, prefix: String, maxLength: Int = 160) -> String {
        var message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.count > maxLength {
            let idx = message.index(message.startIndex, offsetBy: maxLength)
            message = "\(message[..<idx])…"
        }
        return prefix + message
    }

    private func creditsSummary(_ snapshot: CreditsSnapshot) -> String {
        let amount = snapshot.remaining.formatted(.number.precision(.fractionLength(0...2)))
        let timestamp = snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened)
        return "Remaining \(amount) credits as of \(timestamp)."
    }
}
