import Foundation

#if os(macOS)
import Security

/// The result of one Security.framework item operation. The executor owns this value until
/// the synchronous caller returns, so a late Security completion never writes through a
/// caller-owned pointer.
struct KeychainSecurityBackendResult: @unchecked Sendable {
    let status: OSStatus
    let value: CFTypeRef?

    init(status: OSStatus, value: CFTypeRef? = nil) {
        self.status = status
        self.value = value
    }
}

/// Injectable boundary around the four Security.framework item operations.
struct KeychainSecurityBackend: @unchecked Sendable {
    let copyMatching: (CFDictionary) -> KeychainSecurityBackendResult
    let update: (CFDictionary, CFDictionary) -> KeychainSecurityBackendResult
    let add: (CFDictionary) -> KeychainSecurityBackendResult
    let delete: (CFDictionary) -> KeychainSecurityBackendResult

    static let live = KeychainSecurityBackend(
        copyMatching: { query in
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query, &value)
            return KeychainSecurityBackendResult(status: status, value: value)
        },
        update: { query, attributes in
            KeychainSecurityBackendResult(status: SecItemUpdate(query, attributes))
        },
        add: { attributes in
            var value: CFTypeRef?
            let status = SecItemAdd(attributes, &value)
            return KeychainSecurityBackendResult(status: status, value: value)
        },
        delete: { query in
            KeychainSecurityBackendResult(status: SecItemDelete(query))
        })
}

/// Synchronous, deadline-bounded access to a single serial Security.framework worker.
///
/// A Security call cannot be cancelled safely. If the active call exceeds its deadline,
/// subsequent calls fail fast until that exact call completes. Queued calls that reach their
/// deadline before starting are cancelled and never reach the backend. This keeps at most one
/// Security call live and lets a late matching completion restore service without a restart.
final class KeychainOperationExecutor: @unchecked Sendable {
    enum HealthEvent: Equatable, Sendable {
        case breakerTripped(operationKind: String, deadlineSeconds: TimeInterval)
        case breakerHealed(operationKind: String)
    }

    struct Timeouts: Sendable {
        let queueAdmission: TimeInterval
        let noninteractiveRead: TimeInterval
        let noninteractiveMutation: TimeInterval
        let userInitiatedPrompt: TimeInterval

        static let production = Timeouts(
            queueAdmission: 2,
            noninteractiveRead: 2,
            noninteractiveMutation: 5,
            userInitiatedPrompt: 120)

        init(
            queueAdmission: TimeInterval,
            noninteractiveRead: TimeInterval,
            noninteractiveMutation: TimeInterval,
            userInitiatedPrompt: TimeInterval)
        {
            precondition(queueAdmission > 0)
            precondition(noninteractiveRead > 0)
            precondition(noninteractiveMutation > 0)
            precondition(userInitiatedPrompt > 0)
            self.queueAdmission = queueAdmission
            self.noninteractiveRead = noninteractiveRead
            self.noninteractiveMutation = noninteractiveMutation
            self.userInitiatedPrompt = userInitiatedPrompt
        }
    }

    private enum DeadlineResult {
        case completed(KeychainSecurityBackendResult)
        case unavailable
    }

    private let backend: KeychainSecurityBackend
    private let timeouts: Timeouts
    private let worker: DispatchQueue
    private let log = CodexBarLog.logger(LogCategories.keychainSecurity)
    private let healthEventHandler: (@Sendable (HealthEvent) -> Void)?
    private let stateLock = NSLock()
    private var nextJobID: UInt64 = 0
    private var breakerJobID: UInt64?
    private var activeJob: ActiveJob?
    private var breakerTrippedAtUptimeNanoseconds: UInt64?

    init(
        backend: KeychainSecurityBackend,
        timeouts: Timeouts = .production,
        workerLabel: String = "com.columbuslabs.quotakit.keychain",
        healthEventHandler: (@Sendable (HealthEvent) -> Void)? = nil)
    {
        self.backend = backend
        self.timeouts = timeouts
        self.worker = DispatchQueue(label: workerLabel, qos: .userInitiated)
        self.healthEventHandler = healthEventHandler
    }

