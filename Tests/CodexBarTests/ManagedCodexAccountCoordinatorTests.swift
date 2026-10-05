import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized, CodexCredentialFixtures())
@MainActor
struct ManagedCodexAccountCoordinatorTests {
    @Test
    func `coordinator exposes in flight state and rejects overlapping managed authentication`() async throws {
        let root = CodexCredentialFixtures.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let existingAccountID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-111111111111"))
        let existingAccount = self.existingAccount(id: existingAccountID, root: root)
        let runner = BlockingManagedCodexLoginRunner()
        let service = ManagedCodexAccountService(
            store: InMemoryManagedCodexAccountStoreForCoordinatorTests(
                accounts: ManagedCodexAccountSet(version: 3, accounts: [existingAccount])),
            homeFactory: CoordinatorTestManagedCodexHomeFactory(root: root),
            loginRunner: runner,
            identityReader: CoordinatorStubManagedCodexIdentityReader(email: "user@example.com"),
            workspaceResolver: CoordinatorStubManagedCodexWorkspaceResolver())
        let coordinator = ManagedCodexAccountCoordinator(service: service)

        let authTask = Task {
            do {
                let account = try await coordinator.authenticateManagedAccount(existingAccountID: existingAccountID)
                await runner.authenticationDidFinish()
                return account
            } catch {
                await runner.authenticationDidFinish()
                throw error
            }
        }
        try #require(await runner.waitUntilStarted())

        #expect(coordinator.isAuthenticatingManagedAccount)
        #expect(coordinator.authenticatingManagedAccountID == existingAccountID)

        await #expect(throws: ManagedCodexAccountCoordinatorError.authenticationInProgress) {
            try await coordinator.authenticateManagedAccount()
        }

        await runner.resume()
        let account = try await authTask.value

        #expect(account.email == "user@example.com")
        #expect(account.id == existingAccountID)
        #expect(coordinator.isAuthenticatingManagedAccount == false)
        #expect(coordinator.authenticatingManagedAccountID == nil)
    }

    @Test
    func `coordinator clears in flight state after managed login timeout`() async throws {
        let root = CodexCredentialFixtures.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let loginResult = CLILoginRunner.Result(outcome: .timedOut, output: "timed out")
        let existingAccountID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-222222222222"))
        let existingAccount = self.existingAccount(id: existingAccountID, root: root)
        let runner = TimedOutManagedCodexLoginRunner(result: loginResult)
        let service = ManagedCodexAccountService(
            store: InMemoryManagedCodexAccountStoreForCoordinatorTests(
                accounts: ManagedCodexAccountSet(version: 3, accounts: [existingAccount])),
            homeFactory: CoordinatorTestManagedCodexHomeFactory(root: root),
            loginRunner: runner,
            identityReader: CoordinatorStubManagedCodexIdentityReader(email: "user@example.com"),
            workspaceResolver: CoordinatorStubManagedCodexWorkspaceResolver())
        let coordinator = ManagedCodexAccountCoordinator(service: service)

        do {
            _ = try await coordinator.authenticateManagedAccount(existingAccountID: existingAccountID, timeout: 0.2)
            Issue.record("Expected managed login timeout to throw")
        } catch let error as ManagedCodexAccountServiceError {
            #expect(error == .loginFailed(loginResult))
        } catch {
            Issue.record("Expected ManagedCodexAccountServiceError.loginFailed, got \(error)")
        }

        #expect(coordinator.isAuthenticatingManagedAccount == false)
        #expect(coordinator.authenticatingManagedAccountID == nil)
        #expect(await runner.callCount == 1)
    }

    @Test
    func `missing managed account fails before login and clears coordinator state`() async throws {
        let root = CodexCredentialFixtures.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = TimedOutManagedCodexLoginRunner(result: .init(outcome: .timedOut, output: "synthetic timeout"))
        let service = ManagedCodexAccountService(
            store: InMemoryManagedCodexAccountStoreForCoordinatorTests(
                accounts: ManagedCodexAccountSet(version: 3, accounts: [])),
            homeFactory: CoordinatorTestManagedCodexHomeFactory(root: root),
            loginRunner: runner,
            identityReader: CoordinatorStubManagedCodexIdentityReader(email: "user@example.com"),
            workspaceResolver: CoordinatorStubManagedCodexWorkspaceResolver())
        let coordinator = ManagedCodexAccountCoordinator(service: service)

        await #expect(throws: ManagedCodexAccountServiceError.accountChangedWhileAuthenticating) {
            try await coordinator.authenticateManagedAccount(existingAccountID: UUID())
        }

        #expect(await runner.callCount == 0)
        #expect(coordinator.isAuthenticatingManagedAccount == false)
        #expect(coordinator.authenticatingManagedAccountID == nil)
    }

    private func existingAccount(id: UUID, root: URL) -> ManagedCodexAccount {
        ManagedCodexAccount(
            id: id,
            email: "user@example.com",
            managedHomePath: root.appendingPathComponent(id.uuidString, isDirectory: true).path,
            createdAt: 100,
            updatedAt: 100,
            lastAuthenticatedAt: nil)
    }
}

