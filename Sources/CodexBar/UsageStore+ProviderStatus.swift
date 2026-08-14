import CodexBarCore
import Foundation

extension UsageStore {
    func refreshProviderStatus(_ provider: UsageProvider) async {
        guard self.settings.statusChecksEnabled else { return }
        guard let meta = self.providerMetadata[provider] else { return }
        let publicationRevision = self.providerPublicationRevision(for: provider)

        do {
            let status: ProviderStatus
            var components: [ProviderStatusComponent]?
            if let override = self._test_providerStatusFetchOverride {
                status = try await override(provider)
            } else if let urlString = meta.statusPageURL, let baseURL = URL(string: urlString) {
                let summary = try await Self.fetchStatusSummary(from: baseURL)
                status = summary.status
                components = summary.components
            } else if let productID = meta.statusWorkspaceProductID {
                status = try await Self.fetchWorkspaceStatus(productID: productID)
            } else {
                return
            }
            guard self.statusRefreshPublicationIsCurrent(publicationRevision, for: provider) else { return }
            self.statuses[provider.instanceID] = status
            // A component endpoint is best-effort. Preserve the last good list when the
            // overall status succeeds but the component request or decoding fails.
            if let components {
                self.statusComponents[provider.instanceID] = components
            }
            self.emitProviderStatusHooks(provider: provider, indicator: status.indicator)
        } catch {
            guard self.statusRefreshPublicationIsCurrent(publicationRevision, for: provider) else { return }
            self.recordStartupConnectivityRetryableFailure(error)
            // Keep the previous status to avoid flapping when the API hiccups — and keep
            // nothing when there is no previous status. Seeding the transport error here
            // made `MenuDescriptor.statusLine` pin the raw error text ("A TLS error caused
            // the secure connection to fail.") to the bottom of the menu, with no source or
            // timestamp, until a status fetch first succeeded. An app launched while the
            // status endpoint is unreachable (observed live 2026-08-14, status.claude.com
            // serving the bare `*.statuspage.io` certificate) showed it for hours of
            // otherwise-healthy refreshes, reading as a live provider fault. An unreachable
            // status page is an absence of status information, not a provider status; the
            // bounded startup-connectivity retry above is the recovery path.
        }
    }

    private func statusRefreshPublicationIsCurrent(
        _ publicationRevision: ProviderPublicationRevision,
        for provider: UsageProvider) -> Bool
    {
        self.providerPublicationRevisionIsCurrent(publicationRevision, for: provider) &&
            self.settings.statusChecksEnabled &&
            self.settings.isProviderEnabledCached(
                provider: provider,
                metadataByProvider: self.providerMetadata)
    }
}
