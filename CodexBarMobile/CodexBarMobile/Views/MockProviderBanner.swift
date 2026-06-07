import CodexBarSync
import SwiftUI

/// Top-of-tab banner shown when at least one provider in the current
/// sync snapshot is detected as mock data (per `MockProviderDetector`).
struct MockProviderBanner: View {
    let snapshot: SyncedUsageSnapshot?

    var body: some View {
        if let snapshot, MockProviderDetector.hasAnyMock(in: snapshot) {
            let count = MockProviderDetector.mockCount(in: snapshot)
            QKStatusChip(
                text: String(
                    format: String(localized: "Mock · %lld synthetic providers"),
                    count),
                style: .mock,
                systemImage: "testtube.2")
                .frame(maxWidth: .infinity, alignment: .leading)
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
