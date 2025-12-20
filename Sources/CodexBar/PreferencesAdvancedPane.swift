import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct AdvancedPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var store: UsageStore
    @State private var isInstallingCLI = false
    @State private var cliStatus: String?

    var body: some View {
        let ccusageAvailability = self.settings.ccusageAvailability
        let ccusageBinding = Binding(
            get: { ccusageAvailability.isAnyInstalled ? self.settings.ccusageCostUsageEnabled : false },
            set: { self.settings.ccusageCostUsageEnabled = $0 })

        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
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

                SettingsSection(contentSpacing: 12) {
                    Text("Display")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    PreferenceToggleRow(
                        title: "Show usage as used",
                        subtitle: "Progress bars fill as you consume quota (instead of showing remaining).",
                        binding: self.$settings.usageBarsShowUsed)
                    PreferenceToggleRow(
                        title: "Merge Icons",
                        subtitle: "Use a single menu bar icon with a provider switcher.",
                        binding: self.$settings.mergeIcons)
                    PreferenceToggleRow(
                        title: "Surprise me",
                        subtitle: "Check if you like your agents having some fun up there.",
                        binding: self.$settings.randomBlinkEnabled)
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    Text("Usage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    PreferenceToggleRow(
                        title: "Show ccusage cost summary",
                        subtitle: "Requires ccusage. Shows session + monthly cost in the menu.",
                        binding: ccusageBinding)
                        .disabled(!ccusageAvailability.isAnyInstalled)
                    if ccusageAvailability.isAnyInstalled {
                        let detected: [String] = {
                            var items: [String] = []
                            if ccusageAvailability.codexPath != nil { items.append("Codex") }
                            if ccusageAvailability.claudePath != nil { items.append("Claude") }
                            return items
                        }()
                        if !detected.isEmpty {
                            Text("Detected: \(detected.joined(separator: ", "))")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        if ccusageAvailability.codexPath == nil {
                            Text("Missing Codex support (ccusage-codex). Install: npm i -g @ccusage/codex")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        if ccusageAvailability.claudePath == nil {
                            Text("Missing Claude support (ccusage). Install: npm i -g ccusage")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }

                        if self.settings.ccusageCostUsageEnabled {
                            Text("Auto-refresh: hourly · Timeout: 10m")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)

                            Group {
                                if ccusageAvailability.claudePath != nil {
                                    self.ccusageStatusLine(provider: .claude)
                                }
                                if ccusageAvailability.codexPath != nil {
                                    self.ccusageStatusLine(provider: .codex)
                                }
                            }
                        }
                    } else {
                        Text("ccusage not detected.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                        Text("Install Claude: npm i -g ccusage")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                        Text("Install Codex: npm i -g @ccusage/codex")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    Text("Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    PreferenceToggleRow(
                        title: "Check provider status",
                        subtitle: "Polls OpenAI/Claude status pages and surfaces incidents in the icon and menu.",
                        binding: self.$settings.statusChecksEnabled)
                }

                Divider()

                SettingsSection(contentSpacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            Task { await self.installCLI() }
                        } label: {
                            if self.isInstallingCLI {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Install CLI")
                            }
                        }
                        .disabled(self.isInstallingCLI)

                        if let status = self.cliStatus {
                            Text(status)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Text("Symlink CodexBarCLI to /usr/local/bin and /opt/homebrew/bin as codexbar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                SettingsSection(contentSpacing: 10) {
                    PreferenceToggleRow(
                        title: "Show Debug Settings",
                        subtitle: "Expose troubleshooting tools in the Debug tab.",
                        binding: self.$settings.debugMenuEnabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear { self.settings.refreshCCUsageAvailability() }
    }

    private func ccusageStatusLine(provider: UsageProvider) -> some View {
        let name = provider == .claude ? "Claude" : "Codex"
        if self.store.isTokenRefreshInFlight(for: provider) {
            return Text("\(name): fetching…")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        if let snapshot = self.store.tokenSnapshot(for: provider) {
            let updated = UsageFormatter.updatedString(from: snapshot.updatedAt)
            let cost = snapshot.last30DaysCostUSD.map { UsageFormatter.usdString($0) } ?? "—"
            return Text("\(name): \(updated) · 30d \(cost)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        if let error = self.store.tokenError(for: provider), !error.isEmpty {
            let truncated = UsageFormatter.truncatedSingleLine(error, max: 120)
            return Text("\(name): \(truncated)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        if let lastAttempt = self.store.tokenLastAttemptAt(for: provider) {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .abbreviated
            let when = rel.localizedString(for: lastAttempt, relativeTo: Date())
            return Text("\(name): last attempt \(when)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        return Text("\(name): no data yet")
            .font(.footnote)
            .foregroundStyle(.tertiary)
    }

    // MARK: - CLI installer

    private func installCLI() async {
        guard !self.isInstallingCLI else { return }
        self.isInstallingCLI = true
        defer { self.isInstallingCLI = false }

        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("CodexBarCLI")

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            await MainActor.run { self.cliStatus = "Helper missing; reinstall CodexBar." }
            return
        }

        let installScript = """
        #!/usr/bin/env bash
        set -euo pipefail
        HELPER="\(helperURL.path)"
        TARGETS=("/usr/local/bin/codexbar" "/opt/homebrew/bin/codexbar")

        for t in "${TARGETS[@]}"; do
          mkdir -p "$(dirname "$t")"
          ln -sf "$HELPER" "$t"
          echo "Linked $t -> $HELPER"
        done
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("install_codexbar_cli.sh")

        do {
            defer { try? FileManager.default.removeItem(at: scriptURL) }
            try installScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let escapedPath = scriptURL.path.replacingOccurrences(of: "\"", with: "\\\"")
            let appleScript = "do shell script \"bash \\\"\(escapedPath)\\\"\" with administrator privileges"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript]
            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()
            let status: String
            if process.terminationStatus == 0 {
                status = "Installed. Try: codexbar usage"
            } else {
                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                status = "Failed: \(msg ?? "error")"
            }
            await MainActor.run {
                self.cliStatus = status
            }
        } catch {
            await MainActor.run { self.cliStatus = "Failed: \(error.localizedDescription)" }
        }
    }
}
