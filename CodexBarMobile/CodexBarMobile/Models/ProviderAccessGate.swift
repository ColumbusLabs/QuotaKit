import Foundation

struct ProviderAccessResult {
    let visibleGroups: [ProviderAccountGroup]
    let lockedCount: Int
    let effectiveSelectedProviderID: String?
    let isLimited: Bool
}

enum ProviderAccessGate {
    static func resolve(
        groups: [ProviderAccountGroup],
        isDemoMode: Bool,
        isProUnlocked: Bool,
        selectedProviderID: String?,
        isRemotelyDisabled: Bool = false) -> ProviderAccessResult
    {
        guard !groups.isEmpty else {
            return ProviderAccessResult(
                visibleGroups: [],
                lockedCount: 0,
                effectiveSelectedProviderID: nil,
                isLimited: false)
        }

        if !isRemotelyDisabled, isDemoMode || isProUnlocked || groups.count == 1 {
            return ProviderAccessResult(
                visibleGroups: groups,
                lockedCount: 0,
                effectiveSelectedProviderID: selectedProviderID,
                isLimited: false)
        }

        let selected = groups.first { $0.providerID == selectedProviderID } ?? groups[0]
        return ProviderAccessResult(
            visibleGroups: [selected],
            lockedCount: max(groups.count - 1, 0),
            effectiveSelectedProviderID: selected.providerID,
            isLimited: true)
    }
}
