import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeOAuthDelegatedRefreshCoordinatorTests {
    private enum StubError: Error, LocalizedError {
        case failed

        var errorDescription: String? {
            switch self {
            case .failed:
                "failed"
            }
        }
    }

    @Test
    func cooldownPreventsRepeatedAttempts() async {
        ClaudeOAuthDelegatedRefreshCoordinator.resetForTesting()
        defer { ClaudeOAuthDelegatedRefreshCoordinator.resetForTesting() }

        final class FingerprintBox: @unchecked Sendable {
            var fingerprint: ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint?
            init(_ fingerprint: ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint?) {
                self.fingerprint = fingerprint
            }
        }
        let box = FingerprintBox(ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
            modifiedAt: 1,
            createdAt: 1,
            persistentRefHash: "ref1"))
        ClaudeOAuthDelegatedRefreshCoordinator.setKeychainFingerprintOverrideForTesting { box.fingerprint }

        ClaudeOAuthDelegatedRefreshCoordinator.setCLIAvailableOverrideForTesting(true)
        ClaudeOAuthDelegatedRefreshCoordinator.setTouchAuthPathOverrideForTesting { _ in
            box.fingerprint = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                modifiedAt: 2,
                createdAt: 2,
                persistentRefHash: "ref2")
        }

        let start = Date(timeIntervalSince1970: 10000)
        let first = await ClaudeOAuthDelegatedRefreshCoordinator.attempt(now: start, timeout: 0.1)
        let second = await ClaudeOAuthDelegatedRefreshCoordinator
            .attempt(now: start.addingTimeInterval(30), timeout: 0.1)

        #expect(first == .attemptedSucceeded)
        #expect(second == .skippedByCooldown)
    }

    @Test
    func cliUnavailableReturnsCliUnavailable() async {
        ClaudeOAuthDelegatedRefreshCoordinator.resetForTesting()
        defer { ClaudeOAuthDelegatedRefreshCoordinator.resetForTesting() }

        ClaudeOAuthDelegatedRefreshCoordinator.setCLIAvailableOverrideForTesting(false)

        let outcome = await ClaudeOAuthDelegatedRefreshCoordinator.attempt(
            now: Date(timeIntervalSince1970: 20000),
            timeout: 0.1)

        #expect(outcome == .cliUnavailable)
    }

    @Test
    func successfulAuthTouchReportsAttemptedSucceeded() async {
        ClaudeOAuthDelegatedRefreshCoordinator.resetForTesting()
        defer { ClaudeOAuthDelegatedRefreshCoordinator.resetForTesting() }

        final class FingerprintBox: @unchecked Sendable {
            var fingerprint: ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint?
            init(_ fingerprint: ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint?) {
                self.fingerprint = fingerprint
            }
        }
        let box = FingerprintBox(ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
            modifiedAt: 10,
            createdAt: 10,
            persistentRefHash: "refA"))
        ClaudeOAuthDelegatedRefreshCoordinator.setKeychainFingerprintOverrideForTesting { box.fingerprint }

        ClaudeOAuthDelegatedRefreshCoordinator.setCLIAvailableOverrideForTesting(true)
        ClaudeOAuthDelegatedRefreshCoordinator.setTouchAuthPathOverrideForTesting { _ in
            box.fingerprint = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                modifiedAt: 11,
                createdAt: 11,
                persistentRefHash: "refB")
        }

        let outcome = await ClaudeOAuthDelegatedRefreshCoordinator.attempt(
            now: Date(timeIntervalSince1970: 30000),
            timeout: 0.1)

        #expect(outcome == .attemptedSucceeded)
    }

    @Test
    func failedAuthTouchReportsAttemptedFailed() async {
        ClaudeOAuthDelegatedRefreshCoordinator.resetForTesting()
        defer { ClaudeOAuthDelegatedRefreshCoordinator.resetForTesting() }

        ClaudeOAuthDelegatedRefreshCoordinator.setKeychainFingerprintOverrideForTesting {
            ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                modifiedAt: 20,
                createdAt: 20,
                persistentRefHash: "refX")
        }

        ClaudeOAuthDelegatedRefreshCoordinator.setCLIAvailableOverrideForTesting(true)
        ClaudeOAuthDelegatedRefreshCoordinator.setTouchAuthPathOverrideForTesting { _ in
            throw StubError.failed
        }

        let outcome = await ClaudeOAuthDelegatedRefreshCoordinator.attempt(
            now: Date(timeIntervalSince1970: 40000),
            timeout: 0.1)

        guard case let .attemptedFailed(message) = outcome else {
            Issue.record("Expected .attemptedFailed outcome")
            return
        }
        #expect(message.contains("failed"))
    }

    @Test
    func concurrentAttemptsJoinInFlight() async {
        ClaudeOAuthDelegatedRefreshCoordinator.resetForTesting()
        defer { ClaudeOAuthDelegatedRefreshCoordinator.resetForTesting() }

        final class FingerprintBox: @unchecked Sendable {
            var fingerprint: ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint?
            init(_ fingerprint: ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint?) {
                self.fingerprint = fingerprint
            }
        }

        final class CounterBox: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var count: Int = 0
            func increment() {
                self.lock.lock()
                self.count += 1
                self.lock.unlock()
            }
        }

        let counter = CounterBox()
        let box = FingerprintBox(ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
            modifiedAt: 1,
            createdAt: 1,
            persistentRefHash: "ref1"))
        ClaudeOAuthDelegatedRefreshCoordinator.setKeychainFingerprintOverrideForTesting { box.fingerprint }

        ClaudeOAuthDelegatedRefreshCoordinator.setCLIAvailableOverrideForTesting(true)
        ClaudeOAuthDelegatedRefreshCoordinator.setTouchAuthPathOverrideForTesting { _ in
            counter.increment()
            try await Task.sleep(nanoseconds: 1_500_000_000)
            box.fingerprint = ClaudeOAuthCredentialsStore.ClaudeKeychainFingerprint(
                modifiedAt: 2,
                createdAt: 2,
                persistentRefHash: "ref2")
        }

        let now = Date(timeIntervalSince1970: 50000)
        async let first = ClaudeOAuthDelegatedRefreshCoordinator.attempt(now: now, timeout: 2)
        try? await Task.sleep(nanoseconds: 100_000_000)
        async let second = ClaudeOAuthDelegatedRefreshCoordinator.attempt(now: now.addingTimeInterval(30), timeout: 2)

        let outcomes = await [first, second]

        #expect(outcomes.allSatisfy { $0 == .attemptedSucceeded })
        #expect(counter.count == 1)
    }
}
