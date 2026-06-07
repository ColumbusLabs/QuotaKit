import CodexBarSync
import SwiftUI
import UIKit

struct OnboardingView: View {
    var onDemo: (() -> Void)?

    private let steps: [(icon: String, title: LocalizedStringResource, detail: LocalizedStringResource)] = [
        ("laptopcomputer.and.arrow.down", "Open setup on your Mac", "Open the setup link on your Mac, then download QuotaKit and move it to Applications."),
        ("gearshape", "Enable iCloud Sync", "Open QuotaKit on your Mac → Settings → turn on iCloud Sync."),
        ("icloud.and.arrow.up", "Wait for Sync", "Usage data will appear here automatically once your Mac pushes data to iCloud."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)

                    Text("Welcome to QuotaKit")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Monitor your AI coding tool usage on iPhone.\nRequires the QuotaKit Mac app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                // Mac setup starts on the Mac; this block gives iPhone users
                // a handoff path instead of pretending the phone can install it.
                VStack(spacing: 8) {
                    Image(systemName: "laptopcomputer.and.arrow.down")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Text("Mac setup required")
                        .font(.subheadline.weight(.semibold))
                    Text("QuotaKit needs the Mac app to collect usage. Share this setup link to your Mac or copy it to open there.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(ProductConfig.macSetupDisplayURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tint)
                        .textSelection(.enabled)
                }
                .padding()
                .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                // Steps
                VStack(spacing: 20) {
                    ForEach(Array(self.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(.tint.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                Image(systemName: step.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(.tint)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(String(localized: "Step")) \(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                                Text(step.title)
                                    .font(.headline)
                                Text(step.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 4)

                // Actions
                VStack(spacing: 12) {
                    MacSetupLinkActions(prominentShare: true)

                    if let onDemo {
                        Button(action: onDemo) {
                            Label("Preview with Demo Data", systemImage: "play.fill")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
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
