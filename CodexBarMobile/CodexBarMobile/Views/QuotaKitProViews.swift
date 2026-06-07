import CodexBarSync
import SwiftUI

struct FreeProviderSelectorView: View {
    let groups: [ProviderAccountGroup]
    @Binding var selectedProviderID: String
    let effectiveSelectedProviderID: String?

    private var selectedGroup: ProviderAccountGroup? {
        guard let effectiveSelectedProviderID else { return nil }
        return self.groups.first { $0.providerID == effectiveSelectedProviderID }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "1.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("Free provider")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(self.selectedGroup?.providerName ?? String(localized: "Choose a provider"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                ForEach(self.groups) { group in
                    Button {
                        self.selectedProviderID = group.providerID
                    } label: {
                        if group.providerID == self.effectiveSelectedProviderID {
                            Label(group.providerName, systemImage: "checkmark")
                        } else {
                            Text(group.providerName)
                        }
                    }
                }
            } label: {
                Label("Change", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 1))
        .accessibilityIdentifier("free-provider-selector")
    }
}

struct QuotaKitProSettingsView: View {
    let store: ProEntitlementStore

    var body: some View {
        QuotaKitProPanel(
            store: self.store,
            title: "QuotaKit Pro",
            lockedMessage: String(localized: "Unlock the official iOS companion features and support ongoing QuotaKit maintenance."),
            unlockedMessage: String(localized: "Lifetime unlock is active on this Apple ID."),
            showsFeatureList: true)
            .padding(.vertical, 4)
    }
}

struct QuotaKitProLockedSummaryView: View {
    let store: ProEntitlementStore
    let lockedProviderCount: Int

    var body: some View {
        QuotaKitProPanel(
            store: self.store,
            title: "QuotaKit Pro",
            lockedMessage: self.lockedMessage,
            unlockedMessage: String(localized: "All synced provider cards are unlocked."),
            showsFeatureList: false)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1))
            .accessibilityIdentifier("quotakit-pro-locked-summary")
    }

    private var lockedMessage: String {
        let format = String(localized: "Hidden synced provider groups: %lld. Upgrade once to unlock unlimited provider cards, widgets, alerts, history, share cards, and export features.")
        return String.localizedStringWithFormat(format, self.lockedProviderCount)
    }
}

private struct QuotaKitProPanel: View {
    let store: ProEntitlementStore
    let title: LocalizedStringResource
    let lockedMessage: String
    let unlockedMessage: String
    let showsFeatureList: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: self.store.isProUnlocked ? "checkmark.seal.fill" : "seal.fill")
                    .font(.title2)
                    .foregroundStyle(self.store.isProUnlocked ? .green : Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(self.title)
                            .font(.headline)
                        Spacer()
                        Text(self.store.statusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(self.store.isProUnlocked ? .green : .secondary)
                    }

                    Text(self.summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !self.store.isProUnlocked {
                Text(self.lockedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if self.showsFeatureList {
                    QuotaKitProFeatureList()
                }
            } else {
                Text(self.unlockedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case .error(let message) = self.store.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            QuotaKitProPurchaseControls(store: self.store)
        }
    }

    private var summaryText: String {
        switch self.store.state {
        case .loading:
            return String(localized: "Checking your Pro status.")
        case .locked:
            let format = String(localized: "%@ · Lifetime unlock. No subscription.")
            return String.localizedStringWithFormat(format, ProductConfig.launchPriceCopy)
        case .unlocked:
            return String(localized: "Lifetime unlock active. Thank you for supporting QuotaKit.")
        case .pending:
            return String(localized: "Purchase is pending approval or completion.")
        case .productUnavailable:
            return String(localized: "QuotaKit Pro is not available from the App Store right now.")
        case .error:
            return String(localized: "Could not update Pro status.")
        }
    }
}

private struct QuotaKitProFeatureList: View {
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: self.columns, alignment: .leading, spacing: 8) {
            ForEach(FeatureGate.allCases) { feature in
                Label(feature.title, systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.top, 2)
    }
}

private struct QuotaKitProPurchaseControls: View {
    let store: ProEntitlementStore

    private var isBusy: Bool {
        self.store.isPurchasing || self.store.isRestoring
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await self.store.purchase() }
            } label: {
                if self.store.isPurchasing {
                    ProgressView()
                } else {
                    Label(self.buyButtonTitle, systemImage: self.store.isProUnlocked ? "checkmark" : "cart.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.store.isProUnlocked || self.isBusy || self.store.state == .productUnavailable)

            Button {
                Task { await self.store.restorePurchases() }
            } label: {
                if self.store.isRestoring {
                    ProgressView()
                } else {
                    Text("Restore")
                }
            }
            .buttonStyle(.bordered)
            .disabled(self.isBusy)
        }
    }

    private var buyButtonTitle: String {
        self.store.isProUnlocked ? String(localized: "Unlocked") : self.store.displayPrice
    }
}

#if DEBUG
#Preview("QuotaKit Pro Settings Locked") {
    List {
        Section {
            QuotaKitProSettingsView(store: .preview(state: .locked))
        }
    }
}

#Preview("QuotaKit Pro Settings Unlocked") {
    List {
        Section {
            QuotaKitProSettingsView(store: .preview(state: .unlocked(source: .storeKit)))
        }
    }
}

#Preview("QuotaKit Pro Locked Summary") {
    QuotaKitProLockedSummaryView(
        store: .preview(state: .locked),
        lockedProviderCount: 4)
        .padding()
}
#endif
