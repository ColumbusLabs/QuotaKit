import CodexBarSync
import SwiftUI
import UIKit

private enum MobileRootTab: Hashable {
    case usage
    case cost
    case settings
}

struct ContentView: View {
    let usageData: SyncedUsageData
    @State private var isDemoMode = false
    @State private var selectedTab: MobileRootTab
    @AppStorage("onboardingSeenVersion") private var onboardingSeenVersion = ""

    init(usageData: SyncedUsageData) {
        self.usageData = usageData
        _selectedTab = State(initialValue: UserDefaults.standard
            .bool(forKey: MobileSettingsKeys.openCostByDefault) ? .cost : .usage)
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var shouldShowOnboarding: Bool {
        self.onboardingSeenVersion != self.currentVersion
    }

    private var hasSyncedData: Bool {
        self.usageData.snapshot != nil
    }

    var body: some View {
        Group {
            if !self.hasSyncedData, !self.isDemoMode {
                NavigationStack {
                    OnboardingView(onDemo: {
                        self.onboardingSeenVersion = self.currentVersion
                        self.isDemoMode = true
                    })
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else {
                TabView(selection: self.$selectedTab) {
                    UsageTab(usageData: self.usageData, isDemoMode: self.$isDemoMode)
                        .tag(MobileRootTab.usage)
                        .tabItem {
                            Label("Usage", systemImage: "chart.bar.fill")
                        }

                    CostTab(usageData: self.usageData, isDemoMode: self.$isDemoMode)
                        .tag(MobileRootTab.cost)
                        .tabItem {
                            Label("Cost", systemImage: "dollarsign.circle.fill")
                        }

                    SettingsTab(
                        usageData: self.usageData,
                        isDemoMode: self.isDemoMode)
                        .tag(MobileRootTab.settings)
                        .tabItem {
                            Label("Setting", systemImage: "gearshape")
                        }
                }
                .modifier(TabBarMinimizeModifier())
                .fullScreenCover(isPresented: .init(
                    get: { self.hasSyncedData && self.shouldShowOnboarding },
                    set: { if !$0 { self.onboardingSeenVersion = self.currentVersion } }))
                {
                    OnboardingSheet(onDismiss: {
                        self.onboardingSeenVersion = self.currentVersion
                    }, onDemo: {
                        self.onboardingSeenVersion = self.currentVersion
                        self.isDemoMode = true
                    })
                }
            }
        }
    }
}

private struct OnboardingSheet: View {
    let onDismiss: () -> Void
    let onDemo: () -> Void

    var body: some View {
        NavigationStack {
            OnboardingView(onDemo: self.onDemo)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            self.onDismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }
}

/// Keeps the tab bar always visible (no auto-minimize on scroll).
private struct TabBarMinimizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.never)
        } else {
            content
        }
    }
}

// MARK: - Usage Tab

private struct UsageTab: View {
    let usageData: SyncedUsageData
    @Binding var isDemoMode: Bool

    private var displaySnapshot: SyncedUsageSnapshot? {
        if self.isDemoMode {
            return PreviewData.sampleSnapshot
        }
        return self.usageData.snapshot
    }

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = self.displaySnapshot {
                    if MockProviderDetector.filteredProviders(from: snapshot).isEmpty {
                        EmptyStateView(
                            title: "No Providers Enabled",
                            message: "Enable providers in QuotaKit on your Mac to see usage data here.",
                            systemImage: "slider.horizontal.3")
                    } else {
                        ProviderListView(
                            snapshot: snapshot,
                            usageData: self.usageData,
                            isDemoMode: self.isDemoMode)
                    }
                } else {
                    OnboardingView(onDemo: { self.isDemoMode = true })
                }
            }
            .navigationTitle(self.isDemoMode || self.displaySnapshot == nil ? "" : String(localized: "QuotaKit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if self.isDemoMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            self.isDemoMode = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Exit demo preview"))
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("With Data") {
    ContentView(usageData: PreviewData.makeSyncedUsageData())
        .environment(ProEntitlementStore.preview(state: .locked))
        .environment(RemoteConfigStore())
        .quotaKitThemed()
}

#Preview("Empty State") {
    ContentView(usageData: PreviewData.makeEmptyUsageData())
        .environment(ProEntitlementStore.preview(state: .locked))
        .environment(RemoteConfigStore())
        .quotaKitThemed()
}
