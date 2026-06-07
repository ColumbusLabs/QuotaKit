import Foundation

enum ProFeatureAccess {
    static func isUnlocked(
        _ feature: FeatureGate,
        isDemoMode: Bool,
        isProUnlocked: Bool) -> Bool
    {
        isDemoMode || !feature.requiresPro || isProUnlocked
    }

    static func isLocked(
        _ feature: FeatureGate,
        isDemoMode: Bool,
        isProUnlocked: Bool) -> Bool
    {
        !self.isUnlocked(
            feature,
            isDemoMode: isDemoMode,
            isProUnlocked: isProUnlocked)
    }
}
