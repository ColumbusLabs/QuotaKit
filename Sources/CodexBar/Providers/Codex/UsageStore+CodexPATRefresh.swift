import CodexBarCore
import Foundation

extension UsageStore {
    nonisolated static func isCodexPATOutcome(_ outcome: ProviderFetchOutcome) -> Bool {
        guard case let .success(result) = outcome.result else { return false }
        return result.strategyID == "codex.pat" || result.sourceLabel == "pat"
    }

    nonisolated static func codexPublicationRefreshOverrides(
        provider: UsageProvider,
        outcome: ProviderFetchOutcome,
        explicitPAT: Bool,
        expectedGuard: CodexAccountScopedRefreshGuard?,
        limitResetOwnerKey: CodexLimitResetOwnerKey?) -> (
        CodexAccountScopedRefreshGuard?,
        CodexLimitResetOwnerKey?)
    {
        let publishesPAT = provider == .codex && self.isCodexPATOutcome(outcome)
        let explicitPATFailure = explicitPAT && {
            if case .failure = outcome.result { return true }
            return false
        }()
        if publishesPAT || explicitPATFailure {
            return (nil, publishesPAT ? nil : limitResetOwnerKey)
        }
        return (expectedGuard, limitResetOwnerKey)
    }
}
