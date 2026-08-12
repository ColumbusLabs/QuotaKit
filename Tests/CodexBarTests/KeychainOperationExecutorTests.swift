import Foundation
import LocalAuthentication
import Security
import Testing
@testable import CodexBarCore

#if os(macOS)
struct KeychainOperationExecutorTests {
    @Test
    func `production deadlines keep queue reads mutations and prompts distinct`() {
        let timeouts = KeychainOperationExecutor.Timeouts.production

        #expect(timeouts.queueAdmission == 2)
        #expect(timeouts.noninteractiveRead == 2)
        #expect(timeouts.noninteractiveMutation == 5)
        #expect(timeouts.userInitiatedPrompt == 120)
    }

    @Test
    func `running timeout opens fail fast breaker and matching completion heals it`() throws {
        let probe = BackendConcurrencyProbe()
        let firstStarted = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let backend = Self.backend(copyMatching: { _ in
            let invocation = probe.begin()
            defer { probe.end() }
            if invocation == 1 {
                firstStarted.signal()
                _ = releaseFirst.wait(timeout: .now() + 2)
            }
            return KeychainSecurityBackendResult(status: errSecSuccess)
        })
        let events = SynchronizedHealthEvents()
        let executor = KeychainOperationExecutor(
            backend: backend,
            timeouts: Self.fastTimeouts,
            healthEventHandler: { events.append($0) })
        defer { releaseFirst.signal() }

        let firstStatus = executor.copyMatching(
            [:] as CFDictionary,
            nil,
            interactionPolicy: .nonInteractive)
        #expect(firstStarted.wait(timeout: .now()) == .success)
        #expect(firstStatus == errSecInteractionNotAllowed)
        #expect(!executor.isAvailableForTesting)
        #expect(executor.healthSnapshot.state == .tripped)
        #expect(executor.healthSnapshot.operationKind == "copy")
        #expect((executor.healthSnapshot.timedOutAfterSeconds ?? 0) >= 0.04)
        #expect(events.values == [.breakerTripped(operationKind: "copy", deadlineSeconds: 0.05)])

        let secondStatus = executor.copyMatching(
            [:] as CFDictionary,
            nil,
            interactionPolicy: .nonInteractive)

        #expect(secondStatus == errSecInteractionNotAllowed)
        #expect(probe.invocationCount == 1)

        releaseFirst.signal()
        try Self.waitUntil { executor.isAvailableForTesting && events.values.count == 2 }
        #expect(executor.healthSnapshot.state == .idle)
        #expect(executor.healthSnapshot.operationKind == nil)
        #expect(events.values == [
            .breakerTripped(operationKind: "copy", deadlineSeconds: 0.05),
            .breakerHealed(operationKind: "copy"),
        ])

        let recoveredStatus = executor.copyMatching(
            [:] as CFDictionary,
            nil,
            interactionPolicy: .nonInteractive)
        #expect(recoveredStatus == errSecSuccess)
        #expect(probe.invocationCount == 2)
    }

    @Test
    func `queue admission is bounded and does not open breaker`() {
        let probe = BackendConcurrencyProbe()
        let firstStarted = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let backend = Self.backend(copyMatching: { _ in
            let invocation = probe.begin()
            defer { probe.end() }
            if invocation == 1 {
                firstStarted.signal()
                _ = releaseFirst.wait(timeout: .now() + 2)
            }
            return KeychainSecurityBackendResult(status: errSecSuccess)
        })
        let timeouts = KeychainOperationExecutor.Timeouts(
            queueAdmission: 0.05,
            noninteractiveRead: 0.5,
            noninteractiveMutation: 0.5,
            userInitiatedPrompt: 0.5)
        let executor = KeychainOperationExecutor(backend: backend, timeouts: timeouts)
        let firstCall = SynchronizedStatus()
        let firstFinished = DispatchSemaphore(value: 0)
        defer { releaseFirst.signal() }

        DispatchQueue.global().async {
            firstCall.value = executor.copyMatching(
                [:] as CFDictionary,
                nil,
                interactionPolicy: .userInitiatedPrompt)
            firstFinished.signal()
        }
        #expect(firstStarted.wait(timeout: .now() + 1) == .success)
        #expect(executor.healthSnapshot.state == .running)
        #expect(executor.healthSnapshot.operationKind == "copy")
        #expect((executor.healthSnapshot.elapsedSeconds ?? -1) >= 0)

        let queuedStart = ContinuousClock.now
        let queuedStatus = executor.copyMatching(
            [:] as CFDictionary,
            nil,
            interactionPolicy: .nonInteractive)
        let queuedElapsed = ContinuousClock.now - queuedStart

        #expect(queuedStatus == errSecInteractionNotAllowed)
        #expect(queuedElapsed >= .milliseconds(40))
        #expect(queuedElapsed < .seconds(1))
        #expect(executor.isAvailableForTesting)
        #expect(probe.invocationCount == 1)

        releaseFirst.signal()
        #expect(firstFinished.wait(timeout: .now() + 1) == .success)
        #expect(firstCall.value == errSecSuccess)
        #expect(probe.invocationCount == 1)
    }

    @Test
    func `serial worker never invokes more than one backend operation at once`() {
        let probe = BackendConcurrencyProbe()
        let backend = Self.backend(copyMatching: { _ in
            _ = probe.begin()
            usleep(10000)
            probe.end()
            return KeychainSecurityBackendResult(status: errSecSuccess)
        })
        let timeouts = KeychainOperationExecutor.Timeouts(
            queueAdmission: 1,
            noninteractiveRead: 1,
            noninteractiveMutation: 1,
            userInitiatedPrompt: 1)
        let executor = KeychainOperationExecutor(backend: backend, timeouts: timeouts)
        let statuses = SynchronizedStatuses()

        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            statuses.append(executor.copyMatching(
                [:] as CFDictionary,
                nil,
                interactionPolicy: .nonInteractive))
        }

        #expect(statuses.values.count == 12)
        #expect(statuses.values.allSatisfy { $0 == errSecSuccess })
        #expect(probe.invocationCount == 12)
        #expect(probe.maximumActiveCount == 1)
    }

    @Test
    func `late result never mutates caller pointer after timeout`() throws {
        let firstStarted = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let lateValue = "late-value" as CFString
        let backend = Self.backend(copyMatching: { _ in
            firstStarted.signal()
            _ = releaseFirst.wait(timeout: .now() + 2)
            return KeychainSecurityBackendResult(status: errSecSuccess, value: lateValue)
        })
        let executor = KeychainOperationExecutor(backend: backend, timeouts: Self.fastTimeouts)
        let sentinel = "sentinel" as CFString
        var callerResult: CFTypeRef? = sentinel
        defer { releaseFirst.signal() }

        let status = executor.copyMatching(
            [:] as CFDictionary,
            &callerResult,
            interactionPolicy: .nonInteractive)

        #expect(firstStarted.wait(timeout: .now()) == .success)
        #expect(status == errSecInteractionNotAllowed)
        #expect((callerResult as? String) == "sentinel")

        releaseFirst.signal()
        try Self.waitUntil { executor.isAvailableForTesting }
        #expect((callerResult as? String) == "sentinel")
    }

    @Test
    func `all ordinary operations normalize no UI even in user initiated task`() {
        let observations = QueryObservations()
        let backend = KeychainSecurityBackend(
            copyMatching: { query in
                observations.record("copy", query: query)
                return KeychainSecurityBackendResult(status: errSecSuccess)
            },
            update: { query, _ in
                observations.record("update", query: query)
                return KeychainSecurityBackendResult(status: errSecSuccess)
            },
            add: { attributes in
                observations.record("add", query: attributes)
                return KeychainSecurityBackendResult(status: errSecSuccess)
            },
            delete: { query in
                observations.record("delete", query: query)
                return KeychainSecurityBackendResult(status: errSecSuccess)
            })
        let executor = KeychainOperationExecutor(backend: backend, timeouts: Self.fastTimeouts)
        let explicitInteractiveQuery = [
            kSecUseAuthenticationUI as String: "interactive-sentinel",
        ] as CFDictionary

        ProviderInteractionContext.$current.withValue(.userInitiated) {
            #expect(executor.copyMatching(
                explicitInteractiveQuery,
                nil,
                interactionPolicy: .nonInteractive) == errSecSuccess)
            #expect(executor.update(
                explicitInteractiveQuery,
                [:] as CFDictionary,
                interactionPolicy: .nonInteractive) == errSecSuccess)
            #expect(executor.add(
                explicitInteractiveQuery,
                nil,
                interactionPolicy: .nonInteractive) == errSecSuccess)
            #expect(executor.delete(
                explicitInteractiveQuery,
                interactionPolicy: .nonInteractive) == errSecSuccess)
        }

        #expect(observations.names == ["copy", "update", "add", "delete"])
        for observation in observations.values {
            #expect(observation.uiPolicy == KeychainNoUIQuery.uiFailPolicyForTesting())
            #expect(observation.interactionNotAllowed)
        }
    }

    @Test
    func `public gateway rejects every background prompt operation before backend invocation`() {
        let observations = QueryObservations()
        let backend = KeychainSecurityBackend(
            copyMatching: { query in
                observations.record("copy", query: query)
                return KeychainSecurityBackendResult(status: errSecSuccess)
            },
            update: { query, _ in
                observations.record("update", query: query)
                return KeychainSecurityBackendResult(status: errSecSuccess)
            },
            add: { attributes in
                observations.record("add", query: attributes)
                return KeychainSecurityBackendResult(status: errSecSuccess)
            },
            delete: { query in
                observations.record("delete", query: query)
                return KeychainSecurityBackendResult(status: errSecSuccess)
            })
        let executor = KeychainOperationExecutor(backend: backend, timeouts: Self.fastTimeouts)
        let explicitInteractiveQuery = [
            kSecUseAuthenticationUI as String: "interactive-sentinel",
        ] as CFDictionary

        KeychainSecurity.withExecutorOverrideForTesting(executor) {
            #expect(KeychainSecurity.copyMatching(
                explicitInteractiveQuery,
                nil,
                interactionPolicy: .userInitiatedPrompt) == errSecInteractionNotAllowed)
            #expect(KeychainSecurity.update(
                explicitInteractiveQuery,
                [:] as CFDictionary,
                interactionPolicy: .userInitiatedPrompt) == errSecInteractionNotAllowed)
            #expect(KeychainSecurity.add(
                explicitInteractiveQuery,
                nil,
                interactionPolicy: .userInitiatedPrompt) == errSecInteractionNotAllowed)
            #expect(KeychainSecurity.delete(
                explicitInteractiveQuery,
                interactionPolicy: .userInitiatedPrompt) == errSecInteractionNotAllowed)
        }
        #expect(observations.values.isEmpty)

        ProviderInteractionContext.$current.withValue(.userInitiated) {
            KeychainSecurity.withExecutorOverrideForTesting(executor) {
                #expect(KeychainSecurity.copyMatching(
                    explicitInteractiveQuery,
                    nil,
                    interactionPolicy: .userInitiatedPrompt) == errSecSuccess)
                #expect(KeychainSecurity.update(
                    explicitInteractiveQuery,
                    [:] as CFDictionary,
                    interactionPolicy: .userInitiatedPrompt) == errSecSuccess)
                #expect(KeychainSecurity.add(
                    explicitInteractiveQuery,
                    nil,
                    interactionPolicy: .userInitiatedPrompt) == errSecSuccess)
                #expect(KeychainSecurity.delete(
                    explicitInteractiveQuery,
                    interactionPolicy: .userInitiatedPrompt) == errSecSuccess)
            }
        }

        #expect(observations.names == ["copy", "update", "add", "delete"])
        for observation in observations.values {
            #expect(observation.uiPolicy == "interactive-sentinel")
            #expect(!observation.interactionNotAllowed)
        }
    }

    private static let fastTimeouts = KeychainOperationExecutor.Timeouts(
        queueAdmission: 0.05,
        noninteractiveRead: 0.05,
        noninteractiveMutation: 0.05,
        userInitiatedPrompt: 0.1)

    private static func backend(
        copyMatching: @escaping (CFDictionary) -> KeychainSecurityBackendResult)
        -> KeychainSecurityBackend
    {
        KeychainSecurityBackend(
            copyMatching: copyMatching,
            update: { _, _ in KeychainSecurityBackendResult(status: errSecSuccess) },
            add: { _ in KeychainSecurityBackendResult(status: errSecSuccess) },
            delete: { _ in KeychainSecurityBackendResult(status: errSecSuccess) })
    }

    private static func waitUntil(
        timeout: Duration = .seconds(1),
        condition: () -> Bool) throws
    {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                throw ExecutorTestError.conditionTimedOut
            }
            usleep(1000)
        }
    }
}

