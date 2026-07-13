import Testing
import UIKit
@testable import CodexBarMobile

@Suite("Background Execution Lease Tests")
@MainActor
struct BackgroundExecutionLeaseTests {
    @Test
    func `Successful operation begins and ends one task`() {
        let manager = BackgroundTaskManagerSpy()

        let value = BackgroundExecutionLease.withExtendedTime(
            name: "test",
            manager: manager,
            operation: { 42 })

        #expect(value == 42)
        #expect(manager.begunNames == ["test"])
        #expect(manager.endedIdentifiers == [manager.identifier])
    }

    @Test
    func `Throwing operation still ends task`() {
        let manager = BackgroundTaskManagerSpy()

        #expect(throws: LeaseTestError.expected) {
            try BackgroundExecutionLease.withExtendedTime(
                name: "throwing",
                manager: manager)
            {
                throw LeaseTestError.expected
            }
        }

        #expect(manager.endedIdentifiers == [manager.identifier])
    }

    @Test
    func `Expiration and scope exit end task once`() {
        let manager = BackgroundTaskManagerSpy()

        BackgroundExecutionLease.withExtendedTime(
            name: "expiring",
            manager: manager)
        {
            manager.expire()
        }

        #expect(manager.endedIdentifiers == [manager.identifier])
    }

    @Test
    func `Invalid identifier runs operation without ending task`() {
        let manager = BackgroundTaskManagerSpy(identifier: .invalid)
        var didRun = false

        BackgroundExecutionLease.withExtendedTime(
            name: "invalid",
            manager: manager)
        {
            didRun = true
        }

        #expect(didRun)
        #expect(manager.endedIdentifiers.isEmpty)
    }
}

@MainActor
private final class BackgroundTaskManagerSpy: BackgroundTaskManaging {
    let identifier: UIBackgroundTaskIdentifier
    private(set) var begunNames: [String] = []
    private(set) var endedIdentifiers: [UIBackgroundTaskIdentifier] = []
    private var expirationHandler: (@MainActor @Sendable () -> Void)?

    init(identifier: UIBackgroundTaskIdentifier = .init(rawValue: 42)) {
        self.identifier = identifier
    }

    func beginBackgroundTask(
        withName taskName: String?,
        expirationHandler handler: (@MainActor @Sendable () -> Void)?) -> UIBackgroundTaskIdentifier
    {
        self.begunNames.append(taskName ?? "")
        self.expirationHandler = handler
        return self.identifier
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        self.endedIdentifiers.append(identifier)
    }

    func expire() {
        self.expirationHandler?()
    }
}

private enum LeaseTestError: Error {
    case expected
}