private actor BlockingManagedCodexLoginRunner: ManagedCodexLoginRunning {
    private var waiters: [CheckedContinuation<CLILoginRunner.Result, Never>] = []
    private var startedWaiters: [CheckedContinuation<Bool, Never>] = []
    private var didStart = false
    private var didFinish = false

    func run(homePath _: String, timeout _: TimeInterval) async -> CLILoginRunner.Result {
        self.didStart = true
        self.startedWaiters.forEach { $0.resume(returning: true) }
        self.startedWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
        }
    }

    func waitUntilStarted() async -> Bool {
        if self.didStart { return true }
        if self.didFinish { return false }
        return await withCheckedContinuation { continuation in
            self.startedWaiters.append(continuation)
        }
    }

    func authenticationDidFinish() {
        self.didFinish = true
        if !self.didStart {
            self.startedWaiters.forEach { $0.resume(returning: false) }
            self.startedWaiters.removeAll()
        }
    }

    func resume() {
        let result = CLILoginRunner.Result(outcome: .success, output: "ok")
        self.waiters.forEach { $0.resume(returning: result) }
        self.waiters.removeAll()
    }
}

private actor TimedOutManagedCodexLoginRunner: ManagedCodexLoginRunning {
    let result: CLILoginRunner.Result
    private(set) var callCount = 0

    init(result: CLILoginRunner.Result) {
        self.result = result
    }

    func run(homePath _: String, timeout _: TimeInterval) async -> CLILoginRunner.Result {
        self.callCount += 1
        return self.result
    }
}

private final class InMemoryManagedCodexAccountStoreForCoordinatorTests: ManagedCodexAccountStoring,
@unchecked Sendable {
    var snapshot: ManagedCodexAccountSet

    init(accounts: ManagedCodexAccountSet) {
        self.snapshot = accounts
    }

    func loadAccounts() throws -> ManagedCodexAccountSet {
        self.snapshot
    }

    func storeAccounts(_ accounts: ManagedCodexAccountSet) throws {
        self.snapshot = accounts
    }

    func ensureFileExists() throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}

private final class CoordinatorTestManagedCodexHomeFactory: ManagedCodexHomeProducing, @unchecked Sendable {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func makeHomeURL() -> URL {
        self.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func validateManagedHomeForDeletion(_ url: URL) throws {
        try ManagedCodexHomeFactory(root: self.root).validateManagedHomeForDeletion(url)
    }
}

private final class CoordinatorStubManagedCodexIdentityReader: ManagedCodexIdentityReading, @unchecked Sendable {
    let email: String

    init(email: String) {
        self.email = email
    }

    func loadAccountIdentity(homePath _: String) throws -> CodexAuthBackedAccount {
        CodexAuthBackedAccount(
            identity: CodexIdentityResolver.resolve(accountId: nil, email: self.email),
            email: self.email,
            plan: "Pro")
    }
}

private struct CoordinatorStubManagedCodexWorkspaceResolver: ManagedCodexWorkspaceResolving {
    func resolveWorkspaceIdentity(
        homePath _: String,
        providerAccountID _: String) async -> CodexOpenAIWorkspaceIdentity?
    {
        nil
    }
}
