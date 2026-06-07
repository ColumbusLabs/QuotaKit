import CodexBarSync
import SwiftUI

/// Quiet top-of-list notice for demo mode. Keeps sample-data context visible
/// without making the provider cards look like debug fixtures.
struct DemoPreviewBanner: View {
    @Environment(\.quotaKitTheme) private var theme
    let snapshot: SyncedUsageSnapshot?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(self.theme.accent)
                .frame(width: 30, height: 30)
                .background(self.theme.surfaceElevated, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Demo data")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(self.theme.textPrimary)
                Text("Synthetic providers for preview")
                    .font(.caption)
                    .foregroundStyle(self.theme.textMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .qkCardBackground(elevation: .surface, cornerRadius: 14)
        .accessibilityIdentifier("demo-preview-banner")
        .accessibilityElement(children: .combine)
    }
}

#Preview("Mock banner") {
    DemoPreviewBanner(snapshot: SyncedUsageSnapshot(
        providers: [PreviewData.claudeProvider],
        syncTimestamp: Date(),
        deviceName: "MacBook Pro",
        appVersion: "0.23.6",
        mobileVersion: "1.5.2"))
}
