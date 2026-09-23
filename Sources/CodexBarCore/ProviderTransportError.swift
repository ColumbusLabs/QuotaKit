import Foundation

enum ProviderTransportError {
    static func preservingIdentity(of error: Error, describedBy providerError: Error) -> Error {
        if error is CancellationError { return error }
        let original = error as NSError
        guard original.domain == NSURLErrorDomain else { return providerError }
        if original.code == NSURLErrorCancelled { return error }

        // Provider diagnostics should stay readable while transport codes remain available to
        // refresh retention, retry, and hook classification.
        var userInfo = original.userInfo
        userInfo[NSLocalizedDescriptionKey] = providerError.localizedDescription
        return NSError(domain: original.domain, code: original.code, userInfo: userInfo)
    }
}
