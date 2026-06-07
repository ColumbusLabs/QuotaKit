import Foundation

enum ProFeatureAccess {
    static func isUnlocked(
        _ feature: FeatureGate,
        isDemoMode: Bool,
        isProUnlocked: Bool,
        isRemotelyDisabled: Bool = false) -> Bool
    {
        !isRemotelyDisabled && (isDemoMode || !feature.requiresPro || isProUnlocked)
    }

    static func isLocked(
        _ feature: FeatureGate,
        isDemoMode: Bool,
        isProUnlocked: Bool,
        isRemotelyDisabled: Bool = false) -> Bool
    {
        !self.isUnlocked(
            feature,
            isDemoMode: isDemoMode,
            isProUnlocked: isProUnlocked,
            isRemotelyDisabled: isRemotelyDisabled)
    }
}