    func copyMatching(
        _ query: CFDictionary,
        _ result: UnsafeMutablePointer<CFTypeRef?>?,
        interactionPolicy: KeychainSecurity.InteractionPolicy) -> OSStatus
    {
        let preparedQuery = Self.prepare(query, interactionPolicy: interactionPolicy)
        let outcome = self.perform(
            kind: .copyMatching,
            operationTimeout: self.timeout(for: .copyMatching, policy: interactionPolicy))
        { [backend] in
            backend.copyMatching(preparedQuery)
        }
        return Self.copy(outcome, to: result)
    }

    func update(
        _ query: CFDictionary,
        _ attributesToUpdate: CFDictionary,
        interactionPolicy: KeychainSecurity.InteractionPolicy) -> OSStatus
    {
        let preparedQuery = Self.prepare(query, interactionPolicy: interactionPolicy)
        let preparedAttributes = Self.copyDictionary(attributesToUpdate)
        return self.perform(
            kind: .update,
            operationTimeout: self.timeout(for: .update, policy: interactionPolicy))
        { [backend] in
            backend.update(preparedQuery, preparedAttributes)
        }.status
    }

    func add(
        _ attributes: CFDictionary,
        _ result: UnsafeMutablePointer<CFTypeRef?>?,
        interactionPolicy: KeychainSecurity.InteractionPolicy) -> OSStatus
    {
        let preparedAttributes = Self.prepare(attributes, interactionPolicy: interactionPolicy)
        let outcome = self.perform(
            kind: .add,
            operationTimeout: self.timeout(for: .add, policy: interactionPolicy))
        { [backend] in
            backend.add(preparedAttributes)
        }
        return Self.copy(outcome, to: result)
    }

    func delete(
        _ query: CFDictionary,
        interactionPolicy: KeychainSecurity.InteractionPolicy) -> OSStatus
    {
        let preparedQuery = Self.prepare(query, interactionPolicy: interactionPolicy)
        return self.perform(
            kind: .delete,
            operationTimeout: self.timeout(for: .delete, policy: interactionPolicy))
        { [backend] in
            backend.delete(preparedQuery)
        }.status
    }

    var isAvailableForTesting: Bool {
        self.stateLock.withLock { self.breakerJobID == nil }
    }

    var healthSnapshot: KeychainSecurity.HealthSnapshot {
        self.stateLock.withLock {
            let now = DispatchTime.now().uptimeNanoseconds
            let elapsed = self.activeJob.map {
                TimeInterval(now - $0.startedAtUptimeNanoseconds) / 1_000_000_000
            }
            let timeoutElapsed = self.breakerTrippedAtUptimeNanoseconds.flatMap { trippedAt in
                self.activeJob.map {
                    TimeInterval(trippedAt - $0.startedAtUptimeNanoseconds) / 1_000_000_000
                }
            }
            return KeychainSecurity.HealthSnapshot(
                state: self.breakerJobID != nil ? .tripped : (self.activeJob == nil ? .idle : .running),
                operationKind: self.activeJob?.kind.rawValue,
                elapsedSeconds: elapsed,
                timedOutAfterSeconds: timeoutElapsed)
        }
    }

    fileprivate enum OperationKind: String, Sendable {
        case copyMatching = "copy"
        case update
        case add
        case delete

        var isRead: Bool {
            self == .copyMatching
        }
    }

    private struct ActiveJob: Sendable {
        let id: UInt64
        let kind: OperationKind
        let startedAtUptimeNanoseconds: UInt64
    }

    private func timeout(
        for kind: OperationKind,
        policy: KeychainSecurity.InteractionPolicy) -> TimeInterval
    {
        if policy == .userInitiatedPrompt {
            return self.timeouts.userInitiatedPrompt
        }
        return kind.isRead ? self.timeouts.noninteractiveRead : self.timeouts.noninteractiveMutation
    }

