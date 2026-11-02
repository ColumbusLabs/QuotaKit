import Foundation
import SweetCookieKit

#if os(macOS) || os(Linux)
extension CursorStatusProbe {
    func scanBrowsers(
        _ browsers: [Browser],
        importSessions: (Browser) -> [CursorCookieImporter.SessionInfo],
        attemptFetch: (CursorCookieImporter.SessionInfo) async -> ImportedSessionFetchOutcome) async
        -> ImportedSessionScanResult
    {
        var firstFailure: CursorStatusProbeError?

        for browser in browsers {
            let sessions = importSessions(browser)
            guard !sessions.isEmpty else { continue }
            for session in sessions {
                switch await attemptFetch(session) {
                case let .succeeded(snapshot):
                    return .succeeded(snapshot)
                case .tryNextBrowser:
                    continue
                case let .failed(error):
                    firstFailure = firstFailure ?? error
                }
            }
        }

        return .exhausted(firstFailure)
    }

    func scanImportedSessions(
        _ sessions: [CursorCookieImporter.SessionInfo],
        attemptFetch: (CursorCookieImporter.SessionInfo) async -> ImportedSessionFetchOutcome) async
        -> ImportedSessionScanResult
    {
        var firstFailure: CursorStatusProbeError?

        for session in sessions {
            switch await attemptFetch(session) {
            case let .succeeded(snapshot):
                return .succeeded(snapshot)
            case .tryNextBrowser:
                continue
            case let .failed(error):
                firstFailure = firstFailure ?? error
            }
        }

        return .exhausted(firstFailure)
    }
}
#endif
