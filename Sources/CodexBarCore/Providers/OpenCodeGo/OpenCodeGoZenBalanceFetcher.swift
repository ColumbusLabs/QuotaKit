import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension OpenCodeGoUsageFetcher {
    static let optionalZenBalanceTimeout: TimeInterval = 5
    static let optionalZenBalanceJoinGrace: Duration = .milliseconds(250)

    public static func zenDashboardURL(workspaceID raw: String?) -> URL {
        guard let workspaceID = self.normalizeWorkspaceID(raw),
              let url = URL(string: "https://opencode.ai/workspace/\(workspaceID)")
        else {
            return URL(string: "https://opencode.ai")!
        }
        return url
    }

    static func fetchOptionalZenBalance(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval,
        session: URLSession) async throws -> Double?
    {
        do {
            let balance = try await self.fetchZenBalance(
                workspaceID: workspaceID,
                cookieHeader: cookieHeader,
                timeout: timeout,
                session: session)
            try Task.checkCancellation()
            return balance
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            return nil
        }
    }

    static func completedOptionalZenBalance(from task: Task<Double?, Error>) async throws -> Double? {
        try await withThrowingTaskGroup(of: Double?.self) { group in
            group.addTask {
                try await task.value
            }
            group.addTask {
                try await Task.sleep(for: self.optionalZenBalanceJoinGrace)
                return nil
            }

            let result = try await group.next()
            group.cancelAll()
            guard let value = result else {
                task.cancel()
                return nil
            }
            if value == nil {
                task.cancel()
            }
            return value
        }
    }

    static func parseZenBalance(text: String) -> Double? {
        OpenCodeGoZenBalanceParser.parse(text: text)
    }

    private static func fetchZenBalance(
        workspaceID: String,
        cookieHeader: String,
        timeout: TimeInterval,
        session: URLSession) async throws -> Double?
    {
        let text = try await self.fetchPageText(
            url: self.zenDashboardURL(workspaceID: workspaceID),
            cookieHeader: cookieHeader,
            timeout: timeout,
            session: session)
        if self.looksSignedOut(text: text) {
            throw OpenCodeGoUsageError.invalidCredentials
        }
        return self.parseZenBalance(text: text)
    }
}
