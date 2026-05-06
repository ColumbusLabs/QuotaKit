import CodexBarSync
import SwiftUI

/// Top-of-tab banner shown when at least one provider in the current
/// sync snapshot is detected as mock data (per `MockProviderDetector`).
///
/// **When visible** (iOS 1.5.2+):
/// - Mac has `CodexBarMockProvidersEnabled` ON (or env var) and has
///   pushed at least one cycle since.
/// - Renders above Usage tab and Cost tab content so the user is
///   reminded their displayed numbers include synthetic data.
///
/// **Why it's prominent**: cost dashboards aggregate every provider's
/// numbers. Without this banner, a QA tester or Beta tester would see
/// "$48 extra" in their 30-day Cost dashboard and assume their real
/// usage spiked. The banner makes it explicit.
///
/// **Dismissal**: there is intentionally no dismiss button. The banner
/// disappears automatically when Mac toggles mock off and the next
/// sync cycle clears the mock CKRecords (~30s). Forcing a dismiss
/// button would let the user accidentally hide the warning while
/// mocks are still active.
struct MockProviderBanner: View {
    let snapshot: SyncedUsageSnapshot?

    var body: some View {
        if let snapshot, MockProviderDetector.hasAnyMock(in: snapshot) {
            HStack(spacing: 10) {
                Image(systemName: "testtube.2")
                    .font(.subheadline.bold())
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Showing mock data")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                    Text("\(MockProviderDetector.mockCount(in: snapshot)) synthetic providers from Mac · toggle off in Mac Settings → Mobile → Debug")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.purple.opacity(0.10)))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.purple.opacity(0.30), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .accessibilityIdentifier("mock-provider-banner")
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview("Mock banner") {
    MockProviderBanner(snapshot: SyncedUsageSnapshot(
        providers: [PreviewData.claudeProvider],
        syncTimestamp: Date(),
        deviceName: "MacBook Pro",
        appVersion: "0.23.6",
        mobileVersion: "1.5.2"))
}