private enum ExecutorTestError: Error {
    case conditionTimedOut
}

private final class BackendConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0
    private var storedInvocationCount = 0
    private var storedMaximumActiveCount = 0

    var invocationCount: Int {
        self.lock.withLock { self.storedInvocationCount }
    }

    var maximumActiveCount: Int {
        self.lock.withLock { self.storedMaximumActiveCount }
    }

    func begin() -> Int {
        self.lock.withLock {
            self.storedInvocationCount += 1
            self.activeCount += 1
            self.storedMaximumActiveCount = max(self.storedMaximumActiveCount, self.activeCount)
            return self.storedInvocationCount
        }
    }

    func end() {
        self.lock.withLock {
            self.activeCount -= 1
        }
    }
}

private final class SynchronizedStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: OSStatus?

    var value: OSStatus? {
        get { self.lock.withLock { self.storedValue } }
        set { self.lock.withLock { self.storedValue = newValue } }
    }
}

private final class SynchronizedStatuses: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [OSStatus] = []

    var values: [OSStatus] {
        self.lock.withLock { self.storedValues }
    }

    func append(_ status: OSStatus) {
        self.lock.withLock { self.storedValues.append(status) }
    }
}

private final class QueryObservations: @unchecked Sendable {
    struct Observation {
        let name: String
        let uiPolicy: String?
        let interactionNotAllowed: Bool
    }

    private let lock = NSLock()
    private var storedValues: [Observation] = []

    var values: [Observation] {
        self.lock.withLock { self.storedValues }
    }

    var names: [String] {
        self.values.map(\.name)
    }

    func record(_ name: String, query: CFDictionary) {
        let dictionary = query as NSDictionary
        let context = dictionary[kSecUseAuthenticationContext as String] as? LAContext
        let observation = Observation(
            name: name,
            uiPolicy: dictionary[kSecUseAuthenticationUI as String] as? String,
            interactionNotAllowed: context?.interactionNotAllowed == true)
        self.lock.withLock { self.storedValues.append(observation) }
    }
}

private final class SynchronizedHealthEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [KeychainOperationExecutor.HealthEvent] = []

    var values: [KeychainOperationExecutor.HealthEvent] {
        self.lock.withLock { self.storedValues }
    }

    func append(_ event: KeychainOperationExecutor.HealthEvent) {
        self.lock.withLock { self.storedValues.append(event) }
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