    private func perform(
        kind: OperationKind,
        operationTimeout: TimeInterval,
        _ operation: @escaping () -> KeychainSecurityBackendResult) -> KeychainSecurityBackendResult
    {
        let job: Job
        self.stateLock.lock()
        guard self.breakerJobID == nil else {
            self.stateLock.unlock()
            return Self.unavailableResult
        }
        self.nextJobID &+= 1
        job = Job(id: self.nextJobID, kind: kind, operationTimeout: operationTimeout, operation: operation)
        self.worker.async { [self, job] in
            guard job.begin() else { return }
            self.recordStart(of: job)
            job.signalStarted()
            let result = job.run()
            let completedAfterTimeout = job.complete(with: result)
            self.recordCompletion(of: job, completedAfterTimeout: completedAfterTimeout)
        }
        self.stateLock.unlock()

        if !job.waitUntilStarted(timeout: self.timeouts.queueAdmission) {
            switch self.resolveQueueDeadline(for: job) {
            case let .completed(result): return result
            case .cancelledBeforeStart: return Self.unavailableResult
            case .alreadyStarted: break
            }
        }

        if job.waitUntilOperationDeadline() {
            return job.completedResult ?? Self.unavailableResult
        }

        return switch self.resolveDeadline(for: job) {
        case let .completed(result): result
        case .unavailable: Self.unavailableResult
        }
    }

    private func resolveQueueDeadline(for job: Job) -> Job.QueueDeadlineState {
        self.stateLock.withLock {
            // Admission may win the race with the queue deadline. In that case the caller
            // proceeds to the separate operation deadline; queue time never trips the breaker.
            job.cancelIfStillQueued()
        }
    }

    private func resolveDeadline(for job: Job) -> DeadlineResult {
        var didTrip = false
        let result: DeadlineResult = self.stateLock.withLock {
            switch job.markDeadlineExceeded() {
            case let .completed(result):
                return .completed(result)
            case .cancelledBeforeStart:
                return .unavailable
            case .timedOutWhileRunning:
                self.breakerJobID = job.id
                self.breakerTrippedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
                didTrip = true
                return .unavailable
            }
        }
        if didTrip {
            self.healthEventHandler?(.breakerTripped(
                operationKind: job.kind.rawValue,
                deadlineSeconds: job.operationTimeout))
            self.log.warning(
                "Keychain worker timed out; breaker tripped",
                metadata: [
                    "operation": job.kind.rawValue,
                    "deadlineSeconds": String(job.operationTimeout),
                ])
        }
        return result
    }

    private func recordStart(of job: Job) {
        self.stateLock.withLock {
            self.activeJob = ActiveJob(
                id: job.id,
                kind: job.kind,
                startedAtUptimeNanoseconds: job.startedAtUptimeNanoseconds)
        }
    }

    private func recordCompletion(of job: Job, completedAfterTimeout: Bool) {
        let didHeal = self.stateLock.withLock {
            if self.activeJob?.id == job.id {
                self.activeJob = nil
            }
            guard completedAfterTimeout, self.breakerJobID == job.id else { return false }
            self.breakerJobID = nil
            self.breakerTrippedAtUptimeNanoseconds = nil
            return true
        }
        if didHeal {
            self.healthEventHandler?(.breakerHealed(operationKind: job.kind.rawValue))
            self.log.info(
                "Keychain worker completed after timeout; breaker healed",
                metadata: ["operation": job.kind.rawValue])
        }
    }

    private static func prepare(
        _ dictionary: CFDictionary,
        interactionPolicy: KeychainSecurity.InteractionPolicy) -> CFDictionary
    {
        var copy = dictionary as NSDictionary as? [String: Any] ?? [:]
        if interactionPolicy == .nonInteractive {
            KeychainNoUIQuery.apply(to: &copy)
        }
        return NSDictionary(dictionary: copy)
    }

    private static func copyDictionary(_ dictionary: CFDictionary) -> CFDictionary {
        NSDictionary(dictionary: dictionary as NSDictionary)
    }

    private static func copy(
        _ backendResult: KeychainSecurityBackendResult,
        to callerResult: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    {
        if backendResult.status != errSecInteractionNotAllowed {
            callerResult?.pointee = backendResult.value
        }
        return backendResult.status
    }

    private static let unavailableResult = KeychainSecurityBackendResult(
        status: errSecInteractionNotAllowed)
}

private final class Job: @unchecked Sendable {
    enum QueueDeadlineState {
        case completed(KeychainSecurityBackendResult)
        case cancelledBeforeStart
        case alreadyStarted
    }

