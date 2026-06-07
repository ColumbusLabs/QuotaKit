import CodexBarSync
import SwiftUI
import UIKit

struct OnboardingView: View {
    @Environment(\.quotaKitTheme) private var theme
    @Environment(RemoteConfigStore.self) private var remoteConfigStore
    var onDemo: (() -> Void)?

    private let steps: [(icon: String, title: LocalizedStringResource, detail: LocalizedStringResource)] = [
        ("laptopcomputer.and.arrow.down", "Open setup on your Mac", "Open the setup link on your Mac, then download QuotaKit and move it to Applications."),
        ("gearshape", "Enable iCloud Sync", "Open QuotaKit on your Mac → Settings → turn on iCloud Sync."),
        ("icloud.and.arrow.up", "Wait for Sync", "Usage data will appear here automatically once your Mac pushes data to iCloud."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(self.theme.accent)
                        .frame(width: 80, height: 80)
                        .background(self.theme.surfaceElevated, in: Circle())

                    Text("Welcome to QuotaKit")
                        .font(.title.weight(.bold))
                        .foregroundStyle(self.theme.textPrimary)

                    Text("Monitor your AI coding tool usage on iPhone.\nRequires the QuotaKit Mac app.")
                        .font(.subheadline)
                        .foregroundStyle(self.theme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Image(systemName: "laptopcomputer.and.arrow.down")
                        .font(.title2)
                        .foregroundStyle(self.theme.accent)
                    Text("Mac setup required")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(self.theme.textPrimary)
                    Text("QuotaKit needs the Mac app to collect usage. Share this setup link to your Mac or copy it to open there.")
                        .font(.caption)
                        .foregroundStyle(self.theme.textMuted)
                        .multilineTextAlignment(.center)
                    Text(self.remoteConfigStore.setupDisplayURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(self.theme.accent)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 8)

                VStack(spacing: 18) {
                    ForEach(Array(self.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: step.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(self.theme.accent)
                                .frame(width: 40, height: 40)
                                .background(self.theme.surfaceElevated, in: Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(String(localized: "Step")) \(index + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(self.theme.accent)
                                Text(step.title)
                                    .font(.headline)
                                    .foregroundStyle(self.theme.textPrimary)
                                Text(step.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(self.theme.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.top, 2)

                if let onDemo {
                    OnboardingActionRow(onDemo: onDemo)
                } else {
                    MacSetupLinkActions(prominentShare: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(self.theme.canvas)
    }
}

#Preview {
    OnboardingView(onDemo: {})
        .environment(RemoteConfigStore())
        .quotaKitThemed()
}

private struct OnboardingActionRow: View {
    @Environment(\.quotaKitTheme) private var theme
    @Environment(RemoteConfigStore.self) private var remoteConfigStore
    let onDemo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ShareLink(item: self.remoteConfigStore.setupURL) {
                OnboardingActionLabel(title: "Share with Mac", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .tint(self.theme.accent)
            .frame(maxWidth: .infinity)

            Button(action: self.onDemo) {
                OnboardingActionLabel(title: "Demo Preview", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(self.theme.accent)
            .frame(maxWidth: .infinity)
        }
        .controlSize(.regular)
    }
}

private struct OnboardingActionLabel: View {
    let title: LocalizedStringResource
    let systemImage: String

    var body: some View {
        Label {
            Text(self.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } icon: {
            Image(systemName: self.systemImage)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 38)
    }
}

struct MacSetupLinkActions: View {
    let prominentShare: Bool
    @State private var didCopySetupLink = false
    @Environment(RemoteConfigStore.self) private var remoteConfigStore

    var body: some View {
        VStack(spacing: 12) {
            if self.prominentShare {
                ShareLink(item: self.remoteConfigStore.setupURL) {
                    Label("Share Mac Setup Link", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                ShareLink(item: self.remoteConfigStore.setupURL) {
                    Label("Share Mac Setup Link", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            Button {
                self.copySetupLink()
            } label: {
                if self.didCopySetupLink {
                    Label("Copied Setup Link", systemImage: "checkmark.circle.fill")
                } else {
                    Label("Copy Setup Link", systemImage: "doc.on.doc")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(self.prominentShare ? .regular : .small)
        }
    }

    private func copySetupLink() {
        UIPasteboard.general.string = self.remoteConfigStore.setupURL.absoluteString
        withAnimation {
            self.didCopySetupLink = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation {
                    self.didCopySetupLink = false
                }
            }
        }
    }
}
