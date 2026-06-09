import CodexBarSync
import SwiftUI

struct FreeProviderSelectorView: View {
    let groups: [ProviderAccountGroup]
    @Binding var selectedProviderID: String
    @Binding var selectedProviderLockedUntil: Double
    let effectiveSelectedProviderID: String?
    private static let selectionLockDuration: TimeInterval = 7 * 24 * 60 * 60

    private var selectedGroup: ProviderAccountGroup? {
        guard let effectiveSelectedProviderID else { return nil }
        return self.groups.first { $0.providerID == effectiveSelectedProviderID }
    }

    private var lockExpirationDate: Date? {
        guard !self.selectedProviderID.isEmpty,
              self.selectedProviderID == self.effectiveSelectedProviderID
        else { return nil }
        let date = Date(timeIntervalSince1970: self.selectedProviderLockedUntil)
        return date > Date() ? date : nil
    }

    private var isSelectionLocked: Bool {
        self.lockExpirationDate != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("Selected provider")
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
                        self.selectedProviderLockedUntil = Date()
                            .addingTimeInterval(Self.selectionLockDuration)
                            .timeIntervalSince1970
                    } label: {
                        if group.providerID == self.effectiveSelectedProviderID {
                            Label(group.providerName, systemImage: "checkmark")
                        } else {
                            Text(group.providerName)
                        }
                    }
                }
            } label: {
                Label(self.changeLabel, systemImage: self.isSelectionLocked ? "lock.fill" : "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(self.isSelectionLocked)
        }
        .padding(14)
        .qkCardBackground(elevation: .elevated, cornerRadius: 12)
        .accessibilityIdentifier("free-provider-selector")
    }

    private var changeLabel: LocalizedStringResource {
        if let lockExpirationDate {
            let formattedDate = lockExpirationDate.formatted(.dateTime.month(.abbreviated).day())
            return LocalizedStringResource("Locked until \(formattedDate)")
        }
        return "Change"
    }
}

struct QuotaKitProSettingsView: View {
    let store: ProEntitlementStore

    var body: some View {
        QuotaKitProPanel(
            store: self.store,
            title: "QuotaKit Pro",
            lockedMessage: String(localized: "Unlock the official iOS companion features, including Home Screen and Lock Screen widgets, and support ongoing QuotaKit maintenance."),
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
            title: "Unlock all providers",
            lockedMessage: self.lockedMessage,
            unlockedMessage: String(localized: "All synced provider cards are unlocked."),
            showsFeatureList: false)
            .accessibilityIdentifier("quotakit-pro-locked-summary")
    }

    private var lockedMessage: String {
        String(localized: "Free mode shows one synced provider. Pro unlocks all providers you've connected, plus widgets, cost history, sharing, and alerts.")
    }
}

struct ProFeatureLockedCard: View {
    let store: ProEntitlementStore
    let feature: FeatureGate
    let message: String

    var body: some View {
        QuotaKitProPanel(
            store: self.store,
            title: self.feature.title,
            lockedMessage: self.message,
            unlockedMessage: String(localized: "This Pro feature is unlocked."),
            showsFeatureList: false)
            .accessibilityIdentifier("pro-feature-locked-\(self.feature.rawValue)")
    }
}

private struct QuotaKitProPanel: View {
    let store: ProEntitlementStore
    let title: String
    let lockedMessage: String
    let unlockedMessage: String
    let showsFeatureList: Bool
    @Environment(\.quotaKitTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: self.store.isProUnlocked ? "checkmark.seal.fill" : "lock.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(self.iconColor)
                    .frame(width: 28, height: 28)
                    .background(self.iconColor.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(self.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(self.theme.textPrimary)

                    Text(self.summaryText)
                        .font(.caption)
                        .foregroundStyle(self.theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !self.store.isProUnlocked {
                Text(self.lockedMessage)
                    .font(.caption)
                    .foregroundStyle(self.theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if self.showsFeatureList {
                    QuotaKitProFeatureList()
                }
            } else {
                Text(self.unlockedMessage)
                    .font(.caption)
                    .foregroundStyle(self.theme.textMuted)
            }

            if case .error(let message) = self.store.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            QuotaKitProPurchaseControls(store: self.store)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.theme.fill(for: .elevated))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(self.iconColor.opacity(self.store.isProUnlocked ? 0.45 : 0.75), lineWidth: 1)
        }
    }

    private var summaryText: String {
        switch self.store.state {
        case .loading:
            return String(localized: "Checking purchase status.")
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

    private var iconColor: Color {
        self.store.isProUnlocked ? .green : self.theme.accent
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
            .tint(QuotaKitTheme.brandAccent.opacity(0.92))
            .foregroundStyle(Color.black.opacity(0.88))
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
            .tint(QuotaKitTheme.brandAccent)
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
