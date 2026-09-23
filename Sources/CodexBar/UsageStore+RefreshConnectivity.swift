import CodexBarCore
import Foundation

extension UsageStore {
    nonisolated static func underlyingProviderTransportError(_ error: Error) -> Error {
        if case let .networkError(underlyingError) = error as? CodexOAuthFetchError {
            return underlyingError
        }
        if case let .networkError(underlyingError) = error as? CodexTokenRefresher.RefreshError {
            return underlyingError
        }
        if case let .networkError(underlyingError) = error as? VertexAIFetchError {
            return underlyingError
        }
        if case let .networkError(underlyingError) = error as? VertexAITokenRefresher.RefreshError {
            return underlyingError
        }
        return error
    }

    nonisolated static func isPreservableNetworkTransportError(_ error: Error) -> Bool {
        let nsError = self.underlyingProviderTransportError(error) as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch nsError.code {
        case NSURLErrorTimedOut,
             NSURLErrorCancelled,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorDNSLookupFailed:
            return true
        default:
            return false
        }
    }

    static func startupConnectivityRetryDelay(forAttempt attempt: Int) -> TimeInterval? {
        let delays: [TimeInterval] = [15, 45, 120, 300]
        guard attempt >= 1, attempt <= delays.count else { return nil }
        return delays[attempt - 1]
    }

    static func isStartupConnectivityRetryableError(_ error: Error) -> Bool {
        let transportError = self.underlyingProviderTransportError(error)
        if transportError is CancellationError {
            return false
        }

        let nsError = transportError as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed:
                return true
            default:
                return false
            }
        }

        let message = transportError.localizedDescription.lowercased()
        return message.contains("timed out") ||
            message.contains("timeout") ||
            message.contains("network connection was lost") ||
            message.contains("not connected to the internet") ||
            message.contains("cannot find host") ||
            message.contains("cannot connect to host") ||
            message.contains("dns lookup")
    }
}
