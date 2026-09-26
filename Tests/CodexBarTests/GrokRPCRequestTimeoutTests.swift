import Foundation
import Testing
@testable import CodexBarCore

struct GrokRPCRequestTimeoutTests {
    private enum Failure: Error, Equatable {
        case timeout
        case stdoutClosed
        case requestFailed
    }

    @Test
    func `timeout remains authoritative when teardown closes stdout`() async {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let stdoutClosed = DispatchSemaphore(value: 0)

        do {
            let _: Int = try await GrokRPCRequestTimeout.run(
                seconds: 0.01,
                timeoutError: Failure.timeout,
                onTimeout: {
                    continuation.finish()
                    #expect(stdoutClosed.wait(timeout: .now() + 1) == .success)
                },
                operation: {
                    for await _ in stream {}
                    stdoutClosed.signal()
                    throw Failure.stdoutClosed
                })
            Issue.record("Expected timeout")
        } catch {
            #expect(error as? Failure == .timeout)
        }
    }

    @Test
    func `request errors retain their classification`() async {
        do {
            let _: Int = try await GrokRPCRequestTimeout.run(
                seconds: 60,
                timeoutError: Failure.timeout,
                onTimeout: { Issue.record("Unexpected timeout teardown") },
                operation: { throw Failure.requestFailed })
            Issue.record("Expected request failure")
        } catch {
            #expect(error as? Failure == .requestFailed)
        }
    }

    @Test
    func `successful request does not tear down process`() async throws {
        let result = try await GrokRPCRequestTimeout.run(
            seconds: 60,
            timeoutError: Failure.timeout,
            onTimeout: { Issue.record("Unexpected timeout teardown") },
            operation: { 42 })

        #expect(result == 42)
    }
}
