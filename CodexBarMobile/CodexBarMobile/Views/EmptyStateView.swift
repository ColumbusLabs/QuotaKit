import SwiftUI

struct EmptyStateView: View {
    @Environment(\.quotaKitTheme) private var theme
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    var systemImage: String = "icloud.and.arrow.down"
    var onDemo: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: self.systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(self.theme.accent)
                .frame(width: 72, height: 72)
                .background(self.theme.surfaceElevated, in: Circle())

            VStack(spacing: 8) {
                Text(self.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(self.theme.textPrimary)
                Text(self.message)
                    .font(.body)
                    .foregroundStyle(self.theme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let onDemo {
                Button(action: onDemo) {
                    Label("View Demo", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(self.theme.accent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(self.theme.canvas)
    }
}