    enum DeadlineState {
        case completed(KeychainSecurityBackendResult)
        case cancelledBeforeStart
        case timedOutWhileRunning
    }

    private enum State {
        case queued
        case running
        case completed(KeychainSecurityBackendResult)
        case cancelledBeforeStart
        case timedOutWhileRunning
    }

    let id: UInt64
    let kind: KeychainOperationExecutor.OperationKind
    let operationTimeout: TimeInterval
    private let operation: () -> KeychainSecurityBackendResult
    private let stateLock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private let completion = DispatchSemaphore(value: 0)
    private var state: State = .queued
    private var startedAt: UInt64?
    private var operationDeadline: DispatchTime?

    init(
        id: UInt64,
        kind: KeychainOperationExecutor.OperationKind,
        operationTimeout: TimeInterval,
        operation: @escaping () -> KeychainSecurityBackendResult)
    {
        self.id = id
        self.kind = kind
        self.operationTimeout = operationTimeout
        self.operation = operation
    }

    func begin() -> Bool {
        self.stateLock.withLock {
            guard case .queued = self.state else { return false }
            let start = DispatchTime.now()
            self.startedAt = start.uptimeNanoseconds
            self.operationDeadline = start + self.operationTimeout
            self.state = .running
            return true
        }
    }

    var startedAtUptimeNanoseconds: UInt64 {
        self.stateLock.withLock {
            guard let startedAt = self.startedAt else {
                assertionFailure("Keychain job start time requested before admission")
                return DispatchTime.now().uptimeNanoseconds
            }
            return startedAt
        }
    }

    func signalStarted() {
        self.started.signal()
    }

    func run() -> KeychainSecurityBackendResult {
        self.operation()
    }

    func complete(with result: KeychainSecurityBackendResult) -> Bool {
        let completedAfterTimeout = self.stateLock.withLock {
            let wasTimedOut: Bool
            switch self.state {
            case .running:
                wasTimedOut = false
            case .timedOutWhileRunning:
                wasTimedOut = true
            case .queued, .completed, .cancelledBeforeStart:
                assertionFailure("Keychain job completed from an invalid state")
                return false
            }
            self.state = .completed(result)
            return wasTimedOut
        }
        self.completion.signal()
        return completedAfterTimeout
    }

    func waitUntilStarted(timeout: TimeInterval) -> Bool {
        self.started.wait(timeout: .now() + timeout) == .success
    }

    func waitUntilOperationDeadline() -> Bool {
        let deadline = self.stateLock.withLock { self.operationDeadline }
        guard let deadline else { return false }
        return self.completion.wait(timeout: deadline) == .success
    }

    var completedResult: KeychainSecurityBackendResult? {
        self.stateLock.withLock {
            guard case let .completed(result) = self.state else { return nil }
            return result
        }
    }

    func markDeadlineExceeded() -> DeadlineState {
        self.stateLock.withLock {
            switch self.state {
            case let .completed(result):
                return .completed(result)
            case .queued:
                self.state = .cancelledBeforeStart
                return .cancelledBeforeStart
            case .running:
                self.state = .timedOutWhileRunning
                return .timedOutWhileRunning
            case .cancelledBeforeStart:
                return .cancelledBeforeStart
            case .timedOutWhileRunning:
                return .timedOutWhileRunning
            }
        }
    }

    func cancelIfStillQueued() -> QueueDeadlineState {
        self.stateLock.withLock {
            switch self.state {
            case let .completed(result):
                return .completed(result)
            case .queued:
                self.state = .cancelledBeforeStart
                return .cancelledBeforeStart
            case .running, .timedOutWhileRunning:
                return .alreadyStarted
            case .cancelledBeforeStart:
                return .cancelledBeforeStart
            }
        }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
        self.lock()
        defer { self.unlock() }
        return try body()
    }
}
#endif
