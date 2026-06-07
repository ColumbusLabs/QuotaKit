import CodexBarSync
import SwiftUI
import UIKit

struct OnboardingView: View {
    @Environment(\.quotaKitTheme) private var theme
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

                QKSurfaceCard(elevation: .elevated) {
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
                        Text(ProductConfig.macSetupDisplayURL)
                            .font(.caption.monospaced())
                            .foregroundStyle(self.theme.accent)
                            .textSelection(.enabled)
                    }
                    .padding(16)
                }

                VStack(spacing: 12) {
                    ForEach(Array(self.steps.enumerated()), id: \.offset) { index, step in
                        QKSurfaceCard {
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
                            .padding(16)
                        }
                    }
                }

                VStack(spacing: 12) {
                    MacSetupLinkActions(prominentShare: true)

                    if let onDemo {
                        Button(action: onDemo) {
                            Label("Preview with Demo Data", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(self.theme.accent)
                        .controlSize(.regular)
                    }
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
}

struct MacSetupLinkActions: View {
    let prominentShare: Bool
    @State private var didCopySetupLink = false

    var body: some View {
        VStack(spacing: 12) {
            if self.prominentShare {
                ShareLink(item: ProductConfig.macSetupURL) {
                    Label("Share Mac Setup Link", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                ShareLink(item: ProductConfig.macSetupURL) {
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
        UIPasteboard.general.string = ProductConfig.macSetupURL.absoluteString
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
