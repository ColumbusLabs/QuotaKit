import AppKit
import CodexBarCore
import SwiftUI

private enum ProviderTableMetrics {
    static let rowSpacing: CGFloat = 8
    static let columnSpacing: CGFloat = 12
    static let sourceWidth: CGFloat = 90
    static let statusWidth: CGFloat = 120
    static let enabledWidth: CGFloat = 70
    static let rowCornerRadius: CGFloat = 12
}

@MainActor
struct ProvidersPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @State private var expandedErrors: Set<UsageProvider> = []
    @State private var settingsStatusTextByID: [String: String] = [:]
    @State private var settingsLastAppActiveRunAtByID: [String: Date] = [:]
    @State private var activeConfirmation: ProviderSettingsConfirmationState?

    private var providers: [UsageProvider] { UsageProvider.allCases }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(contentSpacing: 12) {
                    Text("Providers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ProviderTableHeaderView()
                    ProviderTableView(
                        providers: self.providers,
                        store: self.store,
                        isEnabled: { provider in self.binding(for: provider) },
                        subtitle: { provider in self.providerSubtitle(provider) },
                        sourceLabel: { provider in self.providerSourceLabel(provider) },
                        statusLabel: { provider in self.providerStatusLabel(provider) },
                        settingsToggles: { provider in self.extraSettingsToggles(for: provider) },
                        errorDisplay: { provider in self.providerErrorDisplay(provider) },
                        isErrorExpanded: { provider in self.expandedBinding(for: provider) },
                        onCopyError: { text in self.copyToPasteboard(text) })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.runSettingsDidBecomeActiveHooks()
        }
        .alert(
            self.activeConfirmation?.title ?? "",
            isPresented: Binding(
                get: { self.activeConfirmation != nil },
                set: { isPresented in
                    if !isPresented { self.activeConfirmation = nil }
                }),
            actions: {
                if let active = self.activeConfirmation {
                    Button(active.confirmTitle) {
                        active.onConfirm()
                        self.activeConfirmation = nil
                    }
                    Button("Cancel", role: .cancel) { self.activeConfirmation = nil }
                }
            },
            message: {
                if let active = self.activeConfirmation {
                    Text(active.message)
                }
            })
    }

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
        }

        // Cursor is web-based, no CLI version to detect
        if provider == .cursor {
            return "web • \(usageText)"
        }

        var detail = "\(cliName) \(versionText) • \(usageText)"
        if provider == .antigravity {
            detail += " • experimental"
        }
        return detail
    }

    private func providerSourceLabel(_ provider: UsageProvider) -> String {
        switch provider {
        case .codex:
            if self.settings.openAIDashboardEnabled { return "web + cli" }
            return "cli"
        case .claude:
            if self.settings.debugMenuEnabled {
                return self.settings.claudeUsageDataSource.rawValue
            }
            return "auto"
        case .cursor:
            return "web"
        case .gemini:
            return "api"
        case .antigravity:
            return "local"
        }
    }

    private func providerStatusLabel(_ provider: UsageProvider) -> String {
        if let snapshot = self.store.snapshot(for: provider) {
            return snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened)
        }
        if self.store.isStale(provider: provider) {
            return "failed"
        }
        return "not yet"
    }

    private func providerErrorDisplay(_ provider: UsageProvider) -> ProviderErrorDisplay? {
        guard self.store.isStale(provider: provider), let raw = self.store.error(for: provider) else { return nil }
        return ProviderErrorDisplay(
            preview: self.truncated(raw, prefix: ""),
            full: raw)
    }

    private func extraSettingsToggles(for provider: UsageProvider) -> [ProviderSettingsToggleDescriptor] {
        guard let impl = ProviderCatalog.implementation(for: provider) else { return [] }
        let context = self.makeSettingsContext(provider: provider)
        return impl.settingsToggles(context: context)
            .filter { $0.isVisible?() ?? true }
    }

    private func makeSettingsContext(provider: UsageProvider) -> ProviderSettingsContext {
        ProviderSettingsContext(
            provider: provider,
            settings: self.settings,
            store: self.store,
            boolBinding: { keyPath in
                Binding(
                    get: { self.settings[keyPath: keyPath] },
                    set: { self.settings[keyPath: keyPath] = $0 })
            },
            statusText: { id in
                self.settingsStatusTextByID[id]
            },
            setStatusText: { id, text in
                if let text {
                    self.settingsStatusTextByID[id] = text
                } else {
                    self.settingsStatusTextByID.removeValue(forKey: id)
                }
            },
            lastAppActiveRunAt: { id in
                self.settingsLastAppActiveRunAtByID[id]
            },
            setLastAppActiveRunAt: { id, date in
                if let date {
                    self.settingsLastAppActiveRunAtByID[id] = date
                } else {
                    self.settingsLastAppActiveRunAtByID.removeValue(forKey: id)
                }
            },
            requestConfirmation: { confirmation in
                self.activeConfirmation = ProviderSettingsConfirmationState(confirmation: confirmation)
            })
    }

    private func runSettingsDidBecomeActiveHooks() {
        for provider in UsageProvider.allCases {
            for toggle in self.extraSettingsToggles(for: provider) {
                guard let hook = toggle.onAppDidBecomeActive else { continue }
                Task { @MainActor in
                    await hook()
                }
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

    private func expandedBinding(for provider: UsageProvider) -> Binding<Bool> {
        Binding(
            get: { self.expandedErrors.contains(provider) },
            set: { expanded in
                if expanded {
                    self.expandedErrors.insert(provider)
                } else {
                    self.expandedErrors.remove(provider)
                }
            })
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

private struct ProviderTableHeaderView: View {
    var body: some View {
        HStack(spacing: ProviderTableMetrics.columnSpacing) {
            Text("Provider")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Source")
                .frame(width: ProviderTableMetrics.sourceWidth, alignment: .leading)
            Text("Status")
                .frame(width: ProviderTableMetrics.statusWidth, alignment: .leading)
            Text("Enabled")
                .frame(width: ProviderTableMetrics.enabledWidth, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.bottom, 2)
    }
}

@MainActor
private struct ProviderTableView: View {
    let providers: [UsageProvider]
    @Bindable var store: UsageStore
    let isEnabled: (UsageProvider) -> Binding<Bool>
    let subtitle: (UsageProvider) -> String
    let sourceLabel: (UsageProvider) -> String
    let statusLabel: (UsageProvider) -> String
    let settingsToggles: (UsageProvider) -> [ProviderSettingsToggleDescriptor]
    let errorDisplay: (UsageProvider) -> ProviderErrorDisplay?
    let isErrorExpanded: (UsageProvider) -> Binding<Bool>
    let onCopyError: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ProviderTableMetrics.rowSpacing) {
            ForEach(self.providers, id: \.rawValue) { provider in
                ProviderTableProviderRowView(
                    provider: provider,
                    store: self.store,
                    isEnabled: self.isEnabled(provider),
                    subtitle: self.subtitle(provider),
                    sourceLabel: self.sourceLabel(provider),
                    statusLabel: self.statusLabel(provider))
                    .providerTableRowChrome()

                if self.isEnabled(provider).wrappedValue {
                    ForEach(self.settingsToggles(provider)) { toggle in
                        ProviderTableToggleRowView(toggle: toggle)
                            .providerTableRowChrome()
                    }
                }

                if let display = self.errorDisplay(provider) {
                    ProviderTableErrorRowView(
                        title: "Last \(self.store.metadata(for: provider).displayName) fetch failed:",
                        display: display,
                        isExpanded: self.isErrorExpanded(provider),
                        onCopy: { self.onCopyError(display.full) })
                        .providerTableRowChrome()
                }
            }
        }
    }
}

@MainActor
private struct ProviderTableProviderRowView: View {
    let provider: UsageProvider
    @Bindable var store: UsageStore
    @Binding var isEnabled: Bool
    let subtitle: String
    let sourceLabel: String
    let statusLabel: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ProviderTableMetrics.columnSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.store.metadata(for: self.provider).displayName)
                    .font(.body.weight(.medium))
                Text(self.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(self.sourceLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: ProviderTableMetrics.sourceWidth, alignment: .leading)

            Text(self.statusLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: ProviderTableMetrics.statusWidth, alignment: .leading)

            Toggle("", isOn: self.$isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .frame(width: ProviderTableMetrics.enabledWidth, alignment: .trailing)
        }
    }
}

@MainActor
private struct ProviderTableToggleRowView: View {
    let toggle: ProviderSettingsToggleDescriptor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ProviderTableMetrics.columnSpacing) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(self.toggle.title)
                        .font(.body.weight(.medium))
                    Text(self.toggle.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if self.toggle.binding.wrappedValue {
                    if let status = self.toggle.statusText?(), !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    let actions = self.toggle.actions.filter { $0.isVisible?() ?? true }
                    if !actions.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(actions) { action in
                                Button(action.title) {
                                    Task { @MainActor in
                                        await action.perform()
                                    }
                                }
                                .applyProviderSettingsButtonStyle(action.style)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: ProviderTableMetrics.sourceWidth)

            Color.clear
                .frame(width: ProviderTableMetrics.statusWidth)

            Toggle("", isOn: self.toggle.binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .frame(width: ProviderTableMetrics.enabledWidth, alignment: .trailing)
        }
        .onChange(of: self.toggle.binding.wrappedValue) { _, enabled in
            guard let onChange = self.toggle.onChange else { return }
            Task { @MainActor in
                await onChange(enabled)
            }
        }
        .task(id: self.toggle.binding.wrappedValue) {
            guard self.toggle.binding.wrappedValue else { return }
            guard let onAppear = self.toggle.onAppearWhenEnabled else { return }
            await onAppear()
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func applyProviderSettingsButtonStyle(_ style: ProviderSettingsActionDescriptor.Style) -> some View {
        switch style {
        case .bordered:
            self.buttonStyle(.bordered)
        case .link:
            self.buttonStyle(.link)
        }
    }
}

private struct ProviderErrorDisplay: Sendable {
    let preview: String
    let full: String
}

@MainActor
private struct ProviderTableErrorRowView: View {
    let title: String
    let display: ProviderErrorDisplay
    @Binding var isExpanded: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ProviderTableMetrics.columnSpacing) {
            ProviderErrorView(
                title: self.title,
                display: self.display,
                isExpanded: self.$isExpanded,
                onCopy: self.onCopy)
                .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: ProviderTableMetrics.sourceWidth)

            Color.clear
                .frame(width: ProviderTableMetrics.statusWidth)

            Color.clear
                .frame(width: ProviderTableMetrics.enabledWidth)
        }
    }
}

@MainActor
private struct ProviderErrorView: View {
    let title: String
    let display: ProviderErrorDisplay
    @Binding var isExpanded: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    self.onCopy()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy error")
            }

            Text(self.display.preview)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if self.display.preview != self.display.full {
                Button(self.isExpanded ? "Hide details" : "Show details") { self.isExpanded.toggle() }
                    .buttonStyle(.link)
                    .font(.footnote)
            }

            if self.isExpanded {
                Text(self.display.full)
                    .font(.footnote)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 2)
    }
}

@MainActor
private struct ProviderSettingsConfirmationState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void

    init(confirmation: ProviderSettingsConfirmation) {
        self.title = confirmation.title
        self.message = confirmation.message
        self.confirmTitle = confirmation.confirmTitle
        self.onConfirm = confirmation.onConfirm
    }
}

extension View {
    fileprivate func providerTableRowChrome() -> some View {
        self
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: ProviderTableMetrics.rowCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ProviderTableMetrics.rowCornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1))
    }
}
