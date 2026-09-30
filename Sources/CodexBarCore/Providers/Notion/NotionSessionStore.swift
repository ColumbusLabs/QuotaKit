import Foundation
#if canImport(Darwin)
import Darwin
#endif

#if os(macOS)

public actor NotionSessionStore {
    public struct Session: Codable, Equatable, Sendable {
        public let tokenV2: String
        public let sourceLabel: String

        public init(tokenV2: String, sourceLabel: String) {
            self.tokenV2 = tokenV2
            self.sourceLabel = sourceLabel
        }

        public var cookieHeader: String {
            "\(NotionUsageFetcher.sessionCookieName)=\(self.tokenV2)"
        }
    }

    struct SessionObservation: Equatable, Sendable {
        fileprivate let revision: UInt64
    }

    struct Snapshot: Sendable {
        let session: Session?
        let observation: SessionObservation
    }

    private struct SessionState: Codable, Equatable {
        var revision: UInt64
        var session: Session?
    }

    public static let shared = NotionSessionStore()

    private let fileURL: URL
    private var lockURL: URL {
        self.fileURL.appendingPathExtension("lock")
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ProviderSessionStoreFile.url(for: "notion-session.json")
    }

    public func setSession(tokenV2: String, sourceLabel: String) {
        let token = tokenV2.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            self.clearSession()
            return
        }
        do {
            try self.withLockedState { state in
                state.session = Session(tokenV2: token, sourceLabel: sourceLabel)
                state.revision &+= 1
            }
        } catch {
            CodexBarLog.logger(LogCategories.cookieCache).error("Could not store Notion session")
        }
    }

    func snapshot() throws -> Snapshot {
        try self.withLockedState { state in
            Snapshot(session: state.session, observation: SessionObservation(revision: state.revision))
        }
    }

    func observe() throws -> SessionObservation {
        try self.snapshot().observation
    }

    public func getSession() -> Session? {
        (try? self.snapshot())?.session
    }

    public func clearSession() {
        do {
            try self.withLockedState { state in
                state.session = nil
                state.revision &+= 1
            }
        } catch {
            CodexBarLog.logger(LogCategories.cookieCache).error("Could not clear Notion session")
        }
    }

    @discardableResult
    func clearSessionIfCurrent(
        _ observation: SessionObservation,
        matchingTokenV2 token: String) throws -> Bool
    {
        try self.withLockedState { state in
            guard state.revision == observation.revision,
                  state.session?.tokenV2 == token
            else { return false }
            state.session = nil
            state.revision &+= 1
            return true
        }
    }

    /// Stores a validated imported login as one ordered Notion transaction: session-file lock first,
    /// then CookieHeaderCache's own conditional mutation lock. If publishing the sidecar fails,
    /// compensate by clearing only the exact cookie entry this call stored.
    @discardableResult
    func setSessionIfCurrentAndStoreCookie(
        _ observation: SessionObservation,
        tokenV2: String,
        sourceLabel: String,
        cookieObservation: CookieHeaderCache.ConditionalMutationObservation,
        cookieHeader: String) throws -> Bool
    {
        let token = tokenV2.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }
        return try self.withLockedState(persistChanges: false) { state in
            guard state.revision == observation.revision else { return false }
            let (result, receipt) = CookieHeaderCache.storeIfObservationCurrentReceipt(
                provider: .notion,
                expected: cookieObservation,
                cookieHeader: cookieHeader,
                sourceLabel: sourceLabel)
            guard result == .stored, let receipt else { return false }
            state.session = Session(tokenV2: token, sourceLabel: sourceLabel)
            state.revision &+= 1
            do {
                try self.write(state)
            } catch {
                _ = CookieHeaderCache.clearIfObservationCurrent(
                    provider: .notion,
                    expected: receipt.observation)
                throw error
            }
            return true
        }
    }

    @discardableResult
    func storeCookieIfCurrent(
        cookieObservation: CookieHeaderCache.ConditionalMutationObservation,
        cookieHeader: String,
        sourceLabel: String) -> CookieHeaderCache.ConditionalMutationReceipt?
    {
        let mutation = CookieHeaderCache.storeIfObservationCurrentReceipt(
            provider: .notion,
            expected: cookieObservation,
            cookieHeader: cookieHeader,
            sourceLabel: sourceLabel)
        return mutation.result == .stored ? mutation.receipt : nil
    }

    private func withLockedState<T>(
        persistChanges: Bool = true,
        _ body: (inout SessionState) throws -> T) throws -> T
    {
        let descriptor = try self.openLockFile()
        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = close(descriptor)
        }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var state = try self.readState()
        let initial = state
        let result = try body(&state)
        if persistChanges, state != initial {
            try self.write(state)
        }
        return result
    }

    private func openLockFile() throws -> Int32 {
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let descriptor = self.lockURL.path.withCString {
            open($0, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
        }
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else {
            _ = close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return descriptor
    }

    private func readState() throws -> SessionState {
        CredentialFileWriter.repairPermissions(at: self.fileURL)
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else {
            return SessionState(revision: 0, session: nil)
        }
        let data = try Data(contentsOf: self.fileURL)
        if let state = try? JSONDecoder().decode(SessionState.self, from: data) {
            return state
        }
        let legacy = try JSONDecoder().decode(Session.self, from: data)
        return SessionState(revision: 0, session: legacy.tokenV2.isEmpty ? nil : legacy)
    }

    private func write(_ state: SessionState) throws {
        let data = try JSONEncoder().encode(state)
        try CredentialFileWriter.writePrivate(data, to: self.fileURL)
    }
}

#endif
