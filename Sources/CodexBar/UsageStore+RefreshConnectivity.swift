import Foundation

extension UsageStore {
    nonisolated static func isPreservableNetworkTransportError(_ error: Error) -> Bool {
        let nsError = error as NSError
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
        if error is CancellationError {
            return false
        }

        let nsError = error as NSError
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

        let message = error.localizedDescription.lowercased()
        return message.contains("timed out") ||
            message.contains("timeout") ||
            message.contains("network connection was lost") ||
            message.contains("not connected to the internet") ||
            message.contains("cannot find host") ||
            message.contains("cannot connect to host") ||
            message.contains("dns lookup")
    }
}
