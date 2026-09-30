#if os(macOS)
import Foundation
import Testing
@testable import CodexBarCore

struct ProcessPipeCaptureReadFailureTests {
    @Test
    func `terminal read failure preserves captured prefix without reporting EOF`() async throws {
        let pipe = Pipe()
        let readFileDescriptor = pipe.fileHandleForReading.fileDescriptor
        let capturedPrefix = DispatchSemaphore(value: 0)
        let failedRead = DispatchSemaphore(value: 0)
        let readCount = ReadCount()
        let prefix = Data("captured-prefix".utf8)
        let capture = ProcessPipeCapture(
            pipe: pipe,
            onData: { capturedPrefix.signal() },
            readOperation: { _, count in
                if readCount.increment() == 1 {
                    return try ProcessPipeCapture.readAvailableData(
                        fileDescriptor: readFileDescriptor,
                        upToCount: count)
                }
                failedRead.signal()
                throw POSIXError(.EBADF)
            })
        defer {
            capture.stop()
            try? pipe.fileHandleForWriting.close()
        }

        capture.start()
        try pipe.fileHandleForWriting.write(contentsOf: prefix)
        let receivedPrefix = await Task.detached {
            waitForSignal(capturedPrefix)
        }.value
        #expect(receivedPrefix)
        #expect(capture.currentSnapshot() == prefix)

        try pipe.fileHandleForWriting.write(contentsOf: Data("trigger-error".utf8))
        let receivedReadFailure = await Task.detached {
            waitForSignal(failedRead)
        }.value
        #expect(receivedReadFailure)

        let finishTask = Task { await capture.finish(timeout: .seconds(5)) }
        let finishedPromptly = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await finishTask.value
                return true
            }
            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(1))
                    return false
                } catch {
                    return false
                }
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        if !finishedPromptly {
            capture.stop()
        }
        let output = await finishTask.value

        #expect(finishedPromptly)
        #expect(output == prefix)
        #expect(!capture.reachedEOF)
        #expect(readCount.value == 2)
    }
}

private func waitForSignal(_ semaphore: DispatchSemaphore) -> Bool {
    semaphore.wait(timeout: .now() + .seconds(1)) == .success
}

private final class ReadCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.count
    }

    func increment() -> Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.count += 1
        return self.count
    }
}
#endif
